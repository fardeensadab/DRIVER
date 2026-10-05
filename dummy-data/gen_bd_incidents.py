# Generates DUMMY road-crash records for Bangladesh, for testing DRIVER.
import csv, random, math
from datetime import datetime, timedelta
random.seed(2026)

# (name, lat, lon, spread_deg, weight, box=(minlon,minlat,maxlon,maxlat)) - boxes match bd_divisions_dummy.zip
AREAS = [
 ("Dhaka",      23.78, 90.40, 0.08, 34, (89.5,23.2,91.2,24.3)),
 ("Chattogram", 22.36, 91.80, 0.08, 18, (91.2,20.7,92.7,24.0)),
 ("Sylhet",     24.90, 91.87, 0.07,  7, (91.2,24.0,92.5,25.2)),
 ("Khulna",     22.85, 89.30, 0.08,  8, (88.5,21.6,89.5,23.8)),
 ("Rajshahi",   24.37, 88.62, 0.07,  8, (88.0,23.8,89.5,25.2)),
 ("Barishal",   22.70, 90.37, 0.07,  6, (89.9,21.8,91.2,23.2)),
 ("Rangpur",    25.74, 89.25, 0.07,  6, (88.0,25.2,89.9,26.6)),
 ("Mymensingh", 24.75, 90.40, 0.07,  6, (89.9,24.3,91.2,25.4)),
]
# A few dangerous spots (tight clusters) so black-spot analysis has something to find
HOTSPOTS = [
 ("Jatrabari, Dhaka",          23.7103, 90.4349),
 ("Kanchpur Bridge, Dhaka",    23.7046, 90.5196),
 ("Gabtoli, Dhaka",            23.7835, 90.3445),
 ("Sitakunda, Chattogram",     22.6200, 91.6600),
 ("Dhaka-Chattogram Hwy, Feni",23.0100, 91.3800),
]
N = 600
END = datetime(2026, 10, 3, 23, 59)
START = END - timedelta(days=180)

def weighted(choices):
    total = sum(w for _, w in choices); r = random.uniform(0, total)
    for v, w in choices:
        r -= w
        if r <= 0: return v
    return choices[-1][0]

def hour():
    # more crashes at commuting hours and late evening
    return weighted([(h, w) for h, w in zip(range(24),
        [2,1,1,1,2,4,6,9,10,8,7,7,7,7,7,8,9,10,10,9,8,6,4,3])])

rows = []
for i in range(N):
    if random.random() < 0.18:
        name, lat, lon = random.choice(HOTSPOTS)
        lat += random.gauss(0, 0.0015); lon += random.gauss(0, 0.0015)
        area = "hotspot: " + name
    else:
        a = weighted([(a, a[4]) for a in AREAS])
        name, clat, clon, sd, _, (x0, y0, x1, y1) = a
        while True:
            lat = random.gauss(clat, sd); lon = random.gauss(clon, sd)
            if x0 < lon < x1 and y0 < lat < y1: break
        area = name
    d = START + timedelta(seconds=random.randint(0, int((END - START).total_seconds())))
    d = d.replace(hour=hour(), minute=random.randint(0, 59))
    sev = weighted([("Fatal", 12), ("Injury", 48), ("Property", 40)])
    coll = weighted([("Hit pedestrian", 24), ("Head on", 16), ("Rear end", 18), ("Side swipe", 14),
                     ("Right angle", 8), ("Overturned vehicle", 9), ("Hit object off road", 4),
                     ("Hit parked vehicle", 3), ("Hit object in road", 2), ("Hit animal", 2)])
    nveh = 1 if coll in ("Hit pedestrian", "Overturned vehicle", "Hit object off road",
                         "Hit object in road", "Hit animal") else random.choice([2, 2, 2, 3])
    if sev == "Property":
        drv = pas = ped = 0
    else:
        k = 1 if sev == "Injury" else 2
        ped = random.randint(1, k + 1) if coll == "Hit pedestrian" else 0
        drv = random.randint(0, k)
        pas = random.randint(0, 2 * k)
        if drv + pas + ped == 0: drv = 1
    wet = d.month in (6, 7, 8, 9)  # monsoon
    rows.append({
        "record_date": d.strftime("%Y-%m-%d %H:%M"),
        "lat": "%.6f" % lat, "lon": "%.6f" % lon,
        "severity": sev, "collision_type": coll,
        "main_cause": weighted([("Human error", 78), ("Vehicle defect", 12), ("Road defect", 10)]),
        "num_vehicles": nveh,
        "num_driver_casualties": drv, "num_passenger_casualties": pas, "num_pedestrian_casualties": ped,
        "surface_type": weighted([("Asphalt", 70), ("Concrete", 15), ("Gravel", 8), ("Earth", 7)]),
        "surface_condition": weighted([("Wet", 45), ("Dry", 45), ("Muddy", 6), ("Flooded", 4)] if wet
                                      else [("Dry", 88), ("Wet", 8), ("Muddy", 4)]),
        "traffic_control": weighted([("None", 55), ("Traffic lights", 12), ("Police controlled", 14),
                                     ("Centerline", 10), ("Pedestrian crossing", 6), ("Give way", 3)]),
        "street_lights": "Lit" if 6 <= d.hour <= 18 or random.random() < 0.4 else "Unlit",
        "description": "DUMMY test record (%s)" % area,
    })
rows.sort(key=lambda r: r["record_date"])
cols = ["record_date","lat","lon","severity","collision_type","main_cause","num_vehicles",
        "num_driver_casualties","num_passenger_casualties","num_pedestrian_casualties",
        "surface_type","surface_condition","traffic_control","street_lights","description"]
with open("bd_dummy_incidents.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)
print("wrote", len(rows))
