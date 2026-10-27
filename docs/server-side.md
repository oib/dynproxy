# Server-side scripts (ns1)

All of these live on ns1, the primary DNS server and web frontend for
`ip.dynproxy.net`. See [nginx-site.md](nginx-site.md) for how the HTTP
endpoints map to the scripts.

---

## Provisioning: `/root/scripts/dynProxy_create_subdom_token.sh`

**Shebang:** `#!/bin/bash` — **Version:** 02.1

Interactive script to onboard a new dynDNS client: creates a token file and
adds a placeholder A record to the zone via `nsupdate`.

### Prerequisites

- `/var/www/ip/token/` exists (token store, served by the web scripts).
- `/etc/bind/nsupdate_key.conf` exists (TSIG key for `nsupdate`).

### Steps

1. Prompts for `subdomain` and `domain`, builds `FULL_DOMAIN=sub.domain.`.
2. Generates a random token: `openssl rand -hex 16` (32 hex chars).
3. Creates `/var/www/ip/token/<token>.txt`, mode `644`, owner `www-data`.
4. Runs `nsupdate -k /etc/bind/nsupdate_key.conf` against `127.0.0.1`:

   ```
   server 127.0.0.1
   zone <domain>.
   update add <sub>.<domain>. $TTL A 0.0.0.0
   send
   ```

   > **Bug:** `$TTL` is never set in the script, so it expands to an empty
   > string — the record is added relying on nsupdate's default TTL
   > (effectively zone default). The comment in the script acknowledges TTL is
   > not explicitly set.
5. Verifies with `dig +short @127.0.0.1 <fqdn> A` that it resolves to
   `0.0.0.0`, and that the token file exists.

### Follow-up manual step

After provisioning, add the mapping line to `/etc/bind/tokendnszone.conf`
(see below) so the update endpoint accepts the token.

---

## Update endpoint: `/var/www/ip/scripts/update_zone.sh`

**Shebang:** `#!/bin/zsh` — **Version:** 12.4
**Route:** `POST /update_zone` (fcgiwrap). Logs to `/var/log/dynProxy.log`.
`DEBUG=true` additionally echoes log messages to the HTTP response.

### Request

```
POST /update_zone
token=<32-hex-token>&ip=<ipv4>
```

Extraction is regex-based (`grep -oP '(?<=token=)[a-zA-Z0-9_-]+'` and
`(?<=ip=)[0-9.]+`), so `token=` / `ip=` must appear literally in the POST body.
IPv4 only for `ip`.

### Validation chain

| Check | Failure response |
|---|---|
| `token` present | 400 Missing token |
| `ip` present | 400 Missing IP |
| `/var/www/ip/token/<token>.txt` exists | 403 Token file not found |
| token present in `/etc/bind/tokendnszone.conf` | 403 Token mapping not found |
| zone file from mapping exists | 404 Zone file not found |
| A record parseable from zone file | 500 Failed to extract ZONE_IP |

### Token↔zone mapping — `/etc/bind/tokendnszone.conf`

CSV, one client per line:

```
<token>,<fqdn>,<zone-file-path>
```

Example (tokens anonymized — real values are 32 lowercase hex chars,
`openssl rand -hex 16`):

```
<token-es1>,es1.dynproxy.net,/etc/bind/zones/db.dynproxy.net
<token-at1>,at1.dynproxy.net,/etc/bind/zones/db.dynproxy.net
<token-mx1>,mx1.dynproxy.net,/etc/bind/zones/db.dynproxy.net
```

### Update logic

- The current zone A record IP is extracted from the zone file with `awk`
  (matches `<shortname> A <ip>` or `<fqdn> A <ip>` against origin
  `dynproxy.net.` — note origin is hardcoded in the awk script).
- If `NEW_IP == ZONE_IP`: responds "already up-to-date", exit 0.
- Otherwise runs `nsupdate` (no `-k` needed — the zone's `allow-update`
  permits `localhost`, see [BIND zone configuration](#bind-zone-configuration)):

  ```
  server 127.0.0.1
  zone <domain-without-first-label>
  update delete <fqdn> A
  update add <fqdn> 604800 A <new-ip>
  send
  ```

- Writes the new IP into the token file (used as "current IP" bookkeeping;
  `CURRENT_IP` is read but not actually compared before updating — the
  comparison is against the zone file).
- Responds `IP updated successfully for <fqdn>`.

> **Note:** the `zone` is derived as `${DOMAIN#*.}` (everything after the first
> label), which works for `*.dynproxy.net` but would produce the wrong zone
> name for deeper nesting (e.g. `a.b.dynproxy.net` → `b.dynproxy.net`).

---

## BIND zone configuration

`dynproxy.net` is a **dynamic zone** in `/etc/bind/named.conf.local`:

```
zone "dynproxy.net" {
    type master;
    file "/etc/bind/zones/db.dynproxy.net";
    allow-update { key "nsupdate-key"; localhost; };
    allow-transfer { key "xfr-ns1-ns2"; key "xfr-ns2-ns3"; };
    also-notify    { 152.53.242.245; 95.216.198.140; };
    notify yes;
};
```

Implications:

- Updates can arrive via DDNS **either** authenticated with the `nsupdate-key`
  TSIG key (`/etc/bind/keys/nsupdate-key.key`, used by
  `dynProxy_create_subdom_token.sh` via `/etc/bind/nsupdate_key.conf`) **or**
  unsigned from localhost — which is why the `update_zone.sh` endpoint calls
  `nsupdate` with no `-k`.
- The zone file `db.dynproxy.net` is maintained by named; pending changes
  accumulate in the journal `db.dynproxy.net.jnl`. **Do not hand-edit the zone
  file** — use `rndc freeze dynproxy.net` first (and `rndc thaw` after), or
  make changes via `nsupdate`.
- `notify yes` + `also-notify` pushes updates to slaves **ns2**
  (152.53.242.245, netcup) and **ns3** (95.216.198.140); zone transfers are
  authenticated with the `xfr-ns1-ns2` / `xfr-ns2-ns3` TSIG keys. Client A
  records propagate to the slaves automatically.
- Dynamic client A records (at1, es1, mx1, …) live in the zone with `$TTL 300`
  sections; the updater writes records with TTL 604800.

---

## IP echo: `/var/www/ip/scripts/ip.sh`

**Shebang:** `#!/bin/zsh` — **Version:** 03 — **Route:** `GET /`

Trivial endpoint: emits FastCGI `Content-type: text/plain` then prints
`$REMOTE_ADDR`. This is how clients discover their public IP.

---

## IP save: `/var/www/ip/scripts/update_ip.sh`

**Shebang:** `#!/bin/zsh` — **Version:** 05 — **Route:** `POST /update_ip`
**Log:** `/var/log/update_ip.log`

Simpler variant that stores the caller's IP (`$REMOTE_ADDR`, v4 **or** v6)
into `/var/www/ip/token/<token>.txt` — it does **not** touch DNS. Used as a
lightweight "check-in" / bookkeeping endpoint.

- 400 if `token=` missing or `REMOTE_ADDR` is not a valid IPv4/IPv6.
- 403 if the token file does not exist.
- 200 "IP updated successfully" after writing the IP.

`token=` extraction here accepts any non-`&` characters (`[^&]*`), unlike the
stricter charset in `update_zone.sh`.
