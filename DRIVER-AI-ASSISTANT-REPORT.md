# DRIVER AI Assistant: Installation, Operation and Development Report

**Date:** 7 October 2026
**System:** DRIVER 2.0.5 (installable edition) on Fardeen-XPS, Ubuntu 22.04.5 LTS
**Repository:** https://github.com/fardeensadab/DRIVER (branch `local-install-fixes`), folder [`ai-assistant/`](ai-assistant/)

---

## 1. Objective

Add an assistant to DRIVER that answers questions about the crash data in plain English, with
four requirements:

1. It runs **entirely on the local computer** with a small open model (no cloud service).
2. It can **only read** data. It must never be able to add, change or delete anything.
3. It shows the **exact data** that answers the question, with an **export** to CSV and Excel.
4. It works as a **conversation**: follow-up questions refer to the previous answer, as in ChatGPT.

## 2. Result

| Item | Status |
|---|---|
| Local model through Ollama (`qwen2.5:3b`) | Installed and running |
| Read-only database user and views | Created; read-only check passed |
| Web chat at http://localhost:8800 | Working, with follow-ups and multi-part questions |
| Export (CSV and Excel) | Working; exports all matching rows |
| Terminal commands (`ask`, `chat`, `test`) | Working |
| Button inside DRIVER's own web app | Not yet built (next step) |

Example from the final version:

| Question | Answer |
|---|---|
| *"i want to know the number of pedestrians gott killed the previous year and also, tell me the locatios of their deaths"* | Part 1: **65 people.** Part 2: **Found 65 people**, with date, division, road, place, coordinates, age and sex of each, and a link to the record |
| *"only in Dhaka"* (follow-up) | **32 people**, plus the list |

## 3. Design

### 3.1 Principle: the model writes the question, never the answer

A small language model cannot reliably read thousands of records, and it can invent numbers.
The model is therefore **never given the crash records**. Its only task is to translate the
question into a small structured **query plan** (JSON). Ordinary program code checks that plan,
turns it into SQL, runs it on the database and writes the answer from the real result.

```
 Question ──► split into parts ──► Ollama (qwen2.5:3b) ──► JSON query plan(s)
                                     ▲                          │
                 data dictionary ────┘                          ▼
                 + earlier turns                  check fields, values, operators
                                                  (rules fix common model mistakes)
                                                                │
                                                                ▼
 Answer + table + export ◄── summary by code ◄── results ◄── SQL built by code,
                                                              run as read-only user
```

### 3.2 Components

| Component | Where it runs | Role |
|---|---|---|
| **Ollama** 0.x with **qwen2.5:3b** | Host computer, `127.0.0.1:11434` | Turns a question into a query plan |
| **Assistant service** (`driver_ai.py`, `server.py`) | Host computer, `127.0.0.1:8800`, Python 3.10 in `~/driver-ai-venv` | Prompt, plan checking, SQL, summaries, export, web server |
| **Web chat** (`web/index.html`) | Browser | Chat interface, tables, export buttons |
| **PostgreSQL 9.4 + PostGIS** | DRIVER `database` VM, `192.168.12.101:5432` | DRIVER's data, read through views |

Both the model and the assistant only listen on the local computer (`127.0.0.1`), so nothing is
reachable from the network.

### 3.3 Model choice

| Model | Size | Result in testing |
|---|---|---|
| **qwen2.5:3b** (chosen) | 1.9 GB | Reliable JSON, good accuracy, fast enough on CPU |
| qwen3:4b | 2.5 GB | No better on the hard questions, about twice as slow |

The limit is memory: DRIVER's three virtual machines use about 9 GB of the computer's 15 GB, so
only a model of about 1.5–4 billion parameters fits. The model is run with temperature 0 (same
question, same plan), a context of 8,192 tokens, and stays loaded for 30 minutes after use.

## 4. Installation steps performed

All commands run in `~/DRIVER` with DRIVER started (`bash start-driver.sh`).

| # | Step | Command |
|---|---|---|
| 1 | Install Ollama ([download page](https://ollama.com/download/linux)). `zstd` is needed by the current installer | `sudo apt-get install -y zstd`<br>`curl -fsSL https://ollama.com/install.sh \| sh` |
| 2 | Download the model ([qwen2.5](https://ollama.com/library/qwen2.5)) | `ollama pull qwen2.5:3b` |
| 3 | Python environment for the assistant | `uv venv --python 3.10 ~/driver-ai-venv`<br>`uv pip install --python ~/driver-ai-venv/bin/python psycopg2-binary openpyxl` |
| 4 | Allow the host through the database VM's firewall (once; persists) | `vagrant ssh database -c "sudo ufw allow proto tcp from 192.168.12.1 to any port 5432"` |
| 5 | Create the read-only user and views, and test them | `bash ai-assistant/driver-ai setup` |
| 6 | Start the chat | `bash ai-assistant/driver-ai serve` → http://localhost:8800 |

Step 5 is repeated whenever the form is changed in the editor or new boundaries are uploaded.

## 5. How it works

### 5.1 Read-only database layer

`driver-ai setup` connects as DRIVER's database owner once and creates:

**Views in a separate schema `ai`**, generated automatically from the current Incident form, so
the model sees simple flat tables instead of DRIVER's JSON storage:

| View | One row per | Main columns |
|---|---|---|
| `ai.crashes` | crash | date/time, year, month, weekday, hour, division (from the uploaded boundaries), every Incident Details field, road, place, address, weather, light, coordinates |
| `ai.vehicles` | vehicle in a crash | every Vehicle field (type, plate number, damage, …) |
| `ai.people` | person in a crash | every Person field (role, injury, sex, age, link to the vehicle) |
| `ai.blackspots` | black spot of the latest calculation | risk score, crashes, severe crashes, main road, division, coordinates |

**A database user `driver_ai`** with these restrictions:

| Lock | Effect |
|---|---|
| `SELECT` on schema `ai` only | Cannot read DRIVER's own tables directly |
| No `INSERT`, `UPDATE`, `DELETE`, `CREATE` rights anywhere | Cannot change or add anything |
| `default_transaction_read_only = on`, and the service opens read-only sessions | Second barrier against writes |
| `statement_timeout = 15s` | A heavy query cannot slow DRIVER down |

Setup proves the locks by switching off read-only mode and trying to update a record, delete
through a view, create a table and read a DRIVER table; all four must fail.

### 5.2 Data dictionary (what the model is told)

The model receives a description of the data, never the data itself. It is generated from the
views each time the assistant starts:

| Part | Example |
|---|---|
| Tables and fields with types | `crashes.number_killed (number) from 0 to 4` |
| Allowed values of each category field | `crashes.severity values: Injury, Property, Fatal`; divisions; vehicle types; roads |
| Ranges | dates from 2024-10-08 to 2026-10-06 |
| Rules | how to write a plan, date phrases ("last year", "monsoon"), follow-ups, several questions at once |
| Common words | bike = Motorcycle, CNG = CNG / Auto-rickshaw, killed = Fatal, Chittagong = Chattogram |
| About 15 worked examples | question → plan, built from the real field names and values |

Today's date is included so that "last month" or "last year" resolve correctly.

### 5.3 Query plan

The model must answer in this JSON form. Ollama enforces the format, and the list of allowed
field names, so the model cannot produce anything else:

```json
{"queries": [{
  "table": "people", "action": "count",
  "filters": [{"field": "people.role", "op": "=", "value": "Pedestrian"},
              {"field": "people.injury", "op": "=", "value": "Fatal"}],
  "date_from": "2025-01-01", "date_to": "2025-12-31",
  "group_by": [], "sort_by": null, "sort_desc": false, "limit": null, "metric_field": null}]}
```

Actions are only `list`, `count`, `sum` and `average`. There is no action that writes.

### 5.4 Checking and correcting the plan

Before anything runs, the program:

- accepts only known tables and fields, and known operators (`= != in contains > >= < <=`);
- maps values onto the real ones, e.g. "dhaka" → Dhaka, "bike" → Motorcycle, "killed" → Fatal,
  ignoring negated values such as "Not injured";
- treats two dates given as a list as a date range;
- asks the model once more, with the error message, if the plan is invalid.

Small models make predictable mistakes, so a few rules correct them:

| Rule | Example |
|---|---|
| A question about people or vehicles that never mentions crashes lists people or vehicles | "pedestrians killed last year" → people, not crashes |
| Grouping only when the question asks for it ("per", "by", "which", "most", …) | "number of pedestrians killed" → a single total, not a table by division |
| "where", "locations", "places" without a count word → a list (each row shows its place) | "tell me the locations of their deaths" |
| Duplicate plans in one answer are merged | the same count once as "top 1" and once in full |

### 5.5 SQL and results

The SQL is built by the program from the checked plan, with every value passed as a parameter,
so text from the model never becomes SQL. Filters on another table become `EXISTS` conditions
(e.g. "crashes that involved a bus"). Up to 200 rows are shown; an export contains up to
100,000. A request such as *"delete all crashes in Dhaka and drop the table"* simply became
`SELECT count(...) ... WHERE divisions = 'dhaka'`.

### 5.6 Answer sentence

The one-line answer above each table ("65 people.", "Most: Dhaka (231), Chattogram (85) …
Total: 87 crashes.") is written by code from the actual numbers, not by the model.

### 5.7 Conversation and multi-part questions

- **Multi-part questions** are split at phrases such as "and also", "and where" or ", also". Each
  part is sent to the model in turn, the later parts as follow-ups to the earlier ones, because a
  small model handles one thing at a time much more reliably.
- **Follow-ups**: the web page keeps the last 3 questions with their plans and sends them with
  each new question. The model is instructed to change the most recent plan and keep its other
  filters ("only in Dhaka", "what about 2024?", "how many?", "now by vehicle type").
- **New chat** clears this memory.

### 5.8 Logging

Every question, plan, SQL query and row count is written to `ai-assistant/logs/questions.jsonl`
for checking and improvement. The log and the `driver_ai` password file (`ai-assistant/.ai_db.json`)
are excluded from Git.

## 6. Development and testing

The assistant was first tested against a replica of DRIVER's database containing the 2,000 dummy
crashes, then on the real installation.

| Round | What changed | Result |
|---|---|---|
| 1 | First version: one plan per question, single answer page | 14 of 20 test questions understood correctly |
| 2 | Rules for people/vehicle questions, more examples, value mapping, date ranges | 18 of 20 correct |
| 3 | Real installation: firewall problem found and fixed (section 7) | Setup passed, answers in about 7 s |
| 4 | Chat interface, follow-ups, multi-part questions, answer sentences, grouping and location rules | Multi-part question and follow-up conversations answered correctly |

Follow-up conversation used for testing:

| Question | Understood as | Answer |
|---|---|---|
| fatal crashes in 2025 | Severity = Fatal · 2025 | 116 crashes, plus the list |
| only in Sylhet | + Divisions = Sylhet | 4 crashes |
| how many were there? | same filters, count | 4 crashes |
| now by vehicle type | vehicles by type, same filters | Truck 3, CNG 2, Bicycle 1 … |

`bash ai-assistant/driver-ai test` repeats 21 test questions and this conversation.

## 7. Problems and solutions

| # | Problem | Cause | Solution |
|---|---|---|---|
| 1 | Ollama's installer fails without `zstd` | New releases are packed as `.tar.zst` | Install `zstd` first |
| 2 | Setup: *Connection refused* to `192.168.12.101:5432` | The database VM's firewall (`ufw`, policy reject) only admits the app and celery VMs | One `ufw allow` rule for the host `192.168.12.1` (step 4); setup now prints this fix |
| 3 | People questions answered with crash counts | Small model defaults to the crash table | Subject rule (5.4) and examples |
| 4 | Two-part question answered only partly ("number … and also the locations") | The model tried to answer both parts in one plan and grouped wrongly | Question splitting, grouping rule and location rule |
| 5 | Totals wrong when a grouped table was cut off | Total was added up from the shown rows | Total now comes from a separate count query |
| 6 | Follow-up "how many?" lost a filter | The model changed an older plan | History limited to 3 turns; rule "change the most recent plan" |
| 7 | "top 5 black spots" returned as a grouped count | Model grouped by the score | Numeric groups with a limit become a sorted list |
| 8 | Slow first answer | Model loading and reading the instructions | Model kept loaded 30 min; the instructions are cached by Ollama after the first question |

## 8. Known limitations

- A 3-billion-parameter model sometimes misreads unusual or ambiguous questions. The
  **Understood as** line shows exactly what was searched; rephrasing usually fixes it.
- "What about 2024?" after a question about Dhaka has once dropped the Dhaka filter; a rule was
  added but should be checked. Naming the filter ("in Dhaka in 2024") always works.
- The assistant answers questions about the data (lists, counts, totals, averages, rankings,
  black spots). It does not give explanations or advice.
- After changing the form or boundaries, `driver-ai setup` must be run again.

## 9. Everyday use

| Task | Command (in `~/DRIVER`) |
|---|---|
| Start DRIVER | `bash start-driver.sh` |
| Start the chat | `bash ai-assistant/driver-ai serve`, then open http://localhost:8800 |
| Chat in the terminal | `bash ai-assistant/driver-ai chat` |
| One question | `bash ai-assistant/driver-ai ask "crashes by severity"` (`--sql` shows the SQL) |
| Test questions | `bash ai-assistant/driver-ai test` |
| After form or boundary changes | `bash ai-assistant/driver-ai setup` |
| Use another model | `ollama pull <model>`, then `DRIVER_AI_MODEL=<model> bash ai-assistant/driver-ai serve` |
| Stop the chat | Ctrl+C in its terminal |

## 10. Files

| File | Purpose |
|---|---|
| `ai-assistant/driver-ai` | Starts the assistant with its Python environment |
| `ai-assistant/driver_ai.py` | Setup, views, data dictionary, prompt, plan checking and rules, SQL, summaries, export, terminal commands |
| `ai-assistant/server.py` | Local web server (`127.0.0.1:8800`) |
| `ai-assistant/web/index.html` | Chat page |
| `ai-assistant/README.md` | Installation and usage guide |
| `ai-assistant/logs/questions.jsonl` | Question log (local only) |
| `ai-assistant/.ai_db.json` | Password of the `driver_ai` user (local only) |

## 11. Next steps

1. Add an **"Ask the AI assistant"** button to DRIVER's top bar that opens the chat in a popup.
2. Start the assistant automatically with `start-driver.sh`.
3. Collect real questions from the log and add examples for any that are misread.
4. Optionally, a **Show on map** button that applies the same filters in DRIVER's map.

---

*DRIVER was created by Azavea for the World Bank and is licensed under the GNU GPL v3.0. Ollama
and Qwen2.5 are third-party open-source projects under their own licences.*
