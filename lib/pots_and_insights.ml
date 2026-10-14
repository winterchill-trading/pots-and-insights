(** Savings pots and spending insights over a double-entry ledger. *)

(** Validated caller-chosen identifiers. *)
module Id = Id

(** Identifier of a savings pot. *)
module Pot_id = Pot_id

(** Identifier of the owner of pots and budgets. *)
module Owner_id = Owner_id

(** Identifier of a monthly budget. *)
module Budget_id = Budget_id

(** Identifier of a statement item. *)
module Item_id = Item_id

(** Calendar months in UTC. *)
module Calendar_month = Calendar_month

(** Checks and match keys for short user-typed text. *)
module Text = Text

(** Savings pots: owned sub-accounts with a goal and cosmetic fields. *)
module Pot = Pot

(** Ledger entries for pot deposits, withdrawals and closing. *)
module Pot_booking = Pot_booking

(** Spending category codes. *)
module Category = Category

(** The set of categories a bank offers and their groups. *)
module Catalogue = Catalogue

(** Statement items, the input of insights. *)
module Item = Item

(** Keyword lists that suggest a category from statement text. *)
module Keywords = Keywords

(** A customer's own category choices: overrides and rules. *)
module Preferences = Preferences

(** Filing items under categories and recategorising them. *)
module Categorise = Categorise

(** Exact percentages with one decimal place. *)
module Percentage = Percentage
