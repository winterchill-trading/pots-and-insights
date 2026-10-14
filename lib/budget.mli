(** A monthly budget on one currency account: for one spending category or for all
    spending ([Overall]).

    A budget's amount applies from a month onwards: changing it in October leaves
    September's figures as they were. Removing a budget ends it from a month, so past
    months keep their budget. At most one budget per account and target is in force at a
    time.

    Progress compares what was spent in a month (see {!Insights.spent}) with the amount:
    - [Under] below the near threshold (80 % by default);
    - [Near] from the threshold up to the amount itself;
    - [Over] above the amount.
    For the month in progress, the pace is the even share of the month elapsed:
    [expected = amount * day / days] rounded down, where [day] is today's day of the month
    in UTC; spending above it is [Ahead] of pace, otherwise [On_track]. *)

open! Core

module Target : sig
  type t =
    | Overall
    | Category of Category.t
  [@@deriving sexp, compare, equal]

  (** ["overall"] or the category code. *)
  val to_string : t -> string
end

module Limits : sig
  type t =
    { max_amount : Z.t (** minor units; default 10^12 *)
    ; near_percent : int (** default 80 *)
    }
  [@@deriving sexp_of]

  val default : t
end

module Refusal : sig
  type t =
    | Unknown_category (** not a spending category of the catalogue *)
    | Amount_not_positive
    | Amount_too_large
    | Currency_mismatch of { expected : Money.Currency.t }
    | Budget_exists (** another budget for this account and target is in force *)
    | Removed (** the budget no longer applies from that month *)
  [@@deriving sexp, compare, equal]

  (** [unknown_category], [amount_not_positive], [amount_too_large],
      [currency_mismatch], [budget_exists], [budget_removed]. *)
  val code : t -> string
end

type t = private
  { id : Budget_id.t
  ; owner : Owner_id.t
  ; account : Ledger.Account_id.t
  ; currency : Money.Currency.t
  ; target : Target.t
  ; amounts : (Calendar_month.t * Money.Amount.t) list
  (** each amount applies from its month until the next; oldest first *)
  ; removed_from : Calendar_month.t option
  }
[@@deriving sexp, compare, equal]

(** A budget in force from [from], in the account's [currency]. [existing] are the owner's other budgets; one for the
    same account and target that is in force in [from] or later refuses the new one. *)
val create
  :  ?limits:Limits.t
  -> Catalogue.t
  -> id:Budget_id.t
  -> owner:Owner_id.t
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> target:Target.t
  -> amount:Money.Amount.t
  -> from:Calendar_month.t
  -> existing:t list
  -> (t, Refusal.t) Result.t

(** A new amount from [from] onwards; later amounts set before are dropped. *)
val set_amount
  :  ?limits:Limits.t
  -> t
  -> amount:Money.Amount.t
  -> from:Calendar_month.t
  -> (t, Refusal.t) Result.t

(** Ends the budget: no amount from [from] onwards. *)
val remove : t -> from:Calendar_month.t -> (t, Refusal.t) Result.t

(** The amount in force in a month, if any. *)
val amount_for : t -> Calendar_month.t -> Money.Amount.t option

(** Whether the budget has an amount in a month or any later one. *)
val in_force_from : t -> Calendar_month.t -> bool

module Status : sig
  type t =
    | Under
    | Near
    | Over
  [@@deriving sexp, compare, equal, enumerate]

  (** [under], [near], [over]. *)
  val name : t -> string
end

module Pace : sig
  module Status : sig
    type t =
      | On_track
      | Ahead
    [@@deriving sexp, compare, equal]
  end

  type t =
    { day : int (** today's day of the month, UTC, from 1 *)
    ; days : int
    ; expected : Money.Amount.t
    ; status : Status.t
    }
  [@@deriving sexp, compare, equal]
end

(** [status ~amount ~spent] with the threshold in percent (default 80). *)
val status : ?near_percent:int -> amount:Money.Amount.t -> spent:Money.Amount.t -> unit -> Status.t

(** The pace of [spent] against [amount] at [now], when [now] falls in [month]. *)
val pace
  :  amount:Money.Amount.t
  -> spent:Money.Amount.t
  -> month:Calendar_month.t
  -> now:Time_ns.t
  -> Pace.t option

module Progress : sig
  type t =
    { budget : Budget_id.t
    ; target : Target.t
    ; month : Calendar_month.t
    ; amount : Money.Amount.t
    ; spent : Money.Amount.t
    ; remaining : Money.Amount.t (** [amount - spent], negative when over *)
    ; percent : Percentage.t (** [spent / amount] *)
    ; status : Status.t
    ; pace : Pace.t option (** for the month that contains [now] only *)
    }
  [@@deriving sexp, compare, equal]
end

(** Progress in [month], or [None] when the budget has no amount then. *)
val progress
  :  ?near_percent:int
  -> t
  -> month:Calendar_month.t
  -> spent:Money.Amount.t
  -> now:Time_ns.t
  -> Progress.t option

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
