(** Filing statement items under categories, and changing how they are filed.

    A spending item (a purchase or an outgoing payment) takes the first of:
    + the customer's override of this item;
    + the customer's rule for the card merchant;
    + the category of the standing order that made the payment;
    + the customer's rule for the payee;
    + the first {!Keywords} match in the description, merchant name or payee name;
    + the card network's merchant category ([merchant_category]);
    + the catalogue's default.

    A refund follows the purchase it refunds (its own merchant otherwise), income goes to
    the catalogue's [income] category and internal movements to [internal]. A stored
    choice whose category is no longer a spending category of the catalogue is skipped,
    so retiring a category never breaks old preferences. *)

open! Core

module Source : sig
  type t =
    | Override
    | Merchant_rule
    | Schedule
    | Payee_rule
    | Keyword of string (** the keyword that matched *)
    | Merchant (** the card network's merchant category *)
    | Default
    | Purchase (** a refund, filed with its purchase *)
    | Income
    | Internal
  [@@deriving sexp, compare, equal]

  (** [override], [merchant_rule], [schedule], [payee_rule], [keyword], [merchant],
      [default], [purchase], [income], [internal]. *)
  val name : t -> string

  (** Whether the source is the customer's own choice (the first four). *)
  val is_user : t -> bool
end

module Assignment : sig
  type t =
    { category : Category.t
    ; source : Source.t
    ; automatic : Category.t (** what the item would get without any user choice *)
    ; automatic_source : Source.t
    ; recategorisable : bool (** spending items only; not refunds *)
    }
  [@@deriving sexp, compare, equal]
end

(** The category of one item. Pass the refunded purchase as [original] for a refund. *)
val assign
  :  Catalogue.t
  -> Keywords.t
  -> Preferences.t
  -> ?original:Item.t
  -> Item.t
  -> Assignment.t

(** [assign] over a list, finding each refund's purchase in the same list. *)
val assign_all
  :  Catalogue.t
  -> Keywords.t
  -> Preferences.t
  -> Item.t list
  -> (Item.t * Assignment.t) list

(** Why a change was refused. *)
module Refusal : sig
  type t =
    | Unknown_category (** not a spending category of the catalogue *)
    | Spending_only (** income and internal items keep their category *)
    | Refund_follows_purchase
    | Nothing_to_match
    (** "all from this merchant" on an item without a merchant, or "all to this payee"
        on one without a payee *)
  [@@deriving sexp, compare, equal]

  (** [unknown_category], [spending_only], [refund_follows_purchase],
      [nothing_to_match]. *)
  val code : t -> string
end

module Scope : sig
  type t =
    | One (** this item only *)
    | All_from_merchant (** every card item from this item's merchant *)
    | All_from_payee (** every payment to this item's payee *)
  [@@deriving sexp, compare, equal, enumerate]
end

(** Files an item (and, for the wider scopes, the others like it) under [category], or
    back to automatic with [None]. A wider scope also drops this item's override, so the
    new rule shows on it at once. *)
val recategorise
  :  Catalogue.t
  -> Preferences.t
  -> Item.t
  -> Scope.t
  -> Category.t option
  -> (Preferences.t, Refusal.t) Result.t

(** Sets or clears the category of a standing order. *)
val set_schedule_category
  :  Catalogue.t
  -> Preferences.t
  -> schedule:string
  -> Category.t option
  -> (Preferences.t, Refusal.t) Result.t

(** Sets or clears the category of a payee. *)
val set_payee_category
  :  Catalogue.t
  -> Preferences.t
  -> Preferences.Payee_key.t
  -> Category.t option
  -> (Preferences.t, Refusal.t) Result.t
