open! Core

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Pending
        | Completed
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Payee = struct
  module Stable = struct
    module V1 = struct
      type t =
        { id : string option
        ; name : string
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Source = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Card of
            { merchant : string
            ; merchant_category : Category.Stable.V1.t option
            }
        | Payment of
            { payee : Payee.Stable.V1.t option
            ; schedule : string option
            }
        | Incoming of { payer : string option }
        | Internal
        | Other
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Stable = struct
  module V1 = struct
    type t =
      { id : Item_id.Stable.V1.t
      ; account : Ledger.Account_id.Stable.V1.t
      ; amount : Money.Amount.Stable.V1.t
      ; at : Time_ns.Stable.Alternate_sexp.V1.t
      ; description : string
      ; source : Source.Stable.V1.t
      ; refund_of : Item_id.Stable.V1.t option
      ; status : Status.Stable.V1.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

module Flow = struct
  type t =
    | Spending
    | Refund
    | Income
    | Internal
  [@@deriving sexp, compare, equal]
end

let flow t : Flow.t =
  match t.source with
  | Internal -> Internal
  | Card _ | Payment _ | Incoming _ | Other ->
    if Money.Amount.is_negative t.amount
    then Spending
    else (
      match t.refund_of, t.source with
      | Some _, _ | None, Card _ -> Refund
      | None, (Payment _ | Incoming _ | Other | Internal) -> Income)
;;

let merchant t =
  match t.source with
  | Card { merchant; _ } -> Some merchant
  | Payment _ | Incoming _ | Internal | Other -> None
;;

let payee t =
  match t.source with
  | Payment { payee; _ } -> payee
  | Card _ | Incoming _ | Internal | Other -> None
;;

let schedule t =
  match t.source with
  | Payment { schedule; _ } -> schedule
  | Card _ | Incoming _ | Internal | Other -> None
;;

let counts t = Status.equal t.status Completed
