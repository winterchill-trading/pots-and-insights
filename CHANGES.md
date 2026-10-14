# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## Unreleased

### Added

- Savings pots: `Pot` (details, limits, refusals, goal progress) and `Pot_booking`
  (deposit, withdrawal and close entries under idempotency keys, replays, movement
  history).
- Automatic saving: `Round_up`, `Top_up`, and `Pot_job` running both on scheduler-core.
- Categorisation: `Item`, `Category`, `Catalogue`, `Keywords`, `Preferences`,
  `Categorise` (override, merchant and payee rules, standing orders, keywords, merchant
  categories, default; refunds follow purchases).
- `Insights`: monthly totals by category and merchant, month over month change, shares,
  money in and out over several months.
- `Budget` and `Budget_month`: monthly budgets per account, category or overall, with
  amounts over time, under / near / over states and pace.
- `Notice`: budget near and over, pot goal reached, with dedupe keys.
- `Calendar_month` (UTC) and `Percentage` (exact, one decimal).
- Stable bin_prot types with pinned digests; `examples/quickstart.ml`; the
  `pots-and-insights` CLI.
