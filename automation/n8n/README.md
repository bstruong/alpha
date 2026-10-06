# Phase 3: On-Demand Automation Harness (n8n Integration)

This directory provides the containerized orchestration harness for **Phase 3** of the Berserker project, integrating [n8n](https://n8n.io/) with the local OpenAI-compatible inference engine (`llama-server`) running on the host workstation.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Host Workstation (Linux / CachyOS)                                      │
│                                                                         │
│   llama-server (:8080)                                                 │
│   ├─ Model: Qwen3.6-35B-A3B-UD-Q4_K_M (alias: qwen36-coder)            │
│   └─ Endpoint: http://127.0.0.1:8080/v1                                 │
│                                 ▲                                       │
│                                 │ Direct Loopback / Host Networking     │
│                                 ▼                                       │
│   Docker Container: berserker-n8n (:5678)                              │
│   ├─ Network Mode: host                                                 │
│   ├─ Workflow: email_triage_workflow.json                               │
│   └─ Data Persistence: n8n_data volume                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

The pipeline ingests incoming tasks/emails in batches, evaluates their urgency and business context using our local LLM engine, structures the decision into validated JSON, and routes urgent incidents to immediate alert dispatchers while categorizing routine tasks into departmental queues.

---

## Directory Contents

| File | Purpose |
|---|---|
| `docker-compose.yml` | Container definition for n8n with optimized host network access to `llama-server`. |
| `.env.example` | Environment variable reference template. |
| `email_triage_workflow.json` | Exported n8n workflow for batch email/task ingestion, local LLM triage, and priority routing. |
| `README.md` | Launch, configuration, and workflow import guide. |

---

## Prerequisites

1. **Docker & Docker Compose**: Ensure Docker is installed and the daemon is active (`docker compose version`).
2. **Local Engine Active**: Ensure the Berserker local engine is running on port 8080:
   ```bash
   # From the repository root:
   ./engine/bin/llama-up.sh

   # Verify engine health:
   curl -s http://127.0.0.1:8080/health
   # Expected response: {"status":"ok"}
   ```

---

## Networking Strategy

### Default: Linux Host Networking (`network_mode: host`)
On Linux systems, `llama-server` binds by default to loopback (`127.0.0.1:8080`). 
`docker-compose.yml` uses `network_mode: host`, which enables the following:
* The n8n container shares the host network namespace directly.
* n8n connects to `http://127.0.0.1:8080/v1` without any proxying or port-forwarding overhead.
* The n8n web interface is accessible directly on host port `5678` (`http://localhost:5678`).

### Alternative: Bridge Networking (`extra_hosts`)
If deploying on macOS or Windows (Docker Desktop), or if network isolation is preferred:
1. Open `docker-compose.yml`.
2. Comment out `network_mode: host`.
3. Uncomment the `ports` and `extra_hosts` sections:
   ```yaml
   ports:
     - "5678:5678"
   extra_hosts:
     - "host.docker.internal:host-gateway"
   ```
4. Configure the OpenAI credential in n8n with Base URL: `http://host.docker.internal:8080/v1`
   *(Ensure `llama-server` is bound to `0.0.0.0:8080` or accessible through the gateway IP).*

---

## Launch Instructions

### 1. Start the Container
From the `automation/n8n` directory:
```bash
docker compose up -d
```

### 2. Verify Container Status
Check that the container is running and healthy:
```bash
docker compose ps
docker compose logs -f n8n
```

Once initialized, n8n logs will indicate that the editor is ready:
```
Editor is now accessible via:
http://localhost:5678/
```

### 3. Stop or Restart
```bash
# To stop:
docker compose down

# To restart:
docker compose restart
```

Workflow definitions and credential databases persist across restarts in the named volume `n8n_data`.

---

## Configuring the Workflow in n8n

### Step 1: Access n8n
Open your browser and navigate to:
```
http://localhost:5678
```
*(On first launch, set up an initial admin email and password.)*

### Step 2: Configure OpenAI Credential for Local Engine
Because `llama-server` exposes an OpenAI-compatible API, we configure n8n's standard OpenAI credential to point to our local endpoint:

1. In the left navigation bar, go to **Credentials**.
2. Click **Add Credential** (top right) and search for **OpenAI**.
3. Select **OpenAI API**.
4. Configure the following fields:
   * **API Key**: `dummy` (or any string, e.g. `sk-local-berserker`).
   * **Base URL**: `http://127.0.0.1:8080/v1` *(or `http://host.docker.internal:8080/v1` if using bridge mode)*.
5. Click **Save** and name the credential `Local llama-server`.

> [!NOTE]
> The local `llama-server` does not enforce API key authentication by default, but n8n requires a non-empty string in the API Key field to save the credential.

---

### Step 3: Import the Workflow

1. In the left sidebar, navigate to **Workflows**.
2. Click **Add workflow** or click the **...** (three dots) menu in the top right.
3. Select **Import from File**.
4. Choose `automation/n8n/email_triage_workflow.json` from this repository.
   *(Alternatively, open the JSON file in an editor, copy the contents, and paste directly into the n8n canvas using `Ctrl+V` / `Cmd+V`).*
5. Double-click the node labeled **Local Engine Email Triage (OpenAI Node)**:
   * Under **Credential to connect with**, select the **Local llama-server** credential created in Step 2.
   * Model is pre-set to `qwen36-coder`.
6. Click **Save** in the top right corner.

---

## Workflow Walkthrough

The imported workflow (`Berserker - Email & Task Triage Pipeline`) comprises 6 stages:

```
[When clicking 'Test workflow']
             │
             ├──► [Fetch Email & Task Batch] ──► [Local Engine Email Triage] ──► [Parse & Format Results]
             │                                                                             │
[Batch Polling Schedule]                                                                   ▼
                                                                                 [Route Urgent vs Routine]
                                                                                           │
                                                                           ┌───────────────┴───────────────┐
                                                                           ▼                               ▼
                                                            [Urgent Escalation Dispatcher]   [Routine Queue Dispatcher]
```

### 1. Triggers
* **When clicking 'Test workflow'** (`manualTrigger`): Enables on-demand verification during development and testing.
* **Batch Polling Schedule** (`scheduleTrigger`): Runs periodically (configured for 15-minute intervals) for production automation.

### 2. Fetch Email & Task Batch (`n8n-nodes-base.code`)
Simulates an incoming batch of unread emails and tasks representing diverse operational scenarios:
* `EML-2026-001` (Critical Incident): Database connection pool exhaustion and 504 timeouts.
* `EML-2026-002` (High Bug): Benchmark worker segfault on 35B model weight allocation.
* `EML-2026-003` (Routine Billing): Corporate invoice PO number update request.
* `EML-2026-004` (Feature Proposal): Prometheus metrics exporter request.
* `EML-2026-005` (Spam): Marketing backlinks offer.

### 3. Local Engine Email Triage (`n8n-nodes-base.openAi`)
Submits each item in the batch to `qwen36-coder` via `/v1/chat/completions` with a strict structured output contract:
```json
{
  "category": "incident | bug | billing | feature_request | spam",
  "priority": "P0 | P1 | P2 | P3 | P4",
  "urgency": "high | medium | low",
  "action": "immediate_escalation | engineering_ticket | finance_review | product_backlog | archive",
  "summary": "Concise summary",
  "suggested_reply": "Draft response if applicable"
}
```

### 4. Zero-Credential Alternative: Direct HTTP Request (`n8n-nodes-base.httpRequest`)
Included on the canvas is a parallel **Direct HTTP Request** node. If you wish to test without configuring n8n credentials, you can wire `Fetch Email & Task Batch` directly into this node, which queries `http://127.0.0.1:8080/v1/chat/completions` using native HTTP headers and body.

### 5. Parse & Format Triage Results (`n8n-nodes-base.code`)
* Extracts the generated JSON (stripping markdown code fences if present).
* Merges the classification with original email metadata (`id`, `sender`, `subject`, `received_at`).
* Calculates the `is_urgent` boolean flag (`P0`, `P1`, `high urgency`, or `incident`).

### 6. Priority Routing & Dispatch
* **Route Urgent vs Routine** (`n8n-nodes-base.if`): Evaluates `{{ $json.is_urgent }}`.
* **Urgent Escalation Dispatcher**: Targets high-priority channels (`#eng-incidents`) with immediate action items.
* **Routine Ticket & Queue Dispatcher**: Categorizes and routes routine items to their target queue (`finance_inbox`, `product_backlog`, `engineering_triage`, or `spam_quarantine`).

---

## Testing the Workflow

1. With the workflow open in n8n, click the **Test workflow** button at the bottom of the canvas.
2. Watch the execution flow highlight across the nodes in real-time.
3. Click any node to inspect the input and output JSON at each stage.
4. Verify that:
   * Critical outage (`EML-2026-001`) routes to the **Urgent Escalation Dispatcher**.
   * Billing inquiries and feature requests route to the **Routine Ticket & Queue Dispatcher** with appropriate queue designations.

---

## Production Integration

To connect the workflow to live systems:
* Replace the `Fetch Email & Task Batch` node with live source triggers:
  * **Gmail Trigger** / **IMAP Email** for inbox monitoring.
  * **Webhook** node for incoming alert payloads.
  * **GitHub** / **GitLab** / **Jira** nodes for task ingestion.
* Replace the Dispatcher mock nodes with notification integrations:
  * **Slack** / **Discord** / **Telegram** for incident paging.
  * **PagerDuty** / **Opsgenie** for on-call alerting.
  * **Google Sheets** / **PostgreSQL** / **Notion** for ticket logging.
