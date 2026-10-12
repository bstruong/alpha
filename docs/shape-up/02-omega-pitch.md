# Shape Up Pitch: Project Omega — 2-Week MVP

**Codename:** Omega  
**Appetite:** 2 weeks (small batch)  
**Target:** iOS Hotwire Native cockpit over Tailscale, supervising one headless Pi coding-agent session at a time  
**Problem:** Running Pi on the workstation is SSH/terminal-bound. Phone-side operators cannot safely launch, steer, interrupt, or reattach to long agent runs across Wi-Fi drops without orphan processes, lost token streams, or deadlocked pipes.  
**Solution:** A Rails 8 control plane that owns process lifecycle + append-only event log in Postgres, and a single-screen Hotwire Native shell with a dual-action sticky console.

---

## 1. Pitch

### Who
Homelab operator (you) launching sovereign coding agents against private repos over Tailscale, often from an iPhone.

### What we're solving
1. **No mobile control surface** for Pi RPC sessions.
2. **Unsafe subprocess supervision** — orphans, blocked pipes, unclear interrupt semantics.
3. **Reconnect amnesia** — WebKit/Turbo reconnects mid-stream and either blanks the UI or replays chaos.

### The idea (breadboard)
One `Session` record. Solid Queue job spawns `pi --mode rpc --no-session` in a process group. stdout/stderr/RPC events are parsed into monotonic `SessionEvent` rows. Turbo Streams broadcast throttled batches. Mobile client renders one cockpit screen; on resume it backfills `WHERE seq > last_seq`.

### Appetite boundary
Ship **one** healthy path: auth → create session with prompt → watch tools/tokens → enqueue follow-up **or** interrupt & steer → see touched files → reconnect without corruption. Not a multi-agent fleet UI.

---

## 2. Rabbit holes & defenses

| Rabbit hole | Failure mode | Defense (in scope) |
|-------------|--------------|--------------------|
| Subprocess IO deadlock | Full stdout pipe → Pi blocks → session freezes | Dedicated reader threads/fibers; non-blocking reads; always drain; never `readlines` on hot path |
| Orphan bash children | Kill parent, leave `rg`/`rails` zombies holding locks | `Process.spawn(..., pgroup: true)` + `Process.kill("-TERM", -pgid)` then `KILL`; ensure group leader |
| WebKit DOM thrashing | Token-by-token Turbo morph melts battery | Batch tokens (~100ms / N chars); coalesce broadcasts; Stimulus controller appends text node, not full re-render |
| Mobile lifecycle | App backgrounded; WS drops; user returns mid-run | Monotonic `seq BIGSERIAL`-style per session; client stores `last_seq`; `GET /sessions/:id/events?after=` + Cable resume |
| Tailscale flaps | Transient TCP loss to homelab | Idempotent event append; Cable reconnect; no dependency on in-memory-only buffers |
| Multi-session complexity | Scheduling, GPU contention | **MVP: one active Running session per node** (DB check constraint / advisory lock) |

### Explicit no-gos (protect appetite)
- Android polish beyond “path configured / builds”
- Multi-agent parallelism on one GPU
- In-app model download / engine build UI (use Alpha/engine CLI)
- Fine-grained RBAC / multi-user orgs
- Re-implementing Pi’s planner UI
- Alpha grader execution inside Omega requests (Omega may *link* to Alpha reports, not run batteries inline)
- Offline-first CRDT sync

---

## 3. Stack

| Layer | Choice |
|-------|--------|
| App | Rails 8 API+HTML |
| Jobs | Solid Queue |
| Pub/sub | Solid Cable |
| Cache | Solid Cache |
| DB | PostgreSQL |
| Mobile | Hotwire Native iOS MVP; Android path stub |
| Mesh | Tailscale only for reachability; app binds private services |
| Agent | `@earendil-works/pi-coding-agent` — `pi --mode rpc --no-session` |

---

## 4. Domain model (MVP)

```
User                 # single-operator ok (Devise or Rails 8 auth generator)
Node                 # hostname, tailscale_ip, role (workstation|lab)
AgentRuntime         # path to pi, default model preset, cwd roots allowlist
Session              # node, runtime, status (idle|starting|running|stopping|stopped|failed),
                     # prompt, pid, pgid, model_id, prompt_preset, repo_path,
                     # last_seq, started_at, finished_at
SessionEvent         # session_id, seq, kind, payload jsonb, created_at
                     # kinds: token_delta | tool_start | tool_end | tool_result |
                     #        assistant_message | status | error | steer | follow_up |
                     #        artifact_touch | diff_hunk | exit
SessionArtifact      # path, action (created|modified|deleted), summary
FollowUp             # body, state (queued|applied|cancelled), session_id
SteerInterrupt       # body, reason, applied_at — interrupt current turn + inject
AlphaQualification   # optional FK/link: model_id + preset + alpha_report_uri + qualified_at
```

**Status machine (thin):**  
`idle → starting → running ⇄ running (follow-up) → stopping → stopped`  
`running → failed` on non-zero / crash; `running → stopping` on interrupt.

---

## 5. Process supervisor (core engineering)

```ruby
# Pseudocode — Omega::PiSupervisor
Open3.popen2e(
  { "PYTHONUNBUFFERED" => "1", "NODE_OPTIONS" => "" },
  "pi", "--mode", "rpc", "--no-session",
  pgroup: true,
  chdir: session.repo_path
) do |stdin, stdout_err, wait_thr|
  session.update!(pid: wait_thr.pid, pgid: Process.getpgid(wait_thr.pid), status: "running")
  reader = Thread.new { drain_nonblock(stdout_err) { |chunk| EventIngest.call(session, chunk) } }
  # stdin: initial prompt + later follow-ups / steers via mutexed writes
ensure
  kill_group(session.pgid)
  reader&.join(2)
end
```

**Invariants**
- All durable UI state comes from `SessionEvent`, not from Cable alone.
- Interrupt = SIGTERM to group → wait → SIGKILL; then append `status:stopped`.
- Follow-up while running writes to stdin RPC and appends `follow_up` event; never spawns a second Pi.

---

## 6. Wireframe & component specs (single-screen cockpit)

### Screen: `Sessions#show` (mobile-first, one column)

```
┌─────────────────────────────────────┐
│ Ω  session title          ● Running │  status pill
│ model · preset · repo short path    │
├─────────────────────────────────────┤
│ Transcript / event feed             │  scroll; tool rows collapse
│  ▸ read app/models/foo.rb           │  accordion
│  ▸ edit app/jobs/bar.rb             │
│  assistant prose…                   │  throttled token append
│  …                                  │
├─────────────────────────────────────┤
│ Artifacts (2)          Diffs (1)    │  bottom sheets triggers
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ sticky console                  │ │
│ │ [textarea]                      │ │
│ │ Idle:    [ Launch Prompt ]      │ │
│ │ Running: [ Enqueue Follow-up ]  │ │
│ │          [ Interrupt & Steer ]  │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### ERB / Stimulus map

| Partial / component | Responsibility |
|---------------------|----------------|
| `sessions/show.html.erb` | Layout shell; `data-controller="cockpit"` |
| `_status_bar` | Turbo-updated status + model/preset |
| `_event_feed` | `turbo_stream_from @session`; list of event frames |
| `_event_token` | Stimulus `token-stream` append-only text |
| `_event_tool` | Accordion (`details`/`summary` or Stimulus); collapsed by default |
| `_console` | Dual-action sticky footer; swaps button set by status |
| `_artifacts_sheet` | Hotwire Native / `<dialog>` sheet of touched paths |
| `_diff_sheet` | Unified diff hunks from `artifact_touch` / `diff_hunk` events |

### Stimulus controllers

- `cockpit` — tracks `lastSeq`, on `visibilitychange` / Cable reconnect fetches `/events?after=`
- `token-stream` — buffers deltas; flush on interval; avoids morphing whole feed
- `console` — disables Launch while `starting|running`; confirms Interrupt
- `accordion-tool` — optional; prefer native `<details>` first

### Dual-action sticky console semantics

| Session status | Primary | Secondary |
|----------------|---------|-----------|
| `idle` / `stopped` / `failed` | **Launch Prompt** (creates job, body = textarea) | — |
| `starting` / `stopping` | disabled spinner | — |
| `running` | **Enqueue Follow-up** | **Interrupt & Steer** (SIGTERM group + queue steer text as next turn) |

---

## 7. Vertical slices (build order)

1. **Skeleton:** Rails 8 app, Postgres, Solid Queue/Cable/Cache, Tailscale-only bind, basic auth.
2. **Fake supervisor:** job appends synthetic token/tool events; cockpit renders + reconnect backfill works on iOS simulator/device.
3. **Real Pi spawn:** one allowlisted repo path; process group kill proven with intentional `sleep` child.
4. **Console actions:** launch / follow-up / interrupt-steer wired to supervisor stdin + signals.
5. **Artifacts sheet:** parse tool results for paths; list + open diff hunks.
6. **Hotwire Native iOS shell:** path configuration, sticky console safe areas, background reconnect test over Tailscale.

Done when: from iPhone on Tailscale, launch a Pi session against a toy repo, watch tools, background the app for 60s, return with full history, interrupt, and confirm no orphan processes on the node.

---

## 8. Quality bar / instrumentation

- Structured logs: `session_id`, `pid`, `pgid`, event `seq` gaps alert
- Metrics: time-to-first-event, events/sec broadcast, reconnect backfill size
- Manual test checklist in PR template: deadlock, orphan, thrash, reconnect

---

## 9. After this batch (parked)

- Android Native shell parity
- Multi-session / multi-node scheduler aware of Alpha qualifications
- Deeper diff review (Prism, file tree)
- Export-to-Alpha button (contract §2) as first-class UI
