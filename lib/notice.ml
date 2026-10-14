open! Core
module Amount = Money.Amount

module Stable = struct
  module V1 = struct
    type t =
      | Budget_near of
          { budget : Budget_id.Stable.V1.t
          ; account : Ledger.Account_id.Stable.V1.t
          ; target : Budget.Target.Stable.V1.t
          ; month : Calendar_month.Stable.V1.t
          ; spent : Amount.Stable.V1.t
          ; amount : Amount.Stable.V1.t
          }
      | Budget_over of
          { budget : Budget_id.Stable.V1.t
          ; account : Ledger.Account_id.Stable.V1.t
          ; target : Budget.Target.Stable.V1.t
          ; month : Calendar_month.Stable.V1.t
          ; spent : Amount.Stable.V1.t
          ; amount : Amount.Stable.V1.t
          }
      | Goal_reached of
          { pot : Pot_id.Stable.V1.t
          ; goal : Amount.Stable.V1.t
          ; balance : Amount.Stable.V1.t
          }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let key = function
  | Budget_near { budget; month; _ } ->
    sprintf
      "budget:%s:%s:near"
      (Budget_id.to_string budget)
      (Calendar_month.to_string month)
  | Budget_over { budget; month; _ } ->
    sprintf
      "budget:%s:%s:over"
      (Budget_id.to_string budget)
      (Calendar_month.to_string month)
  | Goal_reached { pot; _ } -> sprintf "pot:%s:goal_reached" (Pot_id.to_string pot)
;;

let rank : Budget.Status.t -> int = function
  | Under -> 0
  | Near -> 1
  | Over -> 2
;;

let budget_changes ~(before : Budget_month.t) ~(after : Budget_month.t) =
  let all (v : Budget_month.t) = Option.to_list v.overall @ v.categories in
  let before_status =
    List.map (all before) ~f:(fun (p : Budget.Progress.t) -> p.budget, p.status)
    |> Budget_id.Map.of_alist_reduce ~f:(fun a _ -> a)
  in
  List.filter_map (all after) ~f:(fun (p : Budget.Progress.t) ->
    let was =
      Option.value (Map.find before_status p.budget) ~default:Budget.Status.Under
    in
    if rank p.status <= rank was
    then None
    else (
      match p.status with
      | Under -> None
      | Near ->
        Some
          (Budget_near
             { budget = p.budget
             ; account = after.account
             ; target = p.target
             ; month = p.month
             ; spent = p.spent
             ; amount = p.amount
             })
      | Over ->
        Some
          (Budget_over
             { budget = p.budget
             ; account = after.account
             ; target = p.target
             ; month = p.month
             ; spent = p.spent
             ; amount = p.amount
             })))
;;

let goal_reached (pot : Pot.t) ~before ~after =
  match pot.details.goal with
  | Some goal when Amount.( < ) before goal && Amount.( >= ) after goal ->
    Some (Goal_reached { pot = pot.id; goal; balance = after })
  | _ -> None
;;
