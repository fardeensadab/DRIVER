# DRIVER Installation Report

| | |
|---|---|
| **Project** | DRIVER: Data for Road Incident Visualization, Evaluation, and Reporting |
| **Source** | https://github.com/WorldBank-Transport/DRIVER, release 2.0.5 (commit `69188882`, October 2019) |
| **Installed on** | `Fardeen-XPS`: Ubuntu 22.04.5 LTS, kernel 6.8.0-138, 20 CPU cores, 15 GB RAM, Secure Boot on |
| **Install folder** | `~/DRIVER` (git branch `local-install-fixes`) |
| **Completed** | 4 October 2026, with all three VMs set up and 0 failures |
| **Access** | http://localhost:7000/ (web app), http://localhost:7000/editor/ (schema editor). Login `admin` / `admin` |

---

## 1. What DRIVER is

DRIVER is an open-source web platform, originally built by Azavea for the World Bank, for recording, mapping and analysing road crashes. It provides:

- recording incidents with location, date, severity and custom fields
- a schema editor for designing your own data-entry forms
- an interactive map with filters by area, date and attributes
- uploading geographic boundaries
- black-spot detection (places with many crashes)
- tracking interventions and estimating the cost of incidents
- data export, plus support for an Android data-collection app

## 2. Architecture

DRIVER runs as **three VirtualBox virtual machines (VMs)**, created by Vagrant and configured by Ansible. Most services inside the VMs run as Docker containers.

```
 Your computer (Ubuntu 22.04)
 ├── VirtualBox 7.1 + Vagrant 2.4.9 + Ansible 2.9.27
 ├── NFS server ── shares ~/DRIVER/{app,web,schema_editor,windshaft,analysis_tasks,gradle} with the VMs
 │
 ├── VM "database"  192.168.12.101   (2 CPU, 2 GB)
 │     PostgreSQL 9.4 + PostGIS 2.3, Redis 2.8, monit
 │
 ├── VM "app"       192.168.12.102   (2 CPU, 3.5 GB)   ← http://localhost:7000
 │     nginx 1.4.6 (web proxy), monit
 │     Docker: driver-app (Django API), windshaft (map tiles),
 │             driver-web + driver-editor (build the Angular front-ends)
 │
 └── VM "celery"    192.168.12.103   (2 CPU, 3.5 GB)
       nginx (file downloads), monit, heimdall (job locking), cron jobs
       Docker: driver-celery (background jobs/exports), driver-gradle (Android JARs),
               driver-analysis (R black-spot analysis)
```

### Ports on your computer

| Port | Service |
|---|---|
| 7000 | DRIVER web app and editor (nginx in the app VM) |
| 7001 / 7002 | Development servers for the editor / web app (only when started manually) |
| 3000 / 3001 | Django runserver (only when started manually) |
| 35731 / 35732 | Live reload for development |
| 2375 / 2376 | Docker API of the app / celery VMs |
| 2222 / 2200 / 2201 | SSH into the database / app / celery VMs (used by Vagrant) |

---

## 3. Software and components

### 3.1 On your computer (the host)

| Component | Version | Source | Purpose |
|---|---|---|---|
| Ubuntu | 22.04.5 LTS, kernel 6.8.0-138 | already installed | Host operating system |
| Oracle VirtualBox | **7.1.18** | download.virtualbox.org apt repo | Runs the three VMs |
| VirtualBox kernel driver | 7.1.18, signed with Ubuntu's MOK key | built by `vboxconfig` | Required for VMs; needed one-time Secure Boot key enrolment |
| Vagrant | **2.4.9** | apt.releases.hashicorp.com | Creates and manages the VMs |
| vagrant-hostmanager plugin | **1.8.10** | rubygems.org | Lets the VMs find each other by hostname |
| NFS server (`nfs-kernel-server`, `nfs-common`) | 2.6.1 | Ubuntu repo | Shares source folders with the VMs |
| uv | 0.12.22 | astral.sh | Installs Python 3.8 without touching system Python |
| Python (virtual environment `~/driver-venv`) | **3.8.20** | uv | Runtime for Ansible |
| Ansible | **2.9.27** | PyPI (in `~/driver-venv`) | Configures the VMs |
| git, curl, wget, gnupg, gcc, make, perl, kernel headers | Ubuntu 22.04 versions | Ubuntu repo | Tools for downloading and building |

### 3.2 Inside every VM (Ubuntu 14.04)

| Component | Version | Notes |
|---|---|---|
| Vagrant box `ubuntu/trusty64` | v20191107.0.0 (Ubuntu 14.04, kernel 3.13.0-170) | Downloaded from Vagrant Cloud |
| Python | 2.7.6 | Old; has no TLS SNI support (see problem 14) |
| pip | 1.5.4 (Ubuntu package) | Installs from a local folder, not PyPI (problem 26) |
| pyOpenSSL / ndg-httpsclient / pyasn1 | 0.13 / 0.4.3 / 0.4.2 | Give pip TLS SNI support |
| Mozilla CA certificate bundle | September 2026 | Added on top of the 2017 Ubuntu bundle |
| Docker CE | **17.06.2** | Installed from its `.deb` file (problem 16) |
| monit | 5.17.1 | Watches services and restarts them |
| curl settings (`.curlrc`) | IPv4 only, 5 retries, stall timeout | Problems 27–28 |

### 3.3 VM-specific components

| VM | Component | Version |
|---|---|---|
| database | PostgreSQL | 9.4.22 (pgdg) |
| database | PostGIS | 2.3.3 |
| database | libpq / libpq-dev | 11.3 |
| database | psycopg2 | 2.6 |
| database | Redis | 2.8.4 |
| app, celery | nginx | 1.4.6 (Ubuntu package) |
| celery | heimdall | 0.2.3 |

### 3.4 Docker images (built inside the VMs)

| Image | Base image | Main contents |
|---|---|---|
| `driver-app` (+ dev variant) | `quay.io/azavea/django:1.11-python2.7-slim` (Debian 10, Python 2.7.17) | Django 1.11.26, Django REST Framework 3.8.0, grout 2.0.1, Celery 3.1.19, django-oidc, Fiona 1.6.3, Shapely 1.5.13, pyproj 1.9.5.1, Rtree 0.8.2, GDAL 1.10 (from Debian 8), gunicorn; dev variant adds IPython 3.0.0 and ipdb 0.8.1. 84 Python packages are pinned in `app/constraints-py27.txt` |
| `driver-web` | `node:8-slim` (Debian 9, Node 8.17.0) | Ruby 2.3 + sass 3.4.22, compass 1.0.3; grunt-cli 1.2.0, bower 1.8.14; AngularJS 1.5, Leaflet 0.7, D3 3.5.5, Bootstrap, moment.js and others (from `web/bower.json`) |
| `driver-editor` | `node:8-slim` | Same toolchain as `driver-web`, for the schema editor |
| `driver-gradle` | `public.ecr.aws/docker/library/openjdk:8-jdk` (Debian 11, OpenJDK 1.8.0_342) | Gradle 2.14, Android build-tools 23.0.2 (`dx.jar`), redis-tools, python3-redis |
| `driver-analysis` | `r-base:3.5.0` | R 3.5.0 with optparse 1.6.4, caret 6.0.84, plyr 1.8.4, gbm 2.1.5, doParallel 1.0.15 (from a 2019-10-01 CRAN snapshot) |
| `windshaft` (pulled, not built) | `quay.io/azavea/windshaft:0.1.0` | Map tile server |

---

## 4. How it was installed

### 4.1 Approach

1. **Preparation and testing in a cloud sandbox** (Claude). The repository was cloned and patched there. The Ansible playbooks were run against Ubuntu 14.04 test containers, all five Docker images were built, and the Django migrations were run against a test database. That surfaced most of the problems in section 5 before anything ran on the real machine.
2. **Delivery to `~/DRIVER`** of three files:
   - `install.sh`: one installer you can safely re-run; it continues where it stopped
   - `driver-local-fixes.patch`: all compatibility fixes as a single git commit
   - `DRIVER-INSTALL-NOTES.md`: notes and next steps
3. **Running `bash install.sh` on the real machine.** Each problem that came up was fixed in the installer or patch, then the installer was run again.

### 4.2 What `install.sh` does

| Step | Action |
|---|---|
| 1 | Checks the machine: x86_64, CPU virtualization, RAM (smaller VMs if < 15 GB), disk space |
| 2 | Installs NFS, build tools and **Oracle VirtualBox 7.1** (replacing Ubuntu's 6.1). Handles Secure Boot key enrolment, unloads KVM, waits for apt locks |
| 3 | Installs **Vagrant** (HashiCorp repo) and **vagrant-hostmanager** (falls back to rubygems.org) |
| 4 | Allows the `192.168.12.0/24` network in `/etc/vbox/networks.conf`, and opens ufw for NFS if ufw is active |
| 5 | Installs **uv → Python 3.8 → Ansible 2.9.27** in `~/driver-venv` |
| 6 | Downloads DRIVER from GitHub into `~/DRIVER`, checks out release 2.0.5 and applies `driver-local-fixes.patch` on branch `local-install-fixes` |
| 7 | `vagrant up --no-provision`, then sets up `database` → `app` → `celery` in order. A marker file in `.vagrant/` records each finished VM. A crashed VM is saved to `logs/` and recreated |
| 8 | Waits until http://localhost:7000 responds |

### 4.3 What the patch changes (by area)

| Area | Files |
|---|---|
| Vagrant | `Vagrantfile`, `vagrant/ansible_galaxy_helper.rb` |
| Ansible playbooks | `deployment/ansible/{database,app,celery}.yml`, `group_vars/all` |
| New compatibility role | `deployment/ansible/roles/driver.compat/` (tasks, defaults, CA bundle, PostgreSQL mirror index) |
| Bundled Galaxy roles | `deployment/ansible/roles/azavea.*` (9 roles, now part of the repository) |
| Other roles | `driver.monit`, `driver.heimdall`, `azavea.docker`, `azavea.nginx`, `azavea.pip`, `azavea.postgresql*`, `azavea.postgis`, `azavea.python-security` |
| Docker images | `app/Dockerfile.base`, `app/constraints-py27.txt`, `web/Dockerfile`, `web/bower.json`, `web/vendor/*`, `schema_editor/Dockerfile`, `gradle/Dockerfile`, `analysis_tasks/Dockerfile` |

Every change is marked with a `Local install patch` comment. To review all of them: `cd ~/DRIVER && git show local-install-fixes`.

---

## 5. Problems and solutions

The original guide anticipated 2 problems (1 and 2). In total, **31** had to be solved during installation (plus 2 afterwards, section 5.5): 20 found while testing in the sandbox, and 11 that only appeared on the real machine (marked *real machine*).

### 5.1 Host: Vagrant, VirtualBox, installer

| # | Problem | Symptom | Solution |
|---|---|---|---|
| 1 | Current Vagrant's Ruby removed `File.exists?` | `vagrant up` crashes immediately | Changed to `File.exist?` in `vagrant/ansible_galaxy_helper.rb` |
| 2 | VirtualBox only allows host-only networks in 192.168.56.0/21 | "IP address … not within the allowed ranges" | Added `* 192.168.12.0/24 192.168.56.0/21` to `/etc/vbox/networks.conf` |
| 3 | Ansible Galaxy no longer serves the 2019 role downloads | `ansible-galaxy` fails with HTTP 403 | Put the 8 pinned `azavea.*` roles into the repository, plus their missing `azavea.python` dependency, with version markers so Vagrant never contacts Galaxy |
| 4 | Ansible 2.9 removed syntax used by the roles (`version_compare`, `\| failed`, `\| search`, `\| changed`) | "No filter named 'version_compare'" | Updated to the new syntax (`is version(...)`, `is failed`, …) |
| 5 | Modern OpenSSH refuses SHA-1 `ssh-rsa` keys, the only RSA kind Ubuntu 14.04 supports | Ansible can't log in (possible) | Vagrantfile passes `PubkeyAcceptedKeyTypes=+ssh-rsa` and `HostKeyAlgorithms=+ssh-rsa` to Ansible |
| 6 | **Secure Boot** blocked the unsigned VirtualBox driver *(real machine)* | `modprobe vboxdrv failed` | Enrolled Ubuntu's MOK key once (`mokutil --import`, reboot, *Enroll MOK*). The driver is signed automatically |
| 7 | Installer bug: `cmd \| grep -q` under `set -o pipefail` reported a loaded driver as missing *(real machine)* | Asked to enrol the key again although it was enrolled | Replaced all such checks with checks that read the command's output first (`out_has`) or read `/proc/modules` directly |
| 8 | KVM kernel modules block VirtualBox | VMs fail to start | Installer (and `start-driver.sh`) unloads `kvm_intel`/`kvm` until the next reboot |
| 9 | `gems.hashicorp.com` unreachable *(real machine)* | `vagrant plugin install` timed out | Fall back to installing from rubygems.org only, then a direct `.gem` download |
| 10 | Ubuntu 22.04's **VirtualBox 6.1** crashes VMs on kernel 6.8 with this CPU *(real machine)* | VM state `gurumeditation` | Switched to **Oracle VirtualBox 7.1.18**. Crashed VMs are logged to `logs/` and recreated |
| 11 | Oracle's installer refuses while an old VirtualBox process runs *(real machine)* | "pre-installation script … exit status 1" | Installer powers off VMs and kills leftover `VBoxSVC`/`VBoxHeadless` processes first |
| 12 | Ubuntu's automatic updates held the apt lock *(real machine)* | "Could not get lock /var/lib/apt/lists/lock" | Installer waits up to 15 minutes for other package managers |

### 5.2 Inside the Ubuntu 14.04 VMs (new role `driver.compat`)

| # | Problem | Symptom | Solution |
|---|---|---|---|
| 13 | 2017-era root certificates; the expired DST Root CA X3 breaks Let's Encrypt chains | TLS errors | Installed the September 2026 Mozilla CA bundle and distrusted DST Root CA X3 |
| 14 | Python 2.7.6 has **no TLS SNI**, so Ansible's own downloads fail against modern servers | "Failed to validate the SSL certificate … SNI" | All downloads (`get_url`, `apt_key url=`, `ppa:`) replaced with `curl` |
| 15 | Ubuntu ESM apt sources can't be reached without a subscription | `apt-get update` fails | Removed `*esm*.list` |
| 16 | apt's HTTPS transport (GnuTLS 2.12) can't connect to modern servers | Docker apt repo unusable | Docker 17.06.2 downloaded as a `.deb` with curl and installed directly |
| 17 | PostgreSQL's apt repo for 14.04 moved to `apt-archive.postgresql.org`, which is HTTPS-only | "apt cache update failed", 404s | Built a **local apt mirror** in the database VM: the index ships with the role, and the 12 `.deb` files are fetched with curl and checked against their SHA256 hashes |
| 18 | `libpq-dev` was pinned to 9.3.4-1, which conflicts with `postgresql-server-dev-9.4` | "Unable to correct problems, held broken packages" | Pinned to the matching `11.3-1.pgdg14.04+1` |
| 19 | `en_US.UTF-8` locale missing | PostgreSQL refuses to start | `locale-gen en_US.UTF-8` |
| 20 | `get-pip.py` URL now serves Python 3 only | pip install would fail | Use `bootstrap.pypa.io/pip/2.7/get-pip.py`; pip 1.5.4 comes from apt |
| 21 | The nginx PPA no longer has 14.04 packages | Empty PPA, wrong signing key | Use Ubuntu's nginx 1.4.6. Both DRIVER nginx configs pass `nginx -t` |

### 5.3 Docker images

| # | Problem | Symptom | Solution |
|---|---|---|---|
| 22 | Debian 8/9/10/11 package repos moved to `archive.debian.org`, and Debian 10's PostgreSQL repo to `apt-archive.postgresql.org` | `apt-get update` 404s; jessie keys expired | All Dockerfiles point at the archives; jessie marked `trusted=yes` |
| 23 | Newer Python package releases are Python-3-only | "Package 'rsa' requires a different Python", "setuptools>=64" | `app/constraints-py27.txt` pins all 84 packages to working versions |
| 24 | Three GitHub repos used by bower were deleted: `ajsd/angular-uuid`, `shahata/angular-debounce`, `Teleborder/FileSaver.js`. GitHub also dropped the `git://` protocol | bower "Authentication failed" | Local copies in `web/vendor/` (see its README), FileSaver served as a local git repo, `git://` rewritten to `https://` |
| 25 | Newer tool versions no longer work with Ruby 2.3 / Node 8: `multi_json` (needs Ruby 3.2), `grunt-cli` (needs Node 10), `tough-cookie` (newer syntax) | Gem install fails; grunt crashes; "Unexpected token ." | Pinned multi_json 1.15.0, chunky_png 1.3.15, compass 1.0.3, grunt-cli 1.2.0, bower 1.8.14, tough-cookie 2.5.0 |
| 26 | CRAN packages now need R ≥ 4; the original install **failed silently** | Black-spot analysis would break later | Install from a dated **2019-10-01 CRAN snapshot**; the build now fails loudly if a package is missing |
| 27 | Docker Hub deleted the `openjdk:8-jdk` image *(real machine)* | "manifest for openjdk:8-jdk not found" | Use the identical image from Amazon's mirror: `public.ecr.aws/docker/library/openjdk:8-jdk` |

### 5.4 Network inside the VMs *(real machine)*

| # | Problem | Symptom | Solution |
|---|---|---|---|
| 28 | pip 1.5 downloads from PyPI hung with no timeout | Stuck on "Install Python TLS SNI dependencies" | The 3 Python packages are fetched with curl into `/var/cache/pip-local` (checked against their SHA256 hashes) and pip installs from there with `--no-index` |
| 29 | VirtualBox NAT has no IPv6 route | "Failed to connect to www.postgresql.org … Network is unreachable" | `.curlrc` forces IPv4 with 5 retries. The PostgreSQL key download was removed as no longer needed |
| 30 | Downloads stalled partway through in the celery VM | Stuck on "Download Python packages" | `.curlrc` aborts transfers below 1 KB/s for 60 s, then retries. The celery VM was reset with `vagrant reload celery` |
| 31 | Each VM's setup ran on **all** VMs, so a celery problem blocked the app VM | App setup waited on celery | Vagrantfile limits: the app VM sets up `app,database`, and the celery VM sets up `celery` only |

### 5.5 After installation

| # | Problem | Symptom | Solution |
|---|---|---|---|
| 32 | Carto basemaps now require an API key, at both the old `cartodb-basemaps-*.global.ssl.fastly.net` address and the newer `basemaps.cartocdn.com` | Maps show only "API KEY REQUIRED" tiles | Streets layer switched to Esri's keyless World Street Map (`server.arcgisonline.com/.../World_Street_Map`) in `web/app/scripts/map-layers/baselayers-service.js`, then the web app was rebuilt |
| 33 | Configuration still had the Philippines defaults | Times in Manila time, map centred on the Philippines | `group_vars/development`: `Asia/Dhaka`, `bd`, `[23.7, 90.4]`, Bangladesh OSM extract, then ran `vagrant provision app` |

Smaller, harmless messages you may see:

- `xauth: file … .Xauthority does not exist` (X11 forwarding is enabled in the Vagrantfile)
- "guest additions do not match" (shared folders use NFS, not guest additions)
- "No package matching linux-image-extra-…" (ignored fallback; Docker works)
- Ansible deprecation warnings

---

## 6. Dependency checklist

All items are installed and verified on `Fardeen-XPS`.

### Host

- [x] Ubuntu 22.04 x86_64 with CPU virtualization (VT-x) enabled
- [x] ≥ 15 GB RAM, ≥ 30 GB free disk
- [x] git, curl, wget, gnupg, gcc, make, perl, `linux-headers-$(uname -r)`
- [x] nfs-kernel-server, nfs-common
- [x] Oracle VirtualBox 7.1.18 (Ubuntu's 6.1 removed)
- [x] VirtualBox kernel driver loaded and signed (Secure Boot MOK key enrolled)
- [x] KVM modules unloaded before starting VMs (repeat after every reboot; `start-driver.sh` does this)
- [x] `/etc/vbox/networks.conf` allows `192.168.12.0/24`
- [x] Vagrant 2.4.9
- [x] vagrant-hostmanager 1.8.10
- [x] uv 0.12.22
- [x] Python 3.8.20 in `~/driver-venv`
- [x] Ansible 2.9.27 in `~/driver-venv`
- [x] DRIVER 2.0.5 source in `~/DRIVER`, branch `local-install-fixes` with fixes applied
- [x] `gradle/data/driver.keystore` present (empty, so Android JAR signing is off)

### VMs

- [x] Vagrant box `ubuntu/trusty64` v20191107.0.0
- [x] VM `database` (192.168.12.101) running and set up
- [x] VM `app` (192.168.12.102) running and set up
- [x] VM `celery` (192.168.12.103) running and set up
- [x] Mozilla CA bundle, curl settings, pip SNI support (all VMs)
- [x] Docker CE 17.06.2 (app, celery)
- [x] monit 5.17.1 (all VMs)
- [x] PostgreSQL 9.4.22 + PostGIS 2.3.3 + `driver`, `windshaft`, `heimdall` databases and users (database)
- [x] Redis 2.8.4 (database)
- [x] nginx 1.4.6 (app, celery)
- [x] heimdall 0.2.3 and cron jobs for black spots, duplicate records and CSV clean-up (celery)
- [x] Firewall (ufw) rules on all VMs

### Docker images and containers

- [x] `driver-app` built and running; migrations applied; admin user created (app)
- [x] `windshaft` pulled and running (app)
- [x] `driver-web` and `driver-editor` built; production front-ends built (app)
- [x] `driver-app` built for celery; `driver-celery` worker running (celery)
- [x] `driver-gradle` built and running (celery)
- [x] `driver-analysis` built (celery)

### Final check

- [x] http://localhost:7000/ answers (checked by the installer)

### Still to do (configuration, not installation)

- [x] Set Bangladesh locale in `deployment/ansible/group_vars/development` (`Asia/Dhaka`, `bd`, `[23.7, 90.4]`), then run `vagrant provision app`
- [ ] Upload boundary shapefiles in the editor
- [ ] Configure cost aggregation in the editor
- [ ] Optional: load the sample data (see `DRIVER-INSTALL-NOTES.md`)
- [ ] Optional: geocoding key (`web_js_nominatim_key`), Google sign-in, real Android keystore
- [ ] Change the default `admin` / `admin` password before anyone else uses it

---

## 7. Daily use

| Task | Command (in `~/DRIVER`) |
|---|---|
| Start after a reboot | `bash start-driver.sh` |
| Stop before shutting down | `vagrant halt` |
| VM status | `vagrant status` |
| Shell into a VM | `vagrant ssh app` (or `database`, `celery`) |
| Re-apply configuration | `source ~/driver-venv/bin/activate && vagrant provision app` |
| Restart one VM | `vagrant reload app` |
| Delete everything | `vagrant destroy -f && rm -f .vagrant/driver-provisioned-*` |

## 8. Files in `~/DRIVER`

| File | Purpose | On GitHub? |
|---|---|---|
| `install.sh` | Installer; safe to re-run | Yes |
| `start-driver.sh` | Start DRIVER after a reboot | Yes |
| `DRIVER-INSTALL-NOTES.md` | Short notes and next steps | Yes |
| `DRIVER-INSTALLATION-REPORT.md` | This report | Yes |
| `README.md` | How to install and use this fork (the original README is in `doc/README-original.md`) | Yes |
| `dummy-data/` | Dummy Bangladesh boundaries and 600 dummy crashes, with a loader | Yes |
| `_local/` | Local-only files: the patch file, old copies and lesson helper scripts | No (ignored by git) |
| `install.log`, `logs/` | Installer output and saved VM crash logs | No (ignored by git) |
| `app/_loaders/` | Data-loading scripts and practice CSV, visible inside the app VM | No (ignored by git) |
| `deployment/ansible/group_vars/development` | This machine's settings (Bangladesh time zone etc.) | No (kept local, as DRIVER's original README recommends) |

The fixes themselves are in the git branch `local-install-fixes`. Anyone who clones that branch gets them; the `.patch` file is only needed to apply them to a fresh download of the original repository.
