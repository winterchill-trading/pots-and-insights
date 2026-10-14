# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## 0.1.1

### Added

- `Percentage.Rounding` (`Half_away_from_zero`, the default, and `Half_even`) and
  `Percentage.of_ratio_rounded`; `of_ratio` is unchanged.
- `?rounding` on `Budget.progress` and `?share_rounding` on `Insights.summarise`.
- `?max_bytes` on `Text.clean` and `?max_name_bytes` on `Pot.create` and `Pot.update`:
  an optional UTF-8 byte cap next to the code point limit.
- `?allow_past_target_date` on `Pot.create` and `Pot.update` (default `false`), for
  pots imported from another system.

### Fixed

- Documentation: name and cosmetic lengths are counted in Unicode code points, not
  user-perceived characters or bytes.

## 0.1.0

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
