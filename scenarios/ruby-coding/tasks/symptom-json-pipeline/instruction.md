`JsonPipeline.summarize` should keep only `status == "ok"` rows, map each to `id` and integer `total`, and sort by `id`.
POST `/tools/summarize` renders those rows in `#summary-rows`. Something in the pipeline is wrong — leave tests green.
