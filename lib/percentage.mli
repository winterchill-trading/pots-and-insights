(** Percentages with one decimal place, exact: an integer count of tenths of a percent.

    [123] is 12.3 %. No floats are involved anywhere. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** [of_ratio ~num ~den] is [num / den] as a percentage, rounded half away from zero to a
    tenth. Fails when [den] is zero or the result does not fit an [int]. *)
val of_ratio : num:Z.t -> den:Z.t -> t Or_error.t

(** [of_tenths 123] is 12.3 %. *)
val of_tenths : int -> t

(** The count of tenths: [123] for 12.3 %. *)
val to_tenths : t -> int

(** ["12.3"], ["-0.5"], ["100.0"]. *)
val to_string : t -> string

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
