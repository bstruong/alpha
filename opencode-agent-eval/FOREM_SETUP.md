# Forem Rails eval — setup progress (Metrotower)

Branch: `opencode-eval-rails` (disposable), repo cloned to `~/forem` (2.0GB).

## Done
- Cloned `https://github.com/forem/forem.git`, branch `opencode-eval-rails` created, clean at clone time.
- **Ruby version mismatch found and resolved**: Forem pinned `.ruby-version` = 3.3.0; Metrotower's
  mise only had 3.4.8 installed (used elsewhere, untouched). Installed Ruby 3.3.0 via mise
  (additive), hit a native-extension build failure on `ruby-prof` (1.7.0) against GCC 16.1.1:
  `unknown type name 'bool'` in `scan_args.h` (Ruby 3.3.0's C headers don't include `<stdbool.h>`;
  GCC 16 is too new/strict for it). Fix (approved as "Option 1"): bumped to **Ruby 3.3.12** (latest
  3.3.x patch) instead of exactly 3.3.0 — compiles clean.
  - Files changed on the disposable branch (uncommitted, easy to diff/revert):
    - `.ruby-version`: `3.3.0` → `3.3.12`
    - `.mise.toml` (Forem's own tracked config — already pinned `yarn=1`, `postgres=13.12`,
      `redis=6.0.9`; this is how the exact DB version requirements were discovered): added
      `ruby = "3.3.12"`
  - mise's shell-hook auto-activation doesn't refresh inside this harness's non-interactive shell;
    use `mise exec ruby@3.3.12 -- <cmd>` (or the direct path
    `~/.local/share/mise/installs/ruby/3.3.12/bin/`) rather than relying on `cd`-triggered PATH
    switching.
- **`bundle install` succeeded**: 166 Gemfile dependencies, 412 gems installed, `ruby-prof` compiled
  clean under 3.3.12.
- **Database requirements confirmed**: `config/database.yml` → PostgreSQL. Forem's `.mise.toml`
  pins exact versions: **postgres 13.12, redis 6.0.9**.

## Blocked — stopped per instructions, awaiting go-ahead
Neither PostgreSQL nor Redis exist on Metrotower at all — no binary, no systemd unit (`could not be
found`, not just inactive), no pacman package. Have NOT installed anything. Next step once approved:
`mise install` (Forem's own `.mise.toml` already pins the exact versions needed) vs. system packages
vs. Docker — decision pending.

## Not yet run
- `bin/rails db:test:prepare`
- Single-spec smoke test (e.g. `spec/models/user_spec.rb`)
- Full RSpec suite (intentionally out of scope for this pass)

## Incident during this session (unrelated to Forem work itself)
The 640x480 display-EDID-loss incident (documented in `SUMMARY.md`) recurred during the qwen3:32b
quant-offload testing that preceded this Forem task (see [[vram-guard-threshold-insufficient]] memory
note) — VRAM guard's 1536MB threshold never breached, but the display broke anyway. Not caused by any
Forem/Ruby step above; flagging here only because it happened in the same session and needed a fix
(guard threshold) before further GPU work resumes on this machine.
