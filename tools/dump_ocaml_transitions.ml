open Statecapsule_core

let states = [ State.Locked; State.Armed; State.Used ]
let commands = [ State.Arm; State.Consume ]

let () =
  List.iter
    (fun before ->
      List.iter
        (fun command ->
          match State.apply before command with
          | Error _ -> ()
          | Ok after ->
              Printf.printf
                "%s\t%s\t%s\n"
                (State.to_string before)
                (State.command_to_string command)
                (State.to_string after))
        commands)
    states
