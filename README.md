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
      rule: "Host(`YOUR_IMMICH_DOMAIN`) && PathPrefix(`/immich`)"
      service: immich-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers
        - compress

    jellyfin:
      rule: "Host(`YOUR_JELLYFIN_DOMAIN`) && PathPrefix(`/jellyfin`)"
      service: jellyfin-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers
        - strip-jellyfin-prefix

    dothesplit:
      rule: "Host(`YOUR_DOTHESPLIT_DOMAIN`)"
      service: dothesplit-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers
        - compress

    # Memos runs on its own subdomain (it does not support a URL sub-path
    # reliably: its frontend uses absolute asset paths).
    memos:
      rule: "Host(`YOUR_MEMOS_DOMAIN`)"
      service: memos-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers
        - compress

    vikunja:
      rule: "Host(`YOUR_VIKUNJA_DOMAIN`)"
      service: vikunja-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - security-headers
        - compress

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
    # gzip/brotli/zstd for text responses (HTML/JS/CSS/JSON). Traefik negotiates
    # the best algorithm per client and skips already-compressed media types,
    # so it is applied only to the web UIs (not jellyfin's media streams).
    compress:
      compress: {}

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

    memos-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30061"

    vikunja-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30071"
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
2. **Application Name**: `custom-dothesplit`.
3. **Install via custom YAML**: paste the compose below. `COOKIE_SECURE` is
   `true` and `WEB_ORIGIN` points at the public HTTPS URL because Traefik
   terminates TLS in front of the app. The `:1` tag tracks the v1 major line; pin
   an exact `:1.Y.Z` if you prefer manual upgrades. `read_only: true` keeps the
   rootfs immutable; the SQLite DB is writable because it lives on the mounted
   `/data` volume.

   ```yaml
   services:
     dothesplit:
       image: ghcr.io/julian-alarcon/dothesplit:1
       restart: unless-stopped
       container_name: custom-app-dothesplit-1
       environment:
         API_HTTP_ADDR: ":8080"
         WEB_ORIGIN: "https://YOUR_DOTHESPLIT_DOMAIN:35000"
         COOKIE_SECURE: "true"
         DATABASE_DRIVER: sqlite
         DATABASE_URL: "file:/data/dts.db"
         EMAIL_ENC_KEY: "<EMAIL_ENC_KEY>"
         EMAIL_HMAC_KEY: "<EMAIL_HMAC_KEY>"
         PASSWORD_PEPPER: "<PASSWORD_PEPPER>"
         JWT_SIGNING_KEY: "<JWT_SIGNING_KEY>"
         TRUSTED_PROXIES: "192.168.1.200/32"
         LOG_LEVEL: info
       ports:
         # The binary serves both /v1 and the embedded SPA.
         - "30051:8080"
       volumes:
         - /mnt/ssd-storage/apps-data/dothesplit/data:/data
       healthcheck:
         test: ["CMD", "/dothesplit", "--healthcheck"]
         interval: 10s
         timeout: 3s
         retries: 5
         start_period: 10s
       read_only: true
       cap_drop: [ALL]
       security_opt: ["no-new-privileges:true"]
       tmpfs:
         - /tmp:rw,noexec,nosuid,size=32m
   ```

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
2. **Application Name**: `custom-memos`.
3. **Install via custom YAML**: paste the compose below. `MEMOS_DRIVER=sqlite`
   is the default, so no database container is needed. Only the `memos`
   container publishes a host port (`30061` -> container `5230`), matching the
   `memos-service` in the Traefik dynamic config above.

   ```yaml
   services:
     memos:
       image: neosmemo/memos:stable # https://github.com/usememos/memos/releases
       restart: unless-stopped
       container_name: custom-app-memos-1
       environment:
         - MEMOS_MODE=prod
         - MEMOS_DRIVER=sqlite
         - MEMOS_PORT=5230
         # Public URL, required behind a reverse proxy.
         - MEMOS_INSTANCE_URL=https://YOUR_MEMOS_DOMAIN:35000
         - TZ=Europe/Berlin
       ports:
         - "30061:5230"
       volumes:
         - /mnt/ssd-storage/apps-data/memos:/var/opt/memos
       security_opt: ["no-new-privileges:true"]
       mem_limit: 256m
       pids_limit: 100
   ```

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
2. **Application Name**: `custom-vikunja`.
3. **Install via custom YAML**: paste the compose below. `VIKUNJA_DATABASE_TYPE`
   is `sqlite`, so no database container is needed. Only the `vikunja` container
   publishes a host port (`30071` -> container `3456`), matching the
   `vikunja-service` in the Traefik dynamic config above.

   ```yaml
   services:
     vikunja:
       image: vikunja/vikunja:2 # https://github.com/go-vikunja/vikunja/releases
       restart: unless-stopped
       container_name: custom-app-vikunja-1
       user: "568:568"
       environment:
         # Public URL, trailing slash required (api<->frontend communication).
         - VIKUNJA_SERVICE_PUBLICURL=https://YOUR_VIKUNJA_DOMAIN:35000/
         - VIKUNJA_SERVICE_SECRET=<VIKUNJA_SERVICE_SECRET>
         - VIKUNJA_DATABASE_TYPE=sqlite
         - VIKUNJA_DATABASE_PATH=/db/vikunja.db
         # Lock the instance down: no self-registration (create users via admin).
         - VIKUNJA_SERVICE_ENABLEREGISTRATION=false
         - VIKUNJA_SERVICE_TIMEZONE=Europe/Berlin
         # SMTP for notifications/password-reset. STARTTLS on 587 by default;
         # set VIKUNJA_MAILER_FORCESSL=true only for implicit TLS on 465.
         - VIKUNJA_MAILER_ENABLED=true
         - VIKUNJA_MAILER_HOST=my-smtp-server
         - VIKUNJA_MAILER_PORT=587
         - VIKUNJA_MAILER_USERNAME=<username-for-smtp>
         - VIKUNJA_MAILER_PASSWORD=<password-for-smtp>
         - VIKUNJA_MAILER_FROMEMAIL=<vikunja@mydomain.com>
       ports:
         - "30071:3456"
       volumes:
         - /mnt/ssd-storage/apps-data/vikunja/db:/db
         - /mnt/ssd-storage/apps-data/vikunja/files:/app/vikunja/files
       security_opt: ["no-new-privileges:true"]
       mem_limit: 512m
       pids_limit: 200
   ```

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

All three apps (DoTheSplit, Memos, Vikunja) use **SQLite**. The DB must be
**dumped, not file-copied**, a live SQLite file copied mid-write can be
inconsistent. A weekly cron dumps each app into a restic-backed directory, so the
existing restic -> S3 job carries them offsite (no second mechanism).

Script `/root/app-backups.sh` (verify container names/DB paths with `docker ps`):

```sh
#!/bin/sh
# Application-consistent dumps into the restic-backed directory.
# Run weekly, BEFORE the restic -> S3 job. Dumps are overwritten each run;
# restic snapshots provide the history.
set -eu

DEST="/mnt/backup-and-downloads/backups/app-backups"
mkdir -p "$DEST"

# DoTheSplit (SQLite): online .backup while the app is running.
sqlite3 "/mnt/ssd-storage/apps-data/dothesplit/data/dts.db" \
  ".backup '$DEST/dothesplit.db'"

# Vikunja: built-in consistent dump (database + files + config in one zip).
docker exec custom-app-vikunja-1 /app/vikunja/vikunja dump -p /app/vikunja/files/dump.zip
mv "/mnt/ssd-storage/apps-data/vikunja/files/dump.zip" "$DEST/vikunja.zip"

# Memos (SQLite): online .backup for a consistent copy while running.
sqlite3 "/mnt/ssd-storage/apps-data/memos/memos_prod.db" \
  ".backup '$DEST/memos.db'"

# Both .backup lines need sqlite3 on the host; if absent, run it in a small
# sqlite container mounting the same paths.
```

Deploy and lock it down:

```sh
cp app-backups.sh /root/app-backups.sh
chmod 700 /root/app-backups.sh
```

Schedule it **before** the restic run (**System Settings > Advanced > Cron
Jobs**):

- **Description:** `app-backups`
- **Command:** `/root/app-backups.sh`
- **Run As User:** `root`
- **Schedule:** `30 0 * * fri` (00:30 Friday, ahead of the 01:00 restic run).

Then add `/mnt/backup-and-downloads/backups/app-backups` to the restic job's
source paths (in [liberte-backup](https://gitlab.com/julian-alarcon/liberte-backup)),
so the dumps sync to S3 alongside the personal media.

#### Photography/Videography workflow

PENDING
