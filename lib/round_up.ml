open! Core
module Amount = Money.Amount

module Stable = struct
  module V1 = struct
    type t =
      { pot : Pot_id.Stable.V1.t
      ; unit : Amount.Stable.V1.t
      ; multiplier : int
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let create ~pot ~unit ?(multiplier = 1) () =
  if not (Amount.is_positive unit)
  then Or_error.error_s [%message "round-up unit must be positive" (unit : Amount.t)]
  else if multiplier < 1 || multiplier > 10
  then Or_error.error_s [%message "round-up multiplier outside 1..10" (multiplier : int)]
  else Ok { pot; unit; multiplier }
;;

let of_spend t ~spend =
  if not (Money.Currency.equal (Amount.currency spend) (Amount.currency t.unit))
  then
    Or_error.error_s
      [%message "round-up in another currency" (spend : Amount.t) ~unit:(t.unit : Amount.t)]
  else (
    let u = Amount.minor_units t.unit in
    let s = Z.abs (Amount.minor_units spend) in
    (* Distance up to the next multiple of the unit; zero on an exact multiple. *)
    let r = Z.erem (Z.neg s) u in
    Ok (Amount.of_minor_units (Amount.currency spend) (Z.mul r (Z.of_int t.multiplier))))
;;

let of_item t (i : Item.t) =
  match i.source, Item.flow i with
  | Card _, Spending when Item.counts i ->
    Result.ok (of_spend t ~spend:(Amount.neg i.amount))
  | _ -> None
;;

let total t ~account ~from ~until items =
  List.filter_map items ~f:(fun (i : Item.t) ->
    if Ledger.Account_id.equal i.account account
       && Time_ns.( >= ) i.at from
       && Time_ns.( < ) i.at until
    then of_item t i
    else None)
  |> List.fold ~init:(Amount.zero (Amount.currency t.unit)) ~f:Amount.add_exn
;;

let item_key id =
  (* Item ids are at most 100 ledger-id characters, so the key is always valid. *)
  Ledger.Idempotency_key.of_string ("roundup:" ^ Item_id.to_string id)
;;
