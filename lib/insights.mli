(** Monthly spending insights for one currency account.

    Only completed items of the account in its currency count (see {!Item.counts}), each
    in the UTC month of its time. Spending is money out to merchants and payees less
    refunds, per category as {!Categorise} files it; a category's total can go below zero
    in a month whose refunds exceed its purchases. Money in and money out leave internal
    movements (pots, exchanges) out. All amounts are exact; shares are {!Percentage}s. *)

open! Core

(** The categorisation inputs, bundled. *)
module Context : sig
  type t =
    { catalogue : Catalogue.t
    ; keywords : Keywords.t
    ; preferences : Preferences.t
    }

  (** {!Catalogue.default}, {!Keywords.default}, no preferences. *)
  val default : t
end

module Category_total : sig
  type t =
    { category : Category.t
    ; total : Money.Amount.t (** spent, net of refunds *)
    ; previous_total : Money.Amount.t (** the month before *)
    ; change : Money.Amount.t (** [total - previous_total] *)
    ; share : Percentage.t option
    (** of the month's spending; [None] when the month's spending is not positive *)
    ; count : int (** spending items, refunds not counted *)
    }
  [@@deriving sexp_of, compare, equal]
end

module Merchant_total : sig
  type t =
    { name : string (** as on the latest item *)
    ; category : Category.t (** of the latest item *)
    ; total : Money.Amount.t
    ; count : int
    }
  [@@deriving sexp_of, compare, equal]
end

module Flow_month : sig
  type t =
    { month : Calendar_month.t
    ; money_in : Money.Amount.t
    ; money_out : Money.Amount.t (** positive *)
    ; net : Money.Amount.t (** [money_in - money_out] *)
    }
  [@@deriving sexp_of, compare, equal]
end

type t =
  { account : Ledger.Account_id.t
  ; currency : Money.Currency.t
  ; month : Calendar_month.t
  ; spending : Money.Amount.t
  ; previous_spending : Money.Amount.t
  ; categories : Category_total.t list
  (** categories with spending this month or the month before, largest total first, ties
      by catalogue order *)
  ; money_in : Money.Amount.t
  ; money_out : Money.Amount.t
  ; flow : Flow_month.t list (** the [flow_months] months ending with [month], oldest first *)
  ; top_merchants : Merchant_total.t list
  (** card merchants by total spent, largest first, at most [top_merchants] *)
  }
[@@deriving sexp_of, compare, equal]

(** The summary of [month]. [items] may hold other accounts, currencies and months; they
    are filtered out. [flow_months] defaults to 6 and [top_merchants] to 5. *)
val summarise
  :  ?flow_months:int
  -> ?top_merchants:int
  -> Context.t
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> month:Calendar_month.t
  -> Item.t list
  -> t

(** Spent per spending category in [month] (net of refunds, never below zero) and the
    month's total: what budgets compare against. *)
val spent
  :  Context.t
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> month:Calendar_month.t
  -> Item.t list
  -> Money.Amount.t Category.Map.t * Money.Amount.t

(** The items of [month] with their categories, newest first, optionally only those in
    [category]. *)
val items
  :  ?category:Category.t
  -> Context.t
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> month:Calendar_month.t
  -> Item.t list
  -> (Item.t * Categorise.Assignment.t) list

(** Months with at least one counting non-internal item, oldest first. *)
val months_with_data
  :  account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> Item.t list
  -> Calendar_month.t list
