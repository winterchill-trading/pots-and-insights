(** Every budget of one currency account in one month, with what was spent. *)

open! Core

type t =
  { account : Ledger.Account_id.t
  ; currency : Money.Currency.t
  ; month : Calendar_month.t
  ; current : bool (** whether [now] falls in [month] *)
  ; overall : Budget.Progress.t option
  ; categories : Budget.Progress.t list (** in catalogue order *)
  ; spending : Money.Amount.t (** all spending in the month, budgeted or not *)
  ; near_percent : int
  }
[@@deriving sexp, compare, equal]

(** The view of [month]. Budgets of other accounts or currencies, and those without an
    amount in [month], are left out. *)
val compute
  :  ?near_percent:int
  -> Insights.Context.t
  -> budgets:Budget.t list
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> month:Calendar_month.t
  -> now:Time_ns.t
  -> Item.t list
  -> t

(** The [months] views ending with [last], oldest first. *)
val history
  :  ?near_percent:int
  -> Insights.Context.t
  -> budgets:Budget.t list
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> last:Calendar_month.t
  -> months:int
  -> now:Time_ns.t
  -> Item.t list
  -> t list
