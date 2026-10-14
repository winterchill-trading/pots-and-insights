(** Ledger entries that move money between a pot and its parent account.

    Pure: each function takes the current [Ledger.Balances.t] and returns an entry
    already checked against it, so the caller appends it to its journal (or drops it).
    Both legs are in the pot's currency and the entry has code [Transfer_intraledger]:

    - deposit: debit the parent, credit the pot (tag [pot_deposit]);
    - withdrawal: debit the pot, credit the parent (tag [pot_withdrawal]);
    - close: the whole balance back to the parent in one entry (tag [pot_close], key
      {!close_key}), or no entry when the pot is empty, then the pot's ledger account is
      closed.

    Every movement carries an idempotency key. Calling again with a key that is already
    booked for the same movement (same accounts, amount and kind, at any time) returns the
    booked entry (a retried request), before any balance check, so a retry after the money
    moved still succeeds; the same key for a different movement is refused. *)

open! Core

(** [pot:<pot id>:<request>], for callers that derive the ledger key from a request key.
    Fails when the result is not a valid ledger id (too long, other characters). *)
val key : Pot_id.t -> request:string -> Ledger.Idempotency_key.t Or_error.t

(** [pot:<pot id>:close]. *)
val close_key : Pot_id.t -> Ledger.Idempotency_key.t

(** The record that opens the pot's ledger account. *)
val open_account : Pot.t -> Ledger.Record.Event.t

(** Moves [amount] from the parent account into the pot. Refused when the pot is closed,
    the amount is not positive or in another currency, or the parent's available balance
    is below it. *)
val deposit
  :  Ledger.Balances.t
  -> Pot.t
  -> amount:Money.Amount.t
  -> idempotency_key:Ledger.Idempotency_key.t
  -> at:Time_ns.t
  -> (Ledger.Entry.t, Pot.Refusal.t) Result.t

(** Moves [amount] from the pot back to the parent account. Refused as {!deposit}, or when
    the pot's balance is below [amount]. *)
val withdraw
  :  Ledger.Balances.t
  -> Pot.t
  -> amount:Money.Amount.t
  -> idempotency_key:Ledger.Idempotency_key.t
  -> at:Time_ns.t
  -> (Ledger.Entry.t, Pot.Refusal.t) Result.t

(** What closing a pot books. *)
module Closing : sig
  type t =
    { entry : Ledger.Entry.t option (** [None] for an empty pot *)
    ; returned : Money.Amount.t (** the balance moved back, zero for an empty pot *)
    ; account_closed : Ledger.Record.Event.t
    (** the status change closing the pot's ledger account, to append after [entry] *)
    ; pot : Pot.t (** the pot, closed *)
    }
  [@@deriving sexp_of]
end

(** Closes an active pot, returning its whole balance to the parent. Refused with
    [Already_closed] for a closed pot. Funds held on the pot (none in normal use) make the
    ledger refuse the account closure, reported as [Ledger_refused]. *)
val close
  :  Ledger.Balances.t
  -> Pot.t
  -> at:Time_ns.t
  -> (Closing.t, Pot.Refusal.t) Result.t

(** The pot's balance in its currency. *)
val balance : Ledger.Balances.t -> Pot.t -> Money.Amount.t

(** One money movement as the pot's owner sees it. *)
module Movement : sig
  (** Which operation made the movement. *)
  module Kind : sig
    type t =
      | Deposit
      | Withdrawal
      | Close
    [@@deriving sexp, compare, equal]
  end

  type t =
    { idempotency_key : Ledger.Idempotency_key.t
    ; kind : Kind.t
    ; amount : Money.Amount.t (** signed from the pot's side: deposits positive *)
    ; at : Time_ns.Alternate_sexp.t (** the entry's effective time *)
    }
  [@@deriving sexp, compare, equal]

  (** The movement an entry made on this pot, if it is one of this module's entries. *)
  val of_entry : Pot.t -> Ledger.Entry.t -> t option
end
