+++
title = "Usage Statistics"
description = "Optional anonymous counts, kept only on the server that hosts the editor."
+++

`yoshida-server` can count how the editor is used. It is a demo of a privacy-first design: the counts **stay on the server that hosts the editor**, nothing is uploaded anywhere else, and no project content is ever part of them. People using the editor choose how much to share, and the person running the server chooses what is possible.

A copy of the editor that is opened from plain files, or served by anything other than `yoshida-server`, has nobody to send to and sends nothing. The [CLI](@/docs/command-line.md) never sends anything.

The editor on the project's website is such a copy: it collects nothing. The numbers on the site's [Stats](@/stats.md) page are counted by GitHub, not by the editor.

## Levels

| Level | What the editor sends | What the server stores |
| --- | --- | --- |
| **Off** | Nothing | Nothing |
| **Basic** | One anonymous ping per editor session: `{"level":"basic"}` | Per UTC day: the number of sessions and the number of unique visitors |
| **Advanced** | Basic, plus a count for each feature used, export format and error code, as a group and a short name (`feature` / `layer.add.rect`) | The same totals per day, plus one counter per name |

Advanced only ever carries a group (`feature`, `export`, `error`) and a short lowercase name. The server refuses anything else (names over 40 characters, capitals, spaces, an error name that is not a four-digit [diagnostic code](@/docs/diagnostics.md)) and stops adding new names beyond 400 per day. Text, file names, card data, layer names and numbers from your project are never sent. Error codes count once per session and code; the editor checks the project after every edit, so counting every check would only measure typing.

### How visitors are counted without an ID

There is **no ID in the browser**: no cookie, no local-storage token. The browser stores only your own choice of level.

The server counts unique visitors per day by hashing `daily random salt + client address + user agent` with SHA-256. The salt exists only in the server's memory and is replaced at UTC midnight, and the hashes are held in memory for that day only. The address is used for that one hash and is never written to disk or to the log. Consequences:

- A visitor on two days counts twice (the stats say so: **daily uniques**).
- A server restart forgets the day's hashes, so a visitor who returns the same day after a restart counts again.
- Behind a reverse proxy every request comes from the proxy's address, which collapses all visitors into a few. Start the server with `--telemetry-trust-proxy` (only when a proxy you control sets `X-Forwarded-For`).
- The counts are advisory. Anybody can send requests to the endpoints and inflate them; the server only limits the size and the vocabulary.

## What the person in the editor sees

- **Start-up notice.** The first time (and again when the notice text changes) a card asks which level to use, with the server's default preselected. **Nothing is sent before the notice was shown and confirmed**, not even a ping.
- **Privacy** (top bar) opens the settings: the level, what each level collects, the full list of event names, and **Sent from this browser**, a live list of every ping and event this browser sent (or queued) with its status.
- **Download my data** saves that local log, with the settings, as `yoshida-telemetry-log.json`. It is a copy of what this browser keeps; the server stores totals only, so it holds nothing it could return per person.

## Server settings

| Option | Environment variable | Default | Meaning |
| --- | --- | --- | --- |
| `--no-telemetry` | `YOSHIDA_TELEMETRY=0` | on | No endpoints, no storage, no notice in the editor |
| `--telemetry-dir` | `YOSHIDA_TELEMETRY_DIR` | `telemetry-data`, `/data` in the Docker image | Folder for the daily files and `public.json`, see [Where the counts are stored](#where-the-counts-are-stored) |
| `--telemetry-default` | `YOSHIDA_TELEMETRY_DEFAULT` | `basic` | `off`, `basic` or `advanced`: the level the notice preselects, and the level for people who never confirmed one |
| `--telemetry-force` | `YOSHIDA_TELEMETRY_FORCE` | none | `off` or `basic`: locks the level for everybody |
| `--telemetry-retention-days` | `YOSHIDA_TELEMETRY_RETENTION_DAYS` | `90` | Days of counts to keep. `infinite` (or `0`) keeps everything |
| `--telemetry-trust-proxy` | `YOSHIDA_TELEMETRY_TRUST_PROXY=1` | off | Count visitors by the first `X-Forwarded-For` address |
| `--admin-token` | `YOSHIDA_ADMIN_TOKEN` | none | Enables the [admin page](#admin-page); at least 16 characters. Prefer the environment variable: command-line arguments are visible to other users |

**A server can only lower, never raise.** `--telemetry-force` accepts `off` and `basic` only; `advanced` is refused at start-up. A forced level cannot be changed in the editor, the notice becomes a banner without a choice, and the settings explain the lock. The server also enforces it: a forced server refuses events, and counts every ping as basic. Advanced stays something people opt in to themselves.

**Retention.** Old days are deleted when the server starts and once per UTC day. Everything is a total per day, so there is nothing finer to delete.

## Where the counts are stored

The counts are small JSON files in one folder: one file per day (`2026-11-09.json`) and `public.json` with the public flags. Files are written every 15 seconds when something changed, so a crash loses seconds, not days. To back the counts up, copy the folder; to start over, stop the server and delete its files.

**One rule:** the user the server runs as must be able to write in the folder. The server tries a write when it starts and says in its first lines where the data goes:

```
telemetry: default basic, keeping 90 days, data in /data
```

`data in memory only` means the folder cannot be used. The line before it names the folder and the reason, and the counts are then lost when the server stops.

| Message | Meaning | Fix |
| --- | --- | --- |
| `cannot create the data folder ... (AccessDenied)` | The folder does not exist and the server may not create it there | Create it yourself and make it writable for the server's user, or choose another folder |
| `cannot write to the data folder ... (AccessDenied)` | The folder exists but belongs to somebody else | Change its owner (Docker: `sudo chown 65534:65534 folder`) |
| `cannot write to the data folder ... (ReadOnlyFileSystem)` | The folder is mounted read-only | Mount it writable |

**The binary.** The folder is `telemetry-data` in the directory the server is started from; it is created on first start. Choose another one with `--telemetry-dir`:

```sh
./yoshida-server --web web --telemetry-dir /var/lib/yoshida
```

**Docker Compose.** Nothing to set up: the image stores the counts in `/data`, and `compose.yaml` keeps that folder in the volume `yoshida-data`. The counts survive `docker compose down`, a restart and a rebuild; `docker compose down -v` deletes them. Leave `YOSHIDA_TELEMETRY_DIR` out of `.env`.

```sh
docker compose up --build -d
docker compose logs yoshida | grep telemetry     # ... data in /data
docker compose cp yoshida:/data ./yoshida-backup # a copy of the counts
```

**Docker without Compose.** Name a volume, or mount a folder of your own. A named volume gets the right owner by itself; a folder from the host keeps its owner, so hand it to the container's user (uid `65534`) first:

```sh
docker run -p 8080:8080 -v yoshida-data:/data yoshida

mkdir yoshida-data && sudo chown 65534:65534 yoshida-data
docker run -p 8080:8080 -v "$PWD/yoshida-data:/data" yoshida
```

Without either, the counts live in a volume that Docker creates for that one container and are gone when the container is removed.

## Admin page

With an admin token set, `/admin/telemetry` shows the stats in the same style as the public page: totals with a line per day, worked-out numbers (the last 7 days against the 7 before, the share of sessions at the Advanced level, sessions per visitor-day, the busiest day, sessions by weekday), the events by group with exports as a share of all exports and events per session, a table per day, and the public flags. The worked-out numbers are added up in the browser from the same counts; nothing new is collected. It is not linked anywhere, answers 404 when no token is set, and asks for the token on the page; the token goes in an `Authorization` header (never in the URL) to `GET /api/admin/stats`. A wrong token is answered after a short delay. There is no TLS on the server, so put it behind a reverse proxy with HTTPS before you use the page over a network.

## Public stats

The admin page lets you tick which stats are public. Ticked stats are served to everybody, as JSON, by `GET /api/stats?days=30` (1 to 366 days):

```json
{
	"retention_days": 90,
	"days": [
		{ "day": "2026-11-09", "sessions": 42, "events": { "feature:layer.add.rect": 17 } }
	]
}
```

A flag is a base stat (`sessions`, `uniques`, `advanced_sessions`), a group (`feature`, `export`, `error`) that includes every event in it, or one event (`export:pdf`). Nothing is public until you tick it. The endpoint sends `Access-Control-Allow-Origin: *`, so a web page can show your numbers.

The server also shows them as a page: `/api/stats/page` (for example `http://localhost:8080/api/stats/page`) has the totals for sessions and visitors with a line per day, and the events as bars per group (exports with their share). When the matching counts are public it also shows the worked-out numbers and the weekday pattern. It reads the same `GET /api/stats`, so it never shows more than you ticked, and it says so when nothing is public. It needs no token, loads nothing from other servers and follows the light or dark theme chosen in the editor. The admin page links to it, and so does **Privacy** in the editor (**Public stats**). With `--no-telemetry` it answers 404 like the other endpoints.

## Not included

Central collection is not part of this: counts are never sent to the yoshida project or anybody else. If you want numbers from several servers you can read each one's admin API yourself.
