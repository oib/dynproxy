# nginx site: `/etc/nginx/sites-enabled/ip` (ns1)

vHost for `ip.dynproxy.net`, plain HTTP on port 80 (IPv4 + IPv6, IPv6 is
`default_server`). Dynamic endpoints go through **fcgiwrap**
(`unix:/run/fcgiwrap.socket`), which executes zsh CGI scripts under
`/var/www/ip/scripts/`.

## Routing table

| Location | Handler | Purpose |
|---|---|---|
| `/` | fastcgi → `/var/www/ip/scripts/ip.sh` | Echo client `$REMOTE_ADDR` (public-IP discovery) |
| `/update_ip` | fastcgi → `/var/www/ip/scripts/update_ip.sh` | Store caller IP in token file (no DNS change) |
| `/update_zone` | fastcgi → `/var/www/ip/scripts/update_zone.sh` | Validate token, run `nsupdate`, update A record |
| `/lua_test` | `proxy_pass http://127.0.0.1:8080` (+ `proxy_params`) | Test backend; a commented `content_by_lua_block` variant exists below |
| `/token/` | `deny all; return 403` | Blocks web access to the token directory |

## Config notes

- `fastcgi_params` is included for every fcgiwrap location; each sets
  `SCRIPT_FILENAME` to the concrete script path.
- No TLS — all update traffic (including tokens) is cleartext. Anything beyond
  localhost relies on the obscurity of the token.
- `/token/` returns 403 as defense-in-depth even though tokens live in
  `/var/www/ip/token` and there is no `location` serving that tree.
