open! Core
open Pots_and_insights
module Amount = Money.Amount

let eur s = Amount.of_string (s ^ " EUR")
let date = Date.of_string
let time s = Time_ns.of_string_with_utc_offset s
let today = date "2026-10-14"
let t0 = time "2026-10-14 09:00:00Z"
let owner = Owner_id.of_string "customer-1"
let account = Ledger.Account_id.of_string "customer:1/eur"
let bank = Ledger.Account_id.of_string "bank:central/eur"
let pot_id = Pot_id.of_string "pot-1"

let details ?goal ?target_date ?(cosmetics = [ "colour", "teal" ]) name : Pot.Details.t =
  { name; goal; target_date; cosmetics }
;;

let pot ?goal ?(id = pot_id) () =
  Pot.create
    ~id
    ~owner
    ~account
    ~currency:Money.Currency.eur
    ~open_pots:0
    ~today
    ~at:t0
    (details ?goal "Holiday")
  |> Result.map_error ~f:(fun r -> Error.create_s (Pot.Refusal.sexp_of_t r))
  |> Or_error.ok_exn
;;

let apply b event =
  Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event } |> Or_error.ok_exn
;;

let post b entry = apply b (Posted entry)

(** Balances with the customer's account, a bank account, [pots] opened and [deposit]
    paid into the customer's account. *)
let ledger ?(deposit = eur "1000.00") ~pots () =
  let b =
    List.fold
      (Ledger.Account.create ~purpose:Customer_funds account Liability
       :: Ledger.Account.create ~allow_negative:true bank Asset
       :: List.map pots ~f:Pot.to_ledger_account)
      ~init:Ledger.Balances.empty
      ~f:(fun b a -> apply b (Account_opened a))
  in
  post
    b
    (Ledger.Entry.create
       ~idempotency_key:(Ledger.Idempotency_key.of_string "deposit-1")
       ~kind:(Transfer "deposit")
       ~code:Deposit
       ~effective_at:t0
       ~recorded_at:t0
       [ Ledger.Posting.debit bank deposit; Ledger.Posting.credit account deposit ]
     |> Or_error.ok_exn)
;;

let key s = Ledger.Idempotency_key.of_string s

let available b =
  Ledger.Balances.available b account Money.Currency.eur |> Amount.to_string
;;

let refusal r = Pot.Refusal.sexp_of_t r
