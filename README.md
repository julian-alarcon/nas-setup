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

Set new custom app with name `custom-app-gluetun`, paste the docker-compose setup below:

```yaml
# Source: https://forums.truenas.com/t/guide-how-to-install-qbittorrent-or-any-app-with-vpn-on-truenas-electric-eel/12677
# Configuration https://github.com/qdm12/gluetun-wiki
name: gluetun
services:
  gluetun:
    image: qmcgaw/gluetun:v3 # https://hub.docker.com/r/qmcgaw/gluetun/tags
    restart: always
    container_name: custom-app-gluetun-1
    cap_add:
      - NET_ADMIN
    ports:
      - 8888:8888/tcp # HTTP proxy
      - 8388:8388/tcp # Shadowsocks
      - 8388:8388/udp # Shadowsocks
      - 8080:8080 # qbittorrent webui
      - 6881:6881 # qbittorrent
      - 6881:6881/udp # qbittorrent
    volumes:
      - /mnt/ssd-storage/apps-data/gluetun:/gluetun
    environment:
      - VPN_TYPE=wireguard
      - VPN_SERVICE_PROVIDER=protonvpn
      - WIREGUARD_PRIVATE_KEY=WIRGUARD_PRIVATE_KEY
      - SERVER_COUNTRIES=Switzerland
      - PORT_FORWARD_ONLY
      - UPDATER_PERIOD=24h
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_PROVIDER=protonvpn
      - FIREWALL_VPN_INPUT_PORTS=6881
```

##### qBittorrent app

Dataset:

- `ssd-storage/apps-data/qbittorrent`

Set new custom app with name `custom-app-qbittorrent`, paste the docker-compose
setup below:

```yaml
# Source: https://forums.truenas.com/t/guide-how-to-install-qbittorrent-or-any-app-with-vpn-on-truenas-electric-eel/12677
# Configuration https://docs.linuxserver.io/images/docker-qbittorrent
name: qbittorrent
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:5.2.1 # https://gitlab.com/Linuxserver.io/docker-qbittorrent/container_registry/774438
    restart: always
    container_name: custom-app-qbittorrent-1
    environment:
      - PUID=568 # Linux User ID for user: apps
      - PGID=568 # Linux User ID for group: apps
      - TZ=Europe/Berlin
      - WEBUI_PORT=8080
      - TORRENTING_PORT=6881
    volumes:
      - /mnt/ssd-storage/apps-data/qbittorrent/config:/config #Directory you want to save your qbit config files
      - /mnt/backup-and-downloads/movies-series:/media #movies/series/music directory
    network_mode: container:custom-app-gluetun-1 #this is what makes the app to connect to the VPN.
    # Note that all ports were moved to the gluetun app.
```

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

#### ddns-updater

Install from Applications (`community`)

Dataset:

- `ssd-storage/apps-data/ddns-updater`

WebUI Port: `30007`
Host path: /mnt/ssd-storage/apps-data/ddns-updater

##### DNS provider prerequisites

1. Create an `A` record for the subdomain pointing at any placeholder IP (the
   updater overwrites it on first run). Disable any CDN proxying so Traefik can
   complete the Let's Encrypt challenge and reach the origin.
2. Get the zone ID and create a DNS-edit API token scoped to that zone.

##### App config

Set the provider, domain, IP version, zone ID, and API token from the steps above.

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

```yaml
# TLS hardening applied to every router via the default options.
# TLS 1.3 only: cipher suites are fixed by the spec, so no cipherSuites
# tuning is needed (it would be ignored). Ensure all clients support TLS 1.3.
tls:
  options:
    default:
      minVersion: VersionTLS13
      sniStrict: true

http:
  routers:
    immich:
      rule: "Host(`YOUR_PHOTOS_DOMAIN`) && PathPrefix(`/immich`)"
      service: immich-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers

    jellyfin:
      rule: "Host(`YOUR_PERSONAL_DOMAIN`) && PathPrefix(`/jellyfin`)"
      service: jellyfin-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers
        - strip-jellyfin-prefix

    dothesplit:
      rule: "Host(`YOUR_PERSONAL_DOMAIN`)"
      service: dothesplit-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers

    # Traefik dashboard. LAN-only + basicAuth;  reachable only from
    # the LAN
    dashboard:
      rule: "PathPrefix(`/dashboard`) || PathPrefix(`/api`)"
      service: api@internal # Traefik's built-in dashboard/API service
      entryPoints:
        - dashboard
      middlewares:
        - dashboard-auth

  middlewares:
    strip-jellyfin-prefix:
      stripPrefix:
        prefixes:
          - "/jellyfin"

    # HSTS + common hardening headers for all public routers.
    security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: strict-origin-when-cross-origin

    # basicAuth for the dashboard. Generate the hash with:
    #   htpasswd -nbB admin 'YOUR_STRONG_PASSWORD'
    # In a YAML file the hash is written literally (no `$$` escaping).
    dashboard-auth:
      basicAuth:
        users:
          - "admin:$2y$05$REPLACE_WITH_YOUR_BCRYPT_HASH"

  services:
    jellyfin-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30013"

    immich-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30041"

    dothesplit-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30051"
```

##### Traefik app

Set new custom app with name `custom-app-traefik` and paste the docker-compose
setup below:

```yaml
name: traefik
services:
  reverse-proxy:
    image: traefik:v3 # https://github.com/traefik/traefik/releases
    restart: always
    container_name: custom-app-traefik-1
    command:
      - "--log.level=INFO"
      - "--accesslog=true"
      # Dashboard served via api@internal on its own `dashboard` entrypoint
      # (port 35001), bound to the `dashboard` router in the dynamic config.
      - "--api.dashboard=true"
      - "--providers.file.filename=/etc/traefik/traefik_dynamic.yml"
      - "--entrypoints.websecure.address=:35000"
      # Dashboard entrypoint: LAN-only. Do NOT port-forward 35001 on the router.
      - "--entrypoints.dashboard.address=:35001"
      - "--certificatesresolvers.myresolver.acme.email=letsencrypt@mail.desentropia.com" # Your email for Let's Encrypt notifications
      - "--certificatesresolvers.myresolver.acme.storage=/etc/traefik/letsencrypt/acme.json" # Storage for certificates
      - "--certificatesresolvers.myresolver.acme.dnschallenge=true"
      - "--certificatesresolvers.myresolver.acme.dnschallenge.provider=YOUR_DNS_PROVIDER"
      - "--certificatesresolvers.myresolver.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
      # - "--certificatesresolvers.myresolver.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory" # Use Let's Encrypt staging server
      - "--certificatesresolvers.myresolver.acme.caserver=https://acme-v02.api.letsencrypt.org/directory" # Use Let's Encrypt production
    environment:
      - DNS_API_TOKEN=YOUR_DNS_API_TOKEN # Use the env vars your DNS provider expects
    ports:
      - "35000:35000" # Public entrypoint (port-forward this one)
      - "35001:35001" # Dashboard entrypoint, LAN-only (do NOT port-forward)
    volumes:
      - /mnt/ssd-storage/apps-data/traefik:/etc/traefik/
    read_only: true # acme.json is on the mounted volume, so the cert store stays writable
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=16m
```

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
External domain: `https://YOUR_PHOTOS_DOMAIN:35000`
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
`https://YOUR_PERSONAL_DOMAIN:35000/`. Full walkthrough in the project's
`INSTALL.md`; below is the NAS-specific summary.

Datasets:

- `ssd-storage/apps-data/dothesplit`

##### Pre-create host directories

The wizard cannot create directories on save, so create them from the shell:

```sh
mkdir -p /mnt/ssd-storage/apps-data/dothesplit/pgdata
mkdir -p /mnt/ssd-storage/apps-data/dothesplit/migrations
chown -R 70:70 /mnt/ssd-storage/apps-data/dothesplit/pgdata
chmod 700      /mnt/ssd-storage/apps-data/dothesplit/pgdata
```

Create `pgdata` and `migrations` as **plain directories**, not ZFS datasets, a
dataset mountpoint can't be `rm`'d and gets pinned busy on any deploy hiccup.

UID `70` is the `postgres` user inside the **`-alpine`** Postgres image pinned
below (`postgres:18.4-alpine3.22`). The Debian-based `postgres:18` image instead
runs as UID `999`, so if you ever switch off the alpine tag, re-`chown` `pgdata`
to `999:999`. Either way, do **not** apply the dataset `Apps` permission preset
(UID 568) to `pgdata` or Postgres refuses to start.

##### Drop the migrations on disk

The `migrate` one-shot reads SQL from a host path. Fetch the migrations matching
the release tag you install (replace `v1.0.0`):

```sh
cd /mnt/ssd-storage/apps-data/dothesplit/migrations
curl -fsSL https://github.com/julian-alarcon/dothesplit/archive/refs/tags/v1.0.0.tar.gz \
  | tar -xz --strip-components=3 --wildcards '*/api/migrations'
ls   # should list 0001_*.up.sql, 0001_*.down.sql, …
```

Refresh this directory to the new tag artifacts before bumping image versions on
upgrades.

##### Generate the five secrets

Run once and store the output in a password manager **before** continuing.
Losing `EMAIL_ENC_KEY`, `EMAIL_HMAC_KEY`, or `PASSWORD_PEPPER` after the database
has data makes that data unrecoverable (rotating `JWT_SIGNING_KEY` only forces a
re-login).

```sh
echo "EMAIL_ENC_KEY=$(openssl rand -base64 32)"
echo "EMAIL_HMAC_KEY=$(openssl rand -base64 32)"
echo "PASSWORD_PEPPER=$(openssl rand -base64 32)"
echo "JWT_SIGNING_KEY=$(openssl rand -base64 32)"
echo "POSTGRES_PASSWORD=$(openssl rand -base64 24)"
```

Build `DATABASE_URL` from the Postgres password (URL-encode it if it contains
any of `: / ? # [ ] @`):

```
postgres://dts:<POSTGRES_PASSWORD>@postgres:5432/dts?sslmode=disable
```

##### Install the Custom App

1. **Apps -> Discover Apps -> Custom App**.
2. **Application Name**: `custom-dothesplit`.
3. **Install via custom YAML**: paste the compose below. One image
   (`dothesplit`) now serves both the JSON API and the embedded client-side Vue
   SPA, so `api` and `worker` share it. `COOKIE_SECURE` is `true` and
   `WEB_ORIGIN` points at the public HTTPS URL because Traefik terminates TLS in
   front of the app. Substitute your release tag for `1.0.0`. The GHCR image tag
   carries **no** `v` prefix (`dothesplit:1.0.0`), unlike the git tag and
   `curl | tar` URL above (`v1.0.0`), don't conflate them:

   ```yaml
   services:
     postgres:
       image: postgres:18.4-alpine3.22
       restart: unless-stopped
       environment:
         POSTGRES_USER: dts
         POSTGRES_PASSWORD: "<POSTGRES_PASSWORD>"
         POSTGRES_DB: dts
       volumes:
         - /mnt/ssd-storage/apps-data/dothesplit/pgdata:/var/lib/postgresql
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U dts -d dts"]
         interval: 5s
         timeout: 3s
         retries: 10
       cap_drop: [ALL]
       cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]
       security_opt: ["no-new-privileges:true"]
       mem_limit: 512m
       pids_limit: 200

     migrate:
       image: migrate/migrate:v4.19.1
       depends_on:
         postgres:
           condition: service_healthy
       volumes:
         - /mnt/ssd-storage/apps-data/dothesplit/migrations:/migrations:ro
       environment:
         DATABASE_URL: "postgres://dts:<POSTGRES_PASSWORD>@postgres:5432/dts?sslmode=disable"
       entrypoint: ["/bin/sh", "-c"]
       command:
         - 'exec migrate -path /migrations -database "$$DATABASE_URL" up'
       restart: "no"
       read_only: true
       cap_drop: [ALL]
       security_opt: ["no-new-privileges:true"]
       tmpfs:
         - /tmp:rw,noexec,nosuid,size=8m

     api:
       image: ghcr.io/julian-alarcon/dothesplit:1.0.0
       depends_on:
         postgres:
           condition: service_healthy
         migrate:
           condition: service_completed_successfully
       environment:
         DATABASE_URL: "postgres://dts:<POSTGRES_PASSWORD>@postgres:5432/dts?sslmode=disable"
         API_HTTP_ADDR: ":8080"
         WEB_ORIGIN: "https://YOUR_PERSONAL_DOMAIN:35000"
         COOKIE_SECURE: "true"
         EMAIL_ENC_KEY: "<EMAIL_ENC_KEY>"
         EMAIL_HMAC_KEY: "<EMAIL_HMAC_KEY>"
         PASSWORD_PEPPER: "<PASSWORD_PEPPER>"
         JWT_SIGNING_KEY: "<JWT_SIGNING_KEY>"
         TRUSTED_PROXIES: "192.168.1.200/32"
         LOG_LEVEL: info
       ports:
         # The api binary serves both /v1 and the embedded SPA.
         - "30051:8080"
       restart: unless-stopped
       healthcheck:
         test: ["CMD", "/api", "--healthcheck"]
         interval: 10s
         timeout: 3s
         retries: 5
         start_period: 10s
       read_only: true
       cap_drop: [ALL]
       security_opt: ["no-new-privileges:true"]
       tmpfs:
         - /tmp:rw,noexec,nosuid,size=32m

     worker:
       image: ghcr.io/julian-alarcon/dothesplit:1.0.0
       depends_on:
         postgres:
           condition: service_healthy
         migrate:
           condition: service_completed_successfully
       entrypoint: ["/worker"]
       environment:
         DATABASE_URL: "postgres://dts:<POSTGRES_PASSWORD>@postgres:5432/dts?sslmode=disable"
         EMAIL_ENC_KEY: "<EMAIL_ENC_KEY>"
         EMAIL_HMAC_KEY: "<EMAIL_HMAC_KEY>"
         PASSWORD_PEPPER: "<PASSWORD_PEPPER>"
         JWT_SIGNING_KEY: "<JWT_SIGNING_KEY>"
         LOG_LEVEL: info
       restart: unless-stopped
       read_only: true
       cap_drop: [ALL]
       security_opt: ["no-new-privileges:true"]
       tmpfs:
         - /tmp:rw,noexec,nosuid,size=32m
   ```

   Only the `api` container publishes a host port (`30051` -> container `8080`);
   it serves both `/v1` and the embedded client-side Vue SPA from one origin, so
   the browser calls `/v1` directly (same origin) once the SPA loads. Traefik
   routes `YOUR_PERSONAL_DOMAIN:35000` to `http://192.168.1.200:30051` (see the
   `dothesplit` router/service in the Traefik dynamic config above).

4. **Fill in the secrets directly in the YAML.** The "Install via YAML" editor
   takes only the compose file, no env-var table, no `.env`, so hardcode the
   values before pasting. Replace every `<...>` placeholder:
   - `<POSTGRES_PASSWORD>`: the same value in `postgres`, `migrate`, `api`, and
     `worker` (it appears both on its own and inside each `DATABASE_URL`).
     URL-encode it inside `DATABASE_URL` if it contains any of `: / ? # [ ] @`.
   - `<EMAIL_ENC_KEY>`, `<EMAIL_HMAC_KEY>`, `<PASSWORD_PEPPER>`,
     `<JWT_SIGNING_KEY>`: the same value in both `api` and `worker`.

5. Click **Install** and watch the **Containers** tab until all four services
   are healthy.

##### DNS and port forwarding

- DNS: point `YOUR_PERSONAL_DOMAIN` at the public IP (the `ddns-updater` app
  keeps it current).
- Router: no new port to open. DoTheSplit reuses the existing `websecure`
  entrypoint (`35000`) that is already port-forwarded to `192.168.1.200`;
  Traefik routes it by `Host` header and obtains the certificate over the DNS
  challenge.

##### First-run setup token

The API prints a one-time setup token on first boot. From the TrueNAS shell:

```sh
docker logs ix-custom-dothesplit-api-1 2>&1 | grep -A2 'first-run setup'
```

Open `https://YOUR_PERSONAL_DOMAIN:35000/setup`, paste the token, and create
the admin account (display name + email + password >= 10 chars). The setup form
locks permanently afterwards.

##### Updates

1. Refresh the migrations directory to the new tag (re-run the `curl | tar`
   command with the new version).
2. **Apps -> dothesplit -> Edit** -> bump the `image:` tag for `api` and
   `worker` (they share one image) to the new `:X.Y.Z` (no `v` prefix), then
   **Save**. The idempotent `migrate` one-shot applies any new `*.up.sql` files
   on the next start.

### Data Protection

- For quick errors: Set Periodic Snapshot Task for the datastore (enable **Recursive**
  if child datastores are in the datastore).

- For physical damage: Set Replication Task for the datastore to backup datastore
  in another Pool store.

- Physical damage and ransomware: Set TrueCloud Backup Task to Starj from backup
  datastore. Make the same for the Immich DB Backup datastore.

#### Photography/Videography workflow

PENDING
