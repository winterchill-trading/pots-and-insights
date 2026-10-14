open! Core

type t =
  { account : Ledger.Account_id.t
  ; currency : Money.Currency.t
  ; month : Calendar_month.t
  ; current : bool
  ; overall : Budget.Progress.t option
  ; categories : Budget.Progress.t list
  ; spending : Money.Amount.t
  ; near_percent : int
  }
[@@deriving sexp, compare, equal]

let compute
  ?(near_percent = Budget.Limits.default.near_percent)
  (ctx : Insights.Context.t)
  ~budgets
  ~account
  ~currency
  ~month
  ~now
  items
  =
  let by_category, spending = Insights.spent ctx ~account ~currency ~month items in
  let zero = Money.Amount.zero currency in
  let mine =
    List.filter budgets ~f:(fun (b : Budget.t) ->
      Ledger.Account_id.equal b.account account
      && Money.Currency.equal b.currency currency)
  in
  let progress (b : Budget.t) =
    let spent =
      match b.target with
      | Overall -> spending
      | Category c -> Option.value (Map.find by_category c) ~default:zero
    in
    Budget.progress ~near_percent b ~month ~spent ~now
  in
  let overall =
    List.find_map mine ~f:(fun b ->
      match b.target with
      | Overall -> progress b
      | Category _ -> None)
  in
  let categories =
    List.filter_map (Catalogue.spending ctx.catalogue) ~f:(fun c ->
      List.find_map mine ~f:(fun b ->
        if Budget.Target.equal b.target (Category c) then progress b else None))
  in
  { account
  ; currency
  ; month
  ; current = Calendar_month.contains month now
  ; overall
  ; categories
  ; spending
  ; near_percent
  }
;;

let history ?near_percent ctx ~budgets ~account ~currency ~last ~months ~now items =
  List.map (Calendar_month.last_n last ~n:months) ~f:(fun month ->
    compute ?near_percent ctx ~budgets ~account ~currency ~month ~now items)
;;
