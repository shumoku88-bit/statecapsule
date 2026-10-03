--------------------------- MODULE StateCapsule ---------------------------
EXTENDS Naturals

CONSTANTS Locked, Armed, Used

VARIABLE state

States == {Locked, Armed, Used}

Init ==
  state = Locked

Arm ==
  /\ state = Locked
  /\ state' = Armed

Consume ==
  /\ state = Armed
  /\ state' = Used

Next ==
  Arm \/ Consume

Spec ==
  Init /\ [][Next]_state

TypeOK ==
  state \in States

=============================================================================
