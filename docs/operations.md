# Operations: logs, files, troubleshooting

## Log files

| File | Host | Written by | Content |
|---|---|---|---|
| `/var/log/dynProxy.log` | ns1 | `/var/www/ip/scripts/update_zone.sh` | Every `/update_zone` request: start, raw POST body, validation failures, nsupdate results |
| `/var/log/update_ip.log` | ns1 | `update_ip.sh` | One line per `/update_ip` call: `IPv4/IPv6 <ip> saved with token <token>` |
| `/var/log/update_zone.log` | each client | `/root/scripts/update_zone.sh` | Token read, IP fetched, change detection, HTTP result |

All use `date '+%Y-%m-%dT%H:%M:%S.%6N'` microsecond timestamps, e.g.:

```
2026-10-27T17:08:46.942693: Starting DNS update script.
2026-10-27T17:08:46.945982: Received POST data:
2026-10-27T17:08:46.955569: Missing token
```

## Key files on ns1

| Path | Purpose |
|---|---|
| `/var/www/ip/token/<token>.txt` | Per-client token file. Existence = valid token; content = last known IP (written by `update_ip`/`update_zone`) |
| `/etc/bind/tokendnszone.conf` | CSV mapping `token,fqdn,zone-file` (see [server-side.md](server-side.md)) |
| `/etc/bind/nsupdate_key.conf` | TSIG key used by the provisioning script |
| `/etc/bind/zones/db.dynproxy.net` (+ `.jnl`) | Dynamic BIND zone file + journal — never hand-edit without `rndc freeze/thaw` (see [server-side.md](server-side.md#bind-zone-configuration)) |
| `/etc/bind/keys/nsupdate-key.key`, `/etc/bind/named.conf.local` | TSIG key and zone config (`allow-update`, slaves ns2/ns3) |

## Adding a new client

1. On ns1: `sudo /root/scripts/dynProxy_create_subdom_token.sh`, enter
   subdomain + domain. Note the generated token filename under
   `/var/www/ip/token/`.
2. Append `<token>,<fqdn>,<zone-file>` to `/etc/bind/tokendnszone.conf`.
3. On the client: write the token into `/root/.dynProxy_token` and install the
   client `update_zone.sh` (see [client-update-zone.md](client-update-zone.md))
   in root's crontab.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `dynProxy.log` shows `Missing token` with empty POST body | Scanner/bot hitting the endpoint (very common — see log history), or a client posting to the wrong URL/format |
| `Token file not found` | Token file deleted, or client using a token that was never provisioned |
| `Token mapping not found` | Token file exists but no line in `tokendnszone.conf` (provisioning step 2 skipped) |
| `Failed to extract ZONE_IP` | A record missing/misformatted in the zone file; awk expects `<name> A <ip>` |
| Client says success but DNS unchanged | Check `dynProxy.log` — `nsupdate` may have failed; the script also reports "already up-to-date" when the zone already has the IP |
| `update_ip` works, `update_zone` fails | Different token charsets: `update_zone` only accepts `[a-zA-Z0-9_-]` and IPv4 IPs |

## Security notes

- All traffic is plain HTTP — tokens are sent unencrypted.
- Tokens are single-factor bearer credentials; anyone with the token can point
  the DNS record at an arbitrary IPv4 address.
- Tokens and last IPs appear in plaintext in server logs (`DEBUG=true` also
  echoes them into HTTP responses).
- `update_zone.sh` interpolates POST data into the `nsupdate` heredoc — the
  regex extraction limits this to safe characters, but treat the input as
  untrusted.
