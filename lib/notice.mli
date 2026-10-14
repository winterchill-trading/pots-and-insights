(** Things worth telling the owner, as values: the caller decides how to render, store
    and deliver them. Each notice has a {!key} so a caller that records the keys it sent
    sends each notice once. *)

open! Core

type t =
  | Budget_near of
      { budget : Budget_id.t
      ; account : Ledger.Account_id.t
      ; target : Budget.Target.t
      ; month : Calendar_month.t
      ; spent : Money.Amount.t
      ; amount : Money.Amount.t
      }
  | Budget_over of
      { budget : Budget_id.t
      ; account : Ledger.Account_id.t
      ; target : Budget.Target.t
      ; month : Calendar_month.t
      ; spent : Money.Amount.t
      ; amount : Money.Amount.t
      }
  | Goal_reached of
      { pot : Pot_id.t
      ; goal : Money.Amount.t
      ; balance : Money.Amount.t
      }
[@@deriving sexp, compare, equal]

(** [budget:<id>:<YYYY-MM>:near], [budget:<id>:<YYYY-MM>:over], [pot:<id>:goal_reached]. *)
val key : t -> string

(** Budgets whose status went up between two views of the same month: [Under] to [Near]
    gives [Budget_near]; anything to [Over] gives [Budget_over]. A budget missing from
    [before] counts as [Under]. Falling back (a refund) gives nothing. *)
val budget_changes : before:Budget_month.t -> after:Budget_month.t -> t list

(** [Goal_reached] when a pot's balance moved from below its goal to the goal or above. *)
val goal_reached
  :  Pot.t
  -> before:Money.Amount.t
  -> after:Money.Amount.t
  -> t option

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
