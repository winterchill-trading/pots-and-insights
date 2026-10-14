open! Core
open Pots_and_insights
open Helpers
module S = Scheduler_core

(* A tiny in-memory service: one journal state, a list of items and the pots. *)
let state = ref Ledger.Balances.empty
let statement : Item.t list ref = ref []
let pots : Pot.t Pot_id.Map.t ref = ref Pot_id.Map.empty
let appended = ref 0

module Env = struct
  let pot id = Map.find !pots id
  let balances () = !state

  let items ~account:a ~from ~until =
    List.filter !statement ~f:(fun (i : Item.t) ->
      Ledger.Account_id.equal i.account a && Time_ns.( >= ) i.at from && Time_ns.( < ) i.at until)
  ;;

  let append entry =
    incr appended;
    state := post !state entry;
    Ok ()
  ;;
end

module Job = Pot_job.Make (Monad.Ident) (Env)
module Store = S.Store_memory.Make (Monad.Ident) (Job)
module Runner = S.Runner.Make (Monad.Ident) (Job) (Store)

let setup ?goal ?(deposit = "1000.00") () =
  let p = pot ?goal () in
  pots := Pot_id.Map.singleton p.id p;
  state := ledger ~deposit:(eur deposit) ~pots:[ p ] ();
  statement := [];
  appended := 0;
  p
;;

let show_executions es =
  List.iter es ~f:(fun (e : Runner.Execution.t) ->
    print_s [%sexp (e.key : S.Run_key.t), (e.status : Runner.Execution.status)])
;;

let%expect_test "weekly top-ups stop at the goal" =
  let p = setup ~goal:(eur "120.00") () in
  let clock = S.Clock.Manual.create ~start:t0 ~zone:Time_float.Zone.utc in
  let runner =
    Runner.create ~store:(Store.create ()) ~clock:(S.Clock.Manual.clock clock) ()
  in
  let top_up =
    Top_up.create ~pot:p.id ~amount:(eur "50.00") ~stop_at_goal:true |> Or_error.ok_exn
  in
  ignore
    (Runner.add
       runner
       ~id:(S.Schedule_id.create_exn "save-weekly")
       (Top_up top_up)
       (S.Recurrence.create_exn Weekly ~start:today ())
     : (Job.t S.Schedule.t, Runner.Command_error.t) Result.t);
  for _ = 1 to 4 do
    show_executions (Runner.tick runner);
    S.Clock.Manual.advance clock (Time_ns.Span.of_day 7.)
  done;
  print_s [%sexp (Pot_booking.balance !state p : Money.Amount.t), (available !state : string)];
  [%expect {|
    (((schedule save-weekly) (due_date 2026-10-14))
     (Ran (attempt 1)
      (outcome (Succeeded (reference pot-auto:save-weekly:2026-10-14)))))
    (((schedule save-weekly) (due_date 2026-10-21))
     (Ran (attempt 1)
      (outcome (Succeeded (reference pot-auto:save-weekly:2026-10-21)))))
    (((schedule save-weekly) (due_date 2026-10-28))
     (Ran (attempt 1)
      (outcome (Succeeded (reference pot-auto:save-weekly:2026-10-28)))))
    (((schedule save-weekly) (due_date 2026-11-04))
     (Ran (attempt 1) (outcome (Succeeded (reference skipped:goal_reached)))))
    ("120.00 EUR" "880.00 EUR")
    |}]
;;

let%expect_test "a retried run books once" =
  let p = setup () in
  let top_up =
    Top_up.create ~pot:p.id ~amount:(eur "10.00") ~stop_at_goal:false |> Or_error.ok_exn
  in
  let ctx : S.Job.Context.t =
    { key = S.Run_key.create (S.Schedule_id.create_exn "s") today
    ; index = 0
    ; attempt = 1
    ; now = t0
    }
  in
  let first = Job.run (Top_up top_up) ctx in
  let second = Job.run (Top_up top_up) { ctx with attempt = 2; now = Time_ns.add t0 Time_ns.Span.hour } in
  print_s [%sexp (first : (string, string) Result.t), (second : (string, string) Result.t)];
  print_s [%sexp (!appended : int), (Pot_booking.balance !state p : Money.Amount.t)];
  [%expect {|
    ((Ok pot-auto:s:2026-10-14) (Ok pot-auto:s:2026-10-14))
    (1 "10.00 EUR")
    |}]
;;

let%expect_test "an account without money fails the date" =
  let p = setup ~deposit:"5.00" () in
  let top_up =
    Top_up.create ~pot:p.id ~amount:(eur "10.00") ~stop_at_goal:false |> Or_error.ok_exn
  in
  let ctx : S.Job.Context.t =
    { key = S.Run_key.create (S.Schedule_id.create_exn "s") today
    ; index = 0
    ; attempt = 1
    ; now = t0
    }
  in
  print_s [%sexp (Job.run (Top_up top_up) ctx : (string, string) Result.t)];
  [%expect {| (Error account_insufficient) |}]
;;

let%expect_test "daily round-up sweeps cover the previous UTC day" =
  let p = setup () in
  let rule = Round_up.create ~pot:p.id ~unit:(eur "1.00") () |> Or_error.ok_exn in
  statement
  := [ item ~id:"a" ~at:(time "2026-10-13 00:00:00Z") ~amount:"-3.40" (card "Cafe")
     ; item ~id:"b" ~at:(time "2026-10-13 23:59:59Z") ~amount:"-10.75" (card "Shop")
     ; item ~id:"c" ~at:(time "2026-10-13 12:00:00Z") ~amount:"-4.00" (card "Shop")
     ; item ~id:"d" ~at:(time "2026-10-13 12:00:00Z") ~amount:"-9.99" (payment "Rent")
     ; item ~id:"e" ~at:(time "2026-10-14 00:00:00Z") ~amount:"-0.10" (card "Cafe")
     ];
  let sweep : Pot_job.t = Round_up_sweep { rule; account } in
  print_s
    [%sexp
      (Job.validate sweep (S.Recurrence.create_exn Weekly ~start:today ()) : unit Or_error.t)];
  let ctx : S.Job.Context.t =
    { key = S.Run_key.create (S.Schedule_id.create_exn "sweep") today
    ; index = 0
    ; attempt = 1
    ; now = t0
    }
  in
  print_s [%sexp (Job.run sweep ctx : (string, string) Result.t)];
  print_s [%sexp (Pot_booking.balance !state p : Money.Amount.t)];
  [%expect {|
    (Error "round-up sweeps run every day")
    (Ok pot-auto:sweep:2026-10-14)
    "0.85 EUR"
    |}]
;;
