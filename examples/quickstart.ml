(* The README's quick start: a pot with a goal, a deposit booked in the ledger, a month of
   categorised spending and a budget that turns "near". *)

open! Core
open Pots_and_insights
module Amount = Money.Amount

let eur s = Amount.of_string (s ^ " EUR")
let at s = Time_ns.of_string_with_utc_offset s
let now = at "2026-10-14 09:00:00Z"
let account = Ledger.Account_id.of_string "customer:1/eur"
let bank = Ledger.Account_id.of_string "bank:central/eur"
let owner = Owner_id.of_string "customer-1"

let book balances event =
  Ledger.Balances.apply balances { seq = Ledger.Balances.next_seq balances; event }
  |> Or_error.ok_exn
;;

let () =
  (* 1. A pot with a goal, and its own ledger account. *)
  let pot =
    Pot.create
      ~id:(Pot_id.of_string "holiday")
      ~owner
      ~account
      ~currency:Money.Currency.eur
      ~open_pots:0
      ~today:(Date.of_string "2026-10-14")
      ~at:now
      { name = "Holiday"
      ; goal = Some (eur "600.00")
      ; target_date = Some (Date.of_string "2027-06-01")
      ; cosmetics = [ "colour", "teal" ]
      }
    |> Result.map_error ~f:Pot.Refusal.code
    |> Result.ok_or_failwith
  in
  let balances =
    List.fold
      [ Ledger.Record.Event.Account_opened
          (Ledger.Account.create ~purpose:Customer_funds account Liability)
      ; Account_opened (Ledger.Account.create ~allow_negative:true bank Asset)
      ; Pot_booking.open_account pot
      ; Posted
          (Ledger.Entry.create
             ~idempotency_key:(Ledger.Idempotency_key.of_string "salary-1")
             ~kind:(Transfer "deposit")
             ~code:Deposit
             ~effective_at:now
             ~recorded_at:now
             [ Ledger.Posting.debit bank (eur "2000.00")
             ; Ledger.Posting.credit account (eur "2000.00")
             ]
           |> Or_error.ok_exn)
      ]
      ~init:Ledger.Balances.empty
      ~f:book
  in
  (* 2. Move money in under an idempotency key. *)
  let entry =
    Pot_booking.deposit
      balances
      pot
      ~amount:(eur "150.00")
      ~idempotency_key:(Ledger.Idempotency_key.of_string "pot:holiday:req-1")
      ~at:now
    |> Result.map_error ~f:Pot.Refusal.code
    |> Result.ok_or_failwith
  in
  let balances = book balances (Posted entry) in
  let balance = Pot_booking.balance balances pot in
  printf
    "pot %s: %s, %d%% of the goal\n"
    pot.details.name
    (Amount.to_string balance)
    (Pot.progress pot ~balance |> Or_error.ok_exn |> Option.value_exn).percent;
  (* 3. A month of statement items, categorised. *)
  let item id ~day ~amount source : Item.t =
    { id = Item_id.of_string id
    ; account
    ; amount = eur amount
    ; at = at (sprintf "2026-10-%02d 12:00:00Z" day)
    ; description = ""
    ; source
    ; refund_of = None
    ; status = Completed
    }
  in
  let card ?category merchant : Item.Source.t =
    Card { merchant; merchant_category = Option.map category ~f:Category.of_string }
  in
  let items =
    [ item "i1" ~day:2 ~amount:"-82.40" (card ~category:"groceries" "Green Grocer")
    ; item "i2" ~day:5 ~amount:"-4.20" (card "Corner Cafe")
    ; item "i3" ~day:9 ~amount:"-97.10" (card ~category:"groceries" "Green Grocer")
    ; item "i4" ~day:10 ~amount:"-150.00" Internal
    ]
  in
  let ctx = Insights.Context.default in
  let month = Calendar_month.of_time now in
  let summary =
    Insights.summarise ctx ~account ~currency:Money.Currency.eur ~month items
  in
  List.iter summary.categories ~f:(fun c ->
    printf
      "%-10s %s (%s%%)\n"
      (Category.to_string c.category)
      (Amount.to_string c.total)
      (Option.value_map c.share ~default:"-" ~f:Percentage.to_string));
  (* 4. A grocery budget, and the notice when it turns near. *)
  let budget =
    Budget.create
      Catalogue.default
      ~id:(Budget_id.of_string "food")
      ~owner
      ~account
      ~currency:Money.Currency.eur
      ~target:(Category (Category.of_string "groceries"))
      ~amount:(eur "220.00")
      ~from:month
      ~existing:[]
    |> Result.map_error ~f:Budget.Refusal.code
    |> Result.ok_or_failwith
  in
  let view items =
    Budget_month.compute
      ctx
      ~budgets:[ budget ]
      ~account
      ~currency:Money.Currency.eur
      ~month
      ~now
      items
  in
  let before = view (List.take items 2) in
  let after = view items in
  List.iter after.categories ~f:(fun p ->
    printf
      "budget %s: %s of %s, %s\n"
      (Budget.Target.to_string p.target)
      (Amount.to_string p.spent)
      (Amount.to_string p.amount)
      (Budget.Status.name p.status));
  List.iter (Notice.budget_changes ~before ~after) ~f:(fun n ->
    print_endline (Notice.key n))
;;
