# DRIVER: Road Crash Data System (2026 installable edition)

**DRIVER** (Data for Road Incident Visualization, Evaluation, and Reporting) is an open-source
web platform for recording, mapping and analysing road crashes. It was originally built by
[Azavea](https://www.azavea.com/) for the World Bank:
https://github.com/WorldBank-Transport/DRIVER

The original project was last updated in 2019 (release 2.0.5) and no longer installs on a
current computer: old download sites are gone, software versions have moved on, and many
dependencies were deleted. **This fork adds 33 compatibility fixes and a one-command
installer**, tested end to end on Ubuntu 22.04 in October 2026. What was changed and why is
documented in [`DRIVER-INSTALLATION-REPORT.md`](DRIVER-INSTALLATION-REPORT.md).

With DRIVER you can:

- record crashes with location, date/time, severity, vehicles, people and photos
- design your own data-entry forms in a schema editor
- see crashes on a map (points, heatmap) and filter by area, date and any field
- find **black spots** (high-risk locations) and estimate the **economic cost** of crashes
- build summary reports and export data to CSV

---

## Tested environment

### Your computer (the host)

| Item | Version used for testing |
|---|---|
| Operating system | **Ubuntu 22.04.5 LTS** (x86_64), kernel 6.8.0 (HWE) |
| Hardware | 20-core Intel CPU with VT-x, 15 GB RAM, Secure Boot **on** |
| VirtualBox | **7.1.18** (Oracle build, installed by the installer) |
| Vagrant | **2.4.9** (HashiCorp) |
| vagrant-hostmanager plugin | **1.8.10** |
| Python (in `~/driver-venv`) | **3.8.20**, installed with uv 0.12.22 |
| Ansible | **2.9.27** |
| NFS server | nfs-kernel-server 2.6.1 |

Other recent Ubuntu/Debian releases on x86_64 should work, but only 22.04 was tested.
Apple Silicon Macs and Windows are **not** supported.

### Inside DRIVER (installed automatically)

| Part | Version |
|---|---|
| DRIVER | 2.0.5 + fixes (branch `local-install-fixes`) |
| Virtual machines | 3 × Ubuntu 14.04 (`ubuntu/trusty64` v20191107.0.0) |
| Database | PostgreSQL 9.4.22 + PostGIS 2.3.3, Redis 2.8.4 |
| Containers | Docker CE 17.06.2 |
| Backend | Django 1.11.26 on Python 2.7.17, Celery 3.1.19 |
| Frontend | AngularJS 1.5, Leaflet 0.7 (built with Node 8.17) |
| Web server | nginx 1.4.6 |
| Black-spot analysis | R 3.5.0 (caret, gbm, …) |
| Base map | Esri World Street Map (no API key needed) |

### Requirements

- Ubuntu/Debian on an **x86_64** computer, with **CPU virtualization (VT-x / AMD-V) enabled** in BIOS/UEFI
- **16 GB RAM** recommended (10 GB minimum: the installer then uses smaller VMs)
- **30 GB free disk space**
- Internet access and an account with `sudo` rights

---

## Installation

```bash
git clone -b local-install-fixes https://github.com/fardeensadab/DRIVER.git ~/DRIVER
cd ~/DRIVER
bash install.sh
```

The installer runs 8 steps and can safely be run again. If something stops it, fix the cause
and run `bash install.sh` again: it continues where it left off.

| Step | What it does |
|---|---|
| 1 | Checks the computer (CPU virtualization, RAM, disk) |
| 2 | Installs Oracle VirtualBox 7.1, NFS and build tools |
| 3 | Installs Vagrant and the vagrant-hostmanager plugin |
| 4 | Allows DRIVER's VM network `192.168.12.0/24` in VirtualBox |
| 5 | Installs uv → Python 3.8 → Ansible 2.9.27 in `~/driver-venv` |
| 6 | Checks the DRIVER source and fixes |
| 7 | Creates and sets up the 3 VMs (**30–90 minutes** the first time) |
| 8 | Checks that http://localhost:7000 answers |

Things to expect:

- **Your sudo password** is asked a few times, including once by Vagrant to set up shared folders.
- **Secure Boot on?** The installer stops once and asks you to choose a temporary password.
  Reboot, choose **Enroll MOK → Continue → Yes** on the blue screen, enter the password, then
  run `bash install.sh` again.
- Long periods without output during step 7 are normal (Docker images are being built).
- Everything is logged to `install.log`.

When it finishes:

| | |
|---|---|
| Web app | http://localhost:7000/ |
| Schema editor | http://localhost:7000/editor/ |
| Django admin | http://localhost:7000/admin/ |
| Login | `admin` / `admin` (change it, see below) |

---

## Everyday use

| Task | Command (in `~/DRIVER`) |
|---|---|
| **Start** DRIVER after a reboot | `bash start-driver.sh` |
| **Stop** DRIVER (before shutting down) | `vagrant halt` |
| Status of the VMs | `vagrant status` |
| Shell inside a VM | `vagrant ssh app` (or `database`, `celery`) |
| Re-apply configuration | `source ~/driver-venv/bin/activate && vagrant provision app` |

`start-driver.sh` also unloads the KVM kernel module, which loads at every boot and blocks
VirtualBox.

---

## First-time setup

DRIVER starts empty. Set it up in the **editor** (http://localhost:7000/editor/):

1. **Change the admin password:** http://localhost:7000/admin/ → Users → admin → "this form".
2. **Create the crash form:** *Add a new record type* with the single title **`Incident`**
   (exactly this word, because the web app looks for it). Then *View related content → Edit*
   to add fields such as Severity (select list: Fatal / Injury / Property), Collision type and
   number of vehicles. Add sections like *Vehicles* and *People* with **Allow multiple** ticked.
3. **Upload boundaries:** *Add new geographies* → a zipped shapefile (e.g. districts) → pick the name field.
4. **Set costs:** *Incident → Cost aggregation settings* → content type *Incident Details*,
   field *Severity*, a cost per level.
5. **Add users:** *Manage Users*, with groups admin / analyst (can edit) / public (read-only).

Then enter crashes in the **web app** with the **⊕** button in the filter bar, or at
http://localhost:7000/#!/add.

### Practice data

[`dummy-data/`](dummy-data/) has dummy Bangladesh division boundaries and 600 dummy crashes,
with a one-command loader. See [`dummy-data/README.md`](dummy-data/README.md).

### Regional settings

Time zone, country and map centre are set in `deployment/ansible/group_vars/development`
(defaults: `Asia/Manila`, `ph`). For Bangladesh, for example:

```yaml
local_time_zone_id: 'Asia/Dhaka'
local_country_code: 'bd'
local_center_lat_lon: [23.7, 90.4]
osm_extract_url: 'https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf'
```

Then run `source ~/driver-venv/bin/activate && vagrant provision app`.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Installer says *vboxdrv not loaded*, Secure Boot on | Follow its MOK instructions, reboot, enroll the key, run `bash install.sh` again |
| VM state `gurumeditation` | Usually old VirtualBox: the installer replaces Ubuntu's 6.1 with Oracle 7.1 and recreates the VM |
| A setup step hangs on a download | Press Ctrl+C, then `vagrant reload <vm>` and `bash install.sh` |
| *Could not get lock /var/lib/apt/…* | Automatic updates are running; the installer waits for them |
| Site doesn't load after a reboot | Run `bash start-driver.sh`; if it's still down after a few minutes: `vagrant reload app` |
| Maps blank or old after an update | Open the site in a private window, or clear the browser cache |
| Save button in the editor does nothing | A field on the page is incomplete (no title, empty option, duplicate name); fix the field marked in red |

The full list of the 33 problems found and how each was fixed is in
[`DRIVER-INSTALLATION-REPORT.md`](DRIVER-INSTALLATION-REPORT.md).

---

## Repository layout

| Path | Contents |
|---|---|
| `install.sh`, `start-driver.sh` | Installer and start script (added in this fork) |
| `DRIVER-INSTALLATION-REPORT.md` | Components, installation method, problems and fixes, dependency checklist |
| `DRIVER-INSTALL-NOTES.md` | Short notes, sample-data loading and next steps |
| `dummy-data/` | Practice boundaries and crashes |
| `app/` | Django backend (API, auth, black spots) |
| `web/` | Main web app (AngularJS) |
| `schema_editor/` | Schema editor (AngularJS) |
| `windshaft/` | Map tile server configuration |
| `analysis_tasks/` | R black-spot analysis |
| `gradle/` | Builds form JARs for the Android app |
| `deployment/ansible/` | Ansible playbooks and roles (includes the `driver.compat` fixes role) |
| `doc/` | Original documentation; the original README is [`doc/README-original.md`](doc/README-original.md) |

## Credits and license

DRIVER was created by Azavea for the World Bank (WorldBank-Transport/DRIVER). This fork only
adds compatibility fixes, installation tooling, documentation and dummy data.
Licensed under the **GNU General Public License v3.0**; see [`LICENSE`](LICENSE).
