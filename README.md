# pots-and-insights

Savings pots and spending insights for banks, as pure OCaml values over the org's
[`money`](https://github.com/winterchill-trading/money) and
[`ledger`](https://github.com/winterchill-trading/ledger) libraries.

- **Savings pots** are owned sub-accounts of a currency account, each with its own
  ledger account, an optional goal and target date, and cosmetic fields (a colour, an
  icon) kept as opaque strings. Money moves in and out as balanced ledger entries under
  idempotency keys; closing returns the whole balance in one entry and closes the
  ledger account.
- **Round-ups and scheduled top-ups** save automatically. Both run as jobs for
  [`scheduler-core`](https://github.com/winterchill-trading/scheduler-core), keyed by the
  run, so a retried date never moves money twice.
- **Spending insights** file statement items under categories (the customer's own
  choices, standing orders, payees, a keyword list, the card network's merchant
  category, else a default), total each calendar month in UTC by category, merchant and
  money flow, and track **monthly budgets** per currency account, per category or
  overall: under, near (from 80 %) or over, with the even pace of the month.
- **Notices** (budget near or over, pot goal reached) are returned as values with a key,
  so the caller sends each one once.

Nothing here persists or performs I/O. A service stores pots, budgets, preferences and
items in its own store and appends the returned ledger entries to its journal.

## Why separate

Every retail bank offers pots and spending insights, and both sit on top of the same
ledger as payments and cards without belonging to either. Keeping them in their own
library keeps the ledger generic, lets the categorisation rules and budget arithmetic be
tested exhaustively without a database, and lets a service pick only the parts it
offers.

## Quick start

```ocaml
open! Core
open Pots_and_insights

(* A pot with a goal, opened in the ledger next to the customer's account. *)
let pot =
  Pot.create
    ~id:(Pot_id.of_string "holiday")
    ~owner:(Owner_id.of_string "customer-1")
    ~account:(Ledger.Account_id.of_string "customer:1/eur")
    ~currency:Money.Currency.eur
    ~open_pots:0
    ~today:(Date.of_string "2026-10-14")
    ~at:now
    { name = "Holiday"
    ; goal = Some (Money.Amount.of_string "600.00 EUR")
    ; target_date = None
    ; cosmetics = [ "colour", "teal" ]
    }

(* Move money in: an entry checked against the current balances, for the caller to
   append to its journal. A retry with the same key returns the booked entry. *)
let entry =
  Pot_booking.deposit
    balances
    pot
    ~amount:(Money.Amount.of_string "150.00 EUR")
    ~idempotency_key:(Ledger.Idempotency_key.of_string "pot:holiday:req-1")
    ~at:now

(* A month of spending and the budgets on it. *)
let summary = Insights.summarise Insights.Context.default ~account ~currency ~month items
let view = Budget_month.compute Insights.Context.default ~budgets ~account ~currency ~month ~now items
let notices = Notice.budget_changes ~before ~after:view
```

The complete program is [`examples/quickstart.ml`](examples/quickstart.ml); CI runs it
and compares its output with `examples/quickstart.expected`:

```
pot Holiday: 150.00 EUR, 25% of the goal
groceries  179.50 EUR (97.7%)
eating_out 4.20 EUR (2.3%)
budget groceries: 179.50 EUR of 220.00 EUR, near
budget:food:2026-10:near
```

## Modules

| Module | What it does |
| --- | --- |
| `Pot` | Pot record, editable details, limits (20 open pots, 30-character names), refusals, goal progress |
| `Pot_booking` | Deposit, withdrawal and close entries; idempotent replays; movement history |
| `Round_up` | Round-up of a card purchase to a unit, with a multiplier; totals over a period |
| `Top_up` | Fixed scheduled top-ups, optionally capped at the goal |
| `Pot_job` | Top-ups and daily round-up sweeps as `Scheduler_core.Job.S` |
| `Item` | Statement items and their flow (spending, refund, income, internal) |
| `Category`, `Catalogue` | Category codes and the set a bank offers, grouped spending / income / neutral |
| `Keywords` | Whole-word keyword lists that suggest a category |
| `Preferences` | The customer's overrides, merchant rules, payee rules, standing order categories |
| `Categorise` | Assigning categories and recategorising one item, a merchant or a payee |
| `Insights` | A month by category, merchant and money flow, with the month before |
| `Budget`, `Budget_month` | Monthly budgets with amounts over time, states and pace |
| `Notice` | Budget near / over and goal reached, with dedupe keys |
| `Calendar_month`, `Percentage` | UTC months and exact one-decimal percentages |

## Rules worth knowing

- **Periods are UTC calendar months.** An item belongs to the month of its UTC date; a
  caller in another zone converts first. Pace uses today's UTC day of the month:
  `expected = amount * day / days`, rounded down.
- **Only completed items count.** A card authorisation, its settlement or release is one
  item, booked when it finishes. Internal movements (pots, exchanges) are neither
  spending nor income.
- **Refunds follow their purchase** into its category and reduce spending there. They
  cannot be recategorised on their own.
- **Category order:** override, merchant rule, standing order, payee rule, keyword,
  merchant category, default. A stored choice whose category was retired from the
  catalogue is skipped, never an error.
- **Budget states:** under below 80 % of the amount, near from 80 % up to the amount,
  over above it, decided on exact amounts. An amount applies from its month onwards, so
  editing a budget does not rewrite past months.
- **Pot money is not spendable.** Each pot has its own credit-normal ledger account
  (`pot:<id>`); a deposit needs the parent's available balance, a withdrawal the pot's.

## Command line

`pots-and-insights` exercises the pure parts:

```sh
$ pots-and-insights round-up -spend 3.40
0.60 EUR
$ pots-and-insights budget-status -amount 310 -spent 140.01 -now 2026-10-14T09:00:00Z
((month 2026-10) (status under) (remaining "169.99 EUR")
 (pace (((day 14) (days 31) (expected "140.00 EUR") (status Ahead)))))
$ pots-and-insights categorise -payee Landlord -description "MONTHLY RENT"
((category bills) (source (Keyword rent)))
```

## Build

Requires the OxCaml compiler and the org's opam repository for `money`, `ledger` and
`scheduler-core`:

```sh
opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git
opam install --deps-only --with-test .
dune build && dune test
```

Inside the workspace (all org repositories as sibling checkouts):
`opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/runtest`.

## Docs

- API: `dune build @doc` (odoc), starting at `doc/index.mld`.
- `CHANGES.md` for what changed.
- `AGENTS.md` for working on this repository with an AI agent.

## Used by

No org repository depends on it yet.

## License

MIT
