------------------------------ MODULE FrameSync ------------------------------
(***************************************************************************)
(* Main loop <-> NMI handshake of src/main.s.                              *)
(*                                                                         *)
(* The NMI can preempt the main loop between any two instructions, so the *)
(* main loop is split into the steps that matter.  The shadow buffers are  *)
(* modelled as two halves (a, b) that the main loop updates one after the  *)
(* other; a "torn" frame is a VRAM upload of a half-updated shadow.        *)
(*                                                                         *)
(* FIXED = FALSE models the original code, FIXED = TRUE the current code:  *)
(*   original: wait_nmi = "lda nmi_count / spin until it changes", entered *)
(*             after frame_ready := 1                                      *)
(*   fixed:    spin until the NMI has consumed frame_ready                 *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS FIXED, MaxFrames

VARIABLES pc, sa, sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, chan, frames, lag

vars == <<pc, sa, sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, chan, frames, lag>>

Init ==
  /\ pc = "workA"           \* main loop position
  /\ sa = 0 /\ sb = 0       \* shadow buffer halves (frame version numbers)
  /\ va = 0 /\ vb = 0       \* VRAM halves
  /\ ready = 0              \* frame_ready
  /\ nmiOn = TRUE           \* NMITIMEN bit 7
  /\ cnt = 0                \* nmi_count (mod 4 is plenty)
  /\ seen = 0               \* value latched by wait_nmi's "lda nmi_count"
  /\ nmiSince = 0           \* NMIs since the frame was published
  /\ chan = "free"          \* DMA channel 0 owner
  /\ frames = 0
  /\ lag = 0                 \* NMIs the main loop waited for, at resume

\* ---- main loop ------------------------------------------------------------
WorkA == pc = "workA" /\ frames < MaxFrames
         /\ sa' = sa + 1 /\ pc' = "workB"
         /\ UNCHANGED <<sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, chan, frames, lag>>
WorkB == pc = "workB"
         /\ sb' = sb + 1
         \* a state handler may take the forced-blank loader path instead
         /\ pc' \in {"publish", "ldOff"}
         /\ UNCHANGED <<sa, va, vb, ready, nmiOn, cnt, seen, nmiSince, chan, frames, lag>>
\* forced-blank loader (load_stage / enter_draft / enter_title)
LdOff == pc = "ldOff" /\ nmiOn' = FALSE /\ pc' = "ldDma"
         /\ UNCHANGED <<sa, sb, va, vb, ready, cnt, seen, nmiSince, chan, frames, lag>>
LdDma == pc = "ldDma" /\ chan = "free" /\ chan' = "main" /\ pc' = "ldGo"
         /\ UNCHANGED <<sa, sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, frames, lag>>
LdGo  == pc = "ldGo" /\ va' = sa /\ vb' = sb /\ chan' = "free" /\ pc' = "ldOn"
         /\ UNCHANGED <<sa, sb, ready, nmiOn, cnt, seen, nmiSince, frames, lag>>
LdOn  == pc = "ldOn" /\ nmiOn' = TRUE /\ pc' = "publish"
         /\ UNCHANGED <<sa, sb, va, vb, ready, cnt, seen, nmiSince, chan, frames, lag>>
Publish == pc = "publish" /\ ready' = 1 /\ nmiSince' = 0
           /\ pc' = (IF FIXED THEN "spinReady" ELSE "latch")
           /\ UNCHANGED <<sa, sb, va, vb, nmiOn, cnt, seen, chan, frames, lag>>
\* original wait_nmi
Latch == pc = "latch" /\ seen' = cnt /\ pc' = "spinCnt"
         /\ UNCHANGED <<sa, sb, va, vb, ready, nmiOn, cnt, nmiSince, chan, frames, lag>>
SpinCnt == pc = "spinCnt" /\ cnt # seen /\ pc' = "workA" /\ frames' = frames + 1
           /\ lag' = nmiSince
           /\ UNCHANGED <<sa, sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, chan>>
\* fixed wait: NMI clears frame_ready once it has uploaded the frame
SpinReady == pc = "spinReady" /\ ready = 0 /\ pc' = "workA" /\ frames' = frames + 1
             /\ lag' = nmiSince
             /\ UNCHANGED <<sa, sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, chan>>

\* ---- NMI (atomic: it runs to completion before the main loop resumes) ----
\* Timing assumption: a spinning main loop sees the change microseconds after
\* the NMI that caused it, i.e. long before the next vblank (16.7ms later).
SpinWouldExit == \/ (pc = "spinCnt" /\ cnt # seen)
                 \/ (pc = "spinReady" /\ ready = 0)
Nmi == nmiOn /\ chan = "free" /\ ~SpinWouldExit
       /\ (IF ready = 1
             THEN va' = sa /\ vb' = sb /\ ready' = 0
             ELSE UNCHANGED <<va, vb, ready>>)
       /\ cnt' = (cnt + 1) % 4
       /\ nmiSince' = (IF nmiSince < 3 THEN nmiSince + 1 ELSE 3)
       /\ UNCHANGED <<pc, sa, sb, nmiOn, seen, chan, frames, lag>>
\* an NMI that fires while the main loop owns the DMA channel would clobber it
NmiDuringDma == nmiOn /\ chan = "main" /\ chan' = "clobbered"
                /\ UNCHANGED <<pc, sa, sb, va, vb, ready, nmiOn, cnt, seen, nmiSince, frames, lag>>

Next == WorkA \/ WorkB \/ LdOff \/ LdDma \/ LdGo \/ LdOn \/ Publish \/ Latch
        \/ SpinCnt \/ SpinReady \/ Nmi \/ NmiDuringDma
        \/ (frames = MaxFrames /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars /\ WF_vars(Next) /\ WF_vars(Nmi)

\* ---- properties ------------------------------------------------------------
NoTornFrame   == va = vb                       \* VRAM never shows half a frame
ReadyOnlyIdle == ready = 1 => pc \in {"latch", "spinCnt", "spinReady"}
DmaExclusive  == chan # "clobbered"
\* the main loop resumes after the NMI that uploaded its frame, not one later
NoDroppedFrame == lag <= 1
=============================================================================
