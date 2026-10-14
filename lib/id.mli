(** Identifiers chosen by the caller (a UUID, a database key).

    Ids end up inside ledger idempotency keys and account ids, so they use the ledger's id
    alphabet ([A-Z a-z 0-9 _ - . : / @ +]) and are at most {!max_length} characters,
    leaving room for the prefixes and suffixes this library adds. *)

open! Core

(** 100. *)
val max_length : int

module type S = sig
  include Ledger.Validated_id.S

  (** [max_length]. *)
  val max_length : int
end

(** A fresh id type; [module_name] appears in error messages. *)
module Make (_ : sig
    val module_name : string
  end) : S
