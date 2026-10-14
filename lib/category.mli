(** A spending category code such as [groceries] or [eating_out].

    A lower-case slug of 1 to 40 characters from [a-z 0-9 _]. Codes, not labels: the
    caller renders a label in the customer's language. Which codes exist and what they
    mean is a {!Catalogue}. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

include Identifiable.S with type t := t

(** Fails on anything but a slug of 1 to 40 characters from [a-z 0-9 _]. *)
val of_string_or_error : string -> t Or_error.t
(** Codes of the default catalogue's common categories. *)
val quickcheck_generator : t Quickcheck.Generator.t
(** Observes the code. *)
val quickcheck_observer : t Quickcheck.Observer.t
(** Does not shrink. *)
val quickcheck_shrinker : t Quickcheck.Shrinker.t

module Stable : sig
  module V1 : sig
    (** Bin_prot is the plain string; decoding validates again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
