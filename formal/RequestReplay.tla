--------------------------- MODULE RequestReplay ---------------------------
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

BaseOutcomes ==
  { Applied(Locked)
  , Applied(Armed)
  , Applied(Used)
  , Refused("already_armed")
  , Refused("not_armed")
  , Refused("already_used")
  }

IdConflict ==
  [kind |-> "id_conflict", value |-> "id_conflict"]

SeenEntries ==
  [id : RequestIds, cmd : Commands, outcome : BaseOutcomes]

NoResponse ==
  [kind |-> "none", id |-> R1, cmd |-> ArmCmd, outcome |-> Applied(Locked)]

FreshResponses ==
  [kind : {"fresh"}, id : RequestIds, cmd : Commands, outcome : BaseOutcomes]

ReplayResponses ==
  [kind : {"replay"}, id : RequestIds, cmd : Commands, outcome : BaseOutcomes]

ConflictResponses ==
  [kind : {"conflict"}, id : RequestIds, cmd : Commands, outcome : {IdConflict}]

Responses ==
  {NoResponse} \cup FreshResponses \cup ReplayResponses \cup ConflictResponses

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

VARIABLES
  state,
  seen,
  successfulConsumes,
  lastResponse

SeenId(id) ==
  \E receipt \in seen : receipt.id = id

Receipt(id) ==
  CHOOSE receipt \in seen : receipt.id = id

vars ==
  <<state, seen, successfulConsumes, lastResponse>>

Init ==
  /\ state = Locked
  /\ seen = {}
  /\ successfulConsumes = 0
  /\ lastResponse = NoResponse

Fresh(id, cmd) ==
  /\ ~SeenId(id)
  /\ LET outcome == Outcome(state, cmd)
         nextState == NextState(state, cmd)
         receipt == [id |-> id, cmd |-> cmd, outcome |-> outcome]
     IN
       /\ seen' = seen \cup {receipt}
       /\ state' = nextState
       /\ successfulConsumes' =
            successfulConsumes
              + IF state = Armed /\ cmd = ConsumeCmd THEN 1 ELSE 0
       /\ lastResponse' =
            [kind |-> "fresh", id |-> id, cmd |-> cmd, outcome |-> outcome]

Replay(id, cmd) ==
  /\ SeenId(id)
  /\ Receipt(id).cmd = cmd
  /\ UNCHANGED <<state, seen, successfulConsumes>>
  /\ lastResponse' =
       [ kind |-> "replay"
       , id |-> id
       , cmd |-> cmd
       , outcome |-> Receipt(id).outcome
       ]

Conflict(id, cmd) ==
  /\ SeenId(id)
  /\ Receipt(id).cmd # cmd
  /\ UNCHANGED <<state, seen, successfulConsumes>>
  /\ lastResponse' =
       [kind |-> "conflict", id |-> id, cmd |-> cmd, outcome |-> IdConflict]

Next ==
  \E id \in RequestIds, cmd \in Commands :
    Fresh(id, cmd) \/ Replay(id, cmd) \/ Conflict(id, cmd)

Spec ==
  Init /\ [][Next]_vars

TypeOK ==
  /\ state \in States
  /\ seen \subseteq SeenEntries
  /\ successfulConsumes \in Nat
  /\ lastResponse \in Responses

UniqueRequestIds ==
  \A left, right \in seen :
    left.id = right.id => left = right

AtMostOneSuccessfulConsume ==
  successfulConsumes <= 1

UsedRequiresSuccessfulConsume ==
  state # Used \/ successfulConsumes = 1

ReplayEchoesStoredOutcome ==
  lastResponse.kind # "replay"
    \/ LET receipt == Receipt(lastResponse.id)
       IN
         /\ receipt.cmd = lastResponse.cmd
         /\ receipt.outcome = lastResponse.outcome

ConflictMeansPayloadMismatch ==
  lastResponse.kind # "conflict"
    \/ LET receipt == Receipt(lastResponse.id)
       IN receipt.cmd # lastResponse.cmd

FreshResponseIsStored ==
  lastResponse.kind # "fresh"
    \/ \E receipt \in seen :
         /\ receipt.id = lastResponse.id
         /\ receipt.cmd = lastResponse.cmd
         /\ receipt.outcome = lastResponse.outcome

=============================================================================
