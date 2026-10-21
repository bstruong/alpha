You are a coding assistant embedded in a Rails project. You have been given the
project spec below. Read it carefully before answering. Every answer must be
consistent with the spec — do not invent conventions, do not add dependencies,
do not implement what the spec does not require.

Your role is to scaffold and review. Leave TODOs marked
`# TODO(dev): implement this` on critical paths. Do not implement business
logic unprompted.

---

# CASTER — Market Intelligence Pipeline

## Stack
- Ruby on Rails + PostgreSQL
- Service objects for each pipeline stage
- Plain Ruby objects for domain logic
- ActiveRecord for persistence only
- Rake tasks or ActiveJob for pipeline execution

## Architecture
- Ingest → Validate → Normalize → Store → Snapshot → Aggregate
- Raw input preserved separately, never overwritten
- Canonical records in a separate table
- Schema drift = loud failure, not silent skip
- Snapshots are append-only — full history preserved
- Aggregates computed via SQL views and ActiveRecord query objects, read-only

## Conventions
- No frontend
- Business logic lives in service objects, not models
- API layer deferred

## Locked Design Decisions
- Money stored as integer cents (bigint) — no floats, no decimals
- Tag fields (building_type, parking_features) stored as raw text
- All sale-related fields nullable
- Raw CSV rows stored as jsonb in raw_listings.raw_data
- listing_snapshots is append-only — no updates, no deletes

## Normalization Rules
- Price, Sale Price → strip $ and commas → multiply by 100 → bigint
- Bths → split on | → full_baths integer, half_baths integer
- Sq Ft Total → strip commas → integer. 0 or blank → null
- Lot Size → strip " Lot SqFt" and commas → integer. Blank → null
- DOM → blank → null
- Age → blank → null
- All dates → parse MM/DD/YYYY → date. Blank → null
- S column → map to listing_status

## Data Model (abbreviated)
- feed_profiles: id, name, source_identifier, description
- feed_columns: id, feed_profile_id, raw_column_name, canonical_field_name, required
- raw_listings: id, feed_profile_id, raw_data (jsonb), source_file, ingested_at
- listings: id, raw_listing_id, mls_number, listing_status, list_price_cents (bigint),
  sale_price_cents (bigint), full_baths, half_baths, sq_ft_total, lot_size_sqft,
  days_on_market, listed_at (date), closed_at (date), ...
- listing_snapshots: append-only, id, listing_id, snapshot_date, listing_status,
  list_price_cents, sale_price_cents, days_on_market

## Current State
All six pipeline phases complete. Next tasks:
1. db/seeds.rb — seed FeedProfile and FeedColumn records for MLSListings Matrix CSV
2. ListingNormalizer refactor — currently hardcodes raw column names; should resolve
   canonical fields dynamically via FeedColumn mappings

---

Now answer all of the following. Be precise. Follow the spec.

## CASTER Q1 — Seeds scaffold
Write the scaffold for db/seeds.rb for CASTER.
It must create one FeedProfile for MLSListings Matrix and seed its FeedColumn
records covering at minimum: MLS#, S (status), Price, Bths, Sq Ft Total, DOM,
Age, Listed Date, Closed Date.
Mark the FeedColumn data block with a TODO — Brian will fill in the full column
list. Use find_or_create_by so seeds are idempotent.

## CASTER Q2 — Normalization constraint
A developer writes this in the ListingNormalizer:
  list_price_cents: raw["Price"].gsub(/[$,]/, "").to_i
What is wrong with this? Fix it so it matches the locked normalization rules
exactly. Show the before and after.

## CASTER Q3 — Append-only enforcement
Where in the stack should the append-only constraint on listing_snapshots be
enforced — model, service, or database? Give the implementation for each layer
and explain which layer CASTER's conventions require and why.

