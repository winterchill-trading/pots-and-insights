(** Round-ups: the change from rounding each card purchase up to a whole unit, saved
    into a pot.

    A purchase of 3.40 with a unit of 1.00 rounds up by 0.60; a purchase of exactly 4.00
    by nothing. A multiplier saves that change several times over (2x saves 1.20). Only
    completed card purchases count; refunds, payments and internal moves do not.

    Round-ups can be moved one purchase at a time (key {!item_key}) or swept once a day
    for the previous UTC day by a scheduled job ({!Pot_job}), which keeps the number of
    ledger entries small. *)

open! Core

type t = private
  { pot : Pot_id.t
  ; unit : Money.Amount.t (** positive; also fixes the currency *)
  ; multiplier : int (** 1 to 10 *)
  }
[@@deriving sexp, compare, equal]

val create : pot:Pot_id.t -> unit:Money.Amount.t -> ?multiplier:int -> unit -> t Or_error.t

(** The round-up of a purchase of [spend] (a positive amount). Fails on a currency other
    than the unit's. *)
val of_spend : t -> spend:Money.Amount.t -> Money.Amount.t Or_error.t

(** The round-up of an item: [Some] for a completed card purchase in the unit's
    currency, even when it rounds up by zero. *)
val of_item : t -> Item.t -> Money.Amount.t option

(** The round-ups of the account's items in [[from, until)], summed. *)
val total
  :  t
  -> account:Ledger.Account_id.t
  -> from:Time_ns.t
  -> until:Time_ns.t
  -> Item.t list
  -> Money.Amount.t

(** [roundup:<item id>], for moving one purchase's round-up on its own. *)
val item_key : Item_id.t -> Ledger.Idempotency_key.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
