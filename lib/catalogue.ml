open! Core

module Group = struct
  type t =
    | Spending
    | Income
    | Neutral
  [@@deriving sexp, compare, equal, enumerate]
end

type t =
  { categories : (Category.t * Group.t) list
  ; groups : Group.t Category.Map.t
  ; default : Category.t
  ; income : Category.t
  ; internal : Category.t
  }
[@@deriving sexp_of]

let create ~categories ~default ~income ~internal =
  let open Or_error.Let_syntax in
  let%bind groups =
    match Category.Map.of_alist categories with
    | `Ok m -> Ok m
    | `Duplicate_key c ->
      Or_error.error_s [%message "duplicate category" (c : Category.t)]
  in
  let check c expected =
    match Map.find groups c with
    | Some g when Group.equal g expected -> Ok ()
    | got ->
      Or_error.error_s
        [%message
          "category in the wrong group"
            (c : Category.t)
            (expected : Group.t)
            (got : Group.t option)]
  in
  let%bind () = check default Spending in
  let%bind () = check income Income in
  let%map () = check internal Neutral in
  { categories; groups; default; income; internal }
;;

let default =
  let c = Category.of_string in
  let spending =
    [ "groceries"
    ; "eating_out"
    ; "transport"
    ; "travel"
    ; "shopping"
    ; "entertainment"
    ; "bills"
    ; "health"
    ; "personal_care"
    ; "education"
    ; "gifts"
    ; "cash"
    ; "fees"
    ; "general"
    ]
  in
  create
    ~categories:
      (List.map spending ~f:(fun s -> c s, Group.Spending)
       @ [ c "income", Group.Income; c "transfers", Neutral ])
    ~default:(c "general")
    ~income:(c "income")
    ~internal:(c "transfers")
  |> Or_error.ok_exn
;;

let categories t = t.categories
let group t c = Map.find t.groups c
let is_spending t c = Option.equal Group.equal (group t c) (Some Spending)

let spending t =
  List.filter_map t.categories ~f:(fun (c, g) ->
    match g with
    | Spending -> Some c
    | Income | Neutral -> None)
;;

let default_category t = t.default
let income t = t.income
let internal t = t.internal
