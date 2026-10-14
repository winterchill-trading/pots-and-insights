(** A keyword list: words in a statement text that suggest a category.

    Matching compares {!Text.match_key}s: lower case, punctuation removed, and whole words
    only, so [rent] matches ["MONTHLY RENT - FLAT 2"] but not ["Parent club"]. A keyword
    may be several words ([cash withdrawal]). The first matching entry wins, so put
    specific keywords before general ones. *)

open! Core

type t [@@deriving sexp_of]

(** Fails on a keyword whose match key is empty. *)
val create : (string * Category.t) list -> t Or_error.t

val empty : t

(** A short general list over {!Catalogue.default}: utility, rent and insurance words for
    [bills], transport, travel, food and cash words. *)
val default : t

(** The first entry whose keyword occurs in [text], with the keyword as written in the
    list. *)
val find : t -> string -> (string * Category.t) option

val to_list : t -> (string * Category.t) list
