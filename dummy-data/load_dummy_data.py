#!/usr/bin/env python3
"""
Load the dummy Bangladesh crash records (bd_dummy_incidents.csv) into DRIVER.

* Works with whatever "Incident" form you have: CSV columns are matched to your
  form's fields by their titles (Severity, Collision type, ...). Values that are
  not options in your form are skipped, so nothing invalid is saved.
* If DRIVER has no "Incident" record type yet, it creates one with DRIVER's
  standard crash form (scripts/incident_schema_v3.json from this repository).
* Uses only the Python 3 standard library. Run it on the computer where DRIVER
  runs, while DRIVER is up:

      python3 dummy-data/load_dummy_data.py              # all 600 records
      python3 dummy-data/load_dummy_data.py --limit 50   # just the first 50

Running it twice loads the records twice.
"""
import argparse
import csv
import getpass
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DHAKA = timezone(timedelta(hours=6))

# CSV column -> words to look for in the form's Incident Details field titles
DETAIL_COLUMNS = [
    ("severity", ["severity"]),
    ("collision_type", ["collision"]),
    ("main_cause", ["cause"]),
    ("num_vehicles", ["vehicle"]),
    ("num_killed", ["kill", "dead", "death", "fatalit"]),
    ("num_injured", ["injur"]),
    ("num_driver_casualties", ["driver"]),
    ("num_passenger_casualties", ["passenger"]),
    ("num_pedestrian_casualties", ["pedestrian"]),
    ("surface_type", ["surface type"]),
    ("surface_condition", ["surface condition", "road condition"]),
    ("traffic_control", ["traffic control"]),
    ("street_lights", ["light"]),
    ("description", ["descr"]),
]
NUMERIC = {"num_vehicles", "num_killed", "num_injured", "num_driver_casualties",
           "num_passenger_casualties", "num_pedestrian_casualties"}


class Api:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.token = None

    def login(self, user, pw):
        data = urllib.parse.urlencode({"username": user, "password": pw}).encode()
        try:
            with urllib.request.urlopen(self.base + "/api-token-auth/", data=data, timeout=30) as r:
                self.token = json.loads(r.read().decode())["token"]
        except urllib.error.HTTPError as e:
            sys.exit("Login failed (HTTP %s) - check the username and password." % e.code)
        except urllib.error.URLError as e:
            sys.exit("Cannot reach DRIVER at %s - is it running? (%s)" % (self.base, e.reason))

    def call(self, method, path, body=None, form=False):
        headers = {"Authorization": "Token " + self.token}
        data = None
        if body is not None:
            if form:
                data = urllib.parse.urlencode(body).encode()
            else:
                data = json.dumps(body).encode()
                headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + "/api" + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status, json.loads(r.read().decode() or "null")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()[:500]


def get_or_create_incident(api):
    st, res = api.call("GET", "/recordtypes/?label=Incident&active=True")
    if st != 200:
        sys.exit("Could not read record types: %s" % res)
    if res["results"]:
        rt = res["results"][0]
        if len(res["results"]) > 1:
            print("Note: %d active 'Incident' record types; using %s" % (len(res["results"]), rt["uuid"]))
        if rt.get("current_schema"):
            return rt["current_schema"]
        sys.exit("The Incident record type has no form yet - add fields in the editor first.")
    schema_file = os.path.join(REPO, "scripts", "incident_schema_v3.json")
    print("No 'Incident' record type found - creating DRIVER's standard crash form from %s" % schema_file)
    st, rt = api.call("POST", "/recordtypes/", {"label": "Incident", "plural_label": "Incidents",
                                                "description": "Road traffic crashes",
                                                "temporal": True, "active": True}, form=True)
    if st != 201:
        sys.exit("Could not create the record type: %s" % rt)
    with open(schema_file) as f:
        schema = json.load(f)
    st, sc = api.call("POST", "/recordschemas/", {"record_type": rt["uuid"], "schema": schema})
    if st != 201:
        sys.exit("Could not create the form: %s" % sc)
    return sc["uuid"]


def details_definition(schema):
    defs = schema["definitions"]
    for key, d in defs.items():
        if d.get("details"):
            return key, d
    for key, d in defs.items():
        if not d.get("multiple") and "detail" in (d.get("title", "") + key).lower():
            return key, d
    sys.exit("Could not find the 'Details' section of the Incident form.")


def build_mapping(definition):
    """Map CSV columns to form field names, matching types."""
    mapping = {}
    used = set()
    props = definition.get("properties", {})
    for col, words in DETAIL_COLUMNS:
        for name, p in props.items():
            if name == "_localId" or name in used:
                continue
            is_num = p.get("type") in ("number", "integer")
            if (col in NUMERIC) != is_num:
                continue
            if any(w in name.lower() for w in words):
                mapping[col] = (name, p)
                used.add(name)
                break
    return mapping


def derive(row):
    """Add num_killed / num_injured columns from severity and casualty counts."""
    total = sum(int(row.get(c) or 0) for c in
                ("num_driver_casualties", "num_passenger_casualties", "num_pedestrian_casualties"))
    if row.get("severity") == "Fatal":
        killed = max(1, int(math.ceil(total / 2.0)))
        row["num_killed"], row["num_injured"] = killed, max(0, total - killed)
    elif row.get("severity") == "Injury":
        row["num_killed"], row["num_injured"] = 0, max(1, total)
    else:
        row["num_killed"], row["num_injured"] = 0, 0
    return row


def main():
    ap = argparse.ArgumentParser(description="Load dummy Bangladesh crashes into DRIVER")
    ap.add_argument("--csv", default=os.path.join(HERE, "bd_dummy_incidents.csv"))
    ap.add_argument("--url", default="http://localhost:7000")
    ap.add_argument("--limit", type=int, default=0, help="load only the first N records")
    args = ap.parse_args()

    with open(args.csv) as f:
        rows = list(csv.DictReader(f))
    if args.limit:
        rows = rows[:args.limit]

    api = Api(args.url)
    user = input("DRIVER username [admin]: ").strip() or "admin"
    api.login(user, getpass.getpass("Password for %s: " % user))

    schema_id = get_or_create_incident(api)
    st, sc = api.call("GET", "/recordschemas/%s/" % schema_id)
    key, definition = details_definition(sc["schema"])
    mapping = build_mapping(definition)
    print("\nYour form's '%s' section; CSV columns will fill these fields:" % definition.get("title", key))
    for col, (name, _) in mapping.items():
        print("  %-26s -> %s" % (col, name))
    unmatched = [c for c, _ in DETAIL_COLUMNS if c not in mapping]
    if unmatched:
        print("  (no matching field, not loaded: %s)" % ", ".join(unmatched))
    if input("\nLoad %d records now? [y/N]: " % len(rows)).strip().lower() != "y":
        sys.exit("Cancelled.")

    ok = failed = 0
    skipped = {}
    for i, row in enumerate(rows, 1):
        row = derive(row)
        details = {"_localId": str(uuid.uuid4())}
        for col, (name, prop) in mapping.items():
            raw = row.get(col)
            if raw in (None, ""):
                continue
            value = int(raw) if col in NUMERIC else str(raw)
            allowed = prop.get("enum") or (prop.get("items") or {}).get("enum")
            if allowed and value not in allowed:
                skipped[(name, value)] = skipped.get((name, value), 0) + 1
                continue
            if prop.get("type") == "array":
                value = [value]
            details[name] = value
        when = datetime.strptime(row["record_date"], "%Y-%m-%d %H:%M").replace(tzinfo=DHAKA)
        data = {key: details}
        for k, d in sc["schema"]["definitions"].items():
            if k != key and d.get("multiple"):
                data[k] = []
        record = {"schema": schema_id, "data": data,
                  "occurred_from": when.isoformat(), "occurred_to": when.isoformat(),
                  "geom": "POINT (%s %s)" % (row["lon"], row["lat"])}
        st, res = api.call("POST", "/records/", record)
        if st == 201:
            ok += 1
        else:
            failed += 1
            if failed <= 3:
                print("record %d failed: HTTP %s %s" % (i, st, res))
        if i % 50 == 0:
            print("  %d / %d" % (i, len(rows)))

    print("\nDone: %d loaded, %d failed." % (ok, failed))
    for (name, value), n in sorted(skipped.items()):
        print("  note: '%s' is not an option of '%s' in your form - left empty in %d records" % (value, name, n))


if __name__ == "__main__":
    main()
