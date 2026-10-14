open! Core
open Pots_and_insights
open Helpers

let month s = Or_error.ok_exn (Calendar_month.of_string s)
let oct = month "2026-10"
let ctx = Insights.Context.default
let ok r = Result.ok r |> Option.value_exn

let budget ?(id = "b1") ?(existing = []) ?(from = oct) target amount =
  Budget.create
    Catalogue.default
    ~id:(Budget_id.of_string id)
    ~owner
    ~account
    ~currency:Money.Currency.eur
    ~target
    ~amount:(eur amount)
    ~from
    ~existing
;;

let%expect_test "status thresholds" =
  List.iter [ "0.00"; "79.99"; "80.00"; "100.00"; "100.01" ] ~f:(fun spent ->
    print_s
      [%sexp
        (spent : string)
        , (Budget.status ~amount:(eur "100.00") ~spent:(eur spent) () : Budget.Status.t)]);
  [%expect
    {|
    (0.00 Under)
    (79.99 Under)
    (80.00 Near)
    (100.00 Near)
    (100.01 Over)
    |}]
;;

let%expect_test "pace is the even share of the month elapsed" =
  let pace now spent =
    print_s
      [%sexp
        (Budget.pace ~amount:(eur "310.00") ~spent:(eur spent) ~month:oct ~now:(time now)
         : Budget.Pace.t option)]
  in
  pace "2026-10-14 09:00:00Z" "140.00";
  pace "2026-10-14 09:00:00Z" "140.01";
  pace "2026-10-31 23:59:59Z" "309.00";
  pace "2026-11-01 00:00:00Z" "1.00";
  [%expect
    {|
    (((day 14) (days 31) (expected "140.00 EUR") (status On_track)))
    (((day 14) (days 31) (expected "140.00 EUR") (status Ahead)))
    (((day 31) (days 31) (expected "310.00 EUR") (status On_track)))
    ()
    |}]
;;

let%expect_test "creation refusals" =
  let b = budget (Category (cat "groceries")) "300.00" |> ok in
  let show r =
    print_s [%sexp (Result.error r |> Option.map ~f:Budget.Refusal.code : string option)]
  in
  show (budget (Category (cat "income")) "300.00");
  show (budget Overall "0.00");
  show (budget Overall "10000000000.01");
  show (budget Overall "10000000000.00");
  show
    (Budget.create
       Catalogue.default
       ~id:(Budget_id.of_string "x")
       ~owner
       ~account
       ~currency:Money.Currency.eur
       ~target:Overall
       ~amount:(Money.Amount.of_string "5.00 USD")
       ~from:oct
       ~existing:[]);
  show (budget ~id:"b2" ~existing:[ b ] (Category (cat "groceries")) "50.00");
  (* Once the first one is removed from November, a new one may start then. *)
  let removed = Budget.remove b ~from:(month "2026-11") |> ok in
  show
    (budget
       ~id:"b2"
       ~existing:[ removed ]
       ~from:(month "2026-11")
       (Category (cat "groceries"))
       "50.00");
  [%expect
    {|
    (unknown_category)
    (amount_not_positive)
    (amount_too_large)
    ()
    (currency_mismatch)
    (budget_exists)
    ()
    |}]
;;

let%expect_test "amounts apply from their month onwards" =
  let b = budget Overall "300.00" |> ok in
  let b = Budget.set_amount b ~amount:(eur "400.00") ~from:(month "2026-12") |> ok in
  let b = Budget.set_amount b ~amount:(eur "350.00") ~from:(month "2026-11") |> ok in
  let b = Budget.remove b ~from:(month "2027-02") |> ok in
  List.iter
    [ "2026-09"; "2026-10"; "2026-11"; "2026-12"; "2027-01"; "2027-02" ]
    ~f:(fun m ->
      print_s
        [%sexp (m : string), (Budget.amount_for b (month m) : Money.Amount.t option)]);
  print_s
    [%sexp
      (Budget.set_amount b ~amount:(eur "1.00") ~from:(month "2027-03") |> Result.error
       : Budget.Refusal.t option)];
  [%expect
    {|
    (2026-09 ())
    (2026-10 ("300.00 EUR"))
    (2026-11 ("350.00 EUR"))
    (2026-12 ("350.00 EUR"))
    (2027-01 ("350.00 EUR"))
    (2027-02 ())
    (Removed)
    |}]
;;

let items =
  [ item
      ~id:"i1"
      ~at:(time "2026-10-02 10:00:00Z")
      ~amount:"-200.00"
      (card ~category:"groceries" "Market")
  ; item ~id:"i2" ~at:(time "2026-10-03 10:00:00Z") ~amount:"-45.00" (card "Corner Cafe")
  ; item
      ~id:"i3"
      ~at:(time "2026-10-04 10:00:00Z")
      ~amount:"-30.00"
      (card ~category:"shopping" "Shop")
  ]
;;

let%expect_test "a month view and the notices a new purchase raises" =
  let budgets =
    [ budget ~id:"overall" Overall "300.00" |> ok
    ; budget ~id:"food" (Category (cat "groceries")) "250.00" |> ok
    ; budget ~id:"cafes" (Category (cat "eating_out")) "50.00" |> ok
    ]
  in
  let now = time "2026-10-14 09:00:00Z" in
  let view items =
    Budget_month.compute
      ctx
      ~budgets
      ~account
      ~currency:Money.Currency.eur
      ~month:oct
      ~now
      items
  in
  let before = view items in
  print_s [%sexp (before : Budget_month.t)];
  let after =
    view
      (item
         ~id:"i4"
         ~at:(time "2026-10-14 08:00:00Z")
         ~amount:"-6.00"
         (card "Corner Cafe")
       :: items)
  in
  List.iter (Notice.budget_changes ~before ~after) ~f:(fun n ->
    print_s [%sexp (Notice.key n : string), (n : Notice.t)]);
  [%expect
    {|
    ((account customer:1/eur) (currency EUR) (month 2026-10) (current true)
     (overall
      (((budget overall) (target Overall) (month 2026-10) (amount "300.00 EUR")
        (spent "275.00 EUR") (remaining "25.00 EUR") (percent 91.7) (status Near)
        (pace (((day 14) (days 31) (expected "135.48 EUR") (status Ahead)))))))
     (categories
      (((budget food) (target (Category groceries)) (month 2026-10)
        (amount "250.00 EUR") (spent "200.00 EUR") (remaining "50.00 EUR")
        (percent 80.0) (status Near)
        (pace (((day 14) (days 31) (expected "112.90 EUR") (status Ahead)))))
       ((budget cafes) (target (Category eating_out)) (month 2026-10)
        (amount "50.00 EUR") (spent "45.00 EUR") (remaining "5.00 EUR")
        (percent 90.0) (status Near)
        (pace (((day 14) (days 31) (expected "22.58 EUR") (status Ahead)))))))
     (spending "275.00 EUR") (near_percent 80))
    (budget:cafes:2026-10:over
     (Budget_over (budget cafes) (account customer:1/eur)
      (target (Category eating_out)) (month 2026-10) (spent "51.00 EUR")
      (amount "50.00 EUR")))
    |}]
;;

let%expect_test "goal reached" =
  let p = pot ~goal:(eur "100.00") () in
  let show before after =
    print_s
      [%sexp
        (Notice.goal_reached p ~before:(eur before) ~after:(eur after) : Notice.t option)]
  in
  show "50.00" "99.99";
  show "50.00" "100.00";
  show "100.00" "120.00";
  [%expect
    {|
    ()
    ((Goal_reached (pot pot-1) (goal "100.00 EUR") (balance "100.00 EUR")))
    ()
    |}]
;;

let%test_unit "status agrees with remaining and percent" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind amount = Int.gen_incl 1 1_000_000 in
    let%map spent = Int.gen_incl 0 2_000_000 in
    amount, spent
  in
  Quickcheck.test gen ~f:(fun (amount, spent) ->
    let b =
      budget
        Overall
        (Money.Amount.to_decimal_string
           (Money.Amount.of_minor_units_int Money.Currency.eur amount))
      |> ok
    in
    let p =
      Budget.progress
        b
        ~month:oct
        ~spent:(Money.Amount.of_minor_units_int Money.Currency.eur spent)
        ~now:(time "2026-10-14 09:00:00Z")
      |> Option.value_exn
    in
    [%test_result: bool]
      (Budget.Status.equal p.status Over)
      ~expect:(Money.Amount.is_negative p.remaining);
    (* The state comes from an exact comparison, so an [Under] budget can still show 80.0
       after rounding; a [Near] one never shows less. *)
    if Budget.Status.equal p.status Near
    then assert (Percentage.to_tenths p.percent >= 800);
    match p.pace with
    | None -> assert false
    | Some pace -> assert (Money.Amount.( <= ) pace.expected p.amount))
;;
