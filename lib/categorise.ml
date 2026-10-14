open! Core

module Source = struct
  type t =
    | Override
    | Merchant_rule
    | Schedule
    | Payee_rule
    | Keyword of string
    | Merchant
    | Default
    | Purchase
    | Income
    | Internal
  [@@deriving sexp, compare, equal]

  let name = function
    | Override -> "override"
    | Merchant_rule -> "merchant_rule"
    | Schedule -> "schedule"
    | Payee_rule -> "payee_rule"
    | Keyword _ -> "keyword"
    | Merchant -> "merchant"
    | Default -> "default"
    | Purchase -> "purchase"
    | Income -> "income"
    | Internal -> "internal"
  ;;

  let is_user = function
    | Override | Merchant_rule | Schedule | Payee_rule -> true
    | Keyword _ | Merchant | Default | Purchase | Income | Internal -> false
  ;;
end

module Assignment = struct
  type t =
    { category : Category.t
    ; source : Source.t
    ; automatic : Category.t
    ; automatic_source : Source.t
    ; recategorisable : bool
    }
  [@@deriving sexp, compare, equal]
end

(* The automatic part of the order: keyword, then merchant category, then default. *)
let automatic catalogue keywords (item : Item.t) =
  let texts =
    item.description
    :: List.filter_opt
         [ Item.merchant item; Option.map (Item.payee item) ~f:(fun p -> p.name) ]
  in
  let usable c = Catalogue.is_spending catalogue c in
  match
    List.find_map texts ~f:(fun text ->
      match Keywords.find keywords text with
      | Some (keyword, c) when usable c -> Some (c, Source.Keyword keyword)
      | _ -> None)
  with
  | Some found -> found
  | None ->
    (match item.source with
     | Card { merchant_category = Some c; _ } when usable c -> c, Source.Merchant
     | _ -> Catalogue.default_category catalogue, Source.Default)
;;

let user catalogue prefs (item : Item.t) =
  let usable = Option.filter ~f:(Catalogue.is_spending catalogue) in
  let first =
    [ (fun () -> usable (Preferences.override prefs item.id), Source.Override)
    ; (fun () ->
        ( usable
            (Option.bind (Item.merchant item) ~f:(fun merchant ->
               Preferences.merchant_rule prefs ~merchant))
        , Merchant_rule ))
    ; (fun () ->
        ( usable
            (Option.bind (Item.schedule item) ~f:(fun schedule ->
               Preferences.schedule_category prefs ~schedule))
        , Schedule ))
    ; (fun () ->
        ( usable (Option.bind (Item.payee item) ~f:(Preferences.payee_rule prefs))
        , Payee_rule ))
    ]
  in
  List.find_map first ~f:(fun f ->
    let c, source = f () in
    Option.map c ~f:(fun c -> c, source))
;;

let spending catalogue keywords prefs item =
  let automatic, automatic_source = automatic catalogue keywords item in
  let category, source =
    Option.value (user catalogue prefs item) ~default:(automatic, automatic_source)
  in
  { Assignment.category; source; automatic; automatic_source; recategorisable = true }
;;

let fixed category source =
  { Assignment.category
  ; source
  ; automatic = category
  ; automatic_source = source
  ; recategorisable = false
  }
;;

let assign catalogue keywords prefs ?original (item : Item.t) =
  match Item.flow item with
  | Internal -> fixed (Catalogue.internal catalogue) Internal
  | Income -> fixed (Catalogue.income catalogue) Income
  | Spending -> spending catalogue keywords prefs item
  | Refund ->
    let base =
      match original with
      | Some (original : Item.t)
        when Option.equal Item_id.equal item.refund_of (Some original.id) ->
        let a = spending catalogue keywords prefs original in
        { a with source = Purchase }
      | _ ->
        (* No purchase to follow: file it like a purchase from the same merchant, but
           without an override of its own. *)
        spending catalogue keywords (Preferences.set_override prefs item.id None) item
    in
    { base with recategorisable = false }
;;

let assign_all catalogue keywords prefs items =
  let by_id =
    Item_id.Map.of_alist_reduce
      (List.map items ~f:(fun (i : Item.t) -> i.id, i))
      ~f:(fun first _ -> first)
  in
  List.map items ~f:(fun (item : Item.t) ->
    let original = Option.bind item.refund_of ~f:(Map.find by_id) in
    item, assign catalogue keywords prefs ?original item)
;;

module Refusal = struct
  type t =
    | Unknown_category
    | Spending_only
    | Refund_follows_purchase
    | Nothing_to_match
  [@@deriving sexp, compare, equal]

  let code = function
    | Unknown_category -> "unknown_category"
    | Spending_only -> "spending_only"
    | Refund_follows_purchase -> "refund_follows_purchase"
    | Nothing_to_match -> "nothing_to_match"
  ;;
end

module Scope = struct
  type t =
    | One
    | All_from_merchant
    | All_from_payee
  [@@deriving sexp, compare, equal, enumerate]
end

let check_category catalogue = function
  | Some c when not (Catalogue.is_spending catalogue c) -> Error Refusal.Unknown_category
  | _ -> Ok ()
;;

let recategorise catalogue prefs (item : Item.t) scope category =
  let open Result.Let_syntax in
  let%bind () = check_category catalogue category in
  let%bind () =
    match Item.flow item with
    | Spending -> Ok ()
    | Refund -> Error Refusal.Refund_follows_purchase
    | Income | Internal -> Error Refusal.Spending_only
  in
  match (scope : Scope.t) with
  | One -> Ok (Preferences.set_override prefs item.id category)
  | All_from_merchant ->
    (match Item.merchant item with
     | None -> Error Refusal.Nothing_to_match
     | Some merchant ->
       Ok
         (Preferences.set_merchant_rule
            (Preferences.set_override prefs item.id None)
            ~merchant
            category))
  | All_from_payee ->
    (match Item.payee item with
     | None -> Error Refusal.Nothing_to_match
     | Some payee ->
       Ok
         (Preferences.set_payee_rule
            (Preferences.set_override prefs item.id None)
            (Preferences.Payee_key.of_payee payee)
            category))
;;

let set_schedule_category catalogue prefs ~schedule category =
  Result.map (check_category catalogue category) ~f:(fun () ->
    Preferences.set_schedule_category prefs ~schedule category)
;;

let set_payee_category catalogue prefs key category =
  Result.map (check_category catalogue category) ~f:(fun () ->
    Preferences.set_payee_rule prefs key category)
;;
