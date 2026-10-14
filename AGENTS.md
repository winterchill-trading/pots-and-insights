# AGENTS.md: pots-and-insights

## Purpose

pots-and-insights is a pure OCaml library for savings pots (owned sub-accounts with a
goal, round-ups and scheduled top-ups, money moved as ledger entries under idempotency
keys) and spending insights (categorisation, monthly totals in UTC, budgets with under,
near and over states, notices as values). It returns values and ledger entries and never
persists anything; services store them.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `pots-and-insights` library (`Pots_and_insights`) |
| `bin/` | The `pots-and-insights` CLI: `round-up`, `budget-status`, `categorise` |
| `test/` | Inline expect and Quickcheck tests, stable digests, cram test `cli.t/` |
| `examples/` | `quickstart.ml`, output diffed against `quickstart.expected` |
| `doc/` | `index.mld`, the odoc start page |
| `.github/` | `workflows/ci.yml` |
| `README.md`, `CHANGES.md` | User guide and changelog |

## Build, test, docs

The workspace keeps every org repository as a sibling checkout with a root
`dune-workspace`. From this directory:

```sh
DUNE_BUILD_DIR=_build-pots-and-insights opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/all
DUNE_BUILD_DIR=_build-pots-and-insights opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/runtest
DUNE_BUILD_DIR=_build-pots-and-insights opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/doc
```

`DUNE_BUILD_DIR` is relative to the workspace root because of `--root ..`; a separate
build directory avoids the shared dune lock when several agents work at once. Run the
CLI with `opam exec --switch 5.2.0+ox -- dune exec --root .. ./pots-and-insights/bin/main.exe -- round-up -spend 3.40`.

Standalone: `opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`,
`opam install --deps-only --with-test .`, then `dune build && dune test`.

## Conventions

- Format only this repository: `dune build --root .. @pots-and-insights/fmt --auto-promote`,
  after the tests pass and `dune promote` is done. Never `dune fmt` across the workspace.
- `open! Core`, an `.mli` for every module, labelled arguments, ppx_jane derivations.
- Persisted types have `Stable.V1` modules; ids and categories validate on decode. Their
  bin_prot digests are pinned in `test/test_stable.ml`: a changed digest means add a
  `V2`, never edit `V1`.
- Behaviour in expect tests, invariants with `Quickcheck.test` in `let%test_unit`
  (money conservation of pot moves, category totals, budget states).
- No floats: amounts are `Money.Amount.t`, shares `Percentage.t` (tenths), periods
  `Calendar_month.t` in UTC.
- Pure: no I/O, no Async, no store. Ledger effects are returned as `Ledger.Entry.t`
  checked against the `Ledger.Balances.t` passed in; scheduled work is a
  `Scheduler_core.Job.S` functor over any monad.
- odoc on every public value (CI fails on odoc warnings); comments for humans at
  non-obvious choices; user-visible changes get a line under "Unreleased" in `CHANGES.md`.
- New modules must be re-exported from `lib/pots_and_insights.ml`.

## Dependencies and dependents

Sibling libraries: `../money` (amounts, currencies), `../ledger` (accounts, entries,
balances), `../scheduler-core` (job interface for top-ups and round-up sweeps);
`../fixed-decimal` comes in through money. CI pins them in that order: fixed-decimal,
money, ledger, scheduler-core. No org repository depends on this one yet.

## CI

`.github/workflows/ci.yml` runs the `ox-setup` action from `../infra` (cached OxCaml
switch) with the pins above, then `dune build`, `dune test` (includes the example diff
and the cram test), runs `examples/quickstart.exe`, builds `@doc` and fails on any odoc
warning, plus the reusable obj-magic job. Check a run with `gh run list --limit 1` and at
most one `gh run watch <id> --exit-status`; never poll in a loop.

## Pitfalls

- `open! Core` shadows library modules named like Core modules (`Percent`, `Month`,
  `Clock`): that is why the percentage type is `Percentage` and months are
  `Calendar_month`.
- `Time_ns.t` sexps print in the machine's zone; records use `Time_ns.Alternate_sexp.t`
  (UTC) so expect output is the same on macOS and Linux.
- `[@sexp.opaque]` on a record field applies only inside parentheses with the
  type: `(Z.t[@sexp.opaque])`.
- odoc rejects unbalanced brackets in code spans, such as a half-open interval written
  `[[from, until)]`; say "inclusive" and "exclusive" in words.
- `Identifiable.Make` over a validated string needs `bin_io` in the input module; the
  `Id.Make` functor puts a validating `Binable.Of_binable_without_uuid` there.
- A ledger idempotency key must be booked once: `Pot_booking` checks for an existing
  entry before checking balances, so a retried deposit replays instead of failing on
  funds that already moved.
- Another agent's half-written sibling repository can print errors in the shared build
  output; filter for `pots-and-insights` paths before treating a build as failed.

## Where to read more

- `README.md`, `CHANGES.md`, `doc/index.mld`.
- `../specs/repos/pots-and-insights.md` for the repository's place in the workspace.
- `../oxcaml-claude-skills/skills/`: `janestreet-ocaml-style`, `banking-standards`.
- `../oxcaml-claude-skills/AGENTS.md`, the workspace-wide guide, and
  `../oxcaml-claude-skills/GOTCHAS.md`, section "Product libraries".

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared `5.2.0+ox` switch; dry-run any install first.
- Publish, tag or release.
- Commit credentials (`.env` is gitignored) or print secrets.
- Poll CI in a loop.
