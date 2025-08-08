# NAS Setup

NAS Setup with TrueNAS

## Installation

[TruenNAS SCALE 24.10](https://www.truenas.com/download-truenas-scale/)iso image.
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
    * IP: `192.168.0.99/24`
    * Gateway: `192.168/0/1`
    * Nameservers: `1.1.1.1, 8.8.8.8, 192.168.0.1`

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

Dataset: `ssd-storage/apps-data/jellyfin`

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
      * H264: checked
      * HEVC: checked
      * MPEG2: checked
      * VC1: checked
      * VP8: checked
      * VP9: checked
      * AV1: checked
      * HEVC 10bit: checked
      * VP9 10bit: checked
      * HEVC RExt 8/10bit: checked
      * HEVC RExt 12bit: checked
      * Prefer OS native DXVA or VA-API hardware decoders: checked
    Hardware encoding options:
      * Enable hardware encoding: checked
      * Enable Intel Low-Power H.264 hardware encoder: checked
      * Enable Intel Low-Power HEVC hardware encoder: checked
    Encoding format options:
      * Allow encoding in HEVC format: checked
      * Enable VPP Tone mapping: checked

> Review of GPU usage can be made in TrueNAS shell with the command `sudo intel_gpu_top`

##### Plugins setup

Install Opensubtitles

* Opensubtitles: Username, password, API

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
    image: qmcgaw/gluetun:v3.40.0 # https://hub.docker.com/r/qmcgaw/gluetun/tags
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

Dataset: `ssd-storage/apps-data/qbittorrent`

Set new custom app with name `custom-app-qbittorrent`, paste the docker-compose
setup below:

```yaml
# Source: https://forums.truenas.com/t/guide-how-to-install-qbittorrent-or-any-app-with-vpn-on-truenas-electric-eel/12677
# Configuration https://docs.linuxserver.io/images/docker-qbittorrent
name: qbittorrent
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:5.1.2 # https://gitlab.com/Linuxserver.io/docker-qbittorrent/container_registry/774438
    restart: always
    container_name: custom-app-qbittorrent-1
    environment:
      - PUID=568 # Linux User ID for user: apps
      - PGID=568 # Linux User ID for group: apps
      - TZ=Europe/Berlin
      - WEBUI_PORT=8080
      - TORRENTING_PORT=6881
    volumes:
      - /mnt/ssd-storage/apps-data/qbittorrent/config:/config   #Directory you want to save your qbit config files
      - /mnt/backup-and-downloads/movies-series:/media    #movies/series/music directory 
    network_mode: container:custom-app-gluetun-1 #this is what makes the app to connect to the VPN.
    # Note that all ports were moved to the gluetun app.
```

##### qBittorrent Web UI settings

Options:

* Web UI -> Authentication -> Password: New Password
* Web UI -> Authentication -> By pass authentication for clients on localhost
* Web UI -> Authentication -> By pass authentication for clients in whitelisted IP subnets: 192.168.0.0/24
* Advanced -> Network interface: tun0
* Optional IP address to bind to: All IPv4 address
* Downloads ->   Default Save Path: `/media`
* Downloads -> Keep incomplete torrents in: `/media/downloads/torrents/incomplete`
* Downloads -> Copy .torrent files to: `/media/downloads/torrents`
* Downloads -> Copy .torrent files for finished downloads to: `/media/downloads/torrents`
* Connection -> Port used for incoming connections: 6881 (Not needed to modify as network is using glutun)
* Connection -> Global maximum number of connections: unchecked
* Connection -> Maximum number of connections per torrent: unchecked
* Connection -> Global maximum number of upload slots: unchecked
* Connection -> Maximum number of upload slots per torrent: unchecked
* BitTorrent -> Torrent Queueing
    * Maximum active downloads: 10
    * Maximum active uploads: 3
    * Maximum active torrents: 15
* BitTorrent -> When total seeding time reaches: 60 minutes
                When inactive seeding time reaches: 120 minutes
                    then: Pause torrent

* Search tab -> Search plugins... -> Check for updates
    * [Install plugins](https://github.com/qbittorrent/search-plugins/wiki/unofficial-search-plugins)

###### Test VPN connection on qBittorrent

Enter to shell for qbittorrent container and check `curl https://ipleak.net/json/`

#### ddns-updater

Install from Applications (`community`)

Dataset: `ssd-storage/apps-data/ddns-updater`

WebUI Port: `30007`
Host path: /mnt/ssd-storage/apps-data/ddns-updater
Public IP DNS Providers
    Provider: Cloudflare
Config
    Cloudflare
        Domain: YOUR_PERSONAL_DOMAIN
        IP Version: IPV4 and IPV6
        Zone ID: From Cloudflare dashboard DNS section
        Token: YOUR_CLOUDFLARE_TOKEN

#### Traefik reverse proxy setup

Dataset: `ssd-storage/apps-data/traefik`

##### Set certificates and config

Create the directory and file for certificates

```sh
mkdir /mnt/ssd-storage/apps-data/traefik/letsencrypt
touch mkdir /mnt/ssd-storage/apps-data/traefik/letsencrypt/
chmod 600 /mnt/ssd-storage/apps-data/traefik/letsencrypt/
```

Add configuration to file `/mnt/ssd-storage/apps-data/traefik/traefik_dynamic.yml`

```yaml
http:
  routers:
    immich:
      rule: "Host(`YOUR_PHOTOS_DOMAIN`) && PathPrefix(`/immich`)"
      service: immich-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver

    jellyfin:
      rule: "Host(`YOUR_PERSONAL_DOMAIN`) && PathPrefix(`/jellyfin`)"
      service: jellyfin-service
      entryPoints:
        - websecure
      tls:
        certResolver: myresolver
      middlewares:
        - strip-jellyfin-prefix

  middlewares:
    strip-jellyfin-prefix:
      stripPrefix:
        prefixes:
          - "/jellyfin"

  services:
    jellyfin-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30013"

    immich-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.200:30041"
```

##### Traefik app

Set new custom app with name `custom-app-traefik` and paste the docker-compose
setup below:

```yaml
name: traefik
services:
  reverse-proxy:
    image: traefik:v3.3.6 # https://github.com/traefik/traefik/releases
    restart: always
    container_name: custom-app-traefik-1
    command:
      - "--log.level=DEBUG"
      - "--api.insecure=true" # Enable Traefik dashboard (optional)
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.websecure.address=:35000"
      - "--certificatesresolvers.myresolver.acme.email=letsencrypt@mail.desentropia.com" # Your email for Let's Encrypt notifications
      - "--certificatesresolvers.myresolver.acme.storage=/etc/traefik/letsencrypt/acme.json" # Storage for certificates
      - "--certificatesresolvers.myresolver.acme.dnschallenge=true"
      - "--certificatesresolvers.myresolver.acme.dnschallenge.provider=cloudflare" # Set DNS provider to Cloudflare
      - "--certificatesresolvers.myresolver.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
      # - "--certificatesresolvers.myresolver.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory" # Use Let's Encrypt staging server
      - "--certificatesresolvers.myresolver.acme.caserver=https://acme-v02.api.letsencrypt.org/directory" # Use Let's Encrypt production
      - "--providers.file.filename=/etc/traefik/traefik_dynamic.yml"  # Use the dynamic config
    environment:
      - CF_DNS_API_TOKEN=YOUR_CLOUDFLARE_TOKEN
      - CF_API_EMAIL=YOUR_CLOUDFLARE_EMAIL
    ports:
      - "35000:35000" # External port
      - "30033:8080"  # Traefik dashboard (optional)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # Required for Docker provider
      - /mnt/ssd-storage/apps-data/traefik:/etc/traefik/
 # Whoami Service
  whoami:
    image: traefik/whoami:v1.11.0 # https://github.com/traefik/whoami/releases
    restart: on-failure:5
    container_name: custom-app-traefik-whoami-service-1
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`YOUR_PERSONAL_DOMAIN`)"  # Change to your desired host
      - "traefik.http.routers.whoami.entrypoints=websecure"  # Use websecure for HTTPS
      - "traefik.http.routers.whoami.tls.certResolver=myresolver"  # Enable TLS if you want to secure this route
```

Port forwarding needs to be set in the router for port `35000` (or the port that
you choose) to local NAS IP.

#### Immich

Install from Applications (`community`)

Datasets:

* `ssd-storage/apps-data/immich`
* `personal-media/immich`

Create directories

```sh
mkdir -p /mnt/tank/immich/data/{upload,thumbs,library,profile,backups,encoded-video}
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

### Data Protection

* For quick errors: Set Periodic Snapshot Task for the datastore (enable **Recursive**
if child datastores are in the datastore).

* For physical damage: Set Replication Task for the datastore to backup datastore
in another Pool store.

* Physical damage and ransomware: Set TrueCloud Backup Task to Starj from backup
datastore. Make the same for the Immich DB Backup datastore.

#### Photography/Videography workflow
