open! Core

let max_length = 100

module type S = sig
  include Ledger.Validated_id.S

  val max_length : int
end

module Make (M : sig
    val module_name : string
  end) : S = struct
  let check s =
    Or_error.tag_s
      (if String.length s > max_length
       then Or_error.error_s [%message "too long" (max_length : int)]
       else Ledger.Validated_id.check s)
      ~tag:[%message M.module_name ~id:(s : string)]
  ;;

  let of_string_or_error s = Or_error.map (check s) ~f:(fun () -> s)

  module T = struct
    type t = string [@@deriving compare, equal, hash]

    let module_name = M.module_name
    let to_string t = t
    let of_string s = Or_error.ok_exn (of_string_or_error s)
    let sexp_of_t = sexp_of_string
    let t_of_sexp sexp = of_string (string_of_sexp sexp)

    (* Decoding validates again, so bytes written by hand cannot smuggle in an id the
       smart constructor would refuse. *)
    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (String)
        (struct
          type t = string

          let to_binable = Fn.id
          let of_binable = of_string
        end)
  end

  include T
  include Identifiable.Make (T)

  let max_length = max_length

  let quickcheck_generator =
    let open Quickcheck.Generator.Let_syntax in
    let%bind len = Int.gen_incl 1 24 in
    String.gen_with_length
      len
      (Quickcheck.Generator.of_list (String.to_list "abcxyz09-_"))
  ;;

  let quickcheck_observer = String.quickcheck_observer
  let quickcheck_shrinker : t Quickcheck.Shrinker.t = Quickcheck.Shrinker.empty ()

  module Stable = struct
    module V1 = T
  end
end
