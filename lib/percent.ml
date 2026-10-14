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
       | _ -> of_sexp_error "Percent.t_of_sexp: expected a number with one decimal" sexp)
    | List _ -> of_sexp_error "Percent.t_of_sexp: expected an atom" sexp
  ;;
end

include T

let of_tenths t = t
let to_tenths t = t

let of_ratio ~num ~den =
  if Z.equal den Z.zero
  then Or_error.error_string "Percent.of_ratio: zero denominator"
  else (
    (* tenths = num * 1000 / den, rounded half away from zero, on exact integers. *)
    let n = Z.mul num (Z.of_int 1000) in
    let q = Z.div (Z.add (Z.mul (Z.abs n) (Z.of_int 2)) (Z.abs den)) (Z.mul (Z.abs den) (Z.of_int 2)) in
    let negative = Z.sign n * Z.sign den < 0 in
    let q = if negative then Z.neg q else q in
    if Z.fits_int q
    then Ok (Z.to_int q)
    else Or_error.error_string "Percent.of_ratio: out of range")
;;

include Comparable.Make (T)

module Stable = struct
  module V1 = T
end
