open! Core
module Amount = Money.Amount

module Context = struct
  type t =
    { catalogue : Catalogue.t
    ; keywords : Keywords.t
    ; preferences : Preferences.t
    }

  let default =
    { catalogue = Catalogue.default
    ; keywords = Keywords.default
    ; preferences = Preferences.empty
    }
  ;;
end

module Category_total = struct
  type t =
    { category : Category.t
    ; total : Amount.t
    ; previous_total : Amount.t
    ; change : Amount.t
    ; share : Percentage.t option
    ; count : int
    }
  [@@deriving sexp_of, compare, equal]
end

module Merchant_total = struct
  type t =
    { name : string
    ; category : Category.t
    ; total : Amount.t
    ; count : int
    }
  [@@deriving sexp_of, compare, equal]
end

module Flow_month = struct
  type t =
    { month : Calendar_month.t
    ; money_in : Amount.t
    ; money_out : Amount.t
    ; net : Amount.t
    }
  [@@deriving sexp_of, compare, equal]
end

type t =
  { account : Ledger.Account_id.t
  ; currency : Money.Currency.t
  ; month : Calendar_month.t
  ; spending : Amount.t
  ; previous_spending : Amount.t
  ; categories : Category_total.t list
  ; money_in : Amount.t
  ; money_out : Amount.t
  ; flow : Flow_month.t list
  ; top_merchants : Merchant_total.t list
  }
[@@deriving sexp_of, compare, equal]

let relevant ~account ~currency (i : Item.t) =
  Item.counts i
  && Ledger.Account_id.equal i.account account
  && Money.Currency.equal (Amount.currency i.amount) currency
;;

(* Items of the account, categorised once over the whole list so refunds find their
   purchases even across months. *)
let categorised (ctx : Context.t) ~account ~currency items =
  List.filter items ~f:(relevant ~account ~currency)
  |> Categorise.assign_all ctx.catalogue ctx.keywords ctx.preferences
;;

let in_month month (i, _) = Calendar_month.contains month (i : Item.t).at

(* Spending contribution: purchases add, refunds subtract; other flows add nothing. *)
let spend_of (i : Item.t) =
  match Item.flow i with
  | Spending | Refund -> Some (Amount.neg i.amount)
  | Income | Internal -> None
;;

let by_category ~currency pairs =
  List.fold
    pairs
    ~init:Category.Map.empty
    ~f:(fun acc ((i : Item.t), (a : Categorise.Assignment.t)) ->
      match spend_of i with
      | None -> acc
      | Some spend ->
        let is_purchase = Item.Flow.equal (Item.flow i) Spending in
        Map.update acc a.category ~f:(fun prev ->
          let total, count = Option.value prev ~default:(Amount.zero currency, 0) in
          Amount.add_exn total spend, if is_purchase then count + 1 else count))
;;

let sum currency amounts =
  List.fold amounts ~init:(Amount.zero currency) ~f:Amount.add_exn
;;

let flow_of ~currency month pairs =
  let pairs = List.filter pairs ~f:(in_month month) in
  let external_ =
    List.filter_map pairs ~f:(fun ((i : Item.t), _) ->
      match Item.flow i with
      | Internal -> None
      | Spending | Refund | Income -> Some i.amount)
  in
  let money_in = sum currency (List.filter external_ ~f:Amount.is_positive) in
  let money_out =
    sum currency (List.filter external_ ~f:Amount.is_negative |> List.map ~f:Amount.neg)
  in
  { Flow_month.month; money_in; money_out; net = Amount.sub_exn money_in money_out }
;;

let catalogue_rank (ctx : Context.t) =
  let ranks =
    List.mapi (Catalogue.categories ctx.catalogue) ~f:(fun i (c, _) -> c, i)
    |> Category.Map.of_alist_reduce ~f:Int.min
  in
  fun c -> Option.value (Map.find ranks c) ~default:Int.max_value
;;

let rank_merchants ~limit pairs =
  List.fold
    pairs
    ~init:String.Map.empty
    ~f:(fun acc ((i : Item.t), (a : Categorise.Assignment.t)) ->
      match Item.merchant i, spend_of i with
      | Some name, Some spend ->
        let key = Text.match_key name in
        let is_purchase = Item.Flow.equal (Item.flow i) Spending in
        Map.update acc key ~f:(function
          | None ->
            ( i.at
            , { Merchant_total.name
              ; category = a.category
              ; total = spend
              ; count = Bool.to_int is_purchase
              } )
          | Some (latest, m) ->
            let newer = Time_ns.( >= ) i.at latest in
            ( (if newer then i.at else latest)
            , { name = (if newer then name else m.name)
              ; category = (if newer then a.category else m.category)
              ; total = Amount.add_exn m.total spend
              ; count = m.count + Bool.to_int is_purchase
              } ))
      | _ -> acc)
  |> Map.data
  |> List.map ~f:snd
  |> List.filter ~f:(fun (m : Merchant_total.t) -> Amount.is_positive m.total)
  |> List.sort ~compare:(fun (a : Merchant_total.t) b ->
    match Amount.compare b.total a.total with
    | 0 -> String.compare a.name b.name
    | c -> c)
  |> Fn.flip List.take limit
;;

let summarise
  ?(flow_months = 6)
  ?(top_merchants = 5)
  ?(share_rounding = Percentage.Rounding.default)
  ctx
  ~account
  ~currency
  ~month
  items
  =
  let pairs = categorised ctx ~account ~currency items in
  let this = List.filter pairs ~f:(in_month month) in
  let before = List.filter pairs ~f:(in_month (Calendar_month.prev month)) in
  let now_totals = by_category ~currency this in
  let prev_totals = by_category ~currency before in
  let spending = sum currency (Map.data now_totals |> List.map ~f:fst) in
  let previous_spending = sum currency (Map.data prev_totals |> List.map ~f:fst) in
  let zero = Amount.zero currency in
  let rank = catalogue_rank ctx in
  let categories =
    Map.merge now_totals prev_totals ~f:(fun ~key:category data ->
      let (total, count), previous_total =
        match data with
        | `Both (now, (prev, _)) -> now, prev
        | `Left now -> now, zero
        | `Right (prev, _) -> (zero, 0), prev
      in
      let share =
        if Amount.is_positive spending
        then
          Percentage.of_ratio_rounded
            ~rounding:share_rounding
            ~num:(Amount.minor_units total)
            ~den:(Amount.minor_units spending)
          |> Result.ok
        else None
      in
      Some
        { Category_total.category
        ; total
        ; previous_total
        ; change = Amount.sub_exn total previous_total
        ; share
        ; count
        })
    |> Map.data
    |> List.sort ~compare:(fun (a : Category_total.t) b ->
      match Amount.compare b.total a.total with
      | 0 -> Int.compare (rank a.category) (rank b.category)
      | c -> c)
  in
  let this_flow = flow_of ~currency month pairs in
  { account
  ; currency
  ; month
  ; spending
  ; previous_spending
  ; categories
  ; money_in = this_flow.money_in
  ; money_out = this_flow.money_out
  ; flow =
      List.map (Calendar_month.last_n month ~n:flow_months) ~f:(fun m ->
        flow_of ~currency m pairs)
  ; top_merchants = rank_merchants ~limit:top_merchants this
  }
;;

let spent ctx ~account ~currency ~month items =
  let totals =
    categorised ctx ~account ~currency items
    |> List.filter ~f:(in_month month)
    |> by_category ~currency
    |> Map.map ~f:(fun (total, _) ->
      if Amount.is_negative total then Amount.zero currency else total)
  in
  totals, sum currency (Map.data totals)
;;

let items ?category ctx ~account ~currency ~month items =
  categorised ctx ~account ~currency items
  |> List.filter ~f:(in_month month)
  |> List.filter ~f:(fun (_, (a : Categorise.Assignment.t)) ->
    Option.for_all category ~f:(Category.equal a.category))
  |> List.stable_sort ~compare:(fun ((a : Item.t), _) ((b : Item.t), _) ->
    Time_ns.compare b.at a.at)
;;

let months_with_data ~account ~currency items =
  List.filter items ~f:(fun (i : Item.t) ->
    relevant ~account ~currency i && not (Item.Flow.equal (Item.flow i) Internal))
  |> List.map ~f:(fun (i : Item.t) -> Calendar_month.of_time i.at)
  |> List.dedup_and_sort ~compare:Calendar_month.compare
;;
