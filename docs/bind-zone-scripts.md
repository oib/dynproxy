# BIND zone helper scripts (ns1, `/root/scripts/`)

Static and dynamic zones are maintained differently on ns1. This doc covers
the generic zone helpers; the dynProxy-specific scripts are in
[server-side.md](server-side.md).

## Static zones — serial must be bumped by hand

Static zone files are edited directly (or generated), so the SOA serial has to
be incremented manually before reload/notify.

### `bind_serial.sh` (v05)

```
bind_serial.sh <domain.name>     # e.g. bind_serial.sh example.net
```

- Derives the zone file as `/etc/bind/zones/db.<domain>`.
- Reads the current 10-digit serial (`YYYYMMDDNN`); if the date part is today,
  increments `NN`, otherwise resets to `01`.
- `sed -i` replaces the serial **in place**.
- Runs `named-checkzone`; on success `rndc reload` + `rndc notify` (pushes to
  slaves), on failure exits without reloading.

> **Do not run this on `dynproxy.net`** — it's a dynamic zone
> (`db.dynproxy.net.jnl`). sed-editing a journal-managed file while named owns
> it corrupts state; changes to dynamic zones go through `nsupdate`, which
> increments the serial automatically. If a manual edit is ever needed:
> `rndc freeze dynproxy.net` → edit → `rndc thaw`.

### `bind_checkzone.sh` (v02.9)

Parses every `zone { file "..."; }` entry in `/etc/bind/named.conf.local` and
runs `named-checkzone` on each. Quick health-check after mass edits.

> Note: it extracts the zone name from the filename (`db.<name>`), so it
> assumes the `db.*` naming convention.

### `bind_add_zone.sh` (v01.0)

```
bind_add_zone.sh <domain.tld>
```

- Appends a `zone` stanza to `named.conf.local` (master, transfers/notifies to
  ns2 `116.202.112.180` and ns3 `95.216.198.140` — note the hardcoded
  `ns3-key` and IPs, which predate the current `xfr-ns1-ns2`/`xfr-ns2-ns3` key
  setup; adjust for new zones).
- Creates `/etc/bind/zones/db.<domain>` from a template (SOA, NS records, a
  default A + MX + SPF pointing at `116.202.112.180`).
- `chown bind:bind`, `chmod 640`, `rndc reload`.
- Refuses if the zone file already exists.

## Dynamic zones — serial is automatic

For `dynproxy.net` (`allow-update` enabled), the equivalent "maintenance
script" is DDNS itself:

- `nsupdate` transactions (from `update_zone.sh` /
  `dynProxy_create_subdom_token.sh`) make named bump the SOA serial and append
  to `db.dynproxy.net.jnl` — no manual serial work.
- `rndc sync dynproxy.net` flushes the journal into the master file if needed;
  `rndc freeze`/`thaw` brackets any manual edit.
- Slaves ns2/ns3 learn of changes through `notify yes` + `also-notify`, so
  dynamic updates propagate the same way as static `rndc notify`.
