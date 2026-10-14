open! Core

type entry =
  { keyword : string
  ; key : string (* " " ^ match key ^ " ", for whole-word search *)
  ; category : Category.t
  }
[@@deriving sexp_of]

type t = entry list [@@deriving sexp_of]

let padded s = " " ^ Text.match_key s ^ " "

let create entries =
  List.map entries ~f:(fun (keyword, category) ->
    if String.is_empty (Text.match_key keyword)
    then Or_error.error_s [%message "empty keyword" (keyword : string)]
    else Ok { keyword; key = padded keyword; category })
  |> Or_error.all
;;

let empty = []

let default =
  let c = Category.of_string in
  create
    [ "cash withdrawal", c "cash"
    ; "atm", c "cash"
    ; "rent", c "bills"
    ; "electricity", c "bills"
    ; "water", c "bills"
    ; "insurance", c "bills"
    ; "broadband", c "bills"
    ; "mobile", c "bills"
    ; "council tax", c "bills"
    ; "pharmacy", c "health"
    ; "dentist", c "health"
    ; "taxi", c "transport"
    ; "parking", c "transport"
    ; "fuel", c "transport"
    ; "railway", c "transport"
    ; "hotel", c "travel"
    ; "airline", c "travel"
    ; "restaurant", c "eating_out"
    ; "cafe", c "eating_out"
    ; "supermarket", c "groceries"
    ; "tuition", c "education"
    ]
  |> Or_error.ok_exn
;;

let find t text =
  let text = padded text in
  List.find_map t ~f:(fun e ->
    if String.is_substring text ~substring:e.key
    then Some (e.keyword, e.category)
    else None)
;;

let to_list t = List.map t ~f:(fun e -> e.keyword, e.category)
