# Note: legacy `experiments/hyperbolic-time-chamber/` leftover

## What kept showing up

Untracked path:

`experiments/hyperbolic-time-chamber/notes/workstation/benchmark_analysis_report.md`

This is a **CachyOS i7-4790K / RX 7600 workstation** hardware report from the separate `hyperbolic-time-chamber` project — not a Workstation Flash benchmark artifact.

## Timeline (git)

| When | Event |
|------|--------|
| 2026-10-02 14:51 | Source file birth in `/home/user/Projects/hyperbolic-time-chamber/...` (also `root:root`) |
| 2026-10-02 14:58–14:59 | Copied into this repo; commit `75d2661` on `archive/workstation-benchmark-report`. Working-tree copy birth/mtime/ctime all **2026-10-02 14:59** (inode never rewritten later) |
| 2026-10-06 | Accidentally re-staged in `1887f4e`, removed from the index in `2f0885a` (PR #17). Squash merge `dd6c7f6` never left the file in `master` |
| After removal | Path kept appearing in `git status` as **untracked** because the **on-disk inode was never unlinked** |

## Root cause (proven)

1. **Not an external writer.** Searched scripts, docker-compose mounts, systemd units, cron, snapper configs, git smudge/filters, and agent hooks — nothing recreates this path in the repository.
2. **Not a mysterious “add back”.** `stat` birth = mtime = ctime = Oct 2 14:59. The file was created once (as `root:root` mode `0644`) and left on disk.
3. **Why it looked like it “returned”:** `2f0885a` removed it from git’s tree, but the working-tree file survived as untracked. Agents/sandboxes that run as **root** can create and later notice root-owned leftovers under `experiments/`; a normal user `rm` fails when parent dirs are `root:root` `0755`. From the user’s POV the path keeps reappearing in `git status` after “deletes” that only cleared the index or failed on unlink.
4. **Sibling evidence:** the HTC source repo copy is still `root:root` with an earlier birth (14:51). Archive branch `archive/workstation-benchmark-report` still contains the blob — checking that branch out without ignore rules would restore a tracked copy.

## Fix applied

- Deleted the working-tree directory (removed; path clean).
- Added `.gitignore` rule: `experiments/hyperbolic-time-chamber/`.
- Do **not** re-commit this report; workstation archive lives on `archive/workstation-benchmark-report` / the HTC repo.

### If it reappears as root-owned

```bash
# Inspect
stat experiments/hyperbolic-time-chamber/notes/workstation/benchmark_analysis_report.md
# Delete (passwordless sudo may be required if dirs are root:root 0755)
sudo rm -rf experiments/hyperbolic-time-chamber
```

Then confirm `git check-ignore -v experiments/hyperbolic-time-chamber/notes/workstation/benchmark_analysis_report.md` matches the ignore rule.
