(** A calendar month in UTC, the period insights and budgets are computed over.

    Every boundary is midnight UTC: the month of a timestamp is the month of its UTC date,
    and [start] and [stop] are the first instants of this month and the next. A caller in
    another zone converts before asking; the library never reads the machine's zone. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** Fails unless [1 <= year <= 9999]. *)
val create : year:int -> month:Month.t -> t Or_error.t

(** The year, 1 to 9999. *)
val year : t -> int
(** The month of the year. *)
val month : t -> Month.t

(** The month a date falls in. *)
val of_date : Date.t -> t

(** The month of the UTC date of a timestamp. *)
val of_time : Time_ns.t -> t

(** The first day of the month. *)
val first_day : t -> Date.t

(** The last day of the month (29 February in a leap year). *)
val last_day : t -> Date.t

(** Number of days, 28 to 31. *)
val days : t -> int

(** Midnight UTC on the first day. *)
val start : t -> Time_ns.t

(** Midnight UTC on the first day of the next month: the exclusive end. *)
val stop : t -> Time_ns.t

(** [start t <= time < stop t]. *)
val contains : t -> Time_ns.t -> bool

(** [add t n] is [n] months later ([n] may be negative). *)
val add : t -> int -> t

(** The month after. *)
val next : t -> t
(** The month before. *)
val prev : t -> t

(** [months_between a b] is the number of months from [a] to [b]: [1] from 2026-01 to
    2026-02, negative when [b] is earlier. *)
val months_between : t -> t -> int

(** The [n] months ending with [last], oldest first. Empty when [n <= 0]. *)
val last_n : t -> n:int -> t list

(** The day of the month of [now] (UTC, from 1) and the number of days in the month, when
    [now] falls in [t]. *)
val elapsed : t -> now:Time_ns.t -> (int * int) option

(** ["2026-10"]. *)
val to_string : t -> string

(** Parses ["YYYY-MM"] (exactly four and two digits). *)
val of_string : string -> t Or_error.t

(** Months from 1970 to 2100. *)
val quickcheck_generator : t Quickcheck.Generator.t
(** Observes the month number. *)
val quickcheck_observer : t Quickcheck.Observer.t
(** Does not shrink. *)
val quickcheck_shrinker : t Quickcheck.Shrinker.t

module Stable : sig
  module V1 : sig
    (** Bin_prot: year and month number (1 to 12). Sexp: ["2026-10"]. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
