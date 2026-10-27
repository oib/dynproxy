# Client-side updater: `/root/scripts/update_zone.sh`

**Location:** each dynDNS client host (e.g. at1), run as root (typically via cron).
**Shebang:** `#!/bin/zsh` — **Version:** 10.6

Polls the host's public IP and triggers a DNS zone update on the dynProxy
server when it changes.

## Files used

| Path | Purpose |
|---|---|
| `/root/.dynProxy_token` | Client token (must exist and be non-empty; contents of a single line) |
| `/root/.ip.txt` | Cache of the last known public IP (auto-created on first run) |
| `/var/log/update_zone.log` | Local log file |
| `http://ip.dynproxy.net` | GET → returns the caller's public IP |
| `http://ip.dynproxy.net/update_zone` | POST endpoint for updates |
| `/tmp/curl_output` | Temp file for the update response body (removed afterwards) |

## Behavior

1. Detects whether stdout is a TTY (`INTERACTIVE`); prints human messages only
   when run interactively. Always appends to the log file.
2. If stdin is a TTY it emits `Content-Type: text/plain` headers first (so the
   same script can be invoked manually without confusing output expectations).
3. Reads the token from `/root/.dynProxy_token`; exits 1 if missing/empty.
4. Fetches the current public IP: `curl -s http://ip.dynproxy.net`; exits 1 on
   failure.
5. If `/root/.ip.txt` does not exist, creates it with the current IP and treats
   the previous IP as empty (forces the update path).
6. If the IP changed since the last run, POSTs:

   ```
   POST http://ip.dynproxy.net/update_zone
   Content-Type: application/x-www-form-urlencoded

   token=<token>&ip=<ip>
   ```

   (both fields `--data-urlencode`d).
7. On HTTP 200: writes the new IP to `/root/.ip.txt`, logs `SUCCESS`.
   Otherwise logs the HTTP code and response body, exits 1.
8. Removes `/tmp/curl_output`.

## Log format

```
2026-10-27T17:08:46.942693: INFO: IP has not changed. No update needed.
```

Microsecond timestamps, level prefixes: `INFO`, `SUCCESS`, `ERROR`.

## Notes / caveats

- The log line on success includes the full token in plaintext.
- Update traffic is plain HTTP — the token is not encrypted in transit.
- No locking: overlapping cron invocations could race on `/root/.ip.txt`.
