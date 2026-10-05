# DRIVER install notes (October 2026)

This folder holds an installer for DRIVER (https://github.com/WorldBank-Transport/DRIVER, release 2.0.5),
plus a set of fixes that let the 2019 code install today.

| File | What it is |
|---|---|
| `install.sh` | One-shot installer. Run `bash install.sh` from this folder |
| `driver-local-fixes.patch` | All compatibility fixes as one git commit; `install.sh` applies it to a fresh download of the original repo. Not needed when you clone the `local-install-fixes` branch, which already contains them (kept locally in `_local/`) |
| `DRIVER-INSTALL-NOTES.md` | This file |

## How to run

```bash
cd ~/DRIVER
bash install.sh
```

- Run it as your normal user. It asks for your sudo password when it needs it, and Vagrant asks again when it sets up the NFS shared folders.
- If Secure Boot is on, the script stops after installing VirtualBox and tells you how to enroll the MOK key. Reboot, enroll the key, then run `bash install.sh` again.
- The script remembers what it has finished. If a step fails, fix the cause and run it again. It picks up where it stopped (for example, at the VM that failed).
- Everything it prints is also saved to `install.log` in this folder (local only, not pushed to GitHub).
- Expect 30–90 minutes the first time. Most of that is downloading the Ubuntu 14.04 box and building Docker images inside the VMs.

When it finishes, open http://localhost:7000/ and log in with `admin` / `admin`. The schema editor is at http://localhost:7000/editor/.

## What was tested before delivery

These were checked in a cloud sandbox. It can't run VirtualBox, so the VMs themselves were stood in for by Ubuntu 14.04 containers:

| Part | Result |
|---|---|
| `database` playbook (PostgreSQL 9.4, PostGIS 2.3, Redis, monit, firewall) run with Ansible 2.9.27 against Ubuntu 14.04 | Completes with no failures |
| `driver-app` Docker image (Django 1.11, Python 2.7) + dev image | Builds; `manage.py migrate` applies every migration against the provisioned database and creates the admin user |
| `driver-web` and `driver-editor` Docker images | Build; `grunt build` produces the production web app |
| `driver-gradle` Docker image (Android JAR builder) | Builds |
| `driver-analysis` Docker image (R black-spot analysis) | Builds; optparse, caret, plyr, gbm and doParallel all load |
| `app` and `celery` playbooks against Ubuntu 14.04 | Run cleanly through the CA/SNI fixes, Docker 17.06, monit and nginx, up to the point where they need the real VMs (NFS folders, upstart) |
| Vagrantfile + galaxy helper on Vagrant 2.4.9 / Ruby 3.3 | Loads, and no Ansible Galaxy download is needed |

These were **not** tested because they need a real VirtualBox host: booting the VMs, NFS shared folders, and the upstart services that run the containers inside the `app` and `celery` VMs.

## Problems found and how they are fixed

The guide you had listed 2 fixes. Installing in 2026 needed 20. Every change is marked with a `Local install patch` comment in the code. Run `git show` in this folder after installing to see all of them.

### Host / Vagrant
1. **Ruby `File.exists?` removed** (as in the guide). Fixed in `vagrant/ansible_galaxy_helper.rb`.
2. **VirtualBox only allows 192.168.56.0/21** (as in the guide). `install.sh` adds `192.168.12.0/24` to `/etc/vbox/networks.conf`.
3. **Ansible Galaxy downloads fail.** The 9 `azavea.*` roles (plus the missing `azavea.python` dependency) are now included in the repository at their pinned versions, so Galaxy is never contacted.
4. **Ansible 2.9 removed old syntax** used by the roles (`version_compare`, `| failed`, `| search`, `| changed`). The guide's Ansible 2.9.27 would stop on the database VM. The roles are updated to the new syntax.
5. **Modern OpenSSH refuses `ssh-rsa`** keys, the only RSA kind Ubuntu 14.04 understands. The Vagrantfile passes `+ssh-rsa` options to Ansible's SSH.
6. **KVM conflict on new kernels (6.12+).** VirtualBox can't start VMs while KVM is loaded. `install.sh` unloads the KVM modules if no other VM is using them.

### Inside the Ubuntu 14.04 VMs (new role `driver.compat`, runs first on every VM)
7. **Out-of-date root certificates.** A current Mozilla CA bundle is installed, and the expired DST Root CA X3 is distrusted.
8. **Python 2.7.6 has no TLS SNI**, so Ansible's own downloads (`get_url`, `apt_key url=`, `ppa:`) fail against today's servers. Those steps now use `curl`. pip gets SNI from pyOpenSSL plus `ndg-httpsclient` (checksum-verified).
9. **Ubuntu ESM apt sources** (if the box has them) break `apt-get update`. They are removed.
10. **apt's HTTPS (GnuTLS 2.12) can't talk to modern servers.** Docker 17.06 is now installed from its `.deb`. The PostgreSQL archive, which moved to `apt-archive.postgresql.org` and is HTTPS-only, is served from a small local apt mirror built with `curl` (checksum-verified).
11. **The `libpq-dev 9.3.4-1` pin conflicts** with `postgresql-server-dev-9.4`. The pin is changed to the matching 11.3 package.
12. **The `en_US.UTF-8` locale** is generated, because PostgreSQL's config uses it.
13. **`get-pip.py` URL** now points at the Python 2.7 version.
14. **The nginx PPA is empty for Ubuntu 14.04.** nginx now comes from Ubuntu's own repository (1.4.6). Both DRIVER nginx configs pass `nginx -t` with it.

### Docker images built inside the VMs
15. **Debian archives moved.** jessie, stretch, buster and bullseye now point to `archive.debian.org`, and buster's PostgreSQL repo to `apt-archive.postgresql.org`.
16. **Python 2.7 dependencies.** Newer releases are Python-3-only. `app/constraints-py27.txt` pins the full working set (84 packages).
17. **Deleted GitHub repositories used by bower.** `ajsd/angular-uuid`, `shahata/angular-debounce` and `Teleborder/FileSaver.js` no longer exist. Local copies are in `web/vendor/` (see its README). The `git://` protocol is rewritten to `https://`.
18. **Ruby gems.** The latest `multi_json` needs Ruby 3.2, so compass and its dependencies are pinned.
19. **Node 8 tools.** The latest `grunt-cli` and `tough-cookie` need newer Node, so both are pinned.
20. **R packages.** CRAN now needs R ≥ 4, and the original install failed *silently*, which would have broken black-spot analysis. Packages now come from a dated 2019-10-01 CRAN snapshot, and the build fails loudly if any are missing.

## After installation (from your original guide)

1. **Boundaries.** In the editor, choose *Add new geographies* and upload a zipped shapefile (for example, Bangladesh divisions from Natural Earth). Pick `name` as the display field.
2. **Sample data.** Get your API token from the browser's Network tab (the `Authorization: Token …` header). The loaders are Python 2 scripts that need GDAL, so run them inside the `app` VM. Its `/opt/app` folder is shared with `~/DRIVER/app`:
   ```bash
   cd ~/DRIVER && source ~/driver-venv/bin/activate
   cp -r scripts app/_loaders            # makes them visible in the VM as /opt/app/_loaders
   vagrant ssh app
   # --- inside the VM ---
   sudo apt-get install -y python-gdal python-dateutil python-tz python-requests
   sudo pip install geojson==2.5.0
   cd /opt/app/_loaders
   python load_incidents_v3.py --api-url http://localhost/api --authz 'Token <TOKEN>' sample_data/
   python load_black_spots.py  --api-url http://localhost/api --authz 'Token <TOKEN>' sample_data/black_spots.json
   python load_interventions.py --api-url http://localhost/api --authz 'Token <TOKEN>' sample_data/interventions_sample_pts.geojson
   ```
   The full incident set takes about 2 hours. To try it faster, shorten the CSV first, for example `head -2000 sample_data/sample_traffic.csv > /tmp/s.csv`, and point the loader at a folder that holds only that file. Delete `app/_loaders` when you're done.
3. **Costs.** In the editor, open Incident → *Cost aggregation settings* and set the currency prefix, *Incident Details* and *Severity*, then a cost per level.
4. **Localization.** `deployment/ansible/group_vars/development` still uses the Philippines defaults: `local_time_zone_id: 'Asia/Manila'`, `local_country_code: 'ph'` and the map centre. For Bangladesh, change these to `Asia/Dhaka`, `bd` and `[23.7, 90.4]`, then run `vagrant provision app`.

## Everyday commands

Run these in `~/DRIVER` after `source ~/driver-venv/bin/activate`:

| Task | Command |
|---|---|
| Start / stop VMs | `vagrant up` / `vagrant halt` |
| Status | `vagrant status` |
| Shell in a VM | `vagrant ssh app` (or `database`, `celery`) |
| Re-run setup for one VM | `vagrant provision app` |
| Delete everything | `vagrant destroy` (then delete `.vagrant/driver-provisioned-*`) |

## Known risks that could not be tested

- **Docker Hub limits anonymous pulls.** If a build in the `celery` VM fails with `toomanyrequests`, wait an hour and run `bash install.sh` again.
- **Debian 11 (bullseye) is moving to the archive.** The gradle image already uses `archive.debian.org`.
- **The box's own hardware settings.** If a VM hangs at boot with VirtualBox 7, run `vagrant reload <vm>`.

## Install log — completed 2026-10-04 on Fardeen-XPS (Ubuntu 22.04, kernel 6.8, Secure Boot on)

All three VMs provisioned with 0 failures, and http://localhost:7000 answers. Problems that only showed up on the real machine, all now fixed in `install.sh` and the patch:
- **Secure Boot:** the VirtualBox driver key had to be enrolled once (MOK screen at reboot).
- **Installer bug:** `cmd | grep -q` under `pipefail` gave false "not loaded" results. Replaced with checks that don't use pipes.
- **Vagrant plugin download:** gems.hashicorp.com timed out, so the installer falls back to rubygems.org.
- **VirtualBox:** Ubuntu's 6.1 crashed VMs ("gurumeditation") on kernel 6.8 with this CPU, so the installer switches to Oracle VirtualBox 7.1. It first stops leftover VBox processes and waits for apt locks.
- **Downloads in the VMs:** pip downloads hung, so packages are now fetched with curl into a local folder. curl is forced to IPv4 and gives up on stalled downloads. The PostgreSQL key download was removed (no longer needed).
- **Celery VM network:** it stalled once and was fixed with `vagrant reload celery`. Each VM's setup now only touches the hosts it needs.
- **Docker Hub:** removed `openjdk:8-jdk`. The gradle image now uses `public.ecr.aws/docker/library/openjdk:8-jdk`.
