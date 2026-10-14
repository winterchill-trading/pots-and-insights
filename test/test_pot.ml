open! Core
open Pots_and_insights
open Helpers

let show r =
  print_s
    (match r with
     | Ok (p : Pot.t) -> [%sexp Ok (p.details : Pot.Details.t)]
     | Error e -> [%sexp Error (e : Pot.Refusal.t), (Pot.Refusal.code e : string)])
;;

let create ?(open_pots = 0) ?max_name_bytes ?allow_past_target_date d =
  Pot.create
    ?max_name_bytes
    ?allow_past_target_date
    ~id:pot_id
    ~owner
    ~account
    ~currency:Money.Currency.eur
    ~open_pots
    ~today
    ~at:t0
    d
;;

let%expect_test "create trims the name and sorts cosmetics" =
  show
    (create
       (details
          ~goal:(eur "500.00")
          ~target_date:(date "2027-06-01")
          ~cosmetics:[ "icon", "\xf0\x9f\x8f\x96"; "colour", "teal" ]
          "  Holiday  "));
  [%expect
    {|
    (Ok
     ((name Holiday) (goal ("500.00 EUR")) (target_date (2027-06-01))
      (cosmetics ((colour teal) (icon "\240\159\143\150")))))
    |}]
;;

let%expect_test "refusals" =
  List.iter
    [ create (details "")
    ; create (details (String.make 31 'a'))
    ; create (details "Tab\there")
    ; create (details ~goal:(eur "0.00") "Goal")
    ; create (details ~goal:(Money.Amount.of_string "5.00 USD") "Goal")
    ; create (details ~target_date:(date "2026-10-13") "Late")
    ; create (details ~cosmetics:[ "Colour", "teal" ] "Bad key")
    ; create (details ~cosmetics:[ "icon", "a"; "icon", "b" ] "Dup")
    ; create (details ~cosmetics:[ "icon", String.make 17 'x' ] "Long icon")
    ; create ~open_pots:20 (details "One too many")
    ]
    ~f:show;
  [%expect
    {|
    ((Error (Name_invalid empty)) name_invalid)
    ((Error (Name_invalid too_long)) name_invalid)
    ((Error (Name_invalid control_character)) name_invalid)
    ((Error Goal_not_positive) goal_not_positive)
    ((Error (Goal_currency_mismatch (expected EUR))) goal_currency_mismatch)
    ((Error Target_date_in_past) target_date_in_past)
    ((Error (Cosmetic_invalid (key Colour) (reason key_not_slug)))
     cosmetic_invalid)
    ((Error (Cosmetic_invalid (key icon) (reason duplicate_key)))
     cosmetic_invalid)
    ((Error (Cosmetic_invalid (key icon) (reason too_long))) cosmetic_invalid)
    ((Error (Too_many_open_pots (max 20))) pots_limit)
    |}]
;;

let%expect_test "thirty code points of a multi-byte script fit" =
  (* 30 Cyrillic letters are 60 bytes; the limit counts code points. *)
  let name = String.concat (List.init 30 ~f:(fun _ -> "\xd0\xb6")) in
  print_s [%sexp (Text.code_points name : int option), (String.length name : int)];
  print_s [%sexp (Result.is_ok (create (details name)) : bool)];
  print_s [%sexp (Result.is_ok (create (details (name ^ "\xd0\xb6"))) : bool)];
  [%expect {|
    ((30) 60)
    true
    false
    |}]
;;

let%expect_test "a byte cap on names is optional" =
  (* 20 Cyrillic letters: 20 code points, 40 bytes. *)
  let name = String.concat (List.init 20 ~f:(fun _ -> "\xd0\xb6")) in
  let ok r = print_s [%sexp (Result.is_ok r : bool)] in
  ok (create (details name));
  ok (create ~max_name_bytes:40 (details name));
  show (create ~max_name_bytes:39 (details name));
  [%expect {|
    true
    true
    ((Error (Name_invalid too_long)) name_invalid)
    |}]
;;

let%expect_test "past target dates are accepted only when asked, for imports" =
  let d = details ~target_date:(date "2025-01-31") "Imported" in
  show (create d);
  show (create ~allow_past_target_date:false d);
  show (create ~allow_past_target_date:true d);
  let p = pot () in
  show (Pot.update p ~today d);
  show (Pot.update ~allow_past_target_date:true p ~today d);
  [%expect
    {|
    ((Error Target_date_in_past) target_date_in_past)
    ((Error Target_date_in_past) target_date_in_past)
    (Ok
     ((name Imported) (goal ()) (target_date (2025-01-31))
      (cosmetics ((colour teal)))))
    ((Error Target_date_in_past) target_date_in_past)
    (Ok
     ((name Imported) (goal ()) (target_date (2025-01-31))
      (cosmetics ((colour teal)))))
    |}]
;;

let%expect_test "update and close" =
  let p = pot () in
  show (Pot.update p ~today (details ~goal:(eur "100.00") "Renamed"));
  let closed = Pot.close p ~at:t0 |> Result.ok |> Option.value_exn in
  print_s [%sexp (closed.status : Pot.Status.t)];
  show (Pot.update closed ~today (details "Again"));
  print_s [%sexp (Pot.close closed ~at:t0 |> Result.error : Pot.Refusal.t option)];
  [%expect
    {|
    (Ok
     ((name Renamed) (goal ("100.00 EUR")) (target_date ())
      (cosmetics ((colour teal)))))
    (Closed (at "2026-10-14 09:00:00Z"))
    ((Error Pot_closed) pot_closed)
    (Already_closed)
    |}]
;;

let%expect_test "progress rounds down and caps at 100" =
  let p = pot ~goal:(eur "300.00") () in
  List.iter [ "0.00"; "1.00"; "299.99"; "300.00"; "450.00" ] ~f:(fun b ->
    print_s
      [%sexp
        (b : string), (Pot.progress p ~balance:(eur b) : Pot.Progress.t option Or_error.t)]);
  print_s
    [%sexp
      (Pot.progress (pot ()) ~balance:(eur "5.00") : Pot.Progress.t option Or_error.t)];
  [%expect
    {|
    (0.00 (Ok (((percent 0) (remaining "300.00 EUR") (reached false)))))
    (1.00 (Ok (((percent 0) (remaining "299.00 EUR") (reached false)))))
    (299.99 (Ok (((percent 99) (remaining "0.01 EUR") (reached false)))))
    (300.00 (Ok (((percent 100) (remaining "0.00 EUR") (reached true)))))
    (450.00 (Ok (((percent 100) (remaining "0.00 EUR") (reached true)))))
    (Ok ())
    |}]
;;

let%expect_test "ledger account" =
  print_s [%sexp (Pot.to_ledger_account (pot ()) : Ledger.Account.t)];
  [%expect
    {|
    ((id pot:pot-1) (kind Liability) (purpose Customer_funds)
     (allow_negative false)
     (tags ((owner customer-1) (parent customer:1/eur) (pot pot-1))))
    |}]
;;
