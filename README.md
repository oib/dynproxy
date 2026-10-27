# dynproxy

Self-hosted dynamic-DNS service for `dynproxy.net`. Clients detect public-IP
changes and POST a token + IP to `ip.dynproxy.net`; ns1 validates the token and
updates the dynamic BIND zone via `nsupdate` (propagated to slaves ns2/ns3).

## Layout

- `docs/` — full documentation: architecture, client/server scripts, nginx
  site, operations. Start with [docs/README.md](docs/README.md).
- `scripts/client/` — reference copy of the client-side updater
  (`update_zone.sh`, deployed as `/root/scripts/update_zone.sh` on each host).
- `scripts/server/` — reference copies of the ns1-side scripts
  (`/root/scripts/dynProxy_create_subdom_token.sh`, and the fcgiwrap CGI
  scripts from `/var/www/ip/scripts/`).
- `examples/` — config examples, e.g. `nginx-ip-site.conf`
  (`/etc/nginx/sites-enabled/ip` on ns1).

These are reference copies of files that live on the hosts — the repo is the
documentation of record, not a deployment mechanism.
