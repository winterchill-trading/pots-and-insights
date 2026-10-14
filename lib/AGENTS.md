# lib/

The `pots-and-insights` library, wrapped as `Pots_and_insights`; every module is
re-exported from `pots_and_insights.ml` with a one-line doc.

- Pots: `pot`, `pot_booking`, `round_up`, `top_up`, `pot_job`.
- Insights: `item`, `category`, `catalogue`, `keywords`, `preferences`, `categorise`,
  `insights`, `budget`, `budget_month`, `notice`.
- Shared: `id` (validated id functor), `pot_id`, `owner_id`, `budget_id`, `item_id`,
  `calendar_month`, `percentage`, `text`.

Rules here:

- Pure values only: no I/O, no Async, no store. Ledger effects are `Ledger.Entry.t`
  values checked against the `Ledger.Balances.t` the caller passes.
- A type that callers persist gets a `Stable.V1` and a digest line in
  `../test/test_stable.ml`.
- Refusals are variants with a `code` function giving a snake_case string; keep codes
  stable, callers map them to their own errors.
- odoc on every public value; CI fails on odoc warnings.
