# UniPakt

Source of [unipakt.com](https://unipakt.com), the website and members' panel of **UniPakt Öğrenci Kulüpleri Topluluğu**: a network that connects university clubs across Istanbul so they can run joint events and support each other.

UniPakt is a network of clubs, not a single club and not a student social app. The public site presents the network, its clubs and its events; the panel is where clubs and the UniPakt team do their work.

## What is in here

| Part | File | What it does |
| --- | --- | --- |
| Public site | `index.html` | The whole public site in one file. Each path shows a different section: home, story, calendar, clubs, club and event pages, sponsors, contact, join form, KVKK notice and the HACKFEST27: MIXIT pages. |
| Panel | `panel.html` | Sign-in area for clubs and the UniPakt team: announcements, joint events and partnership offers, approvals, event registrations, unit workspaces (Sponsorluk, Sosyal Medya, Halkla İlişkiler, Kulüp İlişkileri, Denetim and others), messaging and optional e-mail two-factor sign-in. |
| Check-in | `kontrol.html` | Door check-in page for events. Scans the QR code on a registration with the phone camera. |
| Not found | `404.html` | Shown for unknown paths. |

Shared pieces:

- `theme.js` applies the brand colour, which is stored in the database and set from the panel, and repaints the logos to match.
- `unit-files.js` handles private file attachments in the unit workspaces.
- `i18n/` holds the translations of the public site (12 languages). Turkish is the source language and lives in `index.html`.
- `src/` holds the three modules built with Vite: the Matrix chat client used by the panel, and the QR maker and scanner.
- `brand/`, `fonts/`, `sponsors/`, `hackfest-media/`, `assets/` hold logos, fonts and images.

## Technology

- Static HTML, CSS and JavaScript with no framework. No cookies and no analytics.
- [Supabase](https://supabase.com) for sign-in, the PostgreSQL database, file storage and Edge Functions. See [`supabase/README.md`](supabase/README.md).
- A private Matrix (Synapse) server at `chat.unipakt.com` for panel messaging. See [`matrix-server/README.md`](matrix-server/README.md).
- GitHub Pages for hosting, built and published by GitHub Actions.

## Repository layout

```
index.html, panel.html, kontrol.html, 404.html   pages
theme.js, unit-files.js                          shared scripts
i18n/                                            translations of the public site
src/                                             Vite sources (chat client, QR helpers)
supabase/schema.sql                              snapshot of the database
supabase/migrations/                             database changes, one file per change
supabase/functions/                              Edge Functions
matrix-server/                                   chat server setup (Docker Compose, Caddy)
tools/build_pages.py                             builds the published folder (_site/)
tools/brand.py                                   repaints logos with the brand colour
tests/                                           unit workspace tests
docs/                                            notes on larger changes
.github/workflows/pages.yml                      build and deploy
```

## Running locally

You need Node.js 22, pnpm and Python 3.12.

```sh
pnpm install --frozen-lockfile
pnpm run build:matrix        # chat client  -> assets/matrix/
pnpm run build:qr            # QR helpers   -> assets/qr/
python -m pip install pillow numpy
python tools/build_pages.py  # builds _site/
python -m http.server -d _site
```

Then open <http://localhost:8000>.

GitHub Pages cannot rewrite paths, so `build_pages.py` writes one copy of `index.html` per route (`_site/takvim/index.html`, and so on), each with its own title, description and link preview. It also reads the published events and the current brand colour from the live database, so it needs an internet connection.

## Tests

```sh
pnpm test              # unit workspace permissions and migrations
pnpm run test:browser  # browser test with Playwright
```

## Deployment

Every push to `main` builds the site and publishes it to unipakt.com. The same workflow also runs once an hour, so new event share pages and brand colour changes go live without a push. The workflow is [`.github/workflows/pages.yml`](.github/workflows/pages.yml).

## Database

Database changes live in `supabase/migrations/`, named `YYYYMMDD_description.sql`. They are applied to the database separately from a code push. Secrets such as service keys are never stored in this repository.

More detail:

- [`supabase/README.md`](supabase/README.md): database layout and the functions the public site calls
- [`SQL-CALISTIRMA-SIRASI.md`](SQL-CALISTIRMA-SIRASI.md): order for running the unit workspace SQL files (Turkish)
- [`KOD-KURULUM.md`](KOD-KURULUM.md) and [`docs/unit-workspace-renewal.md`](docs/unit-workspace-renewal.md): unit workspace delivery notes (Turkish)

## Contact

- General: iletisim@unipakt.com
- Sponsorship: sponsorluk@unipakt.com

## License

No licence has been chosen yet. Licensing information will be added later.

---

Digitally crafted by Flower Studios.
