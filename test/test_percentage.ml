open! Core
open Pots_and_insights

let%expect_test "rounding half away from zero" =
  List.iter
    [ 1, 3; 2, 3; 1, 2000; 1, 1999; -1, 2000; 5, 4; 0, 7; 1, 0 ]
    ~f:(fun (n, d) ->
      print_s
        [%sexp
          (n : int)
          , (d : int)
          , (Percentage.of_ratio ~num:(Z.of_int n) ~den:(Z.of_int d)
             : Percentage.t Or_error.t)]);
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

let%expect_test "half even rounding settles exact halves on the even tenth" =
  List.iter
    [ 1, 2000; 3, 2000; -1, 2000; -3, 2000; 1, 3; 2, 3; 1, 1999 ]
    ~f:(fun (n, d) ->
      let r rounding =
        Percentage.of_ratio_rounded ~rounding ~num:(Z.of_int n) ~den:(Z.of_int d)
        |> ok_exn
      in
      print_s
        [%sexp
          (n : int)
          , (d : int)
          , (r Half_away_from_zero : Percentage.t)
          , (r Half_even : Percentage.t)]);
  [%expect
    {|
    (1 2000 0.1 0.0)
    (3 2000 0.2 0.2)
    (-1 2000 -0.1 0.0)
    (-3 2000 -0.2 -0.2)
    (1 3 33.3 33.3)
    (2 3 66.7 66.7)
    (1 1999 0.1 0.1)
    |}]
;;

let%test_unit "the modes differ only on exact halves, by one tenth at most" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2
       (Int.gen_incl (-1_000_000) 1_000_000)
       (Int.gen_incl 1 1_000_000))
    ~f:(fun (n, d) ->
      let r rounding =
        Percentage.of_ratio_rounded ~rounding ~num:(Z.of_int n) ~den:(Z.of_int d)
        |> ok_exn
        |> Percentage.to_tenths
      in
      let away = r Half_away_from_zero
      and even = r Half_even in
      let is_half = n * 1000 * 2 mod d = 0 && n * 1000 * 2 / d mod 2 <> 0 in
      if is_half
      then (
        assert (Int.abs (away - even) <= 1);
        assert (even mod 2 = 0))
      else [%test_result: int] even ~expect:away)
;;

let%test_unit "the default is half away from zero" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2
       (Int.gen_incl (-100_000) 100_000)
       (Int.gen_incl 1 100_000))
    ~f:(fun (n, d) ->
      let num = Z.of_int n
      and den = Z.of_int d in
      [%test_result: Percentage.t Or_error.t]
        (Percentage.of_ratio ~num ~den)
        ~expect:(Percentage.of_ratio_rounded ~rounding:Half_away_from_zero ~num ~den))
;;
