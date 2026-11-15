# TLA+ models

These models check the parts of NOLFIED where **two things run at once**, plus the
explicit game and player state machines. Run all of them with `make tla` (needs Java
and `tla2tools.jar`; set `TLA2TOOLS=/path/to/tla2tools.jar` if it isn't at
`/opt/tla/`).

| Model | What runs at once | Properties |
| --- | --- | --- |
| `FrameSync.tla` | the main loop and the NMI (vblank) handler, which can cut in between any two instructions | no torn frames (VRAM never gets a half-updated shadow buffer); `frame_ready` is only set while the main loop is idle; the DMA channel is never shared; **no dropped frames** |
| `ApuHandshake.tla` | the 65816 and the SPC700 sound CPU, talking through four I/O ports | **no torn DSP writes** (register from one request, value from another); writes arrive in order with none lost; every request is delivered (liveness) |
| `GameFSM.tla` | not concurrency: the frame order inside PLAY (player first, then enemies) with nondeterministic input and hits | only transitions from the table; `pmode = EDGE` exactly when there is no trail; lives never underflow; game over only at 0 lives; no hit after a stage clear in the same frame; READY, DYING, CLEAR and OVER never get stuck |

## What the models found in the original code

The `*_original.cfg` configs model the code as it was before the refactor. They are
kept as regression checks and are **expected to fail**:

1. **Dropped frame (FrameSync).** `wait_nmi` latched `nmi_count` *after* the frame
   was published. If the NMI landed in that gap, the main loop slept a whole extra
   frame. That's one frame of stutter and input lag. The loop now waits until the
   NMI has consumed `frame_ready`.
2. **Lost first sound write (ApuHandshake).** The SNES started sending DSP writes as
   soon as the boot ROM echoed the upload kick. That raced the driver's first read of
   port 0. If the SNES won, its first request, which was the `FLG` write that unmutes
   the DSP, looked old and was never applied. It only worked because the SPC700
   happened to be about 6µs faster. The driver now raises a READY flag in port 1, and
   the SNES waits for it.
3. **Torn DSP write (ApuHandshake).** When an echo timed out, the SNES went on to the
   next request. It overwrote ports 1 and 2 while the SPC700 could still be halfway
   through reading them, so a register got another request's value. A timeout now
   marks the APU dead, and the SNES never touches the ports again.

The GameFSM model drove the refactor in `src/main.s`. It led to:

- a transition table (`fsm_allow`), entry actions (`fsm_enter`) and
  `goto_state` / `set_pmode` as the only writers of `state` / `pmode`;
- PAUSE as a real state instead of a flag;
- the trail and the mode changing together: after a fill, and when a retract empties
  the trail;
- `state` committing only after a multi-frame entry action finishes, so a
  half-loaded stage is never visible.

A runtime checker (`fsm_check`, `FSM_ERRS` in RAM) enforces the same rules in the
ROM. `tools/test_flow.py` and `tools/playtest.py` assert that it stays at zero.

## Scope and assumptions

- An NMI is atomic: it runs to completion before the main loop resumes, and the
  hardware never nests NMIs.
- **Timing (FrameSync):** a spinning main loop notices a change microseconds after
  the NMI that caused it. Without this assumption, the model would allow a second
  NMI 16.7ms later to beat it.
- **Sound ports:** each port is a single byte register that the other CPU reads
  atomically. The SNES writes ports 1 and 2 before port 0.
- **IRQs:** the game uses no IRQs. HDMA and the hardware multiplier/divider are only
  used by the main loop, so they are not modelled.
