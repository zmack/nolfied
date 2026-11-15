------------------------------- MODULE GameFSM -------------------------------
(***************************************************************************)
(* The explicit game-flow and player-mode state machines of src/main.s.    *)
(*                                                                         *)
(* One loop iteration = one frame.  Within a PLAY frame the order is fixed *)
(* by st_play: the player moves first (which may close a cut and clear the *)
(* stage), then, only if the state is still PLAY, every enemy may hit.     *)
(* Hits are nondeterministic; so are input and when a cut closes.          *)
(***************************************************************************)
EXTENDS Integers

CONSTANTS MaxLives, MaxAegis, MaxTrail

States  == {"TITLE", "DRAFT", "READY", "PLAY", "PAUSE", "DYING", "CLEAR", "OVER"}
Modes   == {"EDGE", "DRAW", "RETRACT"}

\* the transition table encoded in fsm_allow (src/main.s)
Allowed ==
  { <<"BOOT", "TITLE">>, <<"TITLE", "DRAFT">>, <<"DRAFT", "READY">>,
    <<"READY", "PLAY">>, <<"PLAY", "PAUSE">>, <<"PAUSE", "PLAY">>,
    <<"PLAY", "DYING">>, <<"PLAY", "CLEAR">>, <<"DYING", "PLAY">>,
    <<"DYING", "OVER">>, <<"CLEAR", "DRAFT">>, <<"OVER", "TITLE">> }
\* pm_allow
PmAllowed ==
  { <<"EDGE", "DRAW">>, <<"DRAW", "EDGE">>, <<"DRAW", "RETRACT">>,
    <<"RETRACT", "DRAW">>, <<"RETRACT", "EDGE">>, <<"EDGE", "EDGE">> }

VARIABLES st, pm, trail, lives, aegis, cleared, hitAfterClear

vars == <<st, pm, trail, lives, aegis, cleared, hitAfterClear>>

Init == /\ st = "BOOT" /\ pm = "EDGE" /\ trail = 0 /\ lives = 0 /\ aegis = 0
        /\ cleared = FALSE /\ hitAfterClear = FALSE

Boot == st = "BOOT" /\ st' = "TITLE" /\ UNCHANGED <<pm, trail, lives, aegis, cleared, hitAfterClear>>

\* TITLE --start--> DRAFT (new_run: lives := 3)
StartRun == st = "TITLE" /\ st' = "DRAFT" /\ lives' = 3
            /\ UNCHANGED <<pm, trail, aegis, cleared, hitAfterClear>>
\* DRAFT --take perk--> READY (PHOENIX +1 / GLASS -1 life; init_entities)
TakePerk == st = "DRAFT" /\ st' = "READY"
            /\ \E dl \in {-1, 0, 1} :
                 lives' = (IF dl = 1 /\ lives < MaxLives THEN lives + 1
                           ELSE IF dl = -1 /\ lives > 1 THEN lives - 1 ELSE lives)
            /\ aegis' \in 0..MaxAegis          \* AEGIS_C := stack count
            /\ pm' = "EDGE" /\ trail' = 0 /\ cleared' = FALSE
            /\ UNCHANGED hitAfterClear
ReadyDone == st = "READY" /\ st' = "PLAY" /\ UNCHANGED <<pm, trail, lives, aegis, cleared, hitAfterClear>>
Pause   == st = "PLAY"  /\ st' = "PAUSE" /\ UNCHANGED <<pm, trail, lives, aegis, cleared, hitAfterClear>>
Unpause == st = "PAUSE" /\ st' = "PLAY"  /\ UNCHANGED <<pm, trail, lives, aegis, cleared, hitAfterClear>>

\* ---- the player half of a PLAY frame (player_update) -----------------------
PStay == UNCHANGED <<pm, trail>>
PStartCut == pm = "EDGE" /\ pm' = "DRAW" /\ trail' = 1
PExtend   == pm = "DRAW" /\ trail < MaxTrail /\ trail' = trail + 1 /\ pm' = "DRAW"
PRelease  == pm = "DRAW" /\ pm' = "RETRACT" /\ UNCHANGED trail
PRepress  == pm = "RETRACT" /\ pm' = "DRAW" /\ UNCHANGED trail
\* retract_step: pop one cell; the mode returns to EDGE in the same step the
\* trail empties
PRetract  == pm = "RETRACT" /\ trail' = trail - 1
             /\ pm' = (IF trail - 1 = 0 THEN "EDGE" ELSE "RETRACT")
\* try_move closes the cut: do_fill (while still DRAW), trail := 0, EDGE
PClose    == pm = "DRAW" /\ pm' = "EDGE" /\ trail' = 0

\* enemies hit only if the state is still PLAY after the player moved
Hit(s, p, t, l, a) ==
  \/ /\ a > 0 /\ p # "EDGE"                         \* AEGIS soaks it: wipe_trail
     /\ st' = s /\ pm' = "EDGE" /\ trail' = 0 /\ aegis' = a - 1 /\ lives' = l
  \/ /\ a = 0 /\ p # "EDGE"
     /\ st' = "DYING" /\ pm' = p /\ trail' = t /\ aegis' = a /\ lives' = l
  \/ /\ p = "EDGE"                                  \* enemies can't reach the edge
     /\ st' = s /\ pm' = p /\ trail' = t /\ aegis' = a /\ lives' = l

PlayFrame ==
  /\ st = "PLAY"
  /\ \E pm1 \in Modes, t1 \in 0..MaxTrail, closes \in BOOLEAN, clearsNow \in BOOLEAN :
       \* player step, re-expressed with explicit intermediate values
       /\ \/ (pm1 = pm /\ t1 = trail)
          \/ (pm = "EDGE" /\ pm1 = "DRAW" /\ t1 = 1)
          \/ (pm = "DRAW" /\ trail < MaxTrail /\ pm1 = "DRAW" /\ t1 = trail + 1)
          \/ (pm = "DRAW" /\ pm1 = "RETRACT" /\ t1 = trail)
          \/ (pm = "RETRACT" /\ pm1 = "DRAW" /\ t1 = trail)
          \/ (pm = "RETRACT" /\ t1 = trail - 1 /\ pm1 = (IF t1 = 0 THEN "EDGE" ELSE "RETRACT"))
          \/ (pm = "DRAW" /\ closes /\ pm1 = "EDGE" /\ t1 = 0)
       /\ LET s1 == IF pm = "DRAW" /\ closes /\ pm1 = "EDGE" /\ t1 = 0 /\ clearsNow
                    THEN "CLEAR" ELSE "PLAY"
          IN \/ /\ s1 = "CLEAR"                       \* st_play returns early
                /\ st' = "CLEAR" /\ pm' = pm1 /\ trail' = t1 /\ UNCHANGED <<lives, aegis>>
                /\ cleared' = TRUE /\ UNCHANGED hitAfterClear
             \/ /\ s1 = "PLAY"
                /\ \/ (st' = "PLAY" /\ pm' = pm1 /\ trail' = t1 /\ UNCHANGED <<lives, aegis>>)
                   \/ Hit(s1, pm1, t1, lives, aegis)
                /\ hitAfterClear' = (cleared /\ st' = "DYING")
                /\ UNCHANGED cleared

\* DYING --timer--> wipe_trail, lives-1, PLAY or OVER
Respawn == st = "DYING" /\ pm' = "EDGE" /\ trail' = 0 /\ lives' = lives - 1
           /\ st' = (IF lives - 1 = 0 THEN "OVER" ELSE "PLAY")
           /\ UNCHANGED <<aegis, cleared, hitAfterClear>>
ClearDone == st = "CLEAR" /\ st' = "DRAFT" /\ UNCHANGED <<pm, trail, lives, aegis, cleared, hitAfterClear>>
OverDone  == st = "OVER"  /\ st' = "TITLE" /\ UNCHANGED <<pm, trail, lives, aegis, cleared, hitAfterClear>>

Next == Boot \/ StartRun \/ TakePerk \/ ReadyDone \/ Pause \/ Unpause
        \/ PlayFrame \/ Respawn \/ ClearDone \/ OverDone

Spec == Init /\ [][Next]_vars
        /\ WF_vars(Boot) /\ WF_vars(ReadyDone) /\ WF_vars(Respawn)
        /\ WF_vars(ClearDone) /\ WF_vars(OverDone)

\* ---- properties --------------------------------------------------------------
TypeOK == /\ st \in States \cup {"BOOT"} /\ pm \in Modes
          /\ trail \in 0..MaxTrail /\ lives \in 0..MaxLives /\ aegis \in 0..MaxAegis
TransitionsLegal == [][ st' = st \/ <<st, st'>> \in Allowed ]_st
ModesLegal       == [][ pm' = pm \/ <<pm, pm'>> \in PmAllowed ]_pm
TrailMatchesMode == st \in {"PLAY", "PAUSE", "CLEAR"} => ((pm = "EDGE") <=> (trail = 0))
OverMeansNoLives == st = "OVER" => lives = 0
LivesWhilePlaying == st \in {"READY", "PLAY", "PAUSE", "DYING"} => lives >= 1
NoHitAfterClear  == ~hitAfterClear
\* timed states always move on
NeverStuck == /\ (st = "READY") ~> (st # "READY")
              /\ (st = "DYING") ~> (st # "DYING")
              /\ (st = "CLEAR") ~> (st # "CLEAR")
              /\ (st = "OVER")  ~> (st # "OVER")
=============================================================================
