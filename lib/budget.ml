open! Core
module Amount = Money.Amount

module Target = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Overall
        | Category of Category.Stable.V1.t
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let to_string = function
    | Overall -> "overall"
    | Category c -> Category.to_string c
  ;;
end

module Limits = struct
  type t =
    { max_amount : (Z.t[@sexp.opaque])
    ; near_percent : int
    }
  [@@deriving sexp_of]

  let default = { max_amount = Z.pow (Z.of_int 10) 12; near_percent = 80 }
end

module Refusal = struct
  type t =
    | Unknown_category
    | Amount_not_positive
    | Amount_too_large
    | Currency_mismatch of { expected : Money.Currency.t }
    | Budget_exists
    | Removed
  [@@deriving sexp, compare, equal]

  let code = function
    | Unknown_category -> "unknown_category"
    | Amount_not_positive -> "amount_not_positive"
    | Amount_too_large -> "amount_too_large"
    | Currency_mismatch _ -> "currency_mismatch"
    | Budget_exists -> "budget_exists"
    | Removed -> "budget_removed"
  ;;
end

module Stable = struct
  module V1 = struct
    type t =
      { id : Budget_id.Stable.V1.t
      ; owner : Owner_id.Stable.V1.t
      ; account : Ledger.Account_id.Stable.V1.t
      ; currency : Money.Currency.Stable.V1.t
      ; target : Target.Stable.V1.t
      ; amounts : (Calendar_month.Stable.V1.t * Amount.Stable.V1.t) list
      ; removed_from : Calendar_month.Stable.V1.t option
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let check_amount (limits : Limits.t) ~currency amount =
  if not (Money.Currency.equal (Amount.currency amount) currency)
  then Error (Refusal.Currency_mismatch { expected = currency })
  else if not (Amount.is_positive amount)
  then Error Refusal.Amount_not_positive
  else if Z.gt (Amount.minor_units amount) limits.max_amount
  then Error Refusal.Amount_too_large
  else Ok ()
;;

let amount_for t month =
  match t.removed_from with
  | Some r when Calendar_month.( >= ) month r -> None
  | _ ->
    List.fold t.amounts ~init:None ~f:(fun acc (from, amount) ->
      if Calendar_month.( <= ) from month then Some amount else acc)
;;

let in_force_from t month =
  match t.removed_from with
  | Some r -> Calendar_month.( < ) month r
  | None -> true
;;

let create
  ?(limits = Limits.default)
  catalogue
  ~id
  ~owner
  ~account
  ~currency
  ~(target : Target.t)
  ~amount
  ~from
  ~existing
  =
  let open Result.Let_syntax in
  let%bind () =
    match target with
    | Overall -> Ok ()
    | Category c ->
      if Catalogue.is_spending catalogue c then Ok () else Error Refusal.Unknown_category
  in
  let%bind () = check_amount limits ~currency amount in
  let%map () =
    if List.exists existing ~f:(fun b ->
         Ledger.Account_id.equal b.account account
         && Target.equal b.target target
         && in_force_from b from)
    then Error Refusal.Budget_exists
    else Ok ()
  in
  { id
  ; owner
  ; account
  ; currency
  ; target
  ; amounts = [ from, amount ]
  ; removed_from = None
  }
;;

let set_amount ?(limits = Limits.default) t ~amount ~from =
  let open Result.Let_syntax in
  let%bind () = if in_force_from t from then Ok () else Error Refusal.Removed in
  let%map () = check_amount limits ~currency:t.currency amount in
  { t with
    amounts =
      List.filter t.amounts ~f:(fun (m, _) -> Calendar_month.( < ) m from)
      @ [ from, amount ]
  }
;;

let remove t ~from =
  if not (in_force_from t from)
  then Error Refusal.Removed
  else Ok { t with removed_from = Some from }
;;

module Status = struct
  type t =
    | Under
    | Near
    | Over
  [@@deriving sexp, compare, equal, enumerate]

  let name = function
    | Under -> "under"
    | Near -> "near"
    | Over -> "over"
  ;;
end

module Pace = struct
  module Status = struct
    type t =
      | On_track
      | Ahead
    [@@deriving sexp, compare, equal]
  end

  type t =
    { day : int
    ; days : int
    ; expected : Amount.t
    ; status : Status.t
    }
  [@@deriving sexp, compare, equal]
end

let status ?(near_percent = Limits.default.near_percent) ~amount ~spent () : Status.t =
  let a = Amount.minor_units amount
  and s = Amount.minor_units spent in
  if Z.gt s a
  then Over
  else if Z.geq (Z.mul s (Z.of_int 100)) (Z.mul a (Z.of_int near_percent))
  then Near
  else Under
;;

let pace ~amount ~spent ~month ~now =
  Option.map (Calendar_month.elapsed month ~now) ~f:(fun (day, days) ->
    let expected =
      Amount.of_minor_units
        (Amount.currency amount)
        (Z.fdiv (Z.mul (Amount.minor_units amount) (Z.of_int day)) (Z.of_int days))
    in
    { Pace.day
    ; days
    ; expected
    ; status = (if Amount.( > ) spent expected then Ahead else On_track)
    })
;;

module Progress = struct
  type t =
    { budget : Budget_id.t
    ; target : Target.t
    ; month : Calendar_month.t
    ; amount : Amount.t
    ; spent : Amount.t
    ; remaining : Amount.t
    ; percent : Percentage.t
    ; status : Status.t
    ; pace : Pace.t option
    }
  [@@deriving sexp, compare, equal]
end

let progress ?near_percent t ~month ~spent ~now =
  Option.map (amount_for t month) ~f:(fun amount ->
    { Progress.budget = t.id
    ; target = t.target
    ; month
    ; amount
    ; spent
    ; remaining = Amount.sub_exn amount spent
    ; percent =
        (* The amount is positive, so the ratio always exists. *)
        Percentage.of_ratio
          ~num:(Amount.minor_units spent)
          ~den:(Amount.minor_units amount)
        |> Or_error.ok_exn
    ; status = status ?near_percent ~amount ~spent ()
    ; pace = pace ~amount ~spent ~month ~now
    })
;;
