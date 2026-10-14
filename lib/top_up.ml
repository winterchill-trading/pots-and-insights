open! Core
module Amount = Money.Amount

module Stable = struct
  module V1 = struct
    type t =
      { pot : Pot_id.Stable.V1.t
      ; amount : Amount.Stable.V1.t
      ; stop_at_goal : bool
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let create ~pot ~amount ~stop_at_goal =
  if Amount.is_positive amount
  then Ok { pot; amount; stop_at_goal }
  else Or_error.error_s [%message "top-up amount must be positive" (amount : Amount.t)]
;;

module Decision = struct
  type t =
    | Deposit of Amount.t
    | Skip of string
  [@@deriving sexp, compare, equal]
end

let decide t (pot : Pot.t) ~balance : Decision.t =
  if not (Pot.is_active pot)
  then Skip "pot_closed"
  else if not (Money.Currency.equal (Amount.currency t.amount) pot.currency)
  then Skip "currency_mismatch"
  else (
    match t.stop_at_goal, pot.details.goal with
    | false, _ | true, None -> Deposit t.amount
    | true, Some goal ->
      let missing = Amount.sub_exn goal balance in
      if not (Amount.is_positive missing)
      then Skip "goal_reached"
      else Deposit (Amount.min t.amount missing))
;;
