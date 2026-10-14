# bin/

`main.ml`: the `pots-and-insights` CLI over the pure parts of the library.

- `round-up -spend D [-unit D] [-multiplier N] [-currency C]`
- `budget-status -amount D -spent D [-now TIME] [-currency C]`
- `categorise [-merchant NAME [-merchant-category CODE]] [-payee NAME] [-description TEXT]`

Run with `opam exec --switch 5.2.0+ox -- dune exec --root .. ./pots-and-insights/bin/main.exe -- <command>`.
Its behaviour is pinned by `../test/cli.t/run.t`; change both together.
