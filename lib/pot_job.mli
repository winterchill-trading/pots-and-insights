(** Pot automation as {!Scheduler_core} jobs.

    Two kinds of job run on a schedule:
    - [Top_up]: on each date, move the top-up amount (see {!Top_up.decide}) into the pot;
    - [Round_up_sweep]: on each date, move the round-ups of the previous UTC day's card
      purchases on [account] into the pot. Sweeps run daily
      ([Every_n_days 1]); {!Make.validate} refuses other frequencies so no day is swept
      twice or skipped.

    The ledger key of each movement is {!idempotency_key} of the run key, so a run the
    scheduler retries after a crash replays the booked entry instead of moving money
    twice. A refusal (not enough money in the account) fails the date with the refusal's
    code; the scheduler pauses the schedule after repeated failures. *)

open! Core

type t =
  | Top_up of Top_up.t
  | Round_up_sweep of
      { rule : Round_up.t
      ; account : Ledger.Account_id.t (** the account whose purchases are rounded up *)
      }
[@@deriving sexp, compare, equal]

(** [pot-auto:<schedule id>:<YYYY-MM-DD>]. Fails when the schedule id is too long for a
    ledger key. *)
val idempotency_key : Scheduler_core.Run_key.t -> Ledger.Idempotency_key.t Or_error.t

(** What a job needs from the service that runs it. *)
module type Env = sig
  type 'a io

  (** The pot, if it exists. *)
  val pot : Pot_id.t -> Pot.t option io

  (** The ledger state to check a movement against. *)
  val balances : unit -> Ledger.Balances.t io

  (** The account's statement items in [[from, until)]. *)
  val items : account:Ledger.Account_id.t -> from:Time_ns.t -> until:Time_ns.t -> Item.t list io

  (** Appends an entry to the journal. An [Error] is taken as transient: the job raises
      so the scheduler retries the date with the same key. *)
  val append : Ledger.Entry.t -> unit Or_error.t io
end

module Make (M : Monad.S) (_ : Env with type 'a io := 'a M.t) :
  Scheduler_core.Job.S with type 'a io = 'a M.t and type t = t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
