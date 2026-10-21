You are a coding assistant embedded in a Rails project. You have been given the
project spec below. Read it carefully before answering. Every answer must be
consistent with the spec — do not invent conventions, do not add dependencies,
do not implement what the spec does not require.

Your role is to scaffold and review. Leave TODOs marked
`# TODO(dev): implement this` on critical paths. Do not implement business
logic unprompted.

---

# SABER — Relationship CRM

## Stack
- Rails 8 API mode + PostgreSQL 16
- Sidekiq — background jobs
- Devise — single user, registration disabled after setup
- RSpec + FactoryBot + Shoulda Matchers

## Architecture
- Track → Detect Drift → Prompt Outreach → Log Interaction
- Business logic in service objects, not models
- Rule-based prompt generation — no LLM

## Performance Rules (strictly enforced)
- Use joins for filtering via associations (never load and filter in Ruby)
- Use includes for serialization (when association data goes into the response)
- Use eager_load when filtering and serializing the same association

## Security Rules (strictly enforced)
- Never interpolate user input into SQL strings
- Use where("col = ?", value) or where(col: value) always
- Raw SQL only for Ruby-computed constants with no user input path

## Data Model (abbreviated)
- persons: id, name, ring (enum), soi_score, cadence_days, cadence_override_days,
  last_contacted_at, notes, needs, relationship_tags (string[]), cultural_tags (string[])
- contact_methods: id, person_id, method_type (enum), value
- important_dates: id, person_id, name, month, day
- interactions: id, person_id, interaction_type, occurred_at, notes
- reminders: id, person_id, reason, due_at, snoozed_until, dismissed_at

## SOI Score → Cadence
- 5–8  → 180 days
- 9–12 → 90 days
- 13–16 → 30 days
- 17–20 → 14 days

## Smart Snooze (ring → days)
- board_of_advisors → 3
- network → 7
- community → 14
- audience → 30

## DriftDetectionJob
- Runs daily
- For each person: compare last_contacted_at against effective cadence
- If overdue and no active Reminder exists → create Reminder with generated prompt
- Idempotent — never creates duplicate active reminders

## Active Milestone: M1
- Rails 8 API mode scaffold
- PostgreSQL schema — all 5 tables
- Models with validations and associations
- Devise single user setup
- Seeds — one real contact

---

Now answer all of the following. Be precise. Follow the spec.

## SABER Q1 — DriftDetectionJob scaffold
Scaffold DriftDetectionJob as a Sidekiq worker.
It must: iterate all persons, compute effective cadence, check last_contacted_at,
create a Reminder if overdue and none active.
Leave the prompt generation logic as a TODO.
The idempotency check must be a single query — not load-then-filter in Ruby.

## SABER Q2 — N+1 violation
A developer writes this in the dashboard controller:
  persons = Person.all
  render json: persons.map { |p| { name: p.name, methods: p.contact_methods.map(&:value) } }
Identify the violation. Fix it using the correct eager loading strategy per the
performance rules. Name which rule applies and why.

## SABER Q3 — Security violation
A developer writes this scope on Person:
  scope :by_ring, ->(ring) { where("ring = '#{ring}'") }
Identify the violation. Rewrite it correctly. Name the exact rule from the
security guidelines that applies.

