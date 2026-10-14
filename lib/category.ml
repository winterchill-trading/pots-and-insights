open! Core

let of_string_or_error s =
  if String.length s >= 1
     && String.length s <= 40
     && String.for_all s ~f:(fun c ->
       Char.is_lowercase c || Char.is_digit c || Char.equal c '_')
  then Ok s
  else
    Or_error.error_s
      [%message "Pots_and_insights.Category: not a slug" ~category:(s : string)]
;;

module T = struct
  type t = string [@@deriving compare, equal, hash]

  let module_name = "Pots_and_insights.Category"
  let to_string t = t
  let of_string s = Or_error.ok_exn (of_string_or_error s)
  let sexp_of_t = sexp_of_string
  let t_of_sexp sexp = of_string (string_of_sexp sexp)

  include
    Binable.Of_binable_without_uuid [@alert "-legacy"]
      (String)
      (struct
        type t = string

        let to_binable = Fn.id
        let of_binable = of_string
      end)
end

include T
include Identifiable.Make (T)

let quickcheck_generator =
  Quickcheck.Generator.of_list
    [ "groceries"; "eating_out"; "transport"; "travel"; "shopping"; "bills"; "general" ]
;;

let quickcheck_observer = String.quickcheck_observer
let quickcheck_shrinker : t Quickcheck.Shrinker.t = Quickcheck.Shrinker.empty ()

module Stable = struct
  module V1 = T
end
