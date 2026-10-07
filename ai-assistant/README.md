# DRIVER AI assistant (read-only)

Ask questions about your crash data in plain English, for example *"fatal bus crashes in Dhaka
in 2025"* or *"total deaths per division"*. The assistant shows the exact matching data in a
table and lets you export it to CSV or Excel. It runs entirely on your computer with a small
[Ollama](https://ollama.com) model and **can only read data, never change it**.

## How it works

```
question ──► small LLM (Ollama, on this computer) ──► JSON query plan
                                                         │  checked against the known fields and values
                                                         ▼
           table + CSV/Excel ◄── read-only database user ◄── SQL built by this program
```

- The model **never sees your records**. It only gets a *data dictionary*: the tables, fields
  and allowed values (generated from your form), synonyms and worked examples.
- The model only writes a query plan. The program checks every field and value in it, then
  builds the SQL itself, so the model's text never becomes SQL.
- The database user `driver_ai` can only `SELECT` from a few views in the `ai` schema. It
  cannot read DRIVER's tables directly, change anything or create tables, and queries stop
  after 15 seconds. `setup` tests all of this and prints the result.

| View | One row per |
|---|---|
| `ai.crashes` | crash: date/time, area (from your boundaries), Incident Details fields, road, weather, light |
| `ai.vehicles`, `ai.people` (named after your form's sections) | vehicle / person in a crash |
| `ai.blackspots` | black spot from the latest calculation, with score, crash counts, main road and area |

## Requirements

- DRIVER installed and running (`bash start-driver.sh`)
- About **3 GB of free memory** for the model while DRIVER runs (check with `free -h`)
- About 3 GB of disk space

## Installation

Run these in a terminal. Each step only needs to be done once.

**1. Install Ollama** ([download page](https://ollama.com/download/linux), [source](https://github.com/ollama/ollama))

```bash
sudo apt-get install -y zstd
curl -fsSL https://ollama.com/install.sh | sh
ollama --version
```

The installer adds an `ollama` service that starts with the computer and listens only on
this computer (`127.0.0.1:11434`).

**2. Download the model** ([qwen2.5:3b](https://ollama.com/library/qwen2.5), 1.9 GB)

```bash
ollama pull qwen2.5:3b
ollama run qwen2.5:3b "Say hello in one sentence"
```

**3. Create the assistant's Python environment** (with [uv](https://docs.astral.sh/uv/), installed by DRIVER's installer)

```bash
uv venv --python 3.10 ~/driver-ai-venv
uv pip install --python ~/driver-ai-venv/bin/python psycopg2-binary openpyxl
```

If `uv` is not found, use `~/.local/bin/uv` instead of `uv`.

**4. Let this computer reach DRIVER's database** (DRIVER must be running)

The database VM has a firewall that only lets DRIVER's own VMs in. Allow your computer
(`192.168.12.1` on DRIVER's private network) once; the rule stays after reboots:

```bash
cd ~/DRIVER
vagrant ssh database -c "sudo ufw allow proto tcp from 192.168.12.1 to any port 5432"
vagrant ssh database -c "sudo ufw status"
```

The status list should now include `5432/tcp ALLOW 192.168.12.1`.

**5. Create the read-only user and views**

```bash
bash ai-assistant/driver-ai setup
```

It lists the views with their row counts and ends with `Read-only check passed.`
Run it again whenever you change the form in the editor or upload new boundaries.

## Use

**In the browser (chat)**

```bash
bash ai-assistant/driver-ai serve
```

Open http://localhost:8800 and ask a question. Each answer has:

- a one-line **answer** written by the program from the real numbers (the model never writes numbers),
- the **Understood as** line, to check how the question was read,
- the matching data as a table, with **Export CSV** / **Export Excel** (all matching rows),
  **Show SQL**, and **open** links to the records in DRIVER.

Then ask **follow-up questions** about the last answer, like in ChatGPT: *"only in Dhaka"*,
*"what about 2024?"*, *"how many?"*, *"now by vehicle type"*. A question with several parts
(*"how many pedestrians were killed last year and where did they die"*) is answered part by part.
**New chat** forgets the conversation. Stop the page with Ctrl+C in the terminal.

**In the terminal**

```bash
bash ai-assistant/driver-ai chat                                          # conversation with follow-ups
bash ai-assistant/driver-ai ask "number of crashes by severity"           # one question
bash ai-assistant/driver-ai ask "pedestrians killed last year" --sql      # also shows the SQL
bash ai-assistant/driver-ai test                                          # test questions + a follow-up conversation
```

The first question after starting takes longer while the model loads (10–30 seconds); later
questions take a few seconds, and a question with two parts takes about twice as long.

### Good questions

| Kind | Example |
|---|---|
| List | "fatal crashes in Dhaka in 2025", "crashes on Airport Road at night" |
| Count | "how many crashes involved a motorcycle", "crashes per month in 2026" |
| Group | "crashes by severity", "crashes by hour of the day", "which vehicle types are involved most" |
| Sum / average | "total deaths per division", "average injured per crash by severity" |
| People / vehicles | "pedestrians killed last year", "female passengers seriously injured in Sylhet" |
| Black spots | "top 5 black spots", "black spots in Chattogram" |
| Several parts | "number of fatal crashes in 2025 and where they happened" |
| Follow-ups | "only in Sylhet", "what about last year?", "how many?", "by month" |

Use the names DRIVER uses (divisions, vehicle types, severities). Common words such as *bike*,
*CNG*, *killed*, *Chittagong* are understood. Always check the **Understood as** line: a small
model sometimes misreads an unusual question; rephrasing usually fixes it.

## Settings

| Variable | Default | Purpose |
|---|---|---|
| `DRIVER_AI_MODEL` | `qwen2.5:3b` | Ollama model, e.g. `DRIVER_AI_MODEL=qwen3:4b bash ai-assistant/driver-ai serve` |
| `DRIVER_AI_PORT` | `8800` | Port of the web page |
| `DRIVER_DB_HOST` | `192.168.12.101` | DRIVER's database VM |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Ollama address |

To try another model: `ollama pull <name>`, then start with `DRIVER_AI_MODEL=<name>`.

## Troubleshooting

| Message | Fix |
|---|---|
| *Cannot connect to DRIVER's database ... Connection refused* | Step 4 (firewall); if DRIVER is stopped, `bash start-driver.sh` |
| *Cannot reach Ollama* | `sudo systemctl start ollama`, check with `systemctl status ollama` |
| *The model ... is not installed* | `ollama pull qwen2.5:3b` |
| *Run 'driver-ai setup' first* | Step 5 |
| A new field or boundary is unknown | `bash ai-assistant/driver-ai setup`, then restart `serve` |
| Computer becomes very slow | Not enough memory: try `ollama pull qwen2.5:1.5b` and `DRIVER_AI_MODEL=qwen2.5:1.5b` |

Every question, plan and SQL query is logged in `ai-assistant/logs/questions.jsonl`
(not uploaded to GitHub). The database password of `driver_ai` is stored in
`ai-assistant/.ai_db.json` (also not uploaded).

## Files

| File | Purpose |
|---|---|
| `driver-ai` | Starts the assistant with its Python environment |
| `driver_ai.py` | Setup, data dictionary, prompt, plan checking, SQL, export, terminal commands |
| `server.py` | Web server on `127.0.0.1:8800` |
| `web/index.html` | The assistant page |
