open! Core

module T = struct
  type t = int [@@deriving bin_io, compare, equal, hash]

  let to_string t =
    let sign = if t < 0 then "-" else "" in
    let a = Int.abs t in
    sprintf "%s%d.%d" sign (a / 10) (a mod 10)
  ;;

  let sexp_of_t t = Sexp.Atom (to_string t)

  let t_of_sexp sexp =
    match sexp with
    | Sexp.Atom s ->
      (match String.lsplit2 s ~on:'.' with
       | Some (whole, frac) when String.length frac = 1 ->
         let negative = String.is_prefix whole ~prefix:"-" in
         let w = Int.of_string (if negative then String.drop_prefix whole 1 else whole) in
         let v = (w * 10) + Int.of_string frac in
         if negative then -v else v
       | _ ->
         of_sexp_error "Percentage.t_of_sexp: expected a number with one decimal" sexp)
    | List _ -> of_sexp_error "Percentage.t_of_sexp: expected an atom" sexp
  ;;
end

include T

let of_tenths t = t
let to_tenths t = t

module Rounding = struct
  type t =
    | Half_away_from_zero
    | Half_even
  [@@deriving sexp, compare, equal, enumerate]

  let default = Half_away_from_zero
end

let of_ratio_rounded ~rounding ~num ~den =
  if Z.equal den Z.zero
  then Or_error.error_string "Percentage.of_ratio: zero denominator"
  else (
    (* tenths = |num| * 1000 / |den| on exact integers, then the sign; [q] is the
       truncated quotient and [r] the remainder, so the result is a half exactly when
       [2r = |den|]. *)
    let n = Z.abs (Z.mul num (Z.of_int 1000)) in
    let d = Z.abs den in
    let q, r = Z.div_rem n d in
    let twice_r = Z.mul r (Z.of_int 2) in
    let c = Z.compare twice_r d in
    let round_up =
      if c > 0
      then true
      else if c < 0
      then false
      else (
        match (rounding : Rounding.t) with
        | Half_away_from_zero -> true
        | Half_even -> Z.is_odd q)
    in
    let q = if round_up then Z.succ q else q in
    let negative = Z.sign num * Z.sign den < 0 in
    let q = if negative then Z.neg q else q in
    if Z.fits_int q
    then Ok (Z.to_int q)
    else Or_error.error_string "Percentage.of_ratio: out of range")
;;

let of_ratio ~num ~den = of_ratio_rounded ~rounding:Rounding.default ~num ~den

include Comparable.Make (T)

module Stable = struct
  module V1 = T
end
