open! Core
module Amount = Money.Amount
module Currency = Money.Currency

module Limits = struct
  type t =
    { max_open_pots : int
    ; max_name_length : int
    ; max_cosmetic_fields : int
    ; max_cosmetic_length : int
    }
  [@@deriving sexp, compare, equal]

  let default =
    { max_open_pots = 20
    ; max_name_length = 30
    ; max_cosmetic_fields = 8
    ; max_cosmetic_length = 16
    }
  ;;
end

module Refusal = struct
  type t =
    | Name_invalid of string
    | Goal_not_positive
    | Goal_currency_mismatch of { expected : Currency.t }
    | Target_date_in_past
    | Cosmetic_invalid of
        { key : string
        ; reason : string
        }
    | Too_many_open_pots of { max : int }
    | Pot_closed
    | Already_closed
    | Amount_not_positive
    | Amount_currency_mismatch of { expected : Currency.t }
    | Insufficient_in_account
    | Insufficient_in_pot
    | Ledger_refused of Error.t
  [@@deriving sexp_of]

  let code = function
    | Name_invalid _ -> "name_invalid"
    | Goal_not_positive -> "goal_not_positive"
    | Goal_currency_mismatch _ -> "goal_currency_mismatch"
    | Target_date_in_past -> "target_date_in_past"
    | Cosmetic_invalid _ -> "cosmetic_invalid"
    | Too_many_open_pots _ -> "pots_limit"
    | Pot_closed -> "pot_closed"
    | Already_closed -> "pot_already_closed"
    | Amount_not_positive -> "amount_not_positive"
    | Amount_currency_mismatch _ -> "amount_currency_mismatch"
    | Insufficient_in_account -> "account_insufficient"
    | Insufficient_in_pot -> "pot_insufficient"
    | Ledger_refused _ -> "ledger_refused"
  ;;
end

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Active
        | Closed of { at : Time_ns.Stable.Alternate_sexp.V1.t }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let name = function
    | Active -> "active"
    | Closed _ -> "closed"
  ;;
end

module Details = struct
  module Stable = struct
    module V1 = struct
      type t =
        { name : string
        ; goal : Amount.Stable.V1.t option
        ; target_date : Date.Stable.V1.t option
        ; cosmetics : (string * string) list
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Stable = struct
  module V1 = struct
    type t =
      { id : Pot_id.Stable.V1.t
      ; owner : Owner_id.Stable.V1.t
      ; account : Ledger.Account_id.Stable.V1.t
      ; currency : Currency.Stable.V1.t
      ; ledger_account : Ledger.Account_id.Stable.V1.t
      ; details : Details.Stable.V1.t
      ; status : Status.Stable.V1.t
      ; created_at : Time_ns.Stable.Alternate_sexp.V1.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let ledger_account_id id = Ledger.Account_id.of_string ("pot:" ^ Pot_id.to_string id)

let is_slug key =
  (not (String.is_empty key))
  && String.length key <= 32
  && String.for_all key ~f:(fun c -> Char.is_lowercase c || Char.is_digit c || Char.equal c '_')
;;

let check_cosmetics (limits : Limits.t) cosmetics =
  let open Result.Let_syntax in
  let invalid key reason = Error (Refusal.Cosmetic_invalid { key; reason }) in
  let%bind () =
    if List.length cosmetics > limits.max_cosmetic_fields
    then invalid "" "too_many_fields"
    else Ok ()
  in
  let sorted = List.sort cosmetics ~compare:(fun (a, _) (b, _) -> String.compare a b) in
  let%bind () =
    match List.find_a_dup sorted ~compare:(fun (a, _) (b, _) -> String.compare a b) with
    | Some (key, _) -> invalid key "duplicate_key"
    | None -> Ok ()
  in
  List.fold_result sorted ~init:[] ~f:(fun acc (key, value) ->
    if not (is_slug key)
    then invalid key "key_not_slug"
    else if String.length value > limits.max_cosmetic_length
    then invalid key "too_long"
    else (
      match Text.clean value ~max_code_points:limits.max_cosmetic_length with
      | Ok value -> Ok ((key, value) :: acc)
      | Error reason -> invalid key reason))
  |> Result.map ~f:List.rev
;;

let check_details (limits : Limits.t) ~currency ~today (d : Details.t) =
  let open Result.Let_syntax in
  let%bind name =
    Text.clean d.name ~max_code_points:limits.max_name_length
    |> Result.map_error ~f:(fun reason -> Refusal.Name_invalid reason)
  in
  let%bind () =
    match d.goal with
    | None -> Ok ()
    | Some goal ->
      if not (Currency.equal (Amount.currency goal) currency)
      then Error (Refusal.Goal_currency_mismatch { expected = currency })
      else if not (Amount.is_positive goal)
      then Error Refusal.Goal_not_positive
      else Ok ()
  in
  let%bind () =
    match d.target_date with
    | Some date when Date.( < ) date today -> Error Refusal.Target_date_in_past
    | _ -> Ok ()
  in
  let%map cosmetics = check_cosmetics limits d.cosmetics in
  { d with name; cosmetics }
;;

let create
  ?(limits = Limits.default)
  ~id
  ~owner
  ~account
  ~currency
  ~open_pots
  ~today
  ~at
  details
  =
  let open Result.Let_syntax in
  let%bind () =
    if open_pots >= limits.max_open_pots
    then Error (Refusal.Too_many_open_pots { max = limits.max_open_pots })
    else Ok ()
  in
  let%map details = check_details limits ~currency ~today details in
  { id
  ; owner
  ; account
  ; currency
  ; ledger_account = ledger_account_id id
  ; details
  ; status = Active
  ; created_at = at
  }
;;

let is_active t =
  match t.status with
  | Active -> true
  | Closed _ -> false
;;

let update ?(limits = Limits.default) t ~today details =
  let open Result.Let_syntax in
  let%bind () = if is_active t then Ok () else Error Refusal.Pot_closed in
  let%map details = check_details limits ~currency:t.currency ~today details in
  { t with details }
;;

let close t ~at =
  match t.status with
  | Closed _ -> Error Refusal.Already_closed
  | Active -> Ok { t with status = Closed { at } }
;;

let to_ledger_account t =
  Ledger.Account.create
    ~purpose:Customer_funds
    ~tags:
      [ "pot", Pot_id.to_string t.id
      ; "owner", Owner_id.to_string t.owner
      ; "parent", Ledger.Account_id.to_string t.account
      ]
    t.ledger_account
    Liability
;;

module Progress = struct
  type t =
    { percent : int
    ; remaining : Amount.t
    ; reached : bool
    }
  [@@deriving sexp, compare, equal]
end

let progress t ~balance =
  let open Or_error.Let_syntax in
  match t.details.goal with
  | None -> Ok None
  | Some goal ->
    let%map remaining = Amount.sub goal balance in
    let reached = not (Amount.is_positive remaining) in
    let percent =
      if reached
      then 100
      else if not (Amount.is_positive balance)
      then 0
      else
        (* Exact: floor (balance * 100 / goal) on minor units, no rounding up to 100 %
           while a minor unit is still missing. *)
        Z.to_int (Z.fdiv (Z.mul (Amount.minor_units balance) (Z.of_int 100)) (Amount.minor_units goal))
    in
    Some
      { Progress.percent
      ; remaining = (if reached then Amount.zero t.currency else remaining)
      ; reached
      }
;;
