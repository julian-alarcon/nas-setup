# NAS Setup

NAS Setup with TrueNAS

## Installation

[TruenNAS SCALE 25.10](https://www.truenas.com/download/) iso image.
Create boot USB with `dd status=progress if=path/to/.iso of=path/to/USB`.

### Decrease pool for OS installation

[Source](https://www.truenas.com/community/threads/howto-split-ssd-with-boot-pool-to-create-partition-for-data-no-usb-install-easy-config-migration.102641/)

Before installing, select shell. Edit file `vi /usr/sbin/truenas-install` and change
line

```sh
    # Create boot pool
    if ! sgdisk -n3:0:0 -t3:BF01 /dev/${_disk}; then
        return 1
    fi
```

to

```sh
    # Create boot pool
    if ! sgdisk -n3:0:+32GiB -t3:BF01 /dev/${_disk}; then
        return 1
    fi
```

Then execute `truenas-install`. Installation will perform with the desired size
instead of using the full partition

If you need SWAP you can select to set it, it will not mess with the size previously
selected (but, of course will create a new partition of E.g. 16 GB).

## Setup

### System Setup

#### Fan control

```sh
chmod +x /usr/bin/apt
chmod +x /usr/bin/apt-key
chmod +x /usr/bin/dpkg

apt install fancontrol

sensors-detect (yes to discover to /etc/modules)
systemctl start kmod
pmwconfig
fancontrol
systemctl start fancontrol
```

### Network setup

1. Login to HTTPS address: [https://192.168.0.99](https://192.168.0.99)
2. Setup password
3. Select name: `nas-hostname`
4. Setup IP
   - IP: `192.168.1.200/24`
   - Gateway: `192.168/0/1`
   - Nameservers: `194.242.2.2, 9.9.9.9, 192.168.0.1`

### User setup

Credentials > Users
User: admin
Email: `<my-personal-email>@<mydomain.com>`

### Email Options

SMTP: `Checked`
From Email: `<my-nas-email>@<mydomain.com>`
From Name: `<NAME> TrueNAS`
Outgoing Mail Server: `my-smtp-server`
Mail Server Port: `587`
Security: `TLS (STARTTLS)`
SMTP Authentication: `Checked`
Username: `<username-for-smtp>`
Password: `<password-for-smtp>`

### Disk setup for VMs/Containers

#### Setup Partition

From previously available disk space, it's needed to create a partition

Commands:

```sh
fdisk -l /dev/nvme0n1
gdisk /dev/nvme0n1
    Command: p

    Number  Start (sector)    End (sector)  Size       Code  Name
   1            4096            6143   1024.0 KiB  EF02
   2            6144         1054719   512.0 MiB   EF00
   3        34609152       101718015   32.0 GiB    BF01
   4         1054720        34609151   16.0 GiB    8200
   5       101718016       488396799   184.4 GiB   BF01  Solaris /usr & Mac ZFS

gdisk /dev/nvme0n1
    Command: n, then default values

    Command: p

gdisk /dev/nvme0n1
    Number  Start (sector)    End (sector)  Size       Code  Name
   1            4096            6143   1024.0 KiB  EF02
   2            6144         1054719   512.0 MiB   EF00
   3        34609152       101718015   32.0 GiB    BF01
   4         1054720        34609151   16.0 GiB    8200
   5       101718016       488396799   184.4 GiB   BF01  Solaris /usr & Mac ZFS
```

#### Setup ZFS configuration

Create the zpool

```sh
zpool create ssd-storage /dev/nvme0n1p5
```

Export (Unmount) the partition, this is required to be imported by TrueNAS system.

```sh
zpool export ssd-storage
```

Useful commands:

```sh
zpool status
```

Now in the TrueNAS Web UI go to **Storage** -> **Import Pool** button and select
the pool to import (E.g. `ssd-storage`).

Setup monthly Scrub Task.

### Disk setup

#### Setup zpool

##### Personal Files

Set name and 2 disks (Mirror)
Set permissions to `apps` user and group

##### Backup Files

Set name and 2 disks (Mirror)
Set permissions to `apps` user and group for `movies-series`
Add `.ignore` file to this to exclude from [Jellyfin scan](https://jellyfin.org/docs/general/server/media/excluding-directory/).

### Datasets setup

#### Create Datasets for Apps

Create `apps-data` dataset in SSD, then 1 per app, E.g.: `apps-data/immich`.
Select as Dataset Preset `Apps`

### Applications setup

Each app's full compose/config file lives under [`config/`](config/) and is
linked from its section below. Commands and short snippets stay inline.

#### Jellyfin

Install from Applications (`community`)

Dataset:

- `ssd-storage/apps-data/jellyfin`

##### Installation setup

WebUI Port: `30013`
Jellyfin Config Storage:
Type: `Host Path`
Host Path: `/mnt/ssd-storage/apps-data/jellyfin`
Jellyfin Cache Storage:
Type: `ixVolume`
Jellyfin Transcode Storage:
Type: `tmpfs`
Additional Storage:
Type: `Host Path`
Mount path: `/media/movies-series`
Host path: `/mnt/backup-and-downloads/movies-series`
Passthrough available (non-NVIDIA) GPUs: `Checked`

##### Web setup

Username: admin-jellyfin

Media Library add
Content type: `Mixed Movies and Shows`
Display name: `Movies and TV Shows`
Folders: `/media/movie-series`

Libraries:
Collection (Movies and TV Shows) -> Manage Library
Subtitle Downloads, Download languages: Spanish; Latin, Spanish; Castilian, English
Subtitle downloaders: Open Subtitles

Playback:
Transcoding:
Hardware acceleration: Intel QuickSync (QSV) (This value depends on the GPU available)
VA-API Device: /dev/dri/renderD128 (can be obtained from `ls -l /dev/dri`)
Enable hardware decoding for: (Can be obtained from `/usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128`)
_ H264: checked
_ HEVC: checked
_ MPEG2: checked
_ VC1: checked
_ VP8: checked
_ VP9: checked
_ AV1: checked
_ HEVC 10bit: checked
_ VP9 10bit: checked
_ HEVC RExt 8/10bit: checked
_ HEVC RExt 12bit: checked
_ Prefer OS native DXVA or VA-API hardware decoders: checked
Hardware encoding options:
_ Enable hardware encoding: checked
_ Enable Intel Low-Power H.264 hardware encoder: checked
_ Enable Intel Low-Power HEVC hardware encoder: checked
Encoding format options:
_ Allow encoding in HEVC format: checked \* Enable VPP Tone mapping: checked

> Review of GPU usage can be made in TrueNAS shell with the command `sudo intel_gpu_top`

##### Plugins setup

- Opensubtitles: Username, password, API

- AniDB

##### Settings

Dashboard -> Scheduled tasks -> Download missing subtitles

#### qBittorrent

##### gluetun app

Dataset: `ssd-storage/apps-data/gluetun`

Set new custom app with name `custom-app-gluetun`. Install via custom YAML
using [`config/qbittorrent/gluetun-compose.yml`](config/qbittorrent/gluetun-compose.yml).

##### qBittorrent app

Dataset:

- `ssd-storage/apps-data/qbittorrent`

Set new custom app with name `custom-app-qbittorrent`. Install via custom YAML
using [`config/qbittorrent/qbittorrent-compose.yml`](config/qbittorrent/qbittorrent-compose.yml).

##### qBittorrent Web UI settings

Options:

- Web UI -> Authentication -> Password: New Password
- Web UI -> Authentication -> By pass authentication for clients on localhost
- Web UI -> Authentication -> By pass authentication for clients in whitelisted IP subnets: 192.168.0.0/24
- Advanced -> Network interface: tun0
- Optional IP address to bind to: All IPv4 address
- Downloads -> Default Save Path: `/media`
- Downloads -> Keep incomplete torrents in: `/media/downloads/torrents/incomplete`
- Downloads -> Copy .torrent files to: `/media/downloads/torrents`
- Downloads -> Copy .torrent files for finished downloads to: `/media/downloads/torrents`
- Connection -> Port used for incoming connections: 6881 (Not needed to modify as network is using glutun)
- Connection -> Global maximum number of connections: unchecked
- Connection -> Maximum number of connections per torrent: unchecked
- Connection -> Global maximum number of upload slots: unchecked
- Connection -> Maximum number of upload slots per torrent: unchecked
- BitTorrent -> Torrent Queueing
  - Maximum active downloads: 10
  - Maximum active uploads: 3
  - Maximum active torrents: 15
- BitTorrent -> When total seeding time reaches: 60 minutes
  When inactive seeding time reaches: 120 minutes
  then: Pause torrent

- Search tab -> Search plugins... -> Check for updates
  - [Install plugins](https://github.com/qbittorrent/search-plugins/wiki/unofficial-search-plugins)

###### Test VPN connection on qBittorrent

Enter to shell for qbittorrent container and check `curl https://ipleak.net/json/`

#### DNS model

With a single ISP public IP, use one dynamic **anchor** host and point every
service at it with a static CNAME.

- **Anchor** `YOUR_ANCHOR_DOMAIN`: `A` + `AAAA` -> the home public IP. This is
  the **only** record `ddns-updater` maintains.
- **Services** (one subdomain per app, and any new one): a static `CNAME` ->
  `YOUR_ANCHOR_DOMAIN`. Created once, never edited; they inherit the anchor's
  IPv4/IPv6 automatically.
- **Apex** (root domain): left free (reserved for a future landing page). Apex
  and home IP stay decoupled.

Rules:

- Keep every NAS record **unproxied** (DNS resolves straight to the home IP). A
  CDN/proxy in front would not pass the custom port `35000` and would break
  Traefik's TLS.
- Use **explicit CNAMEs per service**, not a `*` wildcard. A wildcard resolves
  every possible name to the home IP (wider attack surface); explicit records
  mean only intended hostnames resolve.
- Adding a service = one CNAME + one Traefik router. No `ddns-updater` change, no
  new port-forward.

#### ddns-updater

Install from Applications (`community`)

Dataset:

- `ssd-storage/apps-data/ddns-updater`

WebUI Port: `30007`
Host path: /mnt/ssd-storage/apps-data/ddns-updater

##### DNS provider prerequisites

1. Create the anchor `YOUR_ANCHOR_DOMAIN` as `A` (+ `AAAA` for IPv6) pointing at
   any placeholder IP; the updater overwrites it on first run. Keep it unproxied
   so Traefik can complete the Let's Encrypt challenge and reach the origin.
2. Get the zone ID and create a DNS-edit API token scoped to that zone.

##### App config

Configure a **single** entry for the anchor `YOUR_ANCHOR_DOMAIN` (provider, IP
version `ipv4` + `ipv6`, zone ID, API token). Every service hostname is a static
CNAME to this anchor, so it needs no `ddns-updater` entry of its own.

#### Traefik reverse proxy setup

Dataset:

- `ssd-storage/apps-data/traefik`

##### Set certificates and config

Create the directory and `acme.json` file for certificates. The storage target
is a **file**, not a directory. Traefik refuses to start if `acme.json` is more
permissive than `600`.

```sh
mkdir -p  /mnt/ssd-storage/apps-data/traefik/letsencrypt
touch     /mnt/ssd-storage/apps-data/traefik/letsencrypt/acme.json
chmod 600 /mnt/ssd-storage/apps-data/traefik/letsencrypt/acme.json
chmod 700 /mnt/ssd-storage/apps-data/traefik/letsencrypt
```

Add configuration to file `/mnt/ssd-storage/apps-data/traefik/traefik_dynamic.yml`
(copy from [`config/traefik/traefik_dynamic.yml`](config/traefik/traefik_dynamic.yml) and fill in
`YOUR_*` domains and the dashboard `basicAuth` hash):

##### Traefik app

Set new custom app with name `custom-app-traefik`. Install via custom YAML
using [`config/traefik/compose.yml`](config/traefik/compose.yml). Fill in the
`YOUR_DNS_PROVIDER`, `DNS_API_TOKEN`, and your Let's Encrypt email.

Port forwarding: forward **only** port `35000` (the public entrypoint) on the
router to the NAS IP.

> [!IMPORTANT]
> Do **not** port-forward `35001`. That is the dashboard entrypoint and must
> stay LAN-only. Forwarding it would expose the Traefik dashboard to the
> internet (basicAuth would be the only thing protecting it).

##### Dashboard access (LAN-only)

The dashboard is on the `dashboard` entrypoint (port `35001`), reached by the
NAS LAN IP, so it is unreachable from the internet as long as `35001` is not
port-forwarded. It is served over plain HTTP (the Let's Encrypt cert is for the
public hostname, not the IP), with basicAuth gating access.

1. Generate the basicAuth hash and replace `REPLACE_WITH_YOUR_BCRYPT_HASH` in
   the `dashboard-auth` middleware:

   ```sh
   htpasswd -nbB admin 'YOUR_STRONG_PASSWORD'
   # no htpasswd available:
   # openssl passwd -apr1 'YOUR_STRONG_PASSWORD'   # then prefix with "admin:"
   ```

2. From a LAN host, open `http://192.168.1.200:35001/dashboard/` (trailing
   slash required) and authenticate with the `admin` user.

#### Immich

Install from Applications (`community`)

Datasets:

- `ssd-storage/apps-data/immich`
- `personal-media/immich`

Create directories

```sh
mkdir -p /mnt/personal-media/immich/data/{upload,thumbs,library,profile,backups,encoded-video}
mkdir -p /mnt/ssd-storage/apps-data/immich/pgData
```

##### Installation setup

Timezone: `'Europe/Berlin' timezone`
Enable Machine Learning: **Checked**
Machine Learning Image Type: `Default Machine Learning Image`
Database Password: `THE_NEW_DB_PASSWORD`
Redis Password: `THE_NEW_REDIS_PASSWORD`
Log Level: `Log`
WebUI Port: `30041`
Data Storage (aka Upload Location):
Type: `Host Path`
Host Path: `/mnt/personal-media/immich/data`
Postgres Data Storage:
Type: `Host Path`
Host Path: `/mnt/ssd-storage/apps-data/immich/pgData`

##### Web setup

Enter to the WebUI and set the default username (email) and password for
`admin` user.

Server Settings:
External domain: `https://YOUR_IMMICH_DOMAIN:35000`
Storage Template:
Enable storage template engine: **Checked**
Template preset: `2022/2022-02-03/IMAGE_56437`
Notification Settings > Email:
Host: `my-smtp-server`
Port: `587`
Username: `<username-for-smtp>`
Password: `<password-for-smtp>`
From address: `<immich@>`

#### DoTheSplit

[https://github.com/julian-alarcon/DoTheSplit/](https://github.com/julian-alarcon/DoTheSplit/)

Expense-sharing app. Custom App published through Traefik at
`https://YOUR_DOTHESPLIT_DOMAIN:35000/`. Full walkthrough in the project's
`INSTALL.md`; below is the NAS-specific summary.

Datasets:

- `ssd-storage/apps-data/dothesplit` (Dataset Preset: `Apps`)

A single image serves the JSON API and the embedded Vue SPA, and uses
**SQLite** (no external database). The image is distroless and runs as the
baked-in `nonroot` user **UID/GID 65532**, with no shell to fix permissions at
startup. So the host `data` directory (where `dts.db` + WAL live) must be owned
by 65532 **before** first start; do **not** apply the `Apps` preset (568):

```sh
mkdir -p /mnt/ssd-storage/apps-data/dothesplit/data
chown -R 65532:65532 /mnt/ssd-storage/apps-data/dothesplit/data
```

##### Generate the four secrets

Run once and store the output in a password manager **before** continuing.
Losing `EMAIL_ENC_KEY`, `EMAIL_HMAC_KEY`, or `PASSWORD_PEPPER` after the database
has data makes that data unrecoverable (rotating `JWT_SIGNING_KEY` only forces a
re-login).

```sh
echo "EMAIL_ENC_KEY=$(openssl rand -base64 32)"
echo "EMAIL_HMAC_KEY=$(openssl rand -base64 32)"
echo "PASSWORD_PEPPER=$(openssl rand -base64 32)"
echo "JWT_SIGNING_KEY=$(openssl rand -base64 32)"
```

##### Install the Custom App

1. **Apps -> Discover Apps -> Custom App**.
2. **Application Name**: `custom-app-dothesplit`.
3. **Install via custom YAML**: use the full config at
   [`config/dothesplit/compose.yml`](config/dothesplit/compose.yml), filling in
   the four secrets. `COOKIE_SECURE` is `true` and `WEB_ORIGIN` points at the
   public HTTPS URL because Traefik terminates TLS in front of the app.

   The single container publishes a host port (`30051` -> container `8080`); it
   serves both `/v1` and the embedded client-side Vue SPA from one origin, so the
   browser calls `/v1` directly (same origin) once the SPA loads. Traefik routes
   `YOUR_DOTHESPLIT_DOMAIN:35000` to `http://192.168.1.200:30051` (see the
   `dothesplit` router/service in the Traefik dynamic config above).

4. **Fill in the secrets directly in the YAML.** The "Install via YAML" editor
   takes only the compose file, no env-var table, no `.env`, so hardcode the
   `<EMAIL_ENC_KEY>`, `<EMAIL_HMAC_KEY>`, `<PASSWORD_PEPPER>`, and
   `<JWT_SIGNING_KEY>` values before pasting.

5. Click **Install** and watch the **Containers** tab until the service is
   healthy.

##### DNS and port forwarding

- DNS: `YOUR_DOTHESPLIT_DOMAIN` is a static CNAME -> `YOUR_ANCHOR_DOMAIN` (see
  the DNS model section); `ddns-updater` keeps the anchor current.
- Router: no new port to open. DoTheSplit reuses the existing `websecure`
  entrypoint (`35000`) that is already port-forwarded to `192.168.1.200`;
  Traefik routes it by `Host` header and obtains the certificate over the DNS
  challenge.

##### First-run setup token

The API prints a one-time setup token on first boot. From the TrueNAS shell:

```sh
docker logs custom-app-dothesplit-1 2>&1 | grep -A2 'first-run setup'
```

Open `https://YOUR_DOTHESPLIT_DOMAIN:35000/setup`, paste the token, and create
the admin account (display name + email + password >= 10 chars). The setup form
locks permanently afterwards.

##### Updates

**Apps -> dothesplit -> Edit** -> bump the `image:` tag to the new `:X.Y.Z` (no
`v` prefix), then **Save**. The app applies any schema migrations to the SQLite
DB on start.

#### Memos

[https://github.com/usememos/memos](https://github.com/usememos/memos)

Lightweight self-hosted note-taking app. Uses SQLite (no external database
needed). Published through Traefik at `https://YOUR_MEMOS_DOMAIN:35000/`
on the shared `websecure` entrypoint.

Datasets:

- `ssd-storage/apps-data/memos` (Dataset Preset: `Apps`)

The SQLite database and uploads live in the dataset root, no subdirectories to
pre-create. The Memos entrypoint starts as root, `chown`s `/var/opt/memos` to
its non-root user **UID/GID 10001**, then drops privileges, so it fixes the
mounted directory's ownership itself. No manual `chown` is needed.

##### Install the Custom App

1. **Apps -> Discover Apps -> Custom App**.
2. **Application Name**: `custom-app-memos`.
3. **Install via custom YAML**: use the full config at
   [`config/memos/compose.yml`](config/memos/compose.yml). `MEMOS_DRIVER=sqlite`
   is the default, so no database container is needed. Only the `memos`
   container publishes a host port (`30061` -> container `5230`).

4. Click **Install** and watch the **Containers** tab until the service is
   healthy.

##### DNS and port forwarding

- DNS: create a static `CNAME` `YOUR_MEMOS_DOMAIN` -> `YOUR_ANCHOR_DOMAIN`
  (unproxied), per the DNS model section. No `ddns-updater` entry needed.
- Router: no new port to open. Memos reuses the existing `websecure` entrypoint
  (`35000`); Traefik routes it by `Host` header and obtains the certificate over
  the DNS challenge.

##### First-run setup

Open `https://YOUR_MEMOS_DOMAIN:35000/` and create the admin account on
the first visit (the first registered user becomes the host/admin). Protect this
host account carefully.

Then apply the [Memos security recommendations](https://usememos.com/docs/configuration/security):

- **Settings -> System**: disable **Allow user signup** (private instance).
- **Settings -> System**: disable public memo visibility if nothing should be
  publicly reachable.
- Review who can create personal access tokens; avoid indefinitely active
  tokens and rotate any that leak.
- `MEMOS_MODE=prod` (set above) avoids demo mode's hardcoded JWT secret, never
  run demo mode in production.
- Back up the SQLite DB and attachments (both live under
  `ssd-storage/apps-data/memos`, covered by the snapshot/replication tasks
  below).

#### Vikunja

[https://vikunja.io](https://vikunja.io)

Self-hosted to-do / project management app. Uses SQLite (no external database
needed). One image serves both API and frontend. Published through Traefik at
`https://YOUR_VIKUNJA_DOMAIN:35000/` on the shared `websecure` entrypoint.

Datasets:

- `ssd-storage/apps-data/vikunja` (Dataset Preset: `Apps`)

Create the `db` and `files` subdirectories the container writes to (UID/GID 568
from the `Apps` preset):

```sh
mkdir -p /mnt/ssd-storage/apps-data/vikunja/{db,files}
chown -R 568:568 /mnt/ssd-storage/apps-data/vikunja
```

##### Generate the service secret

`VIKUNJA_SERVICE_SECRET` signs JWT tokens. If left unset Vikunja generates a
random one at each start, invalidating all sessions on restart, so set a fixed
value and store it in a password manager:

```sh
openssl rand -hex 32
```

##### Install the Custom App

1. **Apps -> Discover Apps -> Custom App**.
2. **Application Name**: `custom-app-vikunja`.
3. **Install via custom YAML**: use the full config at
   [`config/vikunja/compose.yml`](config/vikunja/compose.yml). `VIKUNJA_DATABASE_TYPE`
   is `sqlite`, so no database container is needed. Only the `vikunja` container
   publishes a host port (`30071` -> container `3456`).

4. Click **Install** and watch the **Containers** tab until the service is
   healthy.

##### DNS and port forwarding

- DNS: create a static `CNAME` `YOUR_VIKUNJA_DOMAIN` -> `YOUR_ANCHOR_DOMAIN`
  (unproxied), per the DNS model section. No `ddns-updater` entry needed.
- Router: no new port to open. Vikunja reuses the existing `websecure`
  entrypoint (`35000`); Traefik routes it by `Host` header and obtains the
  certificate over the DNS challenge.

##### First-run setup

With registration disabled, create the first user from the shell, then log in at
`https://YOUR_VIKUNJA_DOMAIN:35000/`:

```sh
docker exec -it custom-app-vikunja-1 /app/vikunja/vikunja user create \
  -u admin -e "<your-email>" -p "<strong-password>"
```

Security notes:

- Keep `VIKUNJA_SERVICE_SECRET` fixed and backed up; rotating it logs everyone
  out.
- Registration stays disabled; add users with `vikunja user create`.
- TLS is terminated by Traefik; `VIKUNJA_SERVICE_PUBLICURL` uses `https` so
  generated links and api/frontend calls use the correct origin.
- Back up `db/vikunja.db` and `files/` (covered by the snapshot/replication
  tasks below).

#### Dawarich

[https://dawarich.app](https://dawarich.app)

Self-hosted location-history / GPS-tracking app (Google Timeline alternative).
Uses PostgreSQL/PostGIS plus Redis (four containers). Published through Traefik
at `https://YOUR_DAWARICH_DOMAIN:35000/`.

Datasets:

- `ssd-storage/apps-data/dawarich` (Dataset Preset: `Apps`)

The app runs non-root via the image's `PUID`/`PGID` support (do not use
compose `user:`). PostgreSQL and Redis manage their own privilege dropping.
Only the app-writable dirs need a manual `chown` (not `db`, which the Postgres
entrypoint fixes itself):

```sh
mkdir -p /mnt/ssd-storage/apps-data/dawarich/{db,shared,redis,public,watched,storage}
chown -R 568:568 /mnt/ssd-storage/apps-data/dawarich/{public,watched,storage}
```

##### Generate the service secrets

```sh
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
```

Store both in a password manager. `SECRET_KEY_BASE` signs Rails sessions;
rotating it invalidates all sessions.

##### Install the Custom App

1. **Apps -> Discover Apps -> Custom App**.
2. **Application Name**: `custom-app-dawarich`.
3. **Install via custom YAML**: use
   [`config/dawarich/compose.yml`](config/dawarich/compose.yml), adapted from the
   [official compose](https://github.com/Freika/dawarich/blob/master/docker/docker-compose.yml):
   named volumes replaced by bind mounts; image pinned to `1.11.0` (not
   `:latest`); `PUID`/`PGID` set to `568`; resource limits sized for a 2-user
   household. Only `dawarich_app` publishes a host port (`30081` -> container
   `3000`), matching the `dawarich-service` in the Traefik dynamic config.

   Four containers: `dawarich_db` (PostgreSQL/PostGIS), `dawarich_redis`,
   `dawarich_app` (Rails/Puma), `dawarich_sidekiq` (background jobs). All
   env/placeholders live in the file above.

4. **Fill in the placeholders.** The YAML editor takes no `.env`, so replace
   all `"<POSTGRES_PASSWORD>"` (3x), `"<SECRET_KEY_BASE>"` (2x), SMTP
   placeholders (2x each), and `"<CHIBIGEO_API_KEY>"` (2x) with real values in
   the file before installing. Keep the double quotes.

5. Click **Install** and watch the **Containers** tab until all four services
   are healthy. First-boot Rails migrations can take a few minutes.

##### DNS and port forwarding

- DNS: `YOUR_DAWARICH_DOMAIN` is a static CNAME -> `YOUR_ANCHOR_DOMAIN`.
- Router: no new port. Dawarich reuses `websecure` (`35000`); Traefik routes by
  `Host` header and obtains the certificate over the DNS challenge.

##### First-run setup

Log in at `https://YOUR_DAWARICH_DOMAIN:35000/` with the seeded admin
(`demo@dawarich.app` / `safepassword`) and change it immediately. Then:

- Change the admin email and password in **Settings**.
- Disable public self-registration.
- Point tracking clients (OwnTracks, Overland, Dawarich iOS/Android) at the
  instance using the per-user API key under **Settings**.
- SMTP is set on both app and sidekiq (Sidekiq delivers mail). Email links are
  hardcoded to `https://` since Dawarich 1.7.6.
- Back up the PostgreSQL cluster with `pg_dumpall` (covered below); the
  `public/`, `watched/`, and `storage/` dirs are covered by dataset snapshots.

### Data Protection

Three tiers give a 3-2-1 result (live data -> local ZFS replica -> offsite S3):

- **Quick errors (snapshots):** Periodic Snapshot Task on the datastore (enable
  **Recursive** if it has child datastores).

- **Physical damage (local replica):** Replication Task copying the datastore to
  a backup datastore in another pool. For personal media this replicates
  `/mnt/personal-media` -> `/mnt/backup-and-downloads/backups/backup-personal-media`.

- **Offsite + ransomware (encrypted cloud):** restic backup of the replicated
  copy to AWS S3 Glacier Instant Retrieval, client-side encrypted, weekly,
  keep-last-7. Setup, OpenTofu, script and DR runbook:
  [liberte-backup](https://gitlab.com/julian-alarcon/liberte-backup).

#### Application data backups

DoTheSplit, Memos, and Vikunja use **SQLite**; Dawarich uses **PostgreSQL**.
In both cases the DB must be **dumped, not file-copied**: a live DB file copied
mid-write can be inconsistent. A daily cron dumps each app into a
restic-backed directory, so the existing restic -> S3 job carries them offsite
(no second mechanism).

The dumps live in their own datastore so they snapshot/replicate independently
of personal media. Create it once (**Datasets > Add Dataset**), child of the
backup pool, named `backup-apps`, mounted at
`/mnt/backup-and-downloads/backups/backup-apps`. It then gets the same
three-tier protection as personal media above:

- **Snapshots:** add it to (or cover it with a recursive) Periodic Snapshot Task.
- **Local replica:** Replication Task copies it to a backup datastore in another
  pool, e.g. `/mnt/backup-and-downloads/backups/backup-apps` ->
  `/mnt/<other-pool>/backups/backup-backup-apps`.
- **Offsite:** the restic -> S3 job backs up the `backups/` parent, so it is
  carried to S3 with the other local backups (no separate source path).

The dump script lives at [`scripts/app-backups.sh`](scripts/app-backups.sh)
(verify container names/DB paths with `docker ps`).

Deploy and lock it down:

```sh
cp scripts/app-backups.sh /root/app-backups.sh
chmod 700 /root/app-backups.sh
```

Schedule it **before** the restic run (**System Settings > Advanced > Cron
Jobs**):

- **Description:** `app-backups`
- **Command:** `/root/app-backups.sh`
- **Run As User:** `root`
- **Schedule:** `30 0 * * *` (00:30 daily, ahead of the 01:00 restic run).

On any failure the script emails a report via `midclt call mail.send` (to the
TrueNAS local administrator address) and exits non-zero. Success is silent (no
daily "OK" mail). Set `NOTIFY=0` to disable. TrueNAS Cron Jobs do not raise
their own alert on a non-zero exit, so this email is the failure signal.

The restic job backs up the whole `/mnt/backup-and-downloads/backups/` parent,
so the dumps sync to S3 automatically, no separate source path needed. See
[liberte-backup](https://gitlab.com/julian-alarcon/liberte-backup).

#### Photography/Videography workflow

PENDING
