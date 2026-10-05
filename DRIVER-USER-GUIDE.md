# DRIVER: Installation and User Guide

**DRIVER** (Data for Road Incident Visualization, Evaluation, and Reporting) is an open-source
platform for recording, mapping and analysing road crashes. This guide covers installing the
updated edition, configuring it, entering data and analysing it.

| Resource | Link |
|---|---|
| This edition (installable, with fixes) | https://github.com/fardeensadab/DRIVER (branch `local-install-fixes`) |
| Original project (World Bank / Azavea) | https://github.com/WorldBank-Transport/DRIVER |
| Full installation report (versions, problems, fixes) | [`DRIVER-INSTALLATION-REPORT.md`](DRIVER-INSTALLATION-REPORT.md) |
| Practice data | [`dummy-data/`](dummy-data/) |

---

## 1. Requirements

| Item | Requirement |
|---|---|
| Operating system | Ubuntu 22.04 LTS, x86_64 (tested on 22.04.5, kernel 6.8) |
| CPU | Hardware virtualization (VT-x / AMD-V) enabled in BIOS/UEFI |
| Memory / disk | 16 GB RAM recommended (10 GB minimum); 30 GB free disk |
| Access | Internet connection and a user account with `sudo` rights |

The installer sets up the following tools itself, at the versions tested:
[VirtualBox](https://www.virtualbox.org/wiki/Linux_Downloads) 7.1.18,
[Vagrant](https://developer.hashicorp.com/vagrant/install) 2.4.9 with vagrant-hostmanager 1.8.10,
[uv](https://docs.astral.sh/uv/) with Python 3.8.20, and
[Ansible](https://docs.ansible.com/ansible/2.9/) 2.9.27.

## 2. Installation

```bash
git clone -b local-install-fixes https://github.com/fardeensadab/DRIVER.git ~/DRIVER
cd ~/DRIVER
bash install.sh
```

The installer runs eight steps. The first run takes 30–90 minutes. If it stops, correct the
reported problem and run `bash install.sh` again: completed steps are skipped.

- **Secure Boot:** if it is on, the installer asks for a one-time password and stops. Reboot,
  choose **Enroll MOK → Continue → Yes** on the blue screen, enter the password, and run the
  installer again ([background](https://wiki.ubuntu.com/UEFI/SecureBoot)).
- All output is saved to `install.log`.

After installation:

| Component | Address |
|---|---|
| Web application | http://localhost:7000/ |
| Schema editor | http://localhost:7000/editor/ |
| Administration | http://localhost:7000/admin/ |
| Default login | `admin` / `admin` (change it immediately, see Section 4.5) |

## 3. Starting and stopping

| Action | Command (in `~/DRIVER`) |
|---|---|
| Start after a reboot | `bash start-driver.sh` |
| Stop before shutting down | `vagrant halt` |
| Check status | `vagrant status` |
| Apply configuration changes | `source ~/driver-venv/bin/activate && vagrant provision app` |

**Regional settings.** Time zone, country and map centre are set in
`deployment/ansible/group_vars/development`. For Bangladesh, set `local_time_zone_id: 'Asia/Dhaka'`,
`local_country_code: 'bd'` and `local_center_lat_lon: [23.7, 90.4]`, then apply the configuration.

## 4. Configuration (schema editor)

DRIVER has two interfaces. The **schema editor** (`/editor/`) is used by administrators to design
forms and configure the system. The **web application** (`/`) is used to enter and analyse data.

### 4.1 Data model

```
Record Type "Incident"         one crash; always has location, date/time and address
 ├─ Incident Details (single)  general information: severity, collision type, casualties
 ├─ Vehicles (multiple)        one entry per vehicle
 └─ People   (multiple)        one entry per person, linked to a vehicle
```

### 4.2 Create the record type and its fields

1. **Add a new record type:** Single title `Incident` (this exact name is required),
   Plural title `Incidents`, a description. **Save**. DRIVER creates the *Incident Details* section.
2. **Incident → View related content → Edit** on *Incident Details*, and add fields:

| Field type | Title | Settings |
|---|---|---|
| Select List | Severity | `Fatal`, `Injury`, `Property`; Required; Filterable/Searchable |
| Select List | Collision type | e.g. `Head on`, `Rear end`, `Side swipe`, `Hit pedestrian`, `Overturned`; Filterable/Searchable |
| Number Field | Number of vehicles | Minimum 1 |
| Number Field | Number killed / Number injured | Minimum 0 |
| Text Field | Description | Text option `textarea` |

Add and save fields one at a time. The **Save** button is disabled while any field is incomplete,
for example a missing title, an empty option or a duplicate name.

### 4.3 Add Vehicles and People

**Incident → Add related content**, with **Allow multiple?** ticked:

| Section | Fields |
|---|---|
| Vehicle / Vehicles | Vehicle type (select, filterable), Plate number (text), Damage (select) |
| Person / People | Role, Injury (select, filterable), Sex (select), Age (number 0–120), Vehicle (**Relationship** → Vehicles) |

Use **View all record types → Preview** to review the complete form.

**Rules:** do not rename the *Incident* record type; once data exists, add fields or options
rather than renaming or deleting them; use a single record type for all crashes.

### 4.4 Boundaries and costs

- **Boundaries:** *All Geographies → Add new geographies* → label (e.g. `Divisions`) → zipped
  shapefile (`.shp`, `.shx`, `.dbf`, `.prj`, WGS84) → **Upload** → Display Field `name` → **Save**.
  Official Bangladesh boundaries are available from
  [HDX](https://data.humdata.org/dataset/cod-ab-bgd); a practice file is in
  `dummy-data/bd_divisions_dummy.zip`.
- **Costs:** *Incident → Cost aggregation settings* → prefix (e.g. `BDT `) → content type
  *Incident Details* → field *Severity* → a cost per level → **Save**.
- **Black spots:** *System Settings* sets the severity threshold (0–1). The default is suitable.

### 4.5 Users and password

- **Password:** http://localhost:7000/admin/ → Users → admin → "this form".
- **Users:** editor → *Manage Users* → add a user with group **admin** (full access),
  **analyst** (enter and edit data) or **public** (read only).

## 5. Data entry (web application)

1. Open the form with the **⊕** button at the right of the filter bar (Map or Record List page),
   or at http://localhost:7000/#!/add.
2. **Location & Time:** click the map or enter latitude/longitude, then set the date and time.
3. Complete **Incident Details**, add **Vehicles** and **People**, and link each person to a vehicle.
4. **Save.** The record appears in the Record List, on the map and in the statistics.

Records can be opened from the **Record List** to view, **Edit** or **Delete** them. DRIVER assigns
each record to its boundary automatically from its location.

**Bulk loading.** To load the practice dataset of 600 crashes:

```bash
python3 dummy-data/load_dummy_data.py            # or --limit 50
```

It adapts to your form and asks for confirmation before loading.
See [`dummy-data/README.md`](dummy-data/README.md).

## 6. Analysis

| Feature | Location | Use |
|---|---|---|
| Area filter | Top bar: boundary set and area | Restricts every page to one area |
| Dashboard | Page menu → Dashboard | Totals, economic cost, time-of-day chart, recent crashes |
| Map | Page menu → Map | Points, **Heatmap**, **Blackspots**, street or satellite base map |
| Filters | Grey filter bar | Date range, filterable fields, text search; **✖** clears all |
| Saved filters | Filter bar → filter icon | Store frequently used filters |
| Custom Report | Map → **Export** → Custom Report | Tables such as Division × Severity or Month × Severity |
| CSV export | Map → **Export** → Export CSV → Download | Spreadsheet of the filtered records |

Black spots are calculated nightly. To calculate them immediately:

```bash
vagrant ssh celery -c 'sudo docker exec $(sudo docker ps -q -f name=driver-celery) ./manage.py calculate_black_spots'
```

## 7. Troubleshooting

| Symptom | Action |
|---|---|
| Site not available after a reboot | `bash start-driver.sh`; if it is still down after a few minutes, `vagrant reload app` |
| Records missing from the list | Set the area filter to **All** and clear filters (**✖**); filters are remembered |
| Maps blank or outdated | Open the site in a private window or clear the browser cache |
| Installer stops | Read the last lines of `install.log`, fix the cause and run `bash install.sh` again |

All 33 problems resolved for this edition are listed in
[`DRIVER-INSTALLATION-REPORT.md`](DRIVER-INSTALLATION-REPORT.md).

---

*DRIVER was created by Azavea for the World Bank and is licensed under the GNU GPL v3.0.*
