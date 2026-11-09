# Qualifications (local scratch)

Alpha `qualifications/` is **scratch only**. Durable shipping artifacts and
the active evidence index live in [alpha-lab](https://github.com/bstruong/alpha-lab).

Local workflow (development / Job PVC):

```bash
bin/alpha run -s <scenario> -m <model> --profile shipping
bin/alpha run -s <scenario> -m <model> --profile measurement
bin/alpha qualify --run <shipping_run> --measurement-run <measurement_run>
```

Publish / manifest against the lab tree:

```bash
export ALPHA_ROOT=/home/brian/Projects/alpha-lab
bin/alpha qualify --manifest
bin/alpha qualify --list
```

Lab-owned scenarios (for example `ikigai-dot`) must be run with
`ALPHA_ROOT` pointing at alpha-lab. Do not recreate those scenarios under
`alpha/scenarios/`.

Legacy `alpha.qualification.v1` files under `archive-v1/` (if present) are
ignored by the v2 manifest loader. Do not regenerate `Own` / `Unattended`
routing views from Alpha; see alpha-lab `notes/OPS_TRUST.md`.
