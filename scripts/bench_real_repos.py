#!/usr/bin/env python3
"""Stone 2: Real Production Repository Coding Benchmark on Saber & Caster.

Evaluates local LLMs against actual production Ruby on Rails repositories:
- Saber: Fix 5 test failures (Interaction scopes + Reminder#snoozed? predicate & specs)
- Caster: Complete ListingNormalizer refactored to Cents.to_cents (33 failing tests)
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import requests

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from tests.benchmark_suite.common import CHAT_ENDPOINT, erase_slots, repro_params

REPORTS_DIR = os.path.join(PROJECT_ROOT, "reports")
SABER_DIR = "/home/brian/Projects/saber"
CASTER_DIR = "/home/brian/Projects/caster"


def call_llm(model: str, system_prompt: str, user_prompt: str, max_tokens: int = 2500):
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "max_tokens": max_tokens,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
        **repro_params(),
    }
    start = time.time()
    resp = requests.post(CHAT_ENDPOINT, json=payload, timeout=300)
    wall = time.time() - start
    resp.raise_for_status()
    data = resp.json()
    choice = (data.get("choices") or [{}])[0]
    content = (choice.get("message") or {}).get("content") or ""
    timings = data.get("timings") or {}
    usage = data.get("usage") or {}
    
    prompt_ms = timings.get("prompt_ms", 0.0)
    ttft_sec = round(prompt_ms / 1000.0, 3)
    prefill_tps = round(timings.get("prompt_per_second", 0.0), 2)
    decode_tps = round(timings.get("predicted_per_second", 0.0), 2)
    completion_tokens = usage.get("completion_tokens", 0)

    return {
        "content": content,
        "wall_sec": round(wall, 2),
        "ttft_sec": ttft_sec,
        "prefill_tps": prefill_tps,
        "decode_tps": decode_tps,
        "completion_tokens": completion_tokens,
    }


def extract_code_block(content: str, language: str = "ruby") -> str:
    """Extract code from ```ruby ... ``` or first code block."""
    matches = re.findall(rf"```{language}\n(.*?)```", content, re.DOTALL | re.IGNORECASE)
    if matches:
        return matches[0].strip()
    matches = re.findall(r"```\n?(.*?)```", content, re.DOTALL)
    if matches:
        return matches[0].strip()
    return content.strip()


def run_rspec_saber():
    cmd = (
        "DATABASE_HOST=127.0.0.1 DATABASE_PORT=5433 DATABASE_USER=app DATABASE_PASSWORD=app "
        "mise x ruby@3.4.8 -- bundle exec rspec"
    )
    res = subprocess.run(cmd, shell=True, cwd=SABER_DIR, capture_output=True, text=True)
    out = res.stdout + res.stderr
    
    # Parse rspec summary line: "138 examples, 0 failures, 1 pending"
    m = re.search(r"(\d+) examples?, (\d+) failures?(?:, (\d+) pending)?", out)
    if m:
        examples = int(m.group(1))
        failures = int(m.group(2))
        pending = int(m.group(3) or 0)
    else:
        examples, failures, pending = 0, -1, 0

    return {
        "exit_code": res.returncode,
        "examples": examples,
        "failures": failures,
        "pending": pending,
        "passed": examples - failures - pending if failures >= 0 else 0,
        "raw_summary": [line for line in out.splitlines() if "examples" in line][-1] if m else "Unknown",
    }


def run_rspec_caster():
    cmd = (
        "DATABASE_HOST=127.0.0.1 DATABASE_PORT=5435 DATABASE_USER=app DATABASE_PASSWORD=app "
        "mise x ruby@3.4.8 -- bundle exec rspec"
    )
    res = subprocess.run(cmd, shell=True, cwd=CASTER_DIR, capture_output=True, text=True)
    out = res.stdout + res.stderr
    
    m = re.search(r"(\d+) examples?, (\d+) failures?(?:, (\d+) pending)?", out)
    if m:
        examples = int(m.group(1))
        failures = int(m.group(2))
        pending = int(m.group(3) or 0)
    else:
        examples, failures, pending = 0, -1, 0

    return {
        "exit_code": res.returncode,
        "examples": examples,
        "failures": failures,
        "pending": pending,
        "passed": examples - failures - pending if failures >= 0 else 0,
        "raw_summary": [line for line in out.splitlines() if "examples" in line][-1] if m else "Unknown",
    }


FAILING_REMINDER_SPEC = """require "rails_helper"

RSpec.describe Reminder, type: :model do
  describe "#snoozed?" do
    let(:person) { create(:person) }
    let(:active_reminder) { create(:reminder, person: person) }
    let(:snoozed_reminder) { create(:reminder, person: person, snoozed_until: Date.today + 1.day) }

    it "returns false for active reminders" do
      expect(active_reminder.snoozed?).to be false
    end

    it "returns false for reminders that are not snoozed" do
      expect(snoozed_reminder.snoozed?).to be false
    end

    it "returns true for reminders that are snoozed" do
      expect(snoozed_reminder.snoozed?).to be true
    end
  end
end
"""

FAILING_INTERACTION_SPEC = """require "rails_helper"

RSpec.describe Interaction, type: :model do
  describe "validations" do
    it { should validate_presence_of(:interaction_type) }
    it { should validate_presence_of(:occurred_at) }
  end

  describe "scopes" do
    let(:person) { create(:person) }
    let!(:active_interaction) { create(:interaction, person: person) }
    let!(:voided_interaction) { create(:interaction, person: person, voided_at: Time.current) }
    let!(:recent_interaction) { create(:interaction, person: person, occurred_at: Time.current - RECENT_WINDOW) }
    let!(:not_recent_interaction) { create(:interaction, person: person, occurred_at: Time.current - RECENT_WINDOW - 1.day) }

    it "active excludes voided records" do
      expect(Interaction.active).to include(active_interaction)
      expect(Interaction.active).not_to include(voided_interaction)
    end

    it "voided excludes active records" do
      expect(Interaction.voided).to include(voided_interaction)
      expect(Interaction.voided).not_to include(active_interaction)
    end

    it "recent includes recent records" do
      expect(Interaction.recent).to include(recent_interaction)
      expect(Interaction.recent).not_to include(not_recent_interaction)
    end

    it "recent excludes not recent records" do
      expect(Interaction.recent).not_to include(active_interaction)
      expect(Interaction.recent).not_to include(voided_interaction)
      expect(Interaction.recent).not_to include(not_recent_interaction)
    end
  end
end
"""

TRUNCATED_LISTING_NORMALIZER = """class ListingNormalizer
  CONVERTERS = {
    # ...
    "list_price_cents"  => :price_cents,
    "sale_price_cents"  => :price_cents,
    # ...
  }.freeze

  # ...

  def convert(type, value)
    return nil if value.blank?
    send(type, value)
  end

  def price_cents(value) = Cents.to_cents(value)
  # ...
end
"""


def reset_saber_fixtures():
    with open(os.path.join(SABER_DIR, "spec/models/reminder_spec.rb"), "w") as f:
        f.write(FAILING_REMINDER_SPEC)
    with open(os.path.join(SABER_DIR, "spec/models/interaction_spec.rb"), "w") as f:
        f.write(FAILING_INTERACTION_SPEC)


def reset_caster_fixtures():
    with open(os.path.join(CASTER_DIR, "app/models/listing_normalizer.rb"), "w") as f:
        f.write(TRUNCATED_LISTING_NORMALIZER)


def restore_clean_repos():
    subprocess.run("git checkout HEAD -- app/models/listing_normalizer.rb", shell=True, cwd=CASTER_DIR)


def eval_saber(model: str):
    print(f"\n--- [Saber] Evaluating {model} on Saber Test Suite ---", flush=True)
    reset_saber_fixtures()
    erase_slots(model, label="saber_eval")

    # Step A: Fix spec/models/reminder_spec.rb
    prompt_reminder = """You are a senior Ruby on Rails engineer.
Here is the failing spec `spec/models/reminder_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Reminder, type: :model do
  describe "#snoozed?" do
    let(:person) { create(:person) }
    let(:active_reminder) { create(:reminder, person: person) }
    let(:snoozed_reminder) { create(:reminder, person: person, snoozed_until: Date.today + 1.day) }

    it "returns false for active reminders" do
      expect(active_reminder.snoozed?).to be false
    end

    it "returns false for reminders that are not snoozed" do
      expect(snoozed_reminder.snoozed?).to be false
    end

    it "returns true for reminders that are snoozed" do
      expect(snoozed_reminder.snoozed?).to be true
    end
  end
end
```
Failure:
"Reminder#snoozed? returns false for reminders that are not snoozed" fails because snoozed_reminder has `snoozed_until: Date.today + 1.day`, so it returns true instead of false.
`Reminder#snoozed?` is defined as:
```ruby
def snoozed?
  snoozed_until.present? && snoozed_until > Date.today
end
```
For "reminders that are not snoozed", provide a reminder where snooze has expired (e.g. `snoozed_until: Date.today - 1.day` or `Date.yesterday`).

Rewrite `spec/models/reminder_spec.rb` so that:
1. "returns false for active reminders" tests active_reminder (snoozed_until is nil) -> false
2. "returns false for reminders that are not snoozed" tests a reminder whose snooze has expired (snoozed_until in the past) -> false
3. "returns true for reminders that are snoozed" tests snoozed_reminder (snoozed_until in the future) -> true

Return ONLY the complete updated file content in a ```ruby code block.
"""

    res_reminder = call_llm(model, "You write clean, precise Ruby RSpec tests.", prompt_reminder)
    code_reminder = extract_code_block(res_reminder["content"])

    # Step B: Fix spec/models/interaction_spec.rb and app/models/interaction.rb
    prompt_interaction = """You are a senior Ruby on Rails engineer.
In `saber`:
`app/models/interaction.rb` defines:
```ruby
class Interaction < ApplicationRecord
  belongs_to :person

  scope :active, -> { where(voided_at: nil) }
  scope :voided, -> { where.not(voided_at: nil) }
  scope :recent, -> { where("occurred_at >= ?", Time.current - RECENT_WINDOW) }

  enum :interaction_type, {
    coffee: "coffee",
    lunch:  "lunch",
    text:   "text",
    call:   "call",
    email:  "email",
    event:  "event",
    other:  "other"
  }

  validates :interaction_type, presence: true
  validates :occurred_at,      presence: true

  RECENT_WINDOW = 30.days
end
```

In `spec/models/interaction_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Interaction, type: :model do
  describe "validations" do
    it { should validate_presence_of(:interaction_type) }
    it { should validate_presence_of(:occurred_at) }
  end

  describe "scopes" do
    let(:person) { create(:person) }
    let!(:active_interaction) { create(:interaction, person: person) }
    let!(:voided_interaction) { create(:interaction, person: person, voided_at: Time.current) }
    let!(:recent_interaction) { create(:interaction, person: person, occurred_at: Time.current - RECENT_WINDOW) }
    let!(:not_recent_interaction) { create(:interaction, person: person, occurred_at: Time.current - RECENT_WINDOW - 1.day) }

    it "active excludes voided records" do
      expect(Interaction.active).to include(active_interaction)
      expect(Interaction.active).not_to include(voided_interaction)
    end

    it "voided excludes active records" do
      expect(Interaction.voided).to include(voided_interaction)
      expect(Interaction.voided).not_to include(active_interaction)
    end

    it "recent includes recent records" do
      expect(Interaction.recent).to include(recent_interaction)
      expect(Interaction.recent).not_to include(not_recent_interaction)
    end

    it "recent excludes not recent records" do
      expect(Interaction.recent).not_to include(active_interaction)
      expect(Interaction.recent).not_to include(voided_interaction)
      expect(Interaction.recent).not_to include(not_recent_interaction)
    end
  end
end
```
Notice:
1. `RECENT_WINDOW` causes `NameError: uninitialized constant RECENT_WINDOW` because it must be referenced as `Interaction::RECENT_WINDOW`.
2. Notice the factory default for `occurred_at` is `Date.today`. Because Date.today is within the 30-day window, `active_interaction` will match `Interaction.recent`.
Therefore, in "recent excludes not recent records", `not_recent_interaction` is excluded. It should not expect `active_interaction` to be excluded unless `active_interaction` was in the past.
Rewrite `spec/models/interaction_spec.rb` cleanly so that:
- `Interaction::RECENT_WINDOW` is used properly.
- "recent includes recent records" tests that `recent_interaction` is included and `not_recent_interaction` is not included.
- "recent excludes not recent records" checks that `not_recent_interaction` is not included in `Interaction.recent`.

Return ONLY the complete updated `spec/models/interaction_spec.rb` content in a ```ruby code block.
"""

    res_interaction = call_llm(model, "You write clean, precise Ruby RSpec tests.", prompt_interaction)
    code_interaction = extract_code_block(res_interaction["content"])

    # Write files to saber
    with open(os.path.join(SABER_DIR, "spec/models/reminder_spec.rb"), "w") as f:
        f.write(code_reminder + "\n")
    with open(os.path.join(SABER_DIR, "spec/models/interaction_spec.rb"), "w") as f:
        f.write(code_interaction + "\n")

    # Run RSpec
    rspec_res = run_rspec_saber()
    print(f"  [Saber] Result: {rspec_res['raw_summary']} (failures: {rspec_res['failures']})", flush=True)

    return {
        "model": model,
        "repo": "saber",
        "reminder_llm": {
            "wall_sec": res_reminder["wall_sec"],
            "ttft_sec": res_reminder["ttft_sec"],
            "decode_tps": res_reminder["decode_tps"],
            "tokens": res_reminder["completion_tokens"],
        },
        "interaction_llm": {
            "wall_sec": res_interaction["wall_sec"],
            "ttft_sec": res_interaction["ttft_sec"],
            "decode_tps": res_interaction["decode_tps"],
            "tokens": res_interaction["completion_tokens"],
        },
        "rspec": rspec_res,
        "pass": rspec_res["failures"] == 0,
    }


def eval_caster(model: str):
    print(f"\n--- [Caster] Evaluating {model} on Caster ListingNormalizer ---", flush=True)
    reset_caster_fixtures()
    erase_slots(model, label="caster_eval")

    prompt_caster = """You are a senior Ruby on Rails engineer.
In `caster`, `app/models/cents.rb` has:
```ruby
module Cents
  def self.to_dollars(cents)
    return nil if cents.nil?
    (cents.to_f / 100).round(2)
  end

  def self.to_cents(dollars)
    return nil if dollars.nil?
    (dollars.gsub(/[$,]/, "").to_f * 100).to_i
  end
end
```

We need the complete implementation of `app/models/listing_normalizer.rb`.
It must satisfy all tests in `spec/models/listing_normalizer_spec.rb` and `spec/services/normalizer_spec.rb`.
Requirements:
1. `CONVERTERS` hash mapping canonical fields to converter methods:
   - "mls_number" => :passthrough
   - "listing_status" => :passthrough
   - "street_address" => :passthrough
   - "city" => :passthrough
   - "state" => :passthrough
   - "zip_code" => :passthrough
   - "mls_area_id" => :passthrough
   - "mls_area_name" => :passthrough
   - "property_type" => :passthrough
   - "property_sub_type" => :passthrough
   - "construction_type" => :passthrough
   - "building_type" => :passthrough
   - "parking_features" => :passthrough
   - "bedrooms" => :integer
   - "parking_spaces" => :integer
   - "garage_spaces" => :integer
   - "age_years" => :integer
   - "days_on_market" => :integer
   - "list_price_cents" => :price_cents
   - "sale_price_cents" => :price_cents
   - "listed_at" => :date
   - "expires_at" => :date
   - "sale_agreed_at" => :date
   - "off_market_at" => :date
   - "closed_at" => :date
   - "latitude" => :decimal
   - "longitude" => :decimal
   - "sq_ft_total" => :sq_ft
   - "lot_size_sqft" => :lot_size

2. `initialize(raw_data, feed_profile)`:
   stores `@raw_data = raw_data`
   stores `@mappings = feed_profile.feed_columns.pluck(:canonical_field_name, :raw_column_name).to_h`

3. `normalize`:
   maps every entry in CONVERTERS to `[ canonical.to_sym, convert(type, field(canonical)) ]` into a hash,
   and merges `baths_pair`.

4. Private converters:
   - `convert(type, value)`: returns `nil if value.blank?`, otherwise `send(type, value)`
   - `field(canonical)`: `mappings.fetch(canonical)` and fetches from `raw_data[raw_name]`
   - `passthrough(value)`: `value`
   - `integer(value)`: `value.to_i`
   - `price_cents(value)`: MUST call `Cents.to_cents(value)`!
   - `date(value)`: `Date.strptime(value, "%m/%d/%Y")`
   - `decimal(value)`: `value.to_d`
   - `sq_ft(value)`: `i = value.gsub(",", "").to_i; i.zero? ? nil : i`
   - `lot_size(value)`: `cleaned = value.gsub(/Lot SqFt|,/, "").strip; cleaned.empty? ? nil : cleaned.to_i`
   - `baths_pair`:
     `value = field("baths")`
     `return { full_baths: nil, half_baths: nil } if value.blank?`
     `full, half = value.split("|")`
     `{ full_baths: full.to_i, half_baths: half&.to_i }`

DO NOT abbreviate or truncate with `# ...`. Output the full, unabbreviated class in a ```ruby code block.
"""

    res_caster = call_llm(model, "You write complete, bug-free, production Ruby on Rails code.", prompt_caster, max_tokens=2500)
    code_caster = extract_code_block(res_caster["content"])

    # Write to caster
    normalizer_path = os.path.join(CASTER_DIR, "app/models/listing_normalizer.rb")
    with open(normalizer_path, "w") as f:
        f.write(code_caster + "\n")

    # Run RSpec Turn 1
    rspec_res_1 = run_rspec_caster()
    print(f"  [Caster Turn 1] Result: {rspec_res_1['raw_summary']} (failures: {rspec_res_1['failures']})", flush=True)

    turn_2_data = None
    final_rspec = rspec_res_1
    if rspec_res_1["failures"] > 0:
        print("  [Caster Turn 2] Feeding test error back to model for autonomous repair...", flush=True)
        # Capture error snippet
        cmd = (
            "DATABASE_HOST=127.0.0.1 DATABASE_PORT=5435 DATABASE_USER=app DATABASE_PASSWORD=app "
            "mise x ruby@3.4.8 -- bundle exec rspec spec/models/listing_normalizer_spec.rb:22"
        )
        err_out = subprocess.run(cmd, shell=True, cwd=CASTER_DIR, capture_output=True, text=True).stdout[:1000]

        prompt_repair = f"""Your previous implementation of `app/models/listing_normalizer.rb` caused the following RSpec error:
{err_out}

Here was your previous code:
```ruby
{code_caster}
```

Fix the issue (e.g. define `attr_reader :raw_data, :mappings` or use `@mappings`) so that the class runs cleanly.
Return ONLY the complete updated file content in a ```ruby code block.
"""
        res_repair = call_llm(model, "You fix Ruby syntax and runtime errors accurately.", prompt_repair, max_tokens=2500)
        code_caster_2 = extract_code_block(res_repair["content"])
        with open(normalizer_path, "w") as f:
            f.write(code_caster_2 + "\n")

        rspec_res_2 = run_rspec_caster()
        print(f"  [Caster Turn 2] Result: {rspec_res_2['raw_summary']} (failures: {rspec_res_2['failures']})", flush=True)
        final_rspec = rspec_res_2
        turn_2_data = {
            "wall_sec": res_repair["wall_sec"],
            "ttft_sec": res_repair["ttft_sec"],
            "decode_tps": res_repair["decode_tps"],
            "tokens": res_repair["completion_tokens"],
            "rspec": rspec_res_2,
        }

    return {
        "model": model,
        "repo": "caster",
        "turn_1": {
            "wall_sec": res_caster["wall_sec"],
            "ttft_sec": res_caster["ttft_sec"],
            "decode_tps": res_caster["decode_tps"],
            "tokens": res_caster["completion_tokens"],
            "rspec": rspec_res_1,
        },
        "turn_2": turn_2_data,
        "final_rspec": final_rspec,
        "pass": final_rspec["failures"] == 0,
    }


def main():
    parser = argparse.ArgumentParser(description="Stone 2: Production Repo Coding Benchmark")
    parser.add_argument("--model", required=True, help="Model preset (glm47-reap, qwen36-coder-hybrid)")
    parser.add_argument("--run", type=int, default=None, help="Run number (e.g. 1, 2, 3)")
    args = parser.parse_args()

    saber_result = eval_saber(args.model)
    caster_result = eval_caster(args.model)

    summary = {
        "model": args.model,
        "run_id": args.run,
        "saber": saber_result,
        "caster": caster_result,
        "both_passed": saber_result["pass"] and caster_result["pass"],
    }

    out_file = os.path.join(REPORTS_DIR, f"repo_coding_{args.model}.json")
    with open(out_file, "w") as f:
        json.dump(summary, f, indent=2)
    if args.run is not None:
        runs_dir = os.path.join(REPORTS_DIR, "runs")
        os.makedirs(runs_dir, exist_ok=True)
        run_file = os.path.join(runs_dir, f"repo_coding_{args.model}_run_{args.run}.json")
        with open(run_file, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"Saved repo coding benchmark run {args.run} to {run_file}", flush=True)
    print(f"\nSaved repo coding benchmark to {out_file}", flush=True)

    # Restore clean state on caster so repo stays green
    restore_clean_repos()
    return summary


if __name__ == "__main__":
    main()
