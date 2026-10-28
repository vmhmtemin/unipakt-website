# UniPakt Matrix homeserver

This is a private Matrix Synapse deployment for the UniPakt panel. It uses a dedicated PostgreSQL database and Caddy TLS termination. The server name and URL are `chat.unipakt.com`; point that DNS name to the VPS before starting Caddy. Keep `.env`, `synapse/data/homeserver.yaml`, signing keys, database files, and backups on the server only.

## First setup

1. Create a VPS with Docker Compose, open inbound ports 80 and 443, and set the `chat.unipakt.com` A/AAAA records to its IP.
2. Copy `.env.example` to `.env` on the server and replace the database password with a unique random value.
3. Generate Synapse's initial configuration and signing key:

   ```sh
   docker compose run --rm synapse generate
   ```

4. Edit `synapse/data/homeserver.yaml` on the server. Configure its database to use host `db`, database/user `synapse`, and the password in `.env`. Keep registration disabled, set `federation_domain_whitelist: []`, and leave the generated signing key path in place.
5. Start the services with `docker compose up -d`. Caddy will obtain and renew the HTTPS certificate.
6. Create one Synapse administrator account using Synapse's `register_new_matrix_user` utility. Keep its access token out of the repository.
7. Add these Supabase Edge Function secrets:
   - `MATRIX_HOMESERVER_URL=https://chat.unipakt.com`
   - `MATRIX_SERVER_NAME=chat.unipakt.com`
   - `MATRIX_ADMIN_ACCESS_TOKEN=<the Synapse administrator access token>`
   - `MATRIX_ACCOUNT_DERIVATION_SECRET=<a separate long random secret>`

The panel's Supabase account remains the user's only login. A server-side Edge Function maps that account to a private Matrix identity and returns a device session; Matrix passwords and the Synapse admin token are never sent to the browser. Encrypted room content stays unreadable to Synapse, while room membership and timing metadata remain visible to the homeserver.

## Operations

Back up PostgreSQL and the full `synapse/data` directory together. Test restores before upgrading. Upgrade Synapse by changing the pinned image tag and reviewing the official release notes first. Do not expose the PostgreSQL port or Synapse's 8008 port publicly.
