open! Core
module Amount = Money.Amount
module Refusal = Pot.Refusal

let key pot ~request =
  Ledger.Idempotency_key.of_string_or_error
    (sprintf "pot:%s:%s" (Pot_id.to_string pot) request)
;;

let close_key pot =
  (* Pot ids are at most 100 ledger-id characters, so the key is always valid. *)
  Ledger.Idempotency_key.of_string (sprintf "pot:%s:close" (Pot_id.to_string pot))
;;

let open_account pot = Ledger.Record.Event.Account_opened (Pot.to_ledger_account pot)

let balance balances (pot : Pot.t) =
  Ledger.Balances.balance balances pot.ledger_account pot.currency
;;

let tag_deposit = "pot_deposit"
let tag_withdrawal = "pot_withdrawal"
let tag_close = "pot_close"

let apply balances event =
  Ledger.Balances.apply balances { seq = Ledger.Balances.next_seq balances; event }
;;

let entry (pot : Pot.t) ~tag ~from ~to_ ~amount ~idempotency_key ~at =
  Ledger.Entry.create
    ~idempotency_key
    ~kind:(Transfer tag)
    ~code:Transfer_intraledger
    ~reference:(Pot_id.to_string pot.id)
    ~effective_at:at
    ~recorded_at:at
    [ Ledger.Posting.debit from amount; Ledger.Posting.credit to_ amount ]
  |> Result.map_error ~f:(fun e -> Refusal.Ledger_refused e)
;;

(* A key already booked: the same movement replays, another one is refused. The times are
   left out of the comparison because a retry happens later than the first call. *)
let same_movement (a : Ledger.Entry.t) (b : Ledger.Entry.t) =
  Ledger.Entry.Kind.equal a.kind b.kind
  && Ledger.Entry.Code.equal a.code b.code
  && String.equal a.reference b.reference
  && List.equal Ledger.Posting.equal a.postings b.postings
;;

let replay balances ~idempotency_key fresh =
  match Ledger.Balances.find_entry balances idempotency_key with
  | None -> None
  | Some (_, booked) ->
    if same_movement booked fresh
    then Some (Ok booked)
    else
      Some
        (Error
           (Refusal.Ledger_refused
              (Error.create_s
                 [%message
                   "idempotency key already used for another entry"
                     (idempotency_key : Ledger.Idempotency_key.t)])))
;;

let move balances (pot : Pot.t) ~tag ~from ~to_ ~insufficient ~amount ~idempotency_key ~at
  =
  let open Result.Let_syntax in
  let%bind () = if Pot.is_active pot then Ok () else Error Refusal.Pot_closed in
  let%bind () =
    if not (Money.Currency.equal (Amount.currency amount) pot.currency)
    then Error (Refusal.Amount_currency_mismatch { expected = pot.currency })
    else if not (Amount.is_positive amount)
    then Error Refusal.Amount_not_positive
    else Ok ()
  in
  let%bind fresh = entry pot ~tag ~from ~to_ ~amount ~idempotency_key ~at in
  match replay balances ~idempotency_key fresh with
  | Some result -> result
  | None ->
    let%bind () =
      if Amount.( < ) (Ledger.Balances.available balances from pot.currency) amount
      then Error insufficient
      else Ok ()
    in
    let%map (_ : Ledger.Balances.t) =
      apply balances (Posted fresh)
      |> Result.map_error ~f:(fun e -> Refusal.Ledger_refused e)
    in
    fresh
;;

let deposit balances (pot : Pot.t) ~amount ~idempotency_key ~at =
  move
    balances
    pot
    ~tag:tag_deposit
    ~from:pot.account
    ~to_:pot.ledger_account
    ~insufficient:Refusal.Insufficient_in_account
    ~amount
    ~idempotency_key
    ~at
;;

let withdraw balances (pot : Pot.t) ~amount ~idempotency_key ~at =
  move
    balances
    pot
    ~tag:tag_withdrawal
    ~from:pot.ledger_account
    ~to_:pot.account
    ~insufficient:Refusal.Insufficient_in_pot
    ~amount
    ~idempotency_key
    ~at
;;

module Closing = struct
  type t =
    { entry : Ledger.Entry.t option
    ; returned : Amount.t
    ; account_closed : Ledger.Record.Event.t
    ; pot : Pot.t
    }
  [@@deriving sexp_of]
end

let close balances (pot : Pot.t) ~at =
  let open Result.Let_syntax in
  let%bind closed = Pot.close pot ~at in
  let returned = balance balances pot in
  let%bind entry =
    if Amount.is_zero returned
    then Ok None
    else
      entry
        pot
        ~tag:tag_close
        ~from:pot.ledger_account
        ~to_:pot.account
        ~amount:returned
        ~idempotency_key:(close_key pot.id)
        ~at
      |> Result.map ~f:Option.some
  in
  let account_closed =
    Ledger.Record.Event.Account_status_changed
      { account = pot.ledger_account; status = Closed; recorded_at = at }
  in
  let%map (_ : Ledger.Balances.t) =
    (let open Or_error.Let_syntax in
     let%bind b =
       match entry with
       | None -> Ok balances
       | Some e -> apply balances (Posted e)
     in
     apply b account_closed)
    |> Result.map_error ~f:(fun e -> Refusal.Ledger_refused e)
  in
  { Closing.entry; returned; account_closed; pot = closed }
;;

module Movement = struct
  module Kind = struct
    type t =
      | Deposit
      | Withdrawal
      | Close
    [@@deriving sexp, compare, equal]
  end

  type t =
    { idempotency_key : Ledger.Idempotency_key.t
    ; kind : Kind.t
    ; amount : Amount.t
    ; at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]

  let of_entry (pot : Pot.t) (e : Ledger.Entry.t) =
    let kind =
      match e.kind with
      | Transfer tag when String.equal tag tag_deposit -> Some Kind.Deposit
      | Transfer tag when String.equal tag tag_withdrawal -> Some Withdrawal
      | Transfer tag when String.equal tag tag_close -> Some Close
      | _ -> None
    in
    Option.bind kind ~f:(fun kind ->
      List.find_map e.postings ~f:(fun (p : Ledger.Posting.t) ->
        if Ledger.Account_id.equal p.account pot.ledger_account
        then (
          (* The pot is credit-normal: a credit adds to it. *)
          let amount =
            match p.side with
            | Credit -> p.amount
            | Debit -> Amount.neg p.amount
          in
          Some { idempotency_key = e.idempotency_key; kind; amount; at = e.effective_at })
        else None))
  ;;
end
