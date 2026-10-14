(* A small command line over the pure parts of the library: round-ups, budget states and
   categorisation with the default catalogue and keyword list. *)

open! Core
open Pots_and_insights
module Amount = Money.Amount

let amount_arg = Command.Arg_type.create Fn.id

let parse_amount ~currency s =
  Amount.of_decimal_string (Money.Currency.of_string currency) s |> Or_error.ok_exn
;;

let round_up =
  Command.basic
    ~summary:"Round-up of a card purchase"
    (let%map_open.Command spend =
       flag "-spend" (required amount_arg) ~doc:"DECIMAL purchase"
     and unit =
       flag "-unit" (optional_with_default "1" amount_arg) ~doc:"DECIMAL unit (1)"
     and multiplier =
       flag "-multiplier" (optional_with_default 1 int) ~doc:"N multiplier, 1 to 10 (1)"
     and currency =
       flag "-currency" (optional_with_default "EUR" string) ~doc:"CODE (EUR)"
     in
     fun () ->
       let rule =
         Round_up.create
           ~pot:(Pot_id.of_string "cli")
           ~unit:(parse_amount ~currency unit)
           ~multiplier
           ()
         |> Or_error.ok_exn
       in
       print_endline
         (Amount.to_string
            (Round_up.of_spend rule ~spend:(parse_amount ~currency spend)
             |> Or_error.ok_exn)))
;;

let budget_status =
  Command.basic
    ~summary:"State and pace of a monthly budget"
    (let%map_open.Command amount =
       flag "-amount" (required amount_arg) ~doc:"DECIMAL budget"
     and spent = flag "-spent" (required amount_arg) ~doc:"DECIMAL spent so far"
     and currency =
       flag "-currency" (optional_with_default "EUR" string) ~doc:"CODE (EUR)"
     and now =
       flag
         "-now"
         (optional string)
         ~doc:"TIME e.g. 2026-10-14T09:00:00Z (default: the current time)"
     in
     fun () ->
       let now =
         Option.value_map
           now
           ~default:(Time_ns.now ())
           ~f:Time_ns.of_string_with_utc_offset
       in
       let amount = parse_amount ~currency amount
       and spent = parse_amount ~currency spent in
       let month = Calendar_month.of_time now in
       let pace = Budget.pace ~amount ~spent ~month ~now in
       print_s
         [%sexp
           { month : Calendar_month.t
           ; status = (Budget.Status.name (Budget.status ~amount ~spent ()) : string)
           ; remaining = (Amount.sub_exn amount spent : Amount.t)
           ; pace : Budget.Pace.t option
           }])
;;

let categorise =
  Command.basic
    ~summary:"Category of an outgoing card purchase or payment (default catalogue)"
    (let%map_open.Command merchant =
       flag "-merchant" (optional string) ~doc:"NAME card merchant"
     and merchant_category =
       flag "-merchant-category" (optional string) ~doc:"CODE network category"
     and payee = flag "-payee" (optional string) ~doc:"NAME payment payee"
     and description =
       flag "-description" (optional_with_default "" string) ~doc:"TEXT"
     in
     fun () ->
       let source : Item.Source.t =
         match merchant, payee with
         | Some merchant, _ ->
           Card
             { merchant
             ; merchant_category = Option.map merchant_category ~f:Category.of_string
             }
         | None, Some name ->
           Payment { payee = Some { id = None; name }; schedule = None }
         | None, None -> Other
       in
       let item : Item.t =
         { id = Item_id.of_string "cli"
         ; account = Ledger.Account_id.of_string "cli"
         ; amount = Amount.of_string "-1.00 EUR"
         ; at = Time_ns.epoch
         ; description
         ; source
         ; refund_of = None
         ; status = Completed
         }
       in
       let a =
         Categorise.assign Catalogue.default Keywords.default Preferences.empty item
       in
       print_s
         [%sexp
           { category = (a.category : Category.t)
           ; source = (a.source : Categorise.Source.t)
           }])
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"Savings pots and spending insights"
       [ "round-up", round_up; "budget-status", budget_status; "categorise", categorise ])
;;
