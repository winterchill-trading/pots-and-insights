open! Core
open Pots_and_insights

let%expect_test "rounding half away from zero" =
  List.iter [ 1, 3; 2, 3; 1, 2000; 1, 1999; -1, 2000; 5, 4; 0, 7; 1, 0 ] ~f:(fun (n, d) ->
    print_s
      [%sexp
        (n : int)
        , (d : int)
        , (Percentage.of_ratio ~num:(Z.of_int n) ~den:(Z.of_int d) : Percentage.t Or_error.t)]);
  [%expect
    {|
    (1 3 (Ok 33.3))
    (2 3 (Ok 66.7))
    (1 2000 (Ok 0.1))
    (1 1999 (Ok 0.1))
    (-1 2000 (Ok -0.1))
    (5 4 (Ok 125.0))
    (0 7 (Ok 0.0))
    (1 0 (Error "Percentage.of_ratio: zero denominator"))
    |}]
;;

let%test_unit "sexp round trip" =
  Quickcheck.test (Int.gen_incl (-100_000) 100_000) ~f:(fun n ->
    let p = Percentage.of_tenths n in
    [%test_result: Percentage.t] (Percentage.t_of_sexp (Percentage.sexp_of_t p)) ~expect:p)
;;
