---------------------- MODULE SplitCommitCounterexample ----------------------
EXTENDS FiniteSets

CONSTANTS
  Armed,
  Used,
  ConsumeCmd,
  R1,
  StateFirst,
  ReceiptFirst,
  Order

States == {Armed, Used}
Orders == {StateFirst, ReceiptFirst}

AppliedUsed ==
  [kind |-> "applied", value |-> Used]

ConsumeReceipt ==
  [id |-> R1, cmd |-> ConsumeCmd, outcome |-> AppliedUsed]

Phases ==
  {"idle", "accepted", "first_written", "committed", "crashed", "recovered"}

VARIABLES
  durableState,
  durableSeen,
  phase

vars == <<durableState, durableSeen, phase>>

ReceiptPresent ==
  ConsumeReceipt \in durableSeen

Init ==
  /\ durableState = Armed
  /\ durableSeen = {}
  /\ phase = "idle"

BeginConsume ==
  /\ phase = "idle"
  /\ phase' = "accepted"
  /\ UNCHANGED <<durableState, durableSeen>>

WriteFirst ==
  /\ phase = "accepted"
  /\ IF Order = StateFirst
       THEN /\ durableState' = Used
            /\ UNCHANGED durableSeen
       ELSE /\ Order = ReceiptFirst
            /\ durableSeen' = {ConsumeReceipt}
            /\ UNCHANGED durableState
  /\ phase' = "first_written"

WriteSecond ==
  /\ phase = "first_written"
  /\ IF Order = StateFirst
       THEN /\ durableSeen' = {ConsumeReceipt}
            /\ UNCHANGED durableState
       ELSE /\ Order = ReceiptFirst
            /\ durableState' = Used
            /\ UNCHANGED durableSeen
  /\ phase' = "committed"

CrashAfterFirst ==
  /\ phase = "first_written"
  /\ phase' = "crashed"
  /\ UNCHANGED <<durableState, durableSeen>>

Recover ==
  /\ phase = "crashed"
  /\ phase' = "recovered"
  /\ UNCHANGED <<durableState, durableSeen>>

Next ==
  BeginConsume
  \/ WriteFirst
  \/ WriteSecond
  \/ CrashAfterFirst
  \/ Recover

Spec ==
  Init /\ [][Next]_vars

TypeOK ==
  /\ durableState \in States
  /\ durableSeen \subseteq {ConsumeReceipt}
  /\ phase \in Phases
  /\ Order \in Orders

RecoveredUsedHasReceipt ==
  phase # "recovered"
    \/ durableState # Used
    \/ ReceiptPresent

RecoveredAppliedReceiptRequiresUsed ==
  phase # "recovered"
    \/ ~ReceiptPresent
    \/ durableState = Used

=============================================================================
