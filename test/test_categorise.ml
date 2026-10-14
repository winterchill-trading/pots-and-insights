open! Core
open Pots_and_insights
open Helpers

let catalogue = Catalogue.default
let keywords = Keywords.default

let show ?(prefs = Preferences.empty) ?original i =
  let a = Categorise.assign catalogue keywords prefs ?original i in
  print_s
    [%sexp
      (a.category : Category.t)
      , (Categorise.Source.name a.source : string)
      , (a.automatic : Category.t)
      , (a.recategorisable : bool)]
;;

let%expect_test "automatic order: keyword, merchant category, default" =
  show (item ~amount:"-12.00" (card ~category:"groceries" "Corner Cafe"));
  show (item ~amount:"-12.00" (card ~category:"groceries" "Corner Store"));
  show (item ~amount:"-12.00" (card "Corner Store"));
  show (item ~amount:"-900.00" ~description:"MONTHLY RENT - FLAT 2" (payment "Landlord"));
  show (item ~amount:"-9.00" ~description:"Parent club" (payment "Club"));
  show (item ~amount:"-40.00" ~description:"ATM 42" Other);
  [%expect
    {|
    (eating_out keyword eating_out true)
    (groceries merchant groceries true)
    (general default general true)
    (bills keyword bills true)
    (general default general true)
    (cash keyword cash true)
    |}]
;;

let%expect_test "income, internal and refunds" =
  let purchase = item ~id:"p1" ~amount:"-30.00" (card ~category:"shopping" "Shoe Shop") in
  let refund = item ~id:"r1" ~amount:"10.00" ~refund_of:"p1" (card "Shoe Shop") in
  let prefs =
    Preferences.set_override Preferences.empty (Item_id.of_string "p1") (Some (cat "gifts"))
  in
  show (item ~amount:"2500.00" ~description:"Salary" (Incoming { payer = Some "Employer" }));
  show (item ~amount:"-50.00" Internal);
  show ~prefs ~original:purchase refund;
  (* Without its purchase, a refund is filed like a purchase from its merchant. *)
  show ~prefs (item ~id:"r2" ~amount:"10.00" (card ~category:"shopping" "Shoe Shop"));
  [%expect
    {|
    (income income income false)
    (transfers internal transfers false)
    (gifts purchase shopping false)
    (shopping merchant shopping false)
    |}]
;;

let%expect_test "user choices and their precedence" =
  let coffee = item ~id:"c1" ~amount:"-3.50" (card ~category:"eating_out" "ACME Coffee #12") in
  let rent =
    item
      ~id:"s1"
      ~amount:"-900.00"
      ~description:"Rent"
      (payment ~payee_id:"payee-7" ~schedule:"so-1" "Landlord Ltd")
  in
  let ok r = Result.ok r |> Option.value_exn in
  let prefs =
    Categorise.recategorise catalogue Preferences.empty coffee All_from_merchant (Some (cat "groceries"))
    |> ok
  in
  (* The rule matches the merchant by its match key, not the exact text. *)
  show ~prefs coffee;
  show ~prefs (item ~id:"c2" ~amount:"-4.00" (card "acme coffee 12"));
  let prefs = Categorise.recategorise catalogue prefs coffee One (Some (cat "gifts")) |> ok in
  show ~prefs coffee;
  let prefs =
    Categorise.set_payee_category catalogue prefs (Id "payee-7") (Some (cat "health")) |> ok
  in
  show ~prefs rent;
  let prefs =
    Categorise.set_schedule_category catalogue prefs ~schedule:"so-1" (Some (cat "education"))
    |> ok
  in
  show ~prefs rent;
  let prefs = Categorise.recategorise catalogue prefs rent One None |> ok in
  show ~prefs rent;
  [%expect
    {|
    (groceries merchant_rule eating_out true)
    (groceries merchant_rule general true)
    (gifts override eating_out true)
    (health payee_rule bills true)
    (education schedule bills true)
    (education schedule bills true)
    |}]
;;

let%expect_test "a wider scope replaces the item's own override" =
  let coffee = item ~id:"c1" ~amount:"-3.50" (card "Cafe Blue") in
  let ok r = Result.ok r |> Option.value_exn in
  let prefs =
    Categorise.recategorise catalogue Preferences.empty coffee One (Some (cat "gifts")) |> ok
  in
  let prefs =
    Categorise.recategorise catalogue prefs coffee All_from_merchant (Some (cat "shopping"))
    |> ok
  in
  show ~prefs coffee;
  print_s [%sexp (prefs : Preferences.t)];
  [%expect
    {|
    (shopping merchant_rule eating_out true)
    ((overrides ()) (merchants (("cafe blue" shopping))) (payees ())
     (schedules ()))
    |}]
;;

let%expect_test "refusals" =
  let r i scope c =
    print_s
      [%sexp
        (Categorise.recategorise catalogue Preferences.empty i scope c
         |> Result.error
         |> Option.map ~f:Categorise.Refusal.code
         : string option)]
  in
  let spend = item ~amount:"-3.00" (card "Shop") in
  r spend One (Some (cat "income"));
  r spend One (Some (cat "no_such_thing"));
  r (item ~amount:"3.00" (Incoming { payer = None })) One (Some (cat "gifts"));
  r (item ~amount:"3.00" ~refund_of:"x" (card "Shop")) One (Some (cat "gifts"));
  r (item ~amount:"-3.00" Other) All_from_merchant (Some (cat "gifts"));
  r spend All_from_payee (Some (cat "gifts"));
  r spend All_from_merchant None;
  [%expect
    {|
    (unknown_category)
    (unknown_category)
    (spending_only)
    (refund_follows_purchase)
    (nothing_to_match)
    (nothing_to_match)
    ()
    |}]
;;

let%expect_test "assign_all pairs refunds with their purchases" =
  let items =
    [ item ~id:"p1" ~amount:"-30.00" (card ~category:"travel" "Rail Co")
    ; item ~id:"r1" ~amount:"30.00" ~refund_of:"p1" (card "Rail Co")
    ]
  in
  let prefs =
    Preferences.set_merchant_rule Preferences.empty ~merchant:"Rail Co" (Some (cat "transport"))
  in
  List.iter (Categorise.assign_all catalogue keywords prefs items) ~f:(fun (i, a) ->
    print_s [%sexp (i.id : Item_id.t), (a.category : Category.t), (Categorise.Source.name a.source : string)]);
  [%expect {|
    (p1 transport merchant_rule)
    (r1 transport purchase) |}]
;;

let%test_unit "every item gets a category of the right group" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind cents = Int.gen_incl (-100_000) 100_000 in
    let%bind merchant = Quickcheck.Generator.of_list [ "Cafe"; "Rent Co"; "Shop" ] in
    let%bind hint = Option.quickcheck_generator Category.quickcheck_generator in
    let%bind source =
      Quickcheck.Generator.of_list
        [ card ?category:(Option.map hint ~f:Category.to_string) merchant
        ; payment merchant
        ; Incoming { payer = None }
        ; Internal
        ; Other
        ]
    in
    let%map override = Option.quickcheck_generator Category.quickcheck_generator in
    ( item ~amount:(Money.Amount.to_decimal_string (Money.Amount.of_minor_units_int Money.Currency.eur cents)) source
    , override )
  in
  Quickcheck.test gen ~f:(fun (i, override) ->
    let prefs = Preferences.set_override Preferences.empty i.id override in
    let a = Categorise.assign catalogue keywords prefs i in
    let expected : Catalogue.Group.t =
      match Item.flow i with
      | Spending | Refund -> Spending
      | Income -> Income
      | Internal -> Neutral
    in
    [%test_result: Catalogue.Group.t option] (Catalogue.group catalogue a.category) ~expect:(Some expected);
    [%test_result: bool] a.recategorisable ~expect:(Item.Flow.equal (Item.flow i) Spending))
;;
