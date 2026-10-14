open! Core
open Pots_and_insights
open Helpers

let show_entry r =
  print_s
    (match r with
     | Ok (e : Ledger.Entry.t) ->
       [%sexp
         Ok
           { key = (e.idempotency_key : Ledger.Idempotency_key.t)
           ; kind = (e.kind : Ledger.Entry.Kind.t)
           ; postings = (e.postings : Ledger.Posting.t list)
           }]
     | Error e -> [%sexp Error (e : Pot.Refusal.t)])
;;

let%expect_test "deposit, withdraw and their refusals" =
  let p = pot () in
  let b = ledger ~deposit:(eur "100.00") ~pots:[ p ] () in
  let d =
    Pot_booking.deposit b p ~amount:(eur "60.00") ~idempotency_key:(key "r1") ~at:t0
  in
  show_entry d;
  let b = post b (Result.ok d |> Option.value_exn) in
  print_s [%sexp (available b : string), (Pot_booking.balance b p : Money.Amount.t)];
  [%expect
    {|
    (Ok
     ((key r1) (kind (Transfer pot_deposit))
      (postings
       (((account customer:1/eur) (side Debit) (amount "60.00 EUR"))
        ((account pot:pot-1) (side Credit) (amount "60.00 EUR"))))))
    ("40.00 EUR" "60.00 EUR")
    |}];
  let show r = print_s [%sexp (Result.error r : Pot.Refusal.t option)] in
  show (Pot_booking.deposit b p ~amount:(eur "40.01") ~idempotency_key:(key "r2") ~at:t0);
  show (Pot_booking.withdraw b p ~amount:(eur "60.01") ~idempotency_key:(key "r3") ~at:t0);
  show (Pot_booking.deposit b p ~amount:(eur "0.00") ~idempotency_key:(key "r4") ~at:t0);
  show
    (Pot_booking.deposit
       b
       p
       ~amount:(Money.Amount.of_string "1.00 USD")
       ~idempotency_key:(key "r5")
       ~at:t0);
  [%expect
    {|
    (Insufficient_in_account)
    (Insufficient_in_pot)
    (Amount_not_positive)
    ((Amount_currency_mismatch (expected EUR)))
    |}];
  show_entry
    (Pot_booking.withdraw b p ~amount:(eur "60.00") ~idempotency_key:(key "r6") ~at:t0);
  [%expect
    {|
    (Ok
     ((key r6) (kind (Transfer pot_withdrawal))
      (postings
       (((account pot:pot-1) (side Debit) (amount "60.00 EUR"))
        ((account customer:1/eur) (side Credit) (amount "60.00 EUR"))))))
    |}]
;;

let%expect_test "a retried deposit replays, even after the money moved" =
  let p = pot () in
  let b = ledger ~deposit:(eur "100.00") ~pots:[ p ] () in
  let first =
    Pot_booking.deposit b p ~amount:(eur "100.00") ~idempotency_key:(key "r1") ~at:t0
    |> Result.ok
    |> Option.value_exn
  in
  let b = post b first in
  let later = Time_ns.add t0 (Time_ns.Span.of_min 5.) in
  let retry =
    Pot_booking.deposit b p ~amount:(eur "100.00") ~idempotency_key:(key "r1") ~at:later
  in
  print_s
    [%sexp
      (Result.map retry ~f:(Ledger.Entry.equal first) : (bool, Pot.Refusal.t) Result.t)];
  let other =
    Pot_booking.deposit b p ~amount:(eur "1.00") ~idempotency_key:(key "r1") ~at:later
  in
  print_s [%sexp (Result.error other : Pot.Refusal.t option)];
  [%expect
    {|
    (Ok true)
    ((Ledger_refused
      ("idempotency key already used for another entry" (idempotency_key r1))))
    |}]
;;

let%expect_test "closing returns the balance in one entry and closes the account" =
  let p = pot () in
  let b = ledger ~deposit:(eur "100.00") ~pots:[ p ] () in
  let b =
    post
      b
      (Pot_booking.deposit b p ~amount:(eur "25.50") ~idempotency_key:(key "r1") ~at:t0
       |> Result.ok
       |> Option.value_exn)
  in
  let closing = Pot_booking.close b p ~at:t0 |> Result.ok |> Option.value_exn in
  print_s
    [%sexp
      { entry =
          (Option.map closing.entry ~f:(fun e -> e.idempotency_key, e.postings)
           : (Ledger.Idempotency_key.t * Ledger.Posting.t list) option)
      ; returned = (closing.returned : Money.Amount.t)
      ; status = (closing.pot.status : Pot.Status.t)
      }];
  let b = post b (Option.value_exn closing.entry) in
  let b = apply b closing.account_closed in
  print_s
    [%sexp
      (available b : string)
      , (Ledger.Balances.status b p.ledger_account : Ledger.Account_status.t)];
  print_s
    [%sexp
      (Pot_booking.close b closing.pot ~at:t0 |> Result.error : Pot.Refusal.t option)];
  print_s
    [%sexp
      (Pot_booking.deposit
         b
         closing.pot
         ~amount:(eur "1.00")
         ~idempotency_key:(key "r9")
         ~at:t0
       |> Result.error
       : Pot.Refusal.t option)];
  [%expect
    {|
    ((entry
      ((pot:pot-1:close
        (((account pot:pot-1) (side Debit) (amount "25.50 EUR"))
         ((account customer:1/eur) (side Credit) (amount "25.50 EUR"))))))
     (returned "25.50 EUR") (status (Closed (at "2026-10-14 09:00:00Z"))))
    ("100.00 EUR" Closed)
    (Already_closed)
    (Pot_closed)
    |}]
;;

let%expect_test "closing an empty pot books nothing" =
  let p = pot () in
  let b = ledger ~pots:[ p ] () in
  let closing = Pot_booking.close b p ~at:t0 |> Result.ok |> Option.value_exn in
  print_s
    [%sexp (Option.is_none closing.entry : bool), (closing.returned : Money.Amount.t)];
  [%expect {| (true "0.00 EUR") |}]
;;

(* Random deposits and withdrawals, some of them retried: money is never created, the pot
   never goes below zero and its movements add up to its balance. *)
let%test_unit "pot movements conserve money" =
  let open Quickcheck.Generator.Let_syntax in
  let op =
    let%bind deposit = Bool.quickcheck_generator in
    let%bind cents = Int.gen_incl 1 50_000 in
    let%map retry = Int.gen_incl 0 4 in
    deposit, cents, retry
  in
  Quickcheck.test (List.gen_with_length 30 op) ~trials:200 ~f:(fun ops ->
    let p = pot () in
    let start = eur "1000.00" in
    let b = ledger ~deposit:start ~pots:[ p ] () in
    let b, entries, _ =
      List.foldi
        ops
        ~init:(b, [], [])
        ~f:(fun i (b, entries, keys) (deposit, cents, retry) ->
          (* [retry = 0] reuses an earlier key with this request's amount. *)
          let k =
            match keys with
            | k :: _ when retry = 0 -> k
            | _ -> key (sprintf "r%d" i)
          in
          let amount = Money.Amount.of_minor_units_int Money.Currency.eur cents in
          let book = if deposit then Pot_booking.deposit else Pot_booking.withdraw in
          match book b p ~amount ~idempotency_key:k ~at:t0 with
          | Error _ -> b, entries, k :: keys
          | Ok e ->
            (match Ledger.Balances.find_entry b e.idempotency_key with
             | Some _ -> b, entries, k :: keys
             | None -> post b e, e :: entries, k :: keys))
    in
    let pot_balance = Pot_booking.balance b p in
    assert (not (Money.Amount.is_negative pot_balance));
    [%test_result: Money.Amount.t]
      (Money.Amount.add_exn
         pot_balance
         (Ledger.Balances.available b account Money.Currency.eur))
      ~expect:start;
    [%test_result: Money.Amount.t]
      (List.filter_map entries ~f:(Pot_booking.Movement.of_entry p)
       |> List.map ~f:(fun (m : Pot_booking.Movement.t) -> m.amount)
       |> Money.Amount.sum Money.Currency.eur
       |> Or_error.ok_exn)
      ~expect:pot_balance)
;;
