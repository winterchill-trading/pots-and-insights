open! Core
open Pots_and_insights
open Helpers

(* A changed digest means bytes written by an older version no longer decode: add a
   Stable.V2 instead of editing V1, and keep V1 readable. *)
let%expect_test "stable bin_prot digests" =
  List.iter
    [ "Pot_id", [%bin_digest: Pot_id.Stable.V1.t]
    ; "Owner_id", [%bin_digest: Owner_id.Stable.V1.t]
    ; "Budget_id", [%bin_digest: Budget_id.Stable.V1.t]
    ; "Item_id", [%bin_digest: Item_id.Stable.V1.t]
    ; "Category", [%bin_digest: Category.Stable.V1.t]
    ; "Calendar_month", [%bin_digest: Calendar_month.Stable.V1.t]
    ; "Percentage", [%bin_digest: Percentage.Stable.V1.t]
    ; "Pot", [%bin_digest: Pot.Stable.V1.t]
    ; "Item", [%bin_digest: Item.Stable.V1.t]
    ; "Preferences", [%bin_digest: Preferences.Stable.V1.t]
    ; "Budget", [%bin_digest: Budget.Stable.V1.t]
    ; "Notice", [%bin_digest: Notice.Stable.V1.t]
    ; "Round_up", [%bin_digest: Round_up.Stable.V1.t]
    ; "Top_up", [%bin_digest: Top_up.Stable.V1.t]
    ; "Pot_job", [%bin_digest: Pot_job.Stable.V1.t]
    ]
    ~f:(fun (name, digest) -> printf "%-15s %s\n" name digest);
  [%expect {|
    Pot_id          d9a8da25d5656b016fb4dbdc2e4197fb
    Owner_id        d9a8da25d5656b016fb4dbdc2e4197fb
    Budget_id       d9a8da25d5656b016fb4dbdc2e4197fb
    Item_id         d9a8da25d5656b016fb4dbdc2e4197fb
    Category        d9a8da25d5656b016fb4dbdc2e4197fb
    Calendar_month  82e84542c03e3ad3adbe4012899b29fb
    Percentage      698cfa4093fe5e51523842d37b92aeac
    Pot             1a9d9058ea7ee7d9cd721b06a8bd152f
    Item            16ef353cee55599f3dce377f4518d7c4
    Preferences     023c41d49dc3434c0ddcf0d100af409b
    Budget          31f1527dee8b94eb3eb381a298292a56
    Notice          a9f89bc8a990644d06065c387ee6fe2f
    Round_up        bc3103a81537a1b2a340963bd1c60a37
    Top_up          a43157be3f76e6c4427036aa409d4b71
    Pot_job         695161404a1b6dd100ab55599d7c5154
    |}]
;;

let round_trip (type a) (module M : Binable.S with type t = a) ~equal (v : a) =
  assert (equal (Binable.of_string (module M) (Binable.to_string (module M) v)) v)
;;

let%expect_test "round trips" =
  let p = pot ~goal:(eur "10.00") () in
  round_trip (module Pot.Stable.V1) ~equal:Pot.equal p;
  round_trip
    (module Item.Stable.V1)
    ~equal:Item.equal
    (item ~refund_of:"x" ~amount:"1.00" (card ~category:"travel" "Rail"));
  let prefs =
    Preferences.set_merchant_rule Preferences.empty ~merchant:"Cafe" (Some (cat "gifts"))
  in
  let prefs = Preferences.set_payee_rule prefs (Name "landlord") (Some (cat "bills")) in
  round_trip (module Preferences.Stable.V1) ~equal:Preferences.equal prefs;
  print_s [%sexp (prefs : Preferences.t)];
  [%expect {|
    ((overrides ()) (merchants ((cafe gifts))) (payees (((Name landlord) bills)))
     (schedules ()))
    |}]
;;

(* Ids validate on decode, so hand-made bytes cannot carry an id the constructor refuses. *)
let%expect_test "decoding validates ids" =
  let bytes = Binable.to_string (module String) "has space" in
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Binable.of_string (module Pot_id.Stable.V1) bytes)
       |> Result.is_error
       : bool)];
  [%expect {| true |}]
;;
