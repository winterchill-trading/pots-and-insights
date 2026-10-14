(** Percentages with one decimal place, exact: an integer count of tenths of a percent.

    [123] is 12.3 %. No floats are involved anywhere. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** How {!of_ratio} settles a result that falls between two tenths. Only exact halves
    differ between the modes; every other result goes to the nearer tenth. *)
module Rounding : sig
  type t =
    | Half_away_from_zero (** [0.05 %] becomes [0.1 %], [-0.05 %] becomes [-0.1 %] *)
    | Half_even
    (** a half goes to the even tenth: [0.05 %] becomes [0.0 %], [0.15 %] becomes [0.2 %];
        totals of many rounded shares drift less *)
  [@@deriving sexp, compare, equal, enumerate]

  (** [Half_away_from_zero]. *)
  val default : t
end

(** [of_ratio ~num ~den] is [num / den] as a percentage, rounded half away from zero to a
    tenth. Fails when [den] is zero or the result does not fit an [int]. Same as
    [of_ratio_rounded ~rounding:Half_away_from_zero]. *)
val of_ratio : num:Z.t -> den:Z.t -> t Or_error.t

(** [of_ratio_rounded ~rounding ~num ~den] is {!of_ratio} with the rounding of exact
    halves chosen by the caller. *)
val of_ratio_rounded : rounding:Rounding.t -> num:Z.t -> den:Z.t -> t Or_error.t

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
