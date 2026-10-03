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

let initial = Locked

let apply state command =
  match state, command with
  | Locked, Arm -> Ok Armed
  | Armed, Consume -> Ok Used
  | Armed, Arm -> Error Already_armed
  | Locked, Consume -> Error Not_armed
  | Used, Arm
  | Used, Consume -> Error Already_used

let to_string = function
  | Locked -> "locked"
  | Armed -> "armed"
  | Used -> "used"

let command_to_string = function
  | Arm -> "arm"
  | Consume -> "consume"

let refusal_to_string = function
  | Already_armed -> "already_armed"
  | Not_armed -> "not_armed"
  | Already_used -> "already_used"
