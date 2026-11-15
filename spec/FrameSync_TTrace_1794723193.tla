---- MODULE FrameSync_TTrace_1794723193 ----
EXTENDS Sequences, TLCExt, Toolbox, FrameSync, Naturals, TLC

_expression ==
    LET FrameSync_TEExpression == INSTANCE FrameSync_TEExpression
    IN FrameSync_TEExpression!expression
----

_trace ==
    LET FrameSync_TETrace == INSTANCE FrameSync_TETrace
    IN FrameSync_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        pc = ()
        /\
        frames = ()
        /\
        ready = (0)
        /\
        cnt = (1)
        /\
        nmiOn = ()
        /\
        nmiSince = (1)
        /\
        va = (0)
        /\
        vb = (0)
        /\
        chan = ()
        /\
        seen = ()
        /\
        sa = ()
        /\
        sb = ()
    )
----

_init ==
    /\ seen = _TETrace[1].seen
    /\ sa = _TETrace[1].sa
    /\ sb = _TETrace[1].sb
    /\ frames = _TETrace[1].frames
    /\ cnt = _TETrace[1].cnt
    /\ nmiOn = _TETrace[1].nmiOn
    /\ nmiSince = _TETrace[1].nmiSince
    /\ va = _TETrace[1].va
    /\ vb = _TETrace[1].vb
    /\ pc = _TETrace[1].pc
    /\ ready = _TETrace[1].ready
    /\ chan = _TETrace[1].chan
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ seen  = _TETrace[i].seen
        /\ seen' = _TETrace[j].seen
        /\ sa  = _TETrace[i].sa
        /\ sa' = _TETrace[j].sa
        /\ sb  = _TETrace[i].sb
        /\ sb' = _TETrace[j].sb
        /\ frames  = _TETrace[i].frames
        /\ frames' = _TETrace[j].frames
        /\ cnt  = _TETrace[i].cnt
        /\ cnt' = _TETrace[j].cnt
        /\ nmiOn  = _TETrace[i].nmiOn
        /\ nmiOn' = _TETrace[j].nmiOn
        /\ nmiSince  = _TETrace[i].nmiSince
        /\ nmiSince' = _TETrace[j].nmiSince
        /\ va  = _TETrace[i].va
        /\ va' = _TETrace[j].va
        /\ vb  = _TETrace[i].vb
        /\ vb' = _TETrace[j].vb
        /\ pc  = _TETrace[i].pc
        /\ pc' = _TETrace[j].pc
        /\ ready  = _TETrace[i].ready
        /\ ready' = _TETrace[j].ready
        /\ chan  = _TETrace[i].chan
        /\ chan' = _TETrace[j].chan

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("FrameSync_TTrace_1794723193.json", _TETrace)

=============================================================================

 Note that you can extract this module `FrameSync_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `FrameSync_TEExpression.tla` file takes precedence 
  over the module `FrameSync_TEExpression` below).

---- MODULE FrameSync_TEExpression ----
EXTENDS Sequences, TLCExt, Toolbox, FrameSync, Naturals, TLC

expression == 
    [
        \* To hide variables of the `FrameSync` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        seen |-> seen
        ,sa |-> sa
        ,sb |-> sb
        ,frames |-> frames
        ,cnt |-> cnt
        ,nmiOn |-> nmiOn
        ,nmiSince |-> nmiSince
        ,va |-> va
        ,vb |-> vb
        ,pc |-> pc
        ,ready |-> ready
        ,chan |-> chan
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_seenUnchanged |-> seen = seen'
        
        \* Format the `seen` variable as Json value.
        \* ,_seenJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(seen)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_seenModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].seen # _TETrace[s-1].seen
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE FrameSync_TETrace ----
\*EXTENDS IOUtils, FrameSync, TLC
\*
\*trace == IODeserialize("FrameSync_TTrace_1794723193.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE FrameSync_TETrace ----
EXTENDS FrameSync, TLC

trace == 
    <<
    ([pc |-> "workA",frames |-> 0,ready |-> 0,cnt |-> 0,nmiOn |-> TRUE,nmiSince |-> 0,va |-> 0,vb |-> 0,chan |-> "free",seen |-> 0,sa |-> 0,sb |-> 0]),
    ([pc |-> ,frames |-> ,ready |-> 0,cnt |-> 1,nmiOn |-> ,nmiSince |-> 1,va |-> 0,vb |-> 0,chan |-> ,seen |-> ,sa |-> ,sb |-> ])
    >>
----


=============================================================================

---- CONFIG FrameSync_TTrace_1794723193 ----
CONSTANTS
    FIXED = FALSE
    MaxFrames = 4

INVARIANT
    _inv

CHECK_DEADLOCK
    \* CHECK_DEADLOCK off because of PROPERTY or INVARIANT above.
    FALSE

INIT
    _init

NEXT
    _next

CONSTANT
    _TETrace <- _trace

ALIAS
    _expression
=============================================================================
\* Generated on Sun Nov 15 06:13:13 UTC 2026