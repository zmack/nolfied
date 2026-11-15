---------------------------- MODULE ApuHandshake ----------------------------
(***************************************************************************)
(* SNES (65816) -> SPC700 "write DSP register" mailbox, as in src/main.s.  *)
(*                                                                         *)
(* SNES: port1 := reg; port2 := val; port0 := ++cnt; spin until out0=cnt.  *)
(* SPC:  loop { a := port0; if a # last { last := a; r := port1;           *)
(*       v := port2; DSP[r] := v; out0 := last } }                         *)
(* Each write is identified by its index w; a torn DSP write is one whose  *)
(* register and value come from different requests.                        *)
(*                                                                         *)
(* FIXED = FALSE models the original code:                                 *)
(*  - the SNES starts writing as soon as the IPL echoes the boot kick,     *)
(*    racing the driver's first "mov a,$f4" that initialises `last`;       *)
(*  - on an echo timeout the SNES simply carries on with the next write.   *)
(* FIXED = TRUE: the driver raises a READY flag in out1 after initialising *)
(* `last`; the SNES waits for it; a timeout marks the APU dead and the     *)
(* SNES never touches the ports again.                                     *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS FIXED, N, TIMEOUTS

VARIABLES s, w, cnt, p0, p1, p2, out0, out1, dead,
          c, last, a, r, v, log

vars == <<s, w, cnt, p0, p1, p2, out0, out1, dead, c, last, a, r, v, log>>
Kick == 3

Init ==
  /\ s = "boot" /\ w = 1 /\ cnt = Kick /\ dead = FALSE
  /\ p0 = Kick /\ p1 = 0 /\ p2 = 0     \* ports as left by the IPL upload
  /\ out0 = Kick /\ out1 = 0            \* IPL echoed the kick and jumped
  /\ c = "start" /\ last = 0 /\ a = 0 /\ r = 0 /\ v = 0
  /\ log = <<>>

\* ---------------------------- SNES --------------------------------------
SBoot == s = "boot"
         /\ (FIXED => out1 = 1)                     \* wait for driver READY
         /\ s' = "p1"
         /\ UNCHANGED <<w, cnt, p0, p1, p2, out0, out1, dead, c, last, a, r, v, log>>
SP1 == s = "p1" /\ w <= N /\ ~dead /\ p1' = w /\ s' = "p2"
       /\ UNCHANGED <<w, cnt, p0, p2, out0, out1, dead, c, last, a, r, v, log>>
SP2 == s = "p2" /\ p2' = w /\ s' = "p0"
       /\ UNCHANGED <<w, cnt, p0, p1, out0, out1, dead, c, last, a, r, v, log>>
SP0 == s = "p0" /\ cnt' = (cnt + 1) % 8 /\ p0' = (cnt + 1) % 8 /\ s' = "spin"
       /\ UNCHANGED <<w, p1, p2, out0, out1, dead, c, last, a, r, v, log>>
SAck == s = "spin" /\ out0 = cnt /\ w' = w + 1 /\ s' = "p1"
        /\ UNCHANGED <<cnt, p0, p1, p2, out0, out1, dead, c, last, a, r, v, log>>
\* the spin loop's iteration budget ran out (SPC slow, busy or crashed)
STimeout == TIMEOUTS /\ s = "spin" /\ out0 # cnt
            /\ w' = w + 1 /\ s' = "p1"
            /\ dead' = FIXED
            /\ UNCHANGED <<cnt, p0, p1, p2, out0, out1, c, last, a, r, v, log>>

\* ---------------------------- SPC700 ------------------------------------
CInit == c = "start" /\ last' = p0 /\ c' = (IF FIXED THEN "ready" ELSE "poll")
         /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out0, out1, dead, a, r, v, log>>
CReady == c = "ready" /\ out1' = 1 /\ c' = "poll"
          /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out0, dead, last, a, r, v, log>>
CPoll == c = "poll" /\ a' = p0
         /\ c' = (IF p0 # last THEN "rd1" ELSE "poll")
         /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out0, out1, dead, last, r, v, log>>
CRd1 == c = "rd1" /\ last' = a /\ r' = p1 /\ c' = "rd2"
        /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out0, out1, dead, a, v, log>>
CRd2 == c = "rd2" /\ v' = p2 /\ c' = "dsp"
        /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out0, out1, dead, last, a, r, log>>
CDsp == c = "dsp" /\ log' = Append(log, <<r, v>>) /\ c' = "echo"
        /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out0, out1, dead, last, a, r, v>>
CEcho == c = "echo" /\ out0' = last /\ c' = "poll"
         /\ UNCHANGED <<s, w, cnt, p0, p1, p2, out1, dead, last, a, r, v, log>>

Done == s = "p1" /\ (w > N \/ dead) /\ UNCHANGED vars

Next == SBoot \/ SP1 \/ SP2 \/ SP0 \/ SAck \/ STimeout
        \/ CInit \/ CReady \/ CPoll \/ CRd1 \/ CRd2 \/ CDsp \/ CEcho \/ Done

Spec == Init /\ [][Next]_vars /\ WF_vars(SBoot \/ SP1 \/ SP2 \/ SP0 \/ SAck)
        /\ WF_vars(CInit \/ CReady \/ CPoll \/ CRd1 \/ CRd2 \/ CDsp \/ CEcho)

\* ---------------------------- properties --------------------------------
NoTornWrite == \A i \in 1..Len(log) : log[i][1] = log[i][2]
InOrder     == \A i \in 1..Len(log) : log[i][1] = i       \* nothing lost/dup'd
\* without timeouts every request reaches the DSP
AllDelivered == <>(Len(log) = N)
=============================================================================
