(** A customer's own category choices: user data, kept per owner by the caller.

    - an override files one item under a category;
    - a merchant rule files every card item from a merchant (compared by {!Text.match_key}
      of the merchant name);
    - a payee rule files every payment to a payee (by saved payee id when the payment has
      one, else by the payee name's match key);
    - a schedule category files every payment a standing order makes.

    Values are immutable; each change returns a new value for the caller to store. *)

open! Core

(** How a payee is recognised. *)
module Payee_key : sig
  type t =
    | Id of string
    | Name of string (** a {!Text.match_key} *)
  [@@deriving sexp, compare, equal]

  include Comparable.S with type t := t

  (** [Id] when the payee is saved, [Name] otherwise. *)
  val of_payee : Item.Payee.t -> t
end

type t [@@deriving sexp, compare, equal]

(** No choices: every item is filed automatically. *)
val empty : t
(** The category the owner chose for this one item. *)
val override : t -> Item_id.t -> Category.t option
(** The category the owner chose for every item from this merchant. *)
val merchant_rule : t -> merchant:string -> Category.t option
(** The category the owner chose for every payment to this payee. *)
val payee_rule : t -> Item.Payee.t -> Category.t option
(** The category the owner chose for a standing order. *)
val schedule_category : t -> schedule:string -> Category.t option

(** Sets or, with [None], removes an override. *)
val set_override : t -> Item_id.t -> Category.t option -> t

(** Sets or, with [None], removes a merchant rule. *)
val set_merchant_rule : t -> merchant:string -> Category.t option -> t
(** Sets or, with [None], removes a payee rule. *)
val set_payee_rule : t -> Payee_key.t -> Category.t option -> t
(** Sets or, with [None], removes a standing order's category. *)
val set_schedule_category : t -> schedule:string -> Category.t option -> t

(** Every entry, for storage or display. *)
val overrides : t -> (Item_id.t * Category.t) list

(** Merchant rules by match key. *)
val merchant_rules : t -> (string * Category.t) list
(** Payee rules. *)
val payee_rules : t -> (Payee_key.t * Category.t) list
(** Standing order categories by schedule id. *)
val schedule_categories : t -> (string * Category.t) list

module Stable : sig
  module V1 : sig
    (** Bin_prot: four sorted association lists. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
