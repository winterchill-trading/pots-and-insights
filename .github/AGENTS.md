# .github/

`workflows/ci.yml`: `ox-setup` from the infra repository (cached OxCaml switch) with
`pins:` for fixed-decimal, money, ledger and scheduler-core in dependency order, then
`dune build`, `dune test`, the quick start example, `@doc` with odoc warnings as errors,
and the reusable obj-magic job.

When a sibling library is added to `dune-project`, add it to `pins:` after the libraries
it depends on. Check runs with `gh run list --limit 1` and at most one `gh run watch`.
