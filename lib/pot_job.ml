open! Core
module Amount = Money.Amount

module Stable = struct
  module V1 = struct
    type t =
      | Top_up of Top_up.Stable.V1.t
      | Round_up_sweep of
          { rule : Round_up.Stable.V1.t
          ; account : Ledger.Account_id.Stable.V1.t
          }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let idempotency_key key =
  Ledger.Idempotency_key.of_string_or_error
    ("pot-auto:" ^ Scheduler_core.Run_key.to_string key)
;;

module type Env = sig
  type 'a io

  val pot : Pot_id.t -> Pot.t option io
  val balances : unit -> Ledger.Balances.t io

  val items
    :  account:Ledger.Account_id.t
    -> from:Time_ns.t
    -> until:Time_ns.t
    -> Item.t list io

  val append : Ledger.Entry.t -> unit Or_error.t io
end

module Make (M : Monad.S) (E : Env with type 'a io := 'a M.t) = struct
  type 'a io = 'a M.t
  type nonrec t = t [@@deriving sexp_of]

  open M.Let_syntax

  let validate t recurrence =
    match t, Scheduler_core.Recurrence.frequency recurrence with
    | Top_up _, _ | Round_up_sweep _, Every_n_days 1 -> Ok ()
    | Round_up_sweep _, _ -> Or_error.error_string "round-up sweeps run every day"
  ;;

  let pot_id = function
    | Top_up t -> t.pot
    | Round_up_sweep { rule; _ } -> rule.pot
  ;;

  (* Books [amount] into the pot under the run's key. Replays and fresh entries both
     answer the key as the reference. *)
  let deposit pot ~amount ~(ctx : Scheduler_core.Job.Context.t) =
    match idempotency_key ctx.key with
    | Error _ -> return (Error "invalid_key")
    | Ok idempotency_key ->
      let%bind balances = E.balances () in
      (match Pot_booking.deposit balances pot ~amount ~idempotency_key ~at:ctx.now with
       | Error refusal -> return (Error (Pot.Refusal.code refusal))
       | Ok entry ->
         let reference = Ledger.Idempotency_key.to_string idempotency_key in
         if Option.is_some (Ledger.Balances.find_entry balances idempotency_key)
         then return (Ok reference)
         else (
           match%map E.append entry with
           | Ok () -> Ok reference
           | Error e -> Error.raise e))
  ;;

  let run t (ctx : Scheduler_core.Job.Context.t) =
    match%bind E.pot (pot_id t) with
    | None -> return (Error "pot_not_found")
    | Some pot ->
      (match t with
       | Top_up top_up ->
         let%bind balances = E.balances () in
         (match Top_up.decide top_up pot ~balance:(Pot_booking.balance balances pot) with
          | Skip reason -> return (Ok ("skipped:" ^ reason))
          | Deposit amount -> deposit pot ~amount ~ctx)
       | Round_up_sweep { rule; account } ->
         if not (Pot.is_active pot)
         then return (Ok "skipped:pot_closed")
         else (
           let day = Date.add_days ctx.key.due_date (-1) in
           let from =
             Time_ns.of_date_ofday
               ~zone:Time_float.Zone.utc
               day
               Time_ns.Ofday.start_of_day
           in
           let until = Time_ns.add from Time_ns.Span.day in
           let%bind items = E.items ~account ~from ~until in
           let amount = Round_up.total rule ~account ~from ~until items in
           if Amount.is_zero amount
           then return (Ok "skipped:nothing_to_sweep")
           else deposit pot ~amount ~ctx))
  ;;
end
