# Dummy data for practice

Made-up Bangladesh data for learning DRIVER and trying out its maps, filters and reports.
**None of it is real.** The boundaries are rough rectangles and the crashes are randomly
generated.

| File | What it is |
|---|---|
| `bd_divisions_dummy.zip` | Zipped shapefile with Bangladesh's 8 divisions as simple rectangles (fields: `name`, `code`, `note`; WGS84) |
| `bd_dummy_incidents.csv` | 600 dummy crashes, April–October 2026, spread over the 8 divisions with 5 crash clusters |
| `load_dummy_data.py` | Loads the CSV into DRIVER (Python 3, standard library only) |
| `gen_bd_incidents.py` | The script that generated the CSV (re-run it to make a new random set) |

## 1. Upload the boundaries

1. Open the editor: http://localhost:7000/editor/
2. **All Geographies → Add new geographies**
3. Geography Label: `Divisions`. Choose `bd_divisions_dummy.zip` and click **Upload**.
4. Display Field: `name`. Pick a colour and click **Save**.

The web app's top menu now has a **Divisions** filter (Dhaka, Chattogram, …).

## 2. Load the crashes

With DRIVER running, from the repository folder:

```bash
python3 dummy-data/load_dummy_data.py              # all 600
python3 dummy-data/load_dummy_data.py --limit 50   # or only the first 50
```

It asks for a DRIVER login (default `admin`), shows which of your form's fields it will fill,
and asks before loading.

- **No "Incident" record type yet?** It creates DRIVER's standard crash form
  (`scripts/incident_schema_v3.json`), and every CSV column is used.
- **Built your own form?** Columns are matched to your fields by title (Severity, Collision
  type, Number of vehicles, …). Values that aren't options in your form are left empty and
  listed at the end.
- Running it twice loads the records twice.

## What's in the CSV

| Column | Values |
|---|---|
| `record_date` | `YYYY-MM-DD HH:MM`, Bangladesh time; more crashes at rush hours |
| `lat`, `lon` | Inside the dummy division rectangles; clusters at Jatrabari, Kanchpur Bridge, Gabtoli, Sitakunda and Feni |
| `severity` | Fatal (≈10%), Injury (≈50%), Property (≈40%) |
| `collision_type`, `main_cause`, `surface_type`, `surface_condition`, `traffic_control`, `street_lights` | Options of DRIVER's standard form |
| `num_vehicles`, `num_driver_casualties`, `num_passenger_casualties`, `num_pedestrian_casualties` | Whole numbers consistent with the severity |
| `description` | `DUMMY test record (<area>)`, so the records are easy to find and delete |

After loading, try the **Heatmap** on the Map page, the **Divisions** filter, and a
**Custom Report** (rows: Divisions, columns: Severity). To calculate black spots right away:

```bash
vagrant ssh celery -c 'sudo docker exec $(sudo docker ps -q -f name=driver-celery) ./manage.py calculate_black_spots'
```
