open! Core
open Pots_and_insights
open Helpers

let month s = Or_error.ok_exn (Calendar_month.of_string s)
let ctx = Insights.Context.default

let items =
  [ item
      ~id:"a1"
      ~at:(time "2026-09-03 10:00:00Z")
      ~amount:"-40.00"
      (card ~category:"groceries" "Green Grocer")
  ; item ~id:"a2" ~at:(time "2026-09-20 10:00:00Z") ~amount:"-10.00" (card "Corner Cafe")
  ; item
      ~id:"b1"
      ~at:(time "2026-10-01 00:00:00Z")
      ~amount:"-60.00"
      (card ~category:"groceries" "Green Grocer")
  ; item ~id:"b2" ~at:(time "2026-10-02 08:00:00Z") ~amount:"-4.50" (card "Corner Cafe")
  ; item ~id:"b3" ~at:(time "2026-10-03 08:00:00Z") ~amount:"-5.50" (card "CORNER CAFE")
  ; item
      ~id:"b4"
      ~at:(time "2026-10-05 12:00:00Z")
      ~amount:"-900.00"
      ~description:"Rent October"
      (payment "Landlord")
  ; item
      ~id:"b5"
      ~at:(time "2026-10-06 12:00:00Z")
      ~amount:"20.00"
      ~refund_of:"b1"
      (card "Green Grocer")
  ; item
      ~id:"b6"
      ~at:(time "2026-10-07 12:00:00Z")
      ~amount:"2500.00"
      (Incoming { payer = Some "Employer" })
  ; item ~id:"b7" ~at:(time "2026-10-08 12:00:00Z") ~amount:"-100.00" Internal
  ; item
      ~id:"b8"
      ~at:(time "2026-10-09 12:00:00Z")
      ~amount:"-99.00"
      ~status:Pending
      (card "Shop")
  ; item ~id:"b9" ~at:(time "2026-10-31 23:59:59Z") ~amount:"-1.00" (card "Corner Cafe")
  ; item ~id:"c1" ~at:(time "2026-11-01 00:00:00Z") ~amount:"-7.00" (card "Corner Cafe")
  ]
;;

let%expect_test "a month's summary" =
  let s =
    Insights.summarise
      ~flow_months:3
      ~top_merchants:2
      ctx
      ~account
      ~currency:Money.Currency.eur
      ~month:(month "2026-10")
      items
  in
  print_s [%sexp (s : Insights.t)];
  [%expect
    {|
    ((account customer:1/eur) (currency EUR) (month 2026-10)
     (spending "951.00 EUR") (previous_spending "50.00 EUR")
     (categories
      (((category bills) (total "900.00 EUR") (previous_total "0.00 EUR")
        (change "900.00 EUR") (share (94.6)) (count 1))
       ((category groceries) (total "40.00 EUR") (previous_total "40.00 EUR")
        (change "0.00 EUR") (share (4.2)) (count 1))
       ((category eating_out) (total "11.00 EUR") (previous_total "10.00 EUR")
        (change "1.00 EUR") (share (1.2)) (count 3))))
     (money_in "2520.00 EUR") (money_out "971.00 EUR")
     (flow
      (((month 2026-08) (money_in "0.00 EUR") (money_out "0.00 EUR")
        (net "0.00 EUR"))
       ((month 2026-09) (money_in "0.00 EUR") (money_out "50.00 EUR")
        (net "-50.00 EUR"))
       ((month 2026-10) (money_in "2520.00 EUR") (money_out "971.00 EUR")
        (net "1549.00 EUR"))))
     (top_merchants
      (((name "Green Grocer") (category groceries) (total "40.00 EUR") (count 1))
       ((name "Corner Cafe") (category eating_out) (total "11.00 EUR") (count 3)))))
    |}]
;;

let%expect_test "spent per category for budgets, and the months with data" =
  let by_category, total =
    Insights.spent
      ctx
      ~account
      ~currency:Money.Currency.eur
      ~month:(month "2026-10")
      items
  in
  print_s [%sexp (by_category : Money.Amount.t Category.Map.t), (total : Money.Amount.t)];
  print_s
    [%sexp
      (Insights.months_with_data ~account ~currency:Money.Currency.eur items
       : Calendar_month.t list)];
  print_s
    [%sexp
      (Insights.items
         ~category:(cat "groceries")
         ctx
         ~account
         ~currency:Money.Currency.eur
         ~month:(month "2026-10")
         items
       |> List.map ~f:(fun ((i : Item.t), _) -> i.id)
       : Item_id.t list)];
  [%expect
    {|
    (((bills "900.00 EUR") (eating_out "11.00 EUR") (groceries "40.00 EUR"))
     "951.00 EUR")
    (2026-09 2026-10 2026-11)
    (b5 b1)
    |}]
;;

(* Category totals always add up to the month's spending, and spending is purchases less
   refunds. *)
let%test_unit "category totals add up" =
  let open Quickcheck.Generator.Let_syntax in
  let gen_item i =
    let%bind cents = Int.gen_incl (-50_000) 50_000 in
    let%bind day = Int.gen_incl 1 28 in
    let%bind merchant =
      Quickcheck.Generator.of_list [ "Cafe"; "Rent Co"; "Shop"; "Hotel" ]
    in
    let%map source =
      Quickcheck.Generator.of_list [ card merchant; payment merchant; Internal; Other ]
    in
    item
      ~id:(sprintf "i%d" i)
      ~at:(time (sprintf "2026-10-%02d 12:00:00Z" day))
      ~amount:
        (Money.Amount.to_decimal_string
           (Money.Amount.of_minor_units_int
              Money.Currency.eur
              (if cents = 0 then 1 else cents)))
      source
  in
  let gen =
    let%bind n = Int.gen_incl 0 30 in
    List.init n ~f:gen_item |> Quickcheck.Generator.all
  in
  Quickcheck.test gen ~f:(fun items ->
    let s =
      Insights.summarise
        ctx
        ~account
        ~currency:Money.Currency.eur
        ~month:(month "2026-10")
        items
    in
    let sum l = Money.Amount.sum Money.Currency.eur l |> Or_error.ok_exn in
    [%test_result: Money.Amount.t]
      (sum (List.map s.categories ~f:(fun c -> c.total)))
      ~expect:s.spending;
    [%test_result: Money.Amount.t]
      (sum
         (List.filter_map items ~f:(fun i ->
            match Item.flow i with
            | Spending | Refund -> Some (Money.Amount.neg i.amount)
            | Income | Internal -> None)))
      ~expect:s.spending)
;;
