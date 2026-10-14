# examples/

`quickstart.ml`: the README's quick start as a full program (a pot, a deposit, a month of
categorised spending, a budget turning near). Not installed.

- `dune build --root .. @pots-and-insights/runtest` runs it and diffs its output with
  `quickstart.expected`; CI also runs it with `dune exec ./examples/quickstart.exe`.
- When the output changes on purpose, regenerate `quickstart.expected` from the program
  and update the output block in `../README.md` to match.
