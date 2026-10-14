(lang dune 3.17)

(name pots-and-insights)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/pots-and-insights))

(homepage "https://github.com/winterchill-trading/pots-and-insights")

(bug_reports "https://github.com/winterchill-trading/pots-and-insights/issues")

(documentation "https://github.com/winterchill-trading/pots-and-insights#readme")

(package
 (name pots-and-insights)
 (synopsis
  "Savings pots and spending insights for banks: owned sub-accounts, round-ups, categories and monthly budgets")
 (description
  "pots-and-insights models two retail banking features over a double-entry ledger. Savings pots are owned sub-accounts of a currency account with an optional goal and target date and caller-defined cosmetic fields; money moves in and out as balanced ledger entries under idempotency keys, closing returns the balance in one entry, and round-ups and scheduled top-ups are jobs for scheduler-core. Spending insights categorise statement items (user overrides and rules, standing orders, payees, a keyword list, merchant hints, a default), total them per calendar month in UTC by category and merchant, and track monthly budgets per currency account and category or overall with under, near and over states and an even-pace expectation. Notices (budget near or over, goal reached) are returned as values. Pure: the library never persists anything. Requires the OxCaml compiler (through its money dependency).")
 (tags
  (banking savings pots budgets categories insights ledger oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (core_unix
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  zarith
  money
  ledger
  scheduler-core
  (expect_test_helpers_core
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
