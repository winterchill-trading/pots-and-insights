open! Core

module Payee_key = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Id of string
        | Name of string
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
  include Comparable.Make (Stable.V1)

  let of_payee (p : Item.Payee.t) =
    match p.id with
    | Some id -> Id id
    | None -> Name (Text.match_key p.name)
  ;;
end

type t =
  { overrides : Category.t Item_id.Map.t
  ; merchants : Category.t String.Map.t
  ; payees : Category.t Payee_key.Map.t
  ; schedules : Category.t String.Map.t
  }
[@@deriving compare, equal]

let empty =
  { overrides = Item_id.Map.empty
  ; merchants = String.Map.empty
  ; payees = Payee_key.Map.empty
  ; schedules = String.Map.empty
  }
;;

let override t id = Map.find t.overrides id
let merchant_rule t ~merchant = Map.find t.merchants (Text.match_key merchant)
let payee_rule t payee = Map.find t.payees (Payee_key.of_payee payee)
let schedule_category t ~schedule = Map.find t.schedules schedule

let change map key = function
  | None -> Map.remove map key
  | Some c -> Map.set map ~key ~data:c
;;

let set_override t id c = { t with overrides = change t.overrides id c }

let set_merchant_rule t ~merchant c =
  { t with merchants = change t.merchants (Text.match_key merchant) c }
;;

let set_payee_rule t key c = { t with payees = change t.payees key c }

let set_schedule_category t ~schedule c =
  { t with schedules = change t.schedules schedule c }
;;

let overrides t = Map.to_alist t.overrides
let merchant_rules t = Map.to_alist t.merchants
let payee_rules t = Map.to_alist t.payees
let schedule_categories t = Map.to_alist t.schedules

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { overrides : (Item_id.Stable.V1.t * Category.Stable.V1.t) list
        ; merchants : (string * Category.Stable.V1.t) list
        ; payees : (Payee_key.Stable.V1.t * Category.Stable.V1.t) list
        ; schedules : (string * Category.Stable.V1.t) list
        }
      [@@deriving bin_io, sexp]
    end

    type nonrec t = t [@@deriving compare, equal]

    let to_wire t : Wire.t =
      { overrides = overrides t
      ; merchants = merchant_rules t
      ; payees = payee_rules t
      ; schedules = schedule_categories t
      }
    ;;

    (* Later duplicates win, the way a sequence of [set_*] calls would. *)
    let of_wire (w : Wire.t) =
      { overrides = Item_id.Map.of_alist_reduce w.overrides ~f:(fun _ b -> b)
      ; merchants = String.Map.of_alist_reduce w.merchants ~f:(fun _ b -> b)
      ; payees = Payee_key.Map.of_alist_reduce w.payees ~f:(fun _ b -> b)
      ; schedules = String.Map.of_alist_reduce w.schedules ~f:(fun _ b -> b)
      }
    ;;

    let sexp_of_t t = Wire.sexp_of_t (to_wire t)
    let t_of_sexp s = of_wire (Wire.t_of_sexp s)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable = to_wire
          let of_binable = of_wire
        end)
  end
end

let sexp_of_t = Stable.V1.sexp_of_t
let t_of_sexp = Stable.V1.t_of_sexp
