(** Checks on short user-typed text (names, cosmetic values). *)

open! Core

(** Number of Unicode code points; [None] when [s] is not valid UTF-8. *)
val code_points : string -> int option

(** [s] without leading and trailing whitespace, refused when it is empty, not UTF-8,
    longer than [max_code_points] or contains a control character. The error is a short
    reason: [empty], [not_utf8], [too_long] or [control_character]. *)
val clean : string -> max_code_points:int -> (string, string) Result.t

(** Lower case, every run of characters other than ASCII letters and digits turned into
    one space, trimmed: ["  ACME  Coffee-Shop #12 "] becomes ["acme coffee shop 12"]. The
    key merchant and payee rules and keyword matching compare on. Non-ASCII letters are
    kept as they are. *)
val match_key : string -> string
