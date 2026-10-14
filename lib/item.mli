(** A statement item: one transaction on a currency account as the customer sees it.

    Insights read items, not ledger entries: a card authorisation, its settlement or
    release are one item, booked when it finishes, and only [Completed] items count. The
    caller builds items from its statement or its own store. *)

open! Core

(** Whether the item is final. *)
module Status : sig
  type t =
    | Pending (** still on hold; insights skip it *)
    | Completed
  [@@deriving sexp, compare, equal]
end

(** Who is paid by an outgoing payment. *)
module Payee : sig
  type t =
    { id : string option (** a saved payee's id, when there is one *)
    ; name : string
    }
  [@@deriving sexp, compare, equal]
end

(** Where the item comes from. *)
module Source : sig
  type t =
    | Card of
        { merchant : string
        ; merchant_category : Category.t option
        (** the category the card network's merchant code maps to, if the caller has one *)
        }
    | Payment of
        { payee : Payee.t option
        ; schedule : string option
        (** the standing order or schedule that made the payment *)
        }
    | Incoming of { payer : string option }
    | Internal (** between the owner's own accounts: pots, exchanges *)
    | Other
  [@@deriving sexp, compare, equal]
end

type t =
  { id : Item_id.t
  ; account : Ledger.Account_id.t
  ; amount : Money.Amount.t (** signed: negative when money left the account *)
  ; at : Time_ns.Alternate_sexp.t
  ; description : string (** the statement text, e.g. a payment reference *)
  ; source : Source.t
  ; refund_of : Item_id.t option (** the purchase a refund gives money back for *)
  ; status : Status.t
  }
[@@deriving sexp, compare, equal]

(** How an item counts in insights. *)
module Flow : sig
  type t =
    | Spending (** money out to a merchant or payee *)
    | Refund (** money back from a merchant: reduces spending in its category *)
    | Income (** money in from outside *)
    | Internal (** neither spending nor income *)
  [@@deriving sexp, compare, equal]
end

(** [Internal] for internal items; for the others, [Spending] when money left, and when
    money came in [Refund] if [refund_of] is set or it is a card item, [Income] otherwise. *)
val flow : t -> Flow.t

(** The merchant of a card item. *)
val merchant : t -> string option

(** The payee of a payment. *)
val payee : t -> Payee.t option

(** The schedule that made a payment. *)
val schedule : t -> string option

(** [Completed]. *)
val counts : t -> bool

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
