(** A savings pot: an owned sub-account of one of the owner's currency accounts.

    A pot has its own ledger account (see {!ledger_account_id}) in the currency of its
    parent account, so pot money is never part of the parent's spendable balance. It may
    carry a goal (a positive amount in that currency) and a target date, and any number of
    cosmetic fields (a colour, an icon) that the library stores as opaque strings and
    never interprets.

    {v
    active --close--> closed   (the balance goes back to the parent in one entry)
    v}

    A closed pot stays readable but refuses edits and money movements. Pots earn no
    interest here; a bank that pays interest books it as an ordinary entry. *)

open! Core

module Limits : sig
  type t =
    { max_open_pots : int (** per owner; default 20 *)
    ; max_name_length : int (** code points after trimming; default 30 *)
    ; max_cosmetic_fields : int (** default 8 *)
    ; max_cosmetic_length : int (** bytes per cosmetic value; default 16 *)
    }
  [@@deriving sexp, compare, equal]

  val default : t
end

(** Why a pot operation was refused, for the caller to map onto its own error codes. *)
module Refusal : sig
  type t =
    | Name_invalid of string
    (** [empty], [not_utf8], [too_long] or [control_character] (see {!Text.clean}) *)
    | Goal_not_positive
    | Goal_currency_mismatch of { expected : Money.Currency.t }
    | Target_date_in_past
    | Cosmetic_invalid of
        { key : string
        ; reason : string
        }
    (** a key that is not a lower-case slug of at most 32 characters, a duplicate key,
        too many fields, or a value that is empty, not UTF-8 or too long *)
    | Too_many_open_pots of { max : int }
    | Pot_closed (** an edit or a movement on a closed pot *)
    | Already_closed
    | Amount_not_positive
    | Amount_currency_mismatch of { expected : Money.Currency.t }
    | Insufficient_in_account (** a deposit above the parent's available balance *)
    | Insufficient_in_pot (** a withdrawal above the pot's balance *)
    | Ledger_refused of Error.t
    (** the ledger refused the entry for another reason (a frozen account, a reused
        idempotency key with another body) *)
  [@@deriving sexp_of]

  (** A short snake_case code: [name_invalid], [pots_limit], [pot_closed], ... *)
  val code : t -> string
end

module Status : sig
  type t =
    | Active
    | Closed of { at : Time_ns.Alternate_sexp.t }
  [@@deriving sexp, compare, equal]

  (** [active] or [closed]. *)
  val name : t -> string
end

(** The fields an owner chooses and may edit. *)
module Details : sig
  type t =
    { name : string
    ; goal : Money.Amount.t option
    ; target_date : Date.t option
    ; cosmetics : (string * string) list
    (** opaque key and value pairs such as [("colour", "teal"); ("icon", "...")];
        stored sorted by key *)
    }
  [@@deriving sexp, compare, equal]
end

type t = private
  { id : Pot_id.t
  ; owner : Owner_id.t
  ; account : Ledger.Account_id.t (** the parent currency account *)
  ; currency : Money.Currency.t
  ; ledger_account : Ledger.Account_id.t (** the pot's own account, {!ledger_account_id} *)
  ; details : Details.t
  ; status : Status.t
  ; created_at : Time_ns.Alternate_sexp.t
  }
[@@deriving sexp, compare, equal]

(** [pot:<id>], the id of the pot's ledger account. *)
val ledger_account_id : Pot_id.t -> Ledger.Account_id.t

(** A new active pot. [open_pots] is the number of the owner's pots that are not closed;
    a target date before [today] is refused. *)
val create
  :  ?limits:Limits.t
  -> id:Pot_id.t
  -> owner:Owner_id.t
  -> account:Ledger.Account_id.t
  -> currency:Money.Currency.t
  -> open_pots:int
  -> today:Date.t
  -> at:Time_ns.t
  -> Details.t
  -> (t, Refusal.t) Result.t

(** Replaces the editable fields of an active pot, with the same checks as {!create}. *)
val update
  :  ?limits:Limits.t
  -> t
  -> today:Date.t
  -> Details.t
  -> (t, Refusal.t) Result.t

(** Marks the pot closed. The caller books {!Pot_booking.close} first. *)
val close : t -> at:Time_ns.t -> (t, Refusal.t) Result.t

val is_active : t -> bool

(** The ledger account to open for a pot: a credit-normal [Liability] with purpose
    [Customer_funds] (the bank owes the pot's balance to the owner, as for the parent),
    tagged with [pot], [owner] and [parent]. *)
val to_ledger_account : t -> Ledger.Account.t

(** Progress towards the goal. *)
module Progress : sig
  type t =
    { percent : int (** rounded down, capped at 100 *)
    ; remaining : Money.Amount.t (** zero once reached *)
    ; reached : bool
    }
  [@@deriving sexp, compare, equal]
end

(** [None] for a pot without a goal. Fails when [balance] is in another currency. *)
val progress : t -> balance:Money.Amount.t -> Progress.t option Or_error.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
