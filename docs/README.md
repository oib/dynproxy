# dynProxy — Dynamic DNS Service

dynProxy is a self-hosted dynamic-DNS system. Clients whose public IP may change
periodically check their IP against `http://ip.dynproxy.net` and, when it changes,
POST a token + new IP to `http://ip.dynproxy.net/update_zone`. The primary DNS
server (ns1) validates the token and updates the BIND zone via `nsupdate`.

## Architecture

```
┌──────────────┐                        ┌──────────────────────────────────┐
│ Client host  │                        │ ns1 (primary DNS / web frontend) │
│ (e.g. at1)   │                        │                                  │
│              │  GET ip.dynproxy.net   │ nginx sites-enabled/ip           │
│ update_zone. │ ─────────────────────▶ │  └─ /        → ip.sh (echo IP)   │
│ sh (cron)    │                        │                                  │
│              │  POST /update_zone     │  └─ /update_zone → update_zone.sh│
│              │ ─────────────────────▶ │       (fcgiwrap → zsh script)    │
│              │   token=…&ip=…         │            │                     │
└──────────────┘                        │            ▼                     │
                                        │   /var/www/ip/token/<tok>.txt    │
                                        │   /etc/bind/tokendnszone.conf    │
                                        │            │                     │
                                        │            ▼                     │
                                        │   nsupdate → BIND zone files     │
                                        └──────────────────────────────────┘
```

## Components

| Component | Host | Path | Doc |
|---|---|---|---|
| Client updater | each client (e.g. at1) | `/root/scripts/update_zone.sh` | [client-update-zone.md](client-update-zone.md) |
| Provisioning script | ns1 | `/root/scripts/dynProxy_create_subdom_token.sh` | [server-side.md](server-side.md) |
| Update endpoint | ns1 | `/var/www/ip/scripts/update_zone.sh` | [server-side.md](server-side.md) |
| IP-echo endpoint | ns1 | `/var/www/ip/scripts/ip.sh` | [server-side.md](server-side.md) |
| IP-save endpoint | ns1 | `/var/www/ip/scripts/update_ip.sh` | [server-side.md](server-side.md) |
| nginx site | ns1 | `/etc/nginx/sites-enabled/ip` | [nginx-site.md](nginx-site.md) |
| Token↔zone mapping | ns1 | `/etc/bind/tokendnszone.conf` | [server-side.md](server-side.md) |
| Server log | ns1 | `/var/log/dynProxy.log` | [operations.md](operations.md) |

## Flow

1. Client cron runs `update_zone.sh`, which fetches its public IP via
   `GET http://ip.dynproxy.net/` (`ip.sh` echoes `$REMOTE_ADDR`).
2. If the IP differs from the cached one in `/root/.ip.txt`, the client POSTs
   `token=<token>&ip=<new-ip>` to `/update_zone`.
3. The server script validates:
   - `/var/www/ip/token/<token>.txt` exists (created at provisioning time),
   - the token has a mapping in `/etc/bind/tokendnszone.conf`.
4. It compares the new IP against the A record in the zone file; if different it
   runs `nsupdate` to replace the record (TTL 604800) and stores the new IP in
   the token file.

`dynproxy.net` is a **dynamic** BIND zone on ns1 (`allow-update` permits the
`nsupdate-key` TSIG key and anything from localhost). Changes go through DDNS
and are journaled in `db.dynproxy.net.jnl`, then NOTIFYed to slaves ns2/ns3 —
see [server-side.md](server-side.md#bind-zone-configuration).
5. Everything is logged to `/var/log/dynProxy.log` on ns1 and
   `/var/log/update_zone.log` on the client.

See [operations.md](operations.md) for log formats, file locations and
troubleshooting.
