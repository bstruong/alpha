# Relearning Ruby / Rails inside Alpha

You are an experienced engineer rebuilding muscle memory. This app is intentionally half-empty.

## Mental model

| Layer | Where | Your job |
|-------|-------|----------|
| Rails chrome | `app/`, `config/`, `db/` | Practice ActiveRecord, routes, tests |
| Harness core | `lib/alpha/` | Implement real eval semantics |
| CLI | `bin/alpha` | Wire ARGV → `Alpha::Runner` |
| Fixtures | `scenarios/` | Read existing `task.yml` / tests; don’t rewrite yet |

## Ruby 4 / Rails 8 notes worth remembering

- `Data.define` (see `Alpha::Grader::Result`) — immutable value objects (Ruby 3.2+).
- Zeitwerk autoloads `lib/` via `config.autoload_lib` — file path == constant path (`lib/alpha/task.rb` → `Alpha::Task`).
- API-only app: no views/assets. Omega will be the Hotwire UI later.
- Prefer raising `NotImplementedError` until a path is real — keeps “what’s left” grep-able.

## Suggested drills

1. Write a Minitest for `Alpha::Task.load` against `scenarios/qwen36-daily/tasks/gate-hello`.
2. Implement `Sandbox.provision` with a directory copy first; upgrade to `git worktree` later.
3. Shell out to `bin/rails test` inside a sandbox for `Grader::MinitestFile`.
4. Only then touch Pi RPC / process groups.

## Versions

Pinned in-repo: **Ruby 4.0.7**, **Rails ~> 8.1.4**. Bump deliberately; don’t drift on the Haswell desk vs AM5.
