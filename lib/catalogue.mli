(** The categories a bank offers and how each one counts.

    A [Spending] category is one a customer can file a purchase or an outgoing payment
    under and set a budget on. [income] is where money coming in from outside goes, and
    [internal] is where movements between the customer's own accounts go (pot moves,
    exchanges); neither counts as spending and neither can be chosen by the customer.
    [default] is the spending category of an item nothing else classifies. *)

open! Core

module Group : sig
  type t =
    | Spending
    | Income
    | Neutral
  [@@deriving sexp, compare, equal, enumerate]
end

type t [@@deriving sexp_of]

(** Fails on a duplicate code, when [default] is not a spending category, when [income] is
    not an [Income] one or [internal] not a [Neutral] one. [categories] is in picker
    order. *)
val create
  :  categories:(Category.t * Group.t) list
  -> default:Category.t
  -> income:Category.t
  -> internal:Category.t
  -> t Or_error.t

(** A general-purpose set: [groceries], [eating_out], [transport], [travel], [shopping],
    [entertainment], [bills], [health], [personal_care], [education], [gifts], [cash],
    [fees] and [general] (the default) for spending, [income], and [transfers] for
    internal movements. *)
val default : t

(** In picker order. *)
val categories : t -> (Category.t * Group.t) list

val group : t -> Category.t -> Group.t option
val is_spending : t -> Category.t -> bool
val spending : t -> Category.t list
val default_category : t -> Category.t
val income : t -> Category.t
val internal : t -> Category.t
