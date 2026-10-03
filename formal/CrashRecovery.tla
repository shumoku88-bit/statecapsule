--------------------------- MODULE CrashRecovery ---------------------------
EXTENDS Naturals, FiniteSets

CONSTANTS
  Locked,
  Armed,
  Used,
  ArmCmd,
  ConsumeCmd,
  R1,
  R2

States == {Locked, Armed, Used}
Commands == {ArmCmd, ConsumeCmd}
RequestIds == {R1, R2}

Applied(s) ==
  [kind |-> "applied", value |-> s]

Refused(reason) ==
  [kind |-> "refused", value |-> reason]

Outcomes ==
  { Applied(Armed)
  , Applied(Used)
  , Refused("already_armed")
  , Refused("not_armed")
  , Refused("already_used")
  }

ReceiptEntries ==
  [id : RequestIds, cmd : Commands, outcome : Outcomes]

NoResponse ==
  [kind |-> "none", id |-> R1, cmd |-> ArmCmd, outcome |-> Refused("not_armed")]

FreshResponses ==
  [kind : {"fresh"}, id : RequestIds, cmd : Commands, outcome : Outcomes]

ReplayResponses ==
  [kind : {"replay"}, id : RequestIds, cmd : Commands, outcome : Outcomes]

ConflictOutcome ==
  Refused("id_conflict")

ConflictResponses ==
  [kind : {"conflict"}, id : RequestIds, cmd : Commands, outcome : {ConflictOutcome}]

Responses ==
  {NoResponse} \cup FreshResponses \cup ReplayResponses \cup ConflictResponses

Phases ==
  { "idle"
  , "accepted"
  , "state_updated"
  , "receipt_recorded"
  , "state_prepared"
  , "receipt_prepared"
  , "committed"
  , "crashed"
  , "blocked"
  }

Outcome(s, cmd) ==
  CASE s = Locked /\ cmd = ArmCmd -> Applied(Armed)
    [] s = Locked /\ cmd = ConsumeCmd -> Refused("not_armed")
    [] s = Armed /\ cmd = ArmCmd -> Refused("already_armed")
    [] s = Armed /\ cmd = ConsumeCmd -> Applied(Used)
    [] s = Used /\ cmd = ArmCmd -> Refused("already_used")
    [] s = Used /\ cmd = ConsumeCmd -> Refused("already_used")

NextState(s, cmd) ==
  CASE s = Locked /\ cmd = ArmCmd -> Armed
    [] s = Armed /\ cmd = ConsumeCmd -> Used
    [] OTHER -> s

StateRank(s) ==
  CASE s = Locked -> 0
    [] s = Armed -> 1
    [] s = Used -> 2

VARIABLES
  visibleState,
  volatileState,
  volatileSeen,
  durableState,
  durableSeen,
  preparedState,
  preparedSeen,
  phase,
  activeId,
  activeCmd,
  activeOutcome,
  successfulConsumes,
  commitCount,
  lastResponse

vars ==
  << visibleState
   , volatileState
   , volatileSeen
   , durableState
   , durableSeen
   , preparedState
   , preparedSeen
   , phase
   , activeId
   , activeCmd
   , activeOutcome
   , successfulConsumes
   , commitCount
   , lastResponse
   >>

SeenId(receipts, id) ==
  \E receipt \in receipts : receipt.id = id

Receipt(receipts, id) ==
  CHOOSE receipt \in receipts : receipt.id = id

Init ==
  /\ visibleState = Locked
  /\ volatileState = Locked
  /\ volatileSeen = {}
  /\ durableState = Locked
  /\ durableSeen = {}
  /\ preparedState = Locked
  /\ preparedSeen = {}
  /\ phase = "idle"
  /\ activeId = R1
  /\ activeCmd = ArmCmd
  /\ activeOutcome = Refused("not_armed")
  /\ successfulConsumes = 0
  /\ commitCount = 0
  /\ lastResponse = NoResponse

AcceptFresh(id, cmd) ==
  /\ phase = "idle"
  /\ ~SeenId(volatileSeen, id)
  /\ activeId' = id
  /\ activeCmd' = cmd
  /\ activeOutcome' = Outcome(visibleState, cmd)
  /\ phase' = "accepted"
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , successfulConsumes
        , commitCount
        , lastResponse
        >>

Replay(id, cmd) ==
  /\ phase = "idle"
  /\ SeenId(volatileSeen, id)
  /\ Receipt(volatileSeen, id).cmd = cmd
  /\ lastResponse' =
       [ kind |-> "replay"
       , id |-> id
       , cmd |-> cmd
       , outcome |-> Receipt(volatileSeen, id).outcome
       ]
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , phase
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        >>

Conflict(id, cmd) ==
  /\ phase = "idle"
  /\ SeenId(volatileSeen, id)
  /\ Receipt(volatileSeen, id).cmd # cmd
  /\ lastResponse' =
       [kind |-> "conflict", id |-> id, cmd |-> cmd, outcome |-> ConflictOutcome]
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , phase
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        >>

UpdateVolatileState ==
  /\ phase = "accepted"
  /\ volatileState' = NextState(visibleState, activeCmd)
  /\ phase' = "state_updated"
  /\ UNCHANGED
       << visibleState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        , lastResponse
        >>

RecordVolatileReceipt ==
  /\ phase = "state_updated"
  /\ LET receipt ==
           [id |-> activeId, cmd |-> activeCmd, outcome |-> activeOutcome]
     IN volatileSeen' = volatileSeen \cup {receipt}
  /\ phase' = "receipt_recorded"
  /\ UNCHANGED
       << visibleState
        , volatileState
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        , lastResponse
        >>

PrepareState ==
  /\ phase = "receipt_recorded"
  /\ preparedState' = volatileState
  /\ phase' = "state_prepared"
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        , lastResponse
        >>

PrepareReceipt ==
  /\ phase = "state_prepared"
  /\ preparedSeen' = volatileSeen
  /\ phase' = "receipt_prepared"
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        , lastResponse
        >>

Commit ==
  /\ phase = "receipt_prepared"
  /\ durableState' = preparedState
  /\ durableSeen' = preparedSeen
  /\ successfulConsumes' =
       successfulConsumes
         + IF activeCmd = ConsumeCmd /\ activeOutcome = Applied(Used)
             THEN 1
             ELSE 0
  /\ commitCount' = commitCount + 1
  /\ phase' = "committed"
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , preparedState
        , preparedSeen
        , activeId
        , activeCmd
        , activeOutcome
        , lastResponse
        >>

Publish ==
  /\ phase = "committed"
  /\ visibleState' = durableState
  /\ volatileState' = durableState
  /\ volatileSeen' = durableSeen
  /\ preparedState' = durableState
  /\ preparedSeen' = durableSeen
  /\ lastResponse' =
       [ kind |-> "fresh"
       , id |-> activeId
       , cmd |-> activeCmd
       , outcome |-> activeOutcome
       ]
  /\ phase' = "idle"
  /\ UNCHANGED
       << durableState
        , durableSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        >>

CrashKnown ==
  /\ phase \notin {"crashed", "blocked"}
  /\ phase' = "crashed"
  /\ lastResponse' = NoResponse
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        >>

CrashAmbiguous ==
  /\ phase \notin {"crashed", "blocked"}
  /\ phase' = "blocked"
  /\ lastResponse' = NoResponse
  /\ UNCHANGED
       << visibleState
        , volatileState
        , volatileSeen
        , durableState
        , durableSeen
        , preparedState
        , preparedSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        >>

Recover ==
  /\ phase = "crashed"
  /\ visibleState' = durableState
  /\ volatileState' = durableState
  /\ volatileSeen' = durableSeen
  /\ preparedState' = durableState
  /\ preparedSeen' = durableSeen
  /\ phase' = "idle"
  /\ lastResponse' = NoResponse
  /\ UNCHANGED
       << durableState
        , durableSeen
        , activeId
        , activeCmd
        , activeOutcome
        , successfulConsumes
        , commitCount
        >>

Next ==
  \/ \E id \in RequestIds, cmd \in Commands : AcceptFresh(id, cmd)
  \/ \E id \in RequestIds, cmd \in Commands : Replay(id, cmd)
  \/ \E id \in RequestIds, cmd \in Commands : Conflict(id, cmd)
  \/ UpdateVolatileState
  \/ RecordVolatileReceipt
  \/ PrepareState
  \/ PrepareReceipt
  \/ Commit
  \/ Publish
  \/ CrashKnown
  \/ CrashAmbiguous
  \/ Recover

Spec ==
  Init /\ [][Next]_vars

TypeOK ==
  /\ visibleState \in States
  /\ volatileState \in States
  /\ volatileSeen \subseteq ReceiptEntries
  /\ durableState \in States
  /\ durableSeen \subseteq ReceiptEntries
  /\ preparedState \in States
  /\ preparedSeen \subseteq ReceiptEntries
  /\ phase \in Phases
  /\ activeId \in RequestIds
  /\ activeCmd \in Commands
  /\ activeOutcome \in Outcomes
  /\ successfulConsumes \in 0..1
  /\ commitCount \in 0..Cardinality(RequestIds)
  /\ lastResponse \in Responses

UniqueIds(receipts) ==
  \A left, right \in receipts :
    left.id = right.id => left = right

DurableIdsAreUnique ==
  UniqueIds(durableSeen)

VolatileIdsAreUnique ==
  UniqueIds(volatileSeen)

IdleMatchesDurable ==
  phase # "idle"
    \/ /\ visibleState = durableState
       /\ volatileState = durableState
       /\ volatileSeen = durableSeen

VisibleNeverAheadOfDurability ==
  StateRank(visibleState) <= StateRank(durableState)

AtMostOneSuccessfulConsume ==
  successfulConsumes <= 1

CommittedConsumeCannotRollBack ==
  successfulConsumes = 0 \/ durableState = Used

DurableUsedHasConsumeReceipt ==
  durableState # Used
    \/ \E receipt \in durableSeen :
         /\ receipt.cmd = ConsumeCmd
         /\ receipt.outcome = Applied(Used)

AppliedConsumeReceiptRequiresUsed ==
  \A receipt \in durableSeen :
    receipt.outcome = Applied(Used) => durableState = Used

DurableProgressHasArmReceipt ==
  durableState = Locked
    \/ \E receipt \in durableSeen :
         /\ receipt.cmd = ArmCmd
         /\ receipt.outcome = Applied(Armed)

FreshResponseIsDurable ==
  lastResponse.kind # "fresh"
    \/ \E receipt \in durableSeen :
         /\ receipt.id = lastResponse.id
         /\ receipt.cmd = lastResponse.cmd
         /\ receipt.outcome = lastResponse.outcome

ReplayEchoesDurable ==
  lastResponse.kind # "replay"
    \/ LET receipt == Receipt(durableSeen, lastResponse.id)
       IN
         /\ receipt.cmd = lastResponse.cmd
         /\ receipt.outcome = lastResponse.outcome

ConflictMeansDurablePayloadMismatch ==
  lastResponse.kind # "conflict"
    \/ LET receipt == Receipt(durableSeen, lastResponse.id)
       IN receipt.cmd # lastResponse.cmd

BlockedIsSilent ==
  phase # "blocked" \/ lastResponse = NoResponse

=============================================================================
