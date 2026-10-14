# AGENTS.md: pots-and-insights

## Purpose

pots-and-insights is a pure OCaml library for savings pots (owned sub-accounts with goals,
round-ups and scheduled top-ups) and spending insights (categories, monthly totals and
budgets). It books money through `../ledger` and never persists anything itself.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `pots-and-insights` library |
| `test/` | Inline expect and Quickcheck tests |
| `.github/` | `ci.yml` |

## Build, test, docs

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/all
opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/runtest
```

Use `DUNE_BUILD_DIR=../_build-pots-and-insights` for parallel work.

## Where to read more

`README.md` and `../oxcaml-claude-skills/AGENTS.md` (workspace guide).
