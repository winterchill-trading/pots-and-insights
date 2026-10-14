(** Scheduled top-ups: a fixed amount moved from the parent account into a pot on every
    date of a schedule (see {!Pot_job}). With [stop_at_goal], a top-up moves at most what
    is still missing to the goal and nothing once it is reached. *)

open! Core

type t = private
  { pot : Pot_id.t
  ; amount : Money.Amount.t (** positive *)
  ; stop_at_goal : bool
  }
[@@deriving sexp, compare, equal]

(** Fails unless [amount] is positive. *)
val create : pot:Pot_id.t -> amount:Money.Amount.t -> stop_at_goal:bool -> t Or_error.t

(** What a top-up does on one date. *)
module Decision : sig
  type t =
    | Deposit of Money.Amount.t
    | Skip of string (** [pot_closed], [goal_reached] or [currency_mismatch] *)
  [@@deriving sexp, compare, equal]
end

(** What to move today, given the pot and its balance. *)
val decide : t -> Pot.t -> balance:Money.Amount.t -> Decision.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
