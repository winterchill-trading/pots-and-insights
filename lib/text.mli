(** Checks on short user-typed text (names, cosmetic values). *)

open! Core

(** Number of Unicode code points; [None] when [s] is not valid UTF-8. *)
val code_points : string -> int option

(** [s] without leading and trailing whitespace, refused when it is empty, not UTF-8,
    longer than [max_code_points] or [max_bytes] (no byte cap by default) or contains a
    control character. The error is a short reason: [empty], [not_utf8], [too_long] or
    [control_character].

    Length is counted in Unicode code points, not in user-perceived characters: an emoji
    with a skin tone is 2 code points, a flag is 2, a family emoji joined with zero-width
    joiners can be 7 or more, and an accented letter may be 1 or 2 depending on its
    normalisation. Use [max_bytes] to also bound storage or a fixed-width column. *)
val clean : ?max_bytes:int -> string -> max_code_points:int -> (string, string) Result.t

(** Lower case, every run of characters other than ASCII letters and digits turned into
    one space, trimmed: ["  ACME  Coffee-Shop #12 "] becomes ["acme coffee shop 12"]. The
    key merchant and payee rules and keyword matching compare on. Non-ASCII letters are
    kept as they are. *)
val match_key : string -> string
