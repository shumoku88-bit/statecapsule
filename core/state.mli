(** A deliberately tiny state machine.

    Accepted transitions:
    [Locked --Arm--> Armed --Consume--> Used].

    Every other state/command pair is refused. *)

type t =
  | Locked
  | Armed
  | Used

type command =
  | Arm
  | Consume

type refusal =
  | Already_armed
  | Not_armed
  | Already_used

val initial : t
val apply : t -> command -> (t, refusal) result

val to_string : t -> string
val command_to_string : command -> string
val refusal_to_string : refusal -> string
