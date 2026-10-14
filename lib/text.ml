open! Core

let code_points s =
  if not (Stdlib.String.is_valid_utf_8 s)
  then None
  else (
    let rec loop i n =
      if i >= String.length s
      then n
      else (
        let d = Stdlib.String.get_utf_8_uchar s i in
        loop (i + Stdlib.Uchar.utf_decode_length d) (n + 1))
    in
    Some (loop 0 0))
;;

let clean s ~max_code_points =
  let s = String.strip s in
  if String.is_empty s
  then Error "empty"
  else (
    match code_points s with
    | None -> Error "not_utf8"
    | Some n when n > max_code_points -> Error "too_long"
    | Some _ ->
      (* Bytes below 0x20 and DEL are never part of a multi-byte UTF-8 sequence. *)
      if String.exists s ~f:(fun c -> Char.to_int c < 0x20 || Char.to_int c = 0x7f)
      then Error "control_character"
      else Ok s)
;;

let match_key s =
  let buf = Buffer.create (String.length s) in
  let pending_space = ref false in
  String.iter s ~f:(fun c ->
    if Char.is_alphanum c || Char.to_int c >= 0x80
    then (
      if !pending_space && Buffer.length buf > 0 then Buffer.add_char buf ' ';
      pending_space := false;
      Buffer.add_char buf (Char.lowercase c))
    else pending_space := true);
  Buffer.contents buf
;;
