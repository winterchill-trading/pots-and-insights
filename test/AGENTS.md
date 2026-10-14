# test/

Inline expect tests and Quickcheck properties (`pots_and_insights_test`), and a cram
test for the CLI in `cli.t/`. `helpers.ml` builds pots, ledgers and items for every file.

- Run: `DUNE_BUILD_DIR=_build-pots-and-insights opam exec --switch 5.2.0+ox -- dune build --root .. @pots-and-insights/runtest`.
  Accept new output with `dune promote --root ..` (same `DUNE_BUILD_DIR`) after reading
  the diff; format only after promoting.
- `test_stable.ml` pins bin_prot digests: a change there is a wire break.
- Properties: pot moves conserve money (`test_pot_booking.ml`), category totals add up
  to spending (`test_insights.ml`), budget state agrees with remaining and percent
  (`test_budget.ml`), every item gets a category of the right group
  (`test_categorise.ml`).
- `test_pot_job.ml` drives the scheduler-core runner over `Monad.Ident` with an
  in-memory journal.
