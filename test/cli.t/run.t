Round-ups of a purchase:

  $ pots-and-insights round-up -spend 3.40
  0.60 EUR
  $ pots-and-insights round-up -spend 4.00
  0.00 EUR
  $ pots-and-insights round-up -spend 12.30 -unit 5 -multiplier 2
  5.40 EUR

A budget of 310.00 with 140.01 spent on 14 October:

  $ pots-and-insights budget-status -amount 310 -spent 140.01 -now 2026-10-14T09:00:00Z
  ((month 2026-10) (status under) (remaining "169.99 EUR")
   (pace (((day 14) (days 31) (expected "140.00 EUR") (status Ahead)))))
  $ pots-and-insights budget-status -amount 100 -spent 100.01 -now 2026-10-14T09:00:00Z
  ((month 2026-10) (status over) (remaining "-0.01 EUR")
   (pace (((day 14) (days 31) (expected "45.16 EUR") (status Ahead)))))

Categorisation with the default catalogue and keywords:

  $ pots-and-insights categorise -merchant "Corner Cafe" -merchant-category groceries
  ((category eating_out) (source (Keyword cafe)))
  $ pots-and-insights categorise -merchant "Market" -merchant-category groceries
  ((category groceries) (source Merchant))
  $ pots-and-insights categorise -payee Landlord -description "MONTHLY RENT"
  ((category bills) (source (Keyword rent)))
  $ pots-and-insights categorise -payee Friend
  ((category general) (source Default))
