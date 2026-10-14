open! Core

module T = struct
  (* Months since year 0, January = 0: ordering, arithmetic and hashing come for free. *)
  type t = int [@@deriving compare, equal, hash]

  let year t = t / 12
  let month t = Month.of_int_exn ((t mod 12) + 1)
  let to_string t = sprintf "%04d-%02d" (year t) (Month.to_int (month t))

  let make ~year ~month =
    if year < 1 || year > 9999
    then Or_error.error_s [%message "year out of range" (year : int)]
    else Ok ((year * 12) + Month.to_int month - 1)
  ;;

  let of_string s =
    let fail () = Or_error.error_s [%message "expected YYYY-MM" ~got:(s : string)] in
    let digits a = String.for_all a ~f:Char.is_digit in
    match String.split s ~on:'-' with
    | [ y; m ] when String.length y = 4 && String.length m = 2 && digits y && digits m ->
      let m = Int.of_string m in
      if m < 1 || m > 12
      then fail ()
      else make ~year:(Int.of_string y) ~month:(Month.of_int_exn m)
    | _ -> fail ()
  ;;

  let sexp_of_t t = Sexp.Atom (to_string t)

  let t_of_sexp sexp =
    match sexp with
    | Sexp.Atom s -> Or_error.ok_exn (of_string s)
    | List _ -> of_sexp_error "Calendar_month.t_of_sexp: expected an atom" sexp
  ;;

  module Wire = struct
    type t =
      { year : int
      ; month : int
      }
    [@@deriving bin_io]
  end

  include
    Binable.Of_binable_without_uuid [@alert "-legacy"]
      (Wire)
      (struct
        type nonrec t = t

        let to_binable t : Wire.t = { year = year t; month = Month.to_int (month t) }

        let of_binable ({ year; month } : Wire.t) =
          match Month.of_int month with
          | None -> failwithf "Calendar_month: month %d out of range" month ()
          | Some month -> Or_error.ok_exn (make ~year ~month)
        ;;
      end)
end

include T

let create = make
let of_date date = (Date.year date * 12) + Month.to_int (Date.month date) - 1
let of_time time = of_date (Time_ns.to_date time ~zone:Time_float.Zone.utc)
let first_day t = Date.create_exn ~y:(year t) ~m:(month t) ~d:1
let days t = Date.days_in_month ~year:(year t) ~month:(month t)
let last_day t = Date.create_exn ~y:(year t) ~m:(month t) ~d:(days t)

let midnight date =
  Time_ns.of_date_ofday ~zone:Time_float.Zone.utc date Time_ns.Ofday.start_of_day
;;

let add t n = t + n
let next t = t + 1
let prev t = t - 1
let start t = midnight (first_day t)
let stop t = start (next t)
let contains t time = Time_ns.( >= ) time (start t) && Time_ns.( < ) time (stop t)
let months_between a b = b - a
let last_n last ~n = List.init (Int.max n 0) ~f:(fun i -> last - (n - 1 - i))

let elapsed t ~now =
  if contains t now
  then Some (Date.day (Time_ns.to_date now ~zone:Time_float.Zone.utc), days t)
  else None
;;

let quickcheck_generator =
  Quickcheck.Generator.map (Int.gen_incl (1970 * 12) ((2100 * 12) + 11)) ~f:Fn.id
;;

let quickcheck_observer = Int.quickcheck_observer
let quickcheck_shrinker : t Quickcheck.Shrinker.t = Quickcheck.Shrinker.empty ()

include Comparable.Make (T)

module Stable = struct
  module V1 = T
end
