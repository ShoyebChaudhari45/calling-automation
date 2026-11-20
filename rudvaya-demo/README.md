# Rudvaya AI Lead Automation — Demo Build

This is a runnable DEMO (not production) of the plan in
`Rudvaya_AI_Lead_Automation_Demo_Build_Plan.pdf`. Phone calls can be real
(via your Bolna trial, to verified numbers only); WhatsApp is always
simulated; everything else runs on your Windows laptop plus a free Supabase
Postgres project.

**Status: fully deployed and working on this machine.** Node.js, n8n
(v2.22.6), the `n8n-nodes-bolna` community node, the Supabase project +
schema, the Postgres/OpenAI/Bolna credentials, the Bolna voice agent, and
all 7 workflows are installed, imported, published, and active. A real
end-to-end call (CSV upload → eligibility gate → live Bolna call → your
phone ringing → Bolna recording/transcript) has been verified. If you're
setting this up fresh on a **different** machine, follow sections 1–6 below
in order; if you're picking this repo up as-is on **this** machine, skip to
section 6 ("Everyday use") and section "Where to find recordings,
transcripts and dashboard data".

**New-machine shortcut:** the Supabase project, Bolna agent and OpenAI
project (§2–4) are external and already exist. On a new Windows machine you
only need Node 22 LTS + `npm install n8n@2.22.6 -g` (§1), then run
`powershell -ExecutionPolicy Bypass -File setup-n8n.ps1` with n8n stopped.
It installs the Bolna community node, creates the three n8n credentials with
the IDs the workflows expect (secrets left blank — paste the Supabase DB
password, OpenAI key and Bolna key into them in the n8n UI), points the
three page-serving nodes at this folder, and imports + publishes all seven
workflows. Then start n8n with `start-n8n.bat`.

Several node parameters that are easy to get wrong were corrected against
the real installed package source and live API responses rather than
guessed — see "Resolved since initial build" further down for the exact
list (Postgres SSL, the `insert` operation's actual parameter shape, the
Merge node's real `append` mode schema, the Execute Workflow node's
resource-locator `workflowId` format, Bolna's `userData` needing a JSON
string not an object, and an item-shape rule that silently empties array
API responses). If you hit a similar "works in theory, breaks in the real
n8n version" issue, check that section first.

---

## 0. What's in this folder

```
rudvaya-demo/
  sql/01_schema.sql           -- run first in Supabase SQL Editor
  sql/02_seed.sql             -- run second; REPLACE 3 values before testing
  workflows/WF-01 ... WF-07   -- import into n8n, one file each
  pages/dashboard.html        -- served by WF-06 at /webhook/dashboard
  pages/whatsapp.html         -- served by WF-04 at /webhook/whatsapp
  pages/simulator.html        -- served by WF-07 at /webhook/simulator
  data/sample_leads.csv       -- 20 fictional leads, built-in test cases
  data/test_payloads/*.json   -- example bodies for every POST webhook
  TESTS.md                    -- the 15 tests from the plan, PASS/FAIL table
  RUNBOOK.md                  -- 5-minute and 15-minute demo scripts
  setup-n8n.ps1               -- one-time n8n setup on a new machine (see above)
  start-n8n.bat / .ps1        -- everyday start (sets env vars, opens dashboard)
```

---

## 1. Install Node.js and n8n

```powershell
node -v                         # must be >= 22.16 (n8n 2.22.x requirement); get Node 22 LTS from nodejs.org
npm install n8n@2.22.6 -g       # the version these workflows were tested on (a few minutes)
$env:GENERIC_TIMEZONE = "Asia/Kolkata"
n8n start
```

Open http://localhost:5678 and create the owner account. **Keep this
PowerShell window open** — closing it stops n8n. To make the timezone
permanent: Windows Settings → "Edit environment variables for your account"
→ add `GENERIC_TIMEZONE` = `Asia/Kolkata`.

Run `n8n --version` and note the result — some node parameter names in the
imported workflows (Form Trigger, Switch, Execute Workflow) differ slightly
between n8n releases. Every workflow JSON has a sticky note flagging the
specific nodes to double-check against your version.

### Install the Bolna community node

In n8n: **Settings → Community Nodes → Install** → enter
`n8n-nodes-bolna` → accept the risk prompt → Install → restart n8n if asked.

---

## 2. Create the Supabase project and run the SQL

1. supabase.com → New project, name `rudvaya-demo`, region Mumbai
   (ap-south-1) if offered. Save the database password somewhere safe.
2. Once the project is ready: **SQL Editor → New query** → paste the full
   contents of `sql/01_schema.sql` → Run.
3. New query again → paste `sql/02_seed.sql` → **before running**, edit
   these three lines in that file:
   - `call_allowlist` → your phone + a colleague's phone, both in E.164
     format (e.g. `+919812345678`), comma-separated — these are the ONLY
     numbers demo_mode will allow Bolna to call.
   - `bolna_agent_id` → fill in once you've created the Bolna agent (step 4).
   - `openai_model` → fill in once you've confirmed a model name available
     to your OpenAI account.
   Then Run.
4. **Project → Connect → Session pooler** — copy host, port, database
   name, user. (The session pooler works over IPv4; the direct connection
   may need IPv6, which most home/office networks don't have.)

### Create the n8n Postgres credential

In n8n: **Credentials → New → Postgres**. Name it `Rudvaya Supabase Postgres`
(the workflow JSON files reference this exact name as a label — the
underlying credential ID will differ per install, which is why every
Postgres node says `REPLACE_WITH_YOUR_CREDENTIAL_ID` and must be
re-selected from the dropdown after import). Fill in host/port/database/
user/password from the Session pooler, enable SSL, click **Test**.

---

## 3. Create the OpenAI credential

1. platform.openai.com → create a project `rudvaya-demo` → create an API
   key → set a monthly budget limit (e.g. $5).
2. In n8n: **Credentials → New → OpenAi**. Name it `Rudvaya OpenAI`, paste
   the key.
3. In the OpenAI dashboard, confirm which chat-completion model your
   account can use, and put that exact string into
   `app_config.openai_model` (Supabase SQL Editor):
   ```sql
   update app_config set value = 'YOUR_MODEL_NAME' where key = 'openai_model';
   ```

---

## 4. Create the Bolna account and agent

1. bolna.ai → sign up, confirm the $5 trial credit.
2. **Verify** your mobile number and a colleague's in the Bolna dashboard —
   trial accounts can only call verified numbers.
3. **Developers → API Keys** → copy the key.
4. In n8n: **Credentials → New → Bolna API** (added by the community node).
   Name it `Rudvaya Bolna API`, paste the key. This one credential is used
   everywhere Bolna is called — WF-02's "Bolna: Make Call" node AND WF-03's
   "Get Execution" node (confirmed from the installed node's source: it
   sends `Authorization: Bearer <apiKey>` automatically). No separate
   Header Auth credential is needed.
5. Create an agent named **Aranya Heights Assistant**, paste the prompt
   below (also in the plan §8.1) into its system prompt field, pick a
   Hindi/English-capable voice, set max call duration ≈ 5 minutes.

   <details><summary>Bolna agent prompt (click to expand)</summary>

   ```
   ROLE
   You are Priya, an AI voice assistant calling on behalf of the sales team of
   {property_name}. You are speaking to {lead_name}, who enquired about this
   project. You are an AI assistant and you must say so at the start of the call.

   LANGUAGE
   Start in simple English. If the customer speaks Hindi, Marathi or Hinglish,
   switch to that language. Short sentences. One question at a time.

   OPENING (say exactly this idea, naturally)
   "Hello {lead_name}, this is Priya, an AI assistant calling from the
   {property_name} team about your recent enquiry. Is this a good time to talk
   for two minutes?"
   - If NO or busy: ask when would be a better time, confirm it, thank them, end.

   GOALS (in order, stop as soon as the customer wants to stop)
   1. Confirm interest in {property_name}.
   2. Understand need: 2 BHK or 3 BHK, rough budget, purchase timeline.
   3. Answer questions ONLY from the VERIFIED FACTS below.
   4. Offer a site visit or an office meeting and capture a preferred day/time.
   5. Close politely and say a team member will confirm on WhatsApp.

   VERIFIED FACTS (the only facts you may state)
   {property_facts}
   If asked anything not covered here, say you will have a team member call
   back with exact details. Never guess numbers.

   HOW TO HANDLE THE CUSTOMER
   - Interested: be warm, ask one qualifying question, offer a visit.
   - Busy: ask for a callback time, confirm it, end quickly.
   - Confused: explain simply, check understanding, slow down.
   - Angry or frustrated: stay calm, apologise once, do not argue or defend,
     offer a human callback, end the call if they ask.
   - Not interested: thank them and end. Do not push.
   - Complaint, legal or safety issue: stop selling, say a senior team member
     will call back, end.
   - "Stop calling", "don't call", "remove my number": acknowledge and end
     immediately.

   NEVER
   - Pretend to be human. Pressure, threaten, or create false urgency.
   - Promise discounts, availability, approvals or returns.
   - Ask for Aadhaar, PAN, bank or payment details.
   - Make assumptions about religion, caste, community, gender or family.

   Keep the whole call under 4 minutes.
   ```
   </details>

6. Test it from the Bolna dashboard ("Speak to your agent" / test call to
   your own phone). Copy the **agent_id**:
   ```sql
   update app_config set value = 'YOUR_AGENT_ID' where key = 'bolna_agent_id';
   ```

---

## 5. Import and wire up the workflows

For each file in `workflows/`, in n8n: **Workflows → Import from File**.
Credentials are never stored in the exported JSON (by design, per n8n and
per the plan's safety rule), so after each import:

1. Open every node whose `notes` field says **CREDENTIAL REQUIRED** and pick
   your credential from the dropdown (the JSON's `REPLACE_WITH_YOUR_CREDENTIAL_ID`
   placeholders are just labels — n8n will show you the real list).
2. Open the sticky note at the top-left of the canvas — it lists exactly
   what to fix in that workflow.
3. **File path nodes** (`Read Dashboard Page`, `Read WhatsApp Page`,
   `Read Simulator Page`): replace `C:\REPLACE\...` with this folder's real
   absolute path, e.g. `D:\automation\rudvaya-demo\pages\dashboard.html`.
4. **Cross-workflow references**: several `Execute Workflow` nodes say
   `REPLACE_WITH_WF0X_WORKFLOW_ID` — once ALL seven workflows are imported
   and saved, open each `Execute Workflow` node and pick the target
   workflow from the dropdown (n8n resolves the id for you). Import order
   matters less than wiring order here — import all seven first, *then*
   go back and fix every cross-reference.
5. Toggle each workflow to **Active** (top-right switch). Production
   webhook URLs (`/webhook/...`) only resolve while a workflow is Active;
   the editor's "Test URL" (`/webhook-test/...`) only fires once per click
   from the editor and is not what the HTML pages use.

Recommended build/test order (matches the plan): **SQL → WF-01 → WF-06 →
WF-02 → WF-03 → WF-04 → WF-05 → WF-07**. Test each one per the matching
section of `TESTS.md` before moving to the next — most failures are a
credential not selected or a workflow not yet Active.

---

## 6. Everyday use

- **Start n8n:** open PowerShell and run:
  ```powershell
  $env:GENERIC_TIMEZONE = "Asia/Kolkata"
  $env:N8N_RESTRICT_FILE_ACCESS_TO = "D:\automation\rudvaya-demo\pages;C:\Users\admin\.n8n-files"
  n8n start
  ```
  The second variable is required — n8n 2.x sandboxes filesystem access for
  the Read/Write File nodes that serve the dashboard/WhatsApp/simulator
  pages, and defaults to only allowing `~/.n8n-files`. Without it, those
  three pages return a blank 200 response instead of the HTML. Leave the
  window open; closing it stops n8n.
- **Dashboard:** http://localhost:5678/webhook/dashboard
- **Mock WhatsApp inbox:** http://localhost:5678/webhook/whatsapp
- **Upload leads:** http://localhost:5678/form/wf01-upload-leads — pick
  `data/sample_leads.csv` (or your own file in the same column layout).
- **Call simulator:** opens automatically from the dashboard's "Call now"
  button when `app_config.call_mode = 'simulated'`.

## Where to find recordings, transcripts and dashboard data

- **Dashboard, click any lead row:** opens a detail panel with the last
  call's status, duration, an inline audio player + direct link for the
  Bolna recording (LIVE calls only — simulated calls have no recording),
  the full transcript, and the raw AI classification JSON. This reads
  straight from `call_attempts.transcript` / `.recording_url` /
  `.classification`, populated by WF-03 once a call completes.
- **Mock WhatsApp inbox** (`/webhook/whatsapp`): every simulated message
  thread, per lead, with delivery ticks.
- **Raw SQL**, if you want it directly:
  ```sql
  select lead_id, mode, status, duration_seconds, recording_url, transcript, classification
  from call_attempts order by started_at desc limit 20;
  ```
- **Bolna's own dashboard** (bolna.ai → Monitor → Call History) is the
  source of truth for recordings/transcripts if anything looks wrong in
  Supabase — WF-03 just copies what Bolna's API returns.
- A call only shows transcript/recording data once it reaches a terminal
  status (`completed`, `no-answer`, etc.) — WF-03 polls Bolna every 15
  seconds (up to 10 minutes) after the call is placed, so give it a minute
  after a live call ends before expecting the dashboard row to fill in.

### Switching between live and simulated calls

```sql
-- go live (only allowlisted numbers will actually ring, per demo_mode)
update app_config set value = 'live_bolna' where key = 'call_mode';

-- back to the safe browser fallback
update app_config set value = 'simulated' where key = 'call_mode';
```

### Reset demo data (keep config and property facts)

```sql
truncate table audit_events, appointments, followup_tasks, messages,
  call_attempts, import_rejects, leads restart identity cascade;
```

Run this in the Supabase SQL Editor before every rehearsal. It does **not**
touch `app_config` or `properties`, so your allowlist/model/agent settings
survive a reset.

---

## 7. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `n8n` command not found | Re-run `npm install n8n -g`; if it still fails, try `npx n8n` once as a smoke test, or check for a corporate proxy blocking npm. |
| Postgres credential "Test" fails | Supabase free projects pause after inactivity — open the Supabase dashboard once to wake it, then retry. Also confirm you used the **Session pooler** host/port, not the direct connection. |
| Dashboard/inbox/simulator page is blank or 404 | Workflow not Active, or the `Read ... Page` node's file path wasn't updated to this machine's real path. |
| `/webhook/...` URL returns "workflow not registered" | The workflow is not Active, or n8n was restarted after you last activated it — toggle Active again. |
| Call blocked with `not_in_demo_allowlist` | Expected while `demo_mode = true` and the number isn't in `call_allowlist` — this is the safety net, not a bug. |
| Bolna call never completes / WF-03 loops forever | Check the `Get Execution` node's URL/auth against Bolna's current API reference (marked TODO in WF-03) — the path or status strings this build guessed may not match. Inspect one real response in the n8n execution log and adjust `Check Finished`'s field names. |
| OpenAI node/HTTP Request returns 401/429 | Credential not selected, or the OpenAI project has no billing/credit — add a small prepaid top-up. |
| Classification always goes to "review" | Open the `Classify Call` or `Classify Reply` execution in n8n and inspect the raw OpenAI response — the parsing code expects `choices[0].message.content` to be a JSON object; a non-JSON model response (wrong model name, or `response_format` unsupported by that model) will fail validation by design. |
| Dashboard data blank, calls stuck on "contacting", n8n error `ECIRCUITBREAKER too many authentication failures` | Some other client is logging into Supabase with an old/wrong DB password (typically n8n left running on another laptop, whose WF-05 retries every minute). Supabase's pooler then blocks **everyone** for a few minutes. Close that client or update its password; the block clears by itself. |
| Every answered call ends in `review` | Look at the newest `audit_events` row with `event_type = 'invalid_ai_output'` — WF-03 stores OpenAI's exact error there. `You have no credits remaining` means the OpenAI account needs a prepaid top-up (platform.openai.com → Settings → Billing). The transcript/recording are still saved either way. |
| Microphone doesn't work in the simulator | Chrome blocks mic access on non-HTTPS origins except `localhost` — make sure you're opening `http://localhost:5678/...`, not a LAN IP. Text input always works as a fallback. |

---

## Credentials checklist (create once in n8n → Credentials)

| Name | Type | Used by |
|---|---|---|
| Rudvaya Supabase Postgres | Postgres | every workflow except WF-07's HTTP-only nodes |
| Rudvaya OpenAI | OpenAi | WF-03 Classify Call, WF-04 Classify Reply, WF-07 Agent Reply |
| Rudvaya Bolna API | Bolna API (community node credential) | WF-02 Bolna: Make Call, WF-03 Get Execution |

## What's free vs paid, live vs simulated

- **Free:** n8n, Node.js, Chrome, Supabase free tier, Bolna's $5 signup
  credit, the dashboard/inbox/simulator pages (served by n8n, no external
  host).
- **Paid (small, demo-only):** OpenAI usage (expect well under ₹100 for the
  whole build + demo) and possibly a one-time OpenAI prepaid top-up
  (commonly $5 / ≈ ₹450) if your account has no balance yet.
- **Paid, production only, NOT built here:** real WhatsApp (Meta Cloud
  API), an Indian 140-series number for promotional calling, TRAI
  registration, a hosted n8n server with HTTPS.
- **LIVE:** any call placed through `Bolna: Make Call` when
  `app_config.call_mode = 'live_bolna'` and the number is on the allowlist.
- **SIMULATED, always:** every WhatsApp message (`messages.simulated =
  true` on every row, no exception), and every call attempt with
  `call_attempts.mode = 'simulated'` run through the browser simulator.

## Resolved since initial build

These were originally marked TODO/best-guess; they're now confirmed against
the installed `n8n-nodes-bolna` v0.1.2 source and Bolna's public API docs,
and WF-02/WF-03 were updated to match:

- **WF-03 "Get Execution"** is now the actual Bolna node (resource=call,
  operation=get) instead of a raw HTTP Request — it calls `GET
  /executions/{executionId}` with `Authorization: Bearer <key>` handled
  automatically by the `Rudvaya Bolna API` credential.
- **Terminal call statuses** (`Check Finished` in WF-03): confirmed full
  list is `scheduled, queued, rescheduled, initiated, ringing, in-progress`
  (in-flight) vs. `call-disconnected, completed, balance-low, busy,
  no-answer, canceled, failed, stopped, error` (terminal).
- **Get Execution response fields**: `status`, `transcript`, `summary`,
  `conversation_duration`, `telephony_data.duration`,
  `telephony_data.recording_url` — all confirmed from Bolna's live docs.
- **WF-02 "Bolna: Make Call"** parameters (`agentId`, `recipientPhoneNumber`,
  `additionalFields.userData`) were already correct; confirmed byte-for-byte
  against the installed node's source.
- **POST /call response field for the new call's id**: confirmed as
  `execution_id` (not `id`) — `Save Execution ID` and `Start Result Poller`
  in WF-02 were updated accordingly.
- No separate Header Auth credential is needed for WF-03 — it reuses
  `Rudvaya Bolna API`.

**Found and fixed during live end-to-end testing on this machine** (each of
these broke a real run; fixed by reading the actual installed node source
or a real API response rather than guessing twice):

- **Postgres credential TLS**: Supabase's pooler cert needs
  `allowUnauthorizedCerts: true` on the credential ("Ignore SSL Issues") —
  without it every query fails with `self-signed certificate in
  certificate chain`.
- **`N8N_RESTRICT_FILE_ACCESS_TO`**: n8n 2.x's Read/Write File node refuses
  any path outside `~/.n8n-files` by default — the dashboard/WhatsApp/
  simulator pages need this env var set to this repo's `pages/` folder (see
  §6 above) or they silently return an empty 200 response.
- **Postgres node `insert` operation** (used in WF-01 "Log Rejected" and
  WF-02 "Blocked Audit"): doesn't accept a positional `queryReplacement`
  array the way `executeQuery` does — switched both to `executeQuery` with
  an explicit `INSERT ... VALUES ($1, $2, ...)` query.
- **Merge node v3 "append" mode**: the real parameter shape is
  `{ "mode": "append", "numberInputs": 2 }`, not a `combinationMode` field —
  fixed in WF-01's "Merge Append" node.
- **Array API endpoints returning empty instead of `[]`**: n8n rejects an
  item whose `.json` is an array (`"A 'json' property isn't an object"`).
  Fixed by aggregating rows into a single JSON array column in SQL
  (`COALESCE(json_agg(row_to_json(t)), '[]'::json)`) so the query always
  returns exactly one row, and having the Respond node emit `$json.items`
  directly — no code-node array-wrapping needed. Affects WF-06's
  `/api/leads`, `/api/appointments`, `/api/activity` and WF-04's
  `/api/messages`.
- **Execute Workflow node's `workflowId` parameter**: on this n8n version
  it's a resource-locator object, not a bare string —
  `{ "__rl": true, "value": "<id>", "mode": "id" }`. Affects every
  cross-workflow call (WF-02→WF-03, WF-03→WF-04, WF-05→WF-02,
  WF-07→WF-03, WF-04's self-calls).
- **Bolna `userData` field**: must be a JSON **string**
  (`JSON.stringify({...})`), not a live object — the node calls
  `JSON.parse` on it internally and throws `User Data must be valid JSON`
  otherwise.
- **Call attempt idempotency vs. the webhook response**: if `Create Call
  Attempt`'s `ON CONFLICT DO NOTHING` genuinely finds a duplicate (0 rows),
  the downstream code node wouldn't run at all (n8n skips nodes that
  receive zero input items), leaving the HTTP request hanging forever
  instead of returning `{"blocked_reason": "call_already_in_progress"}`.
  Fixed with `alwaysOutputData: true` on that Postgres node plus a check in
  `Merge Attempt Result` for a missing `call_attempt_id` instead of array
  length.
- **Bolna agent defaults**: a freshly-created agent (via the API) defaults
  to `call_terminate: 90` (seconds), not the ~5 minutes the plan calls
  for — fixed via a `PUT /v2/agent/{id}` to 300. Also added
  `call_hangup_message` (a goodbye line instead of an abrupt cutoff) and
  `hangup_after_LLMCall: true` (lets the agent's own conversational
  judgement end the call instead of relying only on the silence/duration
  timeouts) — both confirmed as real fields from the agent's own `GET`
  response before being set.

**Fixed on 2026-11-20** (second machine, live calls):

- **WF-02 "Respond Blocked"** read `block_reason` from the audit INSERT's
  output (always empty), so the dashboard always said "Blocked: unknown
  reason". It now reads `$('Eligibility Gate')`.
- **WF-03 poll counter** was always 1 (it re-read Init Poll State every
  loop), so the 10-minute timeout never fired. It now uses `$runIndex`.
- **WF-03 saves the call the moment it ends**: new node "Save Call Data
  (instant)" writes status/transcript/recording/duration and sets the lead
  to `contacted` *before* AI classification, so the dashboard updates within
  ~5–10 s of hang-up and the transcript survives an OpenAI failure. Polling
  is now every 5 s (max 120 polls = 10 min).
- **OpenAI failures route to `review`** (as this README always claimed)
  instead of aborting WF-03 silently: "Classify Call" continues on error
  (2 tries), and the error text is stored in `audit_events.details`.

## Open TODOs

All of the original setup TODOs (Form Trigger behaviour, cross-workflow
`workflowId` placeholders, the three file paths) are resolved on this
machine — see "Resolved since initial build" above. What's still genuinely
open:

1. **Rotate the OpenAI and Bolna API keys** that were pasted into this chat
   at setup time (noted at the time; n8n already has them stored encrypted,
   so rotating just means generating a new key and re-importing the
   credential — you don't need to touch the workflows).
2. Only one number (`+917499601744`) is in `call_allowlist` — add a second
   verified number there if you want the "two phones" part of the 15-minute
   demo script.
3. Full pass through every row of `TESTS.md` hasn't been run end-to-end (CSV
   import, opt-out, callback scheduling, etc. were spot-checked, not all 15
   formally recorded) — worth doing once before a client-facing demo, since
   the instruction for this session was "don't test again and again" for
   further live phone calls specifically.
4. `WF-05`'s per-minute schedule trigger and other scheduled/async paths
   (callback re-dial, missed-call WhatsApp flow, opt-out-cancels-callback)
   haven't been exercised with a real completed call yet, since the only
   two real test calls so far were cut short by the caller hanging up
   before the agent's first substantive response — once a future call
   actually completes, double check `call_attempts.classification` lands
   correctly and the lead's status/appointment/followup_task updates match.
