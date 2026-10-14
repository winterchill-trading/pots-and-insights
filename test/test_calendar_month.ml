open! Core
open Pots_and_insights
module M = Calendar_month

let m s = Or_error.ok_exn (M.of_string s)
let time s = Time_ns.of_string_with_utc_offset s

let%expect_test "boundaries are midnight UTC" =
  let t = m "2024-02" in
  print_s
    [%message
      ""
        ~days:(M.days t : int)
        ~first:(M.first_day t : Date.t)
        ~last:(M.last_day t : Date.t)
        ~start:(Time_ns.to_string_iso8601_basic (M.start t) ~zone:Time_float.Zone.utc)
        ~stop:(Time_ns.to_string_iso8601_basic (M.stop t) ~zone:Time_float.Zone.utc)];
  [%expect
    {|
    ((days 29) (first 2024-02-01) (last 2024-02-29)
     (start 2024-02-01T00:00:00.000000000Z)
     (stop 2024-03-01T00:00:00.000000000Z))
    |}];
  (* 01:30 on 1 March at UTC+02:00 is 23:30 on 29 February in UTC. *)
  print_s [%sexp (M.of_time (time "2024-03-01 01:30:00+02:00") : M.t)];
  [%expect {| 2024-02 |}];
  print_s [%sexp (M.elapsed t ~now:(time "2024-02-10 12:00:00Z") : (int * int) option)];
  print_s [%sexp (M.elapsed t ~now:(time "2024-03-01 00:00:00Z") : (int * int) option)];
  [%expect {|
    ((10 29))
    () |}]
;;

let%expect_test "arithmetic across years" =
  let t = m "2026-01" in
  print_s [%sexp (M.prev t : M.t), (M.add t 11 : M.t), (M.add t 12 : M.t)];
  print_s [%sexp (M.last_n t ~n:3 : M.t list)];
  print_s [%sexp (M.months_between (m "2025-11") t : int)];
  [%expect {|
    (2025-12 2026-12 2027-01)
    (2025-11 2025-12 2026-01)
    2 |}]
;;

let%expect_test "parsing" =
  List.iter [ "2026-10"; "2026-13"; "2026-1"; "26-10"; "2026/10"; "0000-01" ] ~f:(fun s ->
    print_s [%sexp (s : string), (M.of_string s : M.t Or_error.t)]);
  [%expect
    {|
    (2026-10 (Ok 2026-10))
    (2026-13 (Error ("expected YYYY-MM" (got 2026-13))))
    (2026-1 (Error ("expected YYYY-MM" (got 2026-1))))
    (26-10 (Error ("expected YYYY-MM" (got 26-10))))
    (2026/10 (Error ("expected YYYY-MM" (got 2026/10))))
    (0000-01 (Error ("year out of range" (year 0))))
    |}]
;;

let%test_unit "every instant of a month maps back to it" =
  Quickcheck.test
    (Quickcheck.Generator.both M.quickcheck_generator (Int.gen_incl 0 (31 * 86_400 - 1)))
    ~f:(fun (t, seconds) ->
      let time = Time_ns.add (M.start t) (Time_ns.Span.of_int_sec seconds) in
      [%test_result: bool]
        (M.contains t time)
        ~expect:(Time_ns.( < ) time (M.stop t));
      if M.contains t time then [%test_result: M.t] (M.of_time time) ~expect:t)
;;

let%test_unit "text and bin_prot round trip" =
  Quickcheck.test M.quickcheck_generator ~f:(fun t ->
    [%test_result: M.t] (Or_error.ok_exn (M.of_string (M.to_string t))) ~expect:t;
    [%test_result: M.t]
      (Binable.of_string (module M.Stable.V1) (Binable.to_string (module M.Stable.V1) t))
      ~expect:t)
;;
