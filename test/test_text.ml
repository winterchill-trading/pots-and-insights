open! Core
open Pots_and_insights

let%expect_test "length is in code points; a byte cap is optional" =
  let show ?max_bytes s =
    print_s
      [%sexp
        (s : string)
        , (Text.code_points s : int option)
        , (String.length s : int)
        , (Text.clean ?max_bytes s ~max_code_points:4 : (string, string) Result.t)]
  in
  show "abcd";
  show "caf\xc3\xa9";
  (* Thumbs up with a skin tone: one visible character, two code points. *)
  show "\xf0\x9f\x91\x8d\xf0\x9f\x8f\xbd";
  show ~max_bytes:4 "caf\xc3\xa9";
  show ~max_bytes:5 "caf\xc3\xa9";
  show ~max_bytes:2 "  ab  ";
  [%expect
    {|
    (abcd (4) 4 (Ok abcd))
    ("caf\195\169" (4) 5 (Ok "caf\195\169"))
    ("\240\159\145\141\240\159\143\189" (2) 8
     (Ok "\240\159\145\141\240\159\143\189"))
    ("caf\195\169" (4) 5 (Error too_long))
    ("caf\195\169" (4) 5 (Ok "caf\195\169"))
    ("  ab  " (6) 6 (Ok ab))
    |}]
;;

let%test_unit "a byte cap never accepts more than the code point check alone" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 String.quickcheck_generator (Int.gen_incl 0 40))
    ~f:(fun (s, max_bytes) ->
      match Text.clean ~max_bytes s ~max_code_points:20 with
      | Ok cleaned ->
        assert (String.length cleaned <= max_bytes);
        [%test_result: (string, string) Result.t]
          (Text.clean s ~max_code_points:20)
          ~expect:(Ok cleaned)
      | Error _ -> ())
;;
