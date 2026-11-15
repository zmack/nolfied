---- MODULE ApuHandshake_TTrace_1794723799 ----
EXTENDS Sequences, TLCExt, ApuHandshake, Toolbox, Naturals, TLC

_expression ==
    LET ApuHandshake_TEExpression == INSTANCE ApuHandshake_TEExpression
    IN ApuHandshake_TEExpression!expression
----

_trace ==
    LET ApuHandshake_TETrace == INSTANCE ApuHandshake_TETrace
    IN ApuHandshake_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        p0 = (4)
        /\
        p1 = (2)
        /\
        a = (4)
        /\
        p2 = (1)
        /\
        c = ("echo")
        /\
        last = (4)
        /\
        log = (<<<<2, 1>>>>)
        /\
        cnt = (4)
        /\
        dead = (FALSE)
        /\
        r = (2)
        /\
        s = ("p2")
        /\
        v = (1)
        /\
        out0 = (3)
        /\
        w = (2)
        /\
        out1 = (0)
    )
----

_init ==
    /\ p0 = _TETrace[1].p0
    /\ p1 = _TETrace[1].p1
    /\ p2 = _TETrace[1].p2
    /\ last = _TETrace[1].last
    /\ a = _TETrace[1].a
    /\ c = _TETrace[1].c
    /\ cnt = _TETrace[1].cnt
    /\ r = _TETrace[1].r
    /\ s = _TETrace[1].s
    /\ v = _TETrace[1].v
    /\ w = _TETrace[1].w
    /\ dead = _TETrace[1].dead
    /\ out0 = _TETrace[1].out0
    /\ out1 = _TETrace[1].out1
    /\ log = _TETrace[1].log
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ p0  = _TETrace[i].p0
        /\ p0' = _TETrace[j].p0
        /\ p1  = _TETrace[i].p1
        /\ p1' = _TETrace[j].p1
        /\ p2  = _TETrace[i].p2
        /\ p2' = _TETrace[j].p2
        /\ last  = _TETrace[i].last
        /\ last' = _TETrace[j].last
        /\ a  = _TETrace[i].a
        /\ a' = _TETrace[j].a
        /\ c  = _TETrace[i].c
        /\ c' = _TETrace[j].c
        /\ cnt  = _TETrace[i].cnt
        /\ cnt' = _TETrace[j].cnt
        /\ r  = _TETrace[i].r
        /\ r' = _TETrace[j].r
        /\ s  = _TETrace[i].s
        /\ s' = _TETrace[j].s
        /\ v  = _TETrace[i].v
        /\ v' = _TETrace[j].v
        /\ w  = _TETrace[i].w
        /\ w' = _TETrace[j].w
        /\ dead  = _TETrace[i].dead
        /\ dead' = _TETrace[j].dead
        /\ out0  = _TETrace[i].out0
        /\ out0' = _TETrace[j].out0
        /\ out1  = _TETrace[i].out1
        /\ out1' = _TETrace[j].out1
        /\ log  = _TETrace[i].log
        /\ log' = _TETrace[j].log

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("ApuHandshake_TTrace_1794723799.json", _TETrace)

=============================================================================

 Note that you can extract this module `ApuHandshake_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `ApuHandshake_TEExpression.tla` file takes precedence 
  over the module `ApuHandshake_TEExpression` below).

---- MODULE ApuHandshake_TEExpression ----
EXTENDS Sequences, TLCExt, ApuHandshake, Toolbox, Naturals, TLC

expression == 
    [
        \* To hide variables of the `ApuHandshake` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        p0 |-> p0
        ,p1 |-> p1
        ,p2 |-> p2
        ,last |-> last
        ,a |-> a
        ,c |-> c
        ,cnt |-> cnt
        ,r |-> r
        ,s |-> s
        ,v |-> v
        ,w |-> w
        ,dead |-> dead
        ,out0 |-> out0
        ,out1 |-> out1
        ,log |-> log
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_p0Unchanged |-> p0 = p0'
        
        \* Format the `p0` variable as Json value.
        \* ,_p0Json |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(p0)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_p0ModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].p0 # _TETrace[s-1].p0
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE ApuHandshake_TETrace ----
\*EXTENDS IOUtils, ApuHandshake, TLC
\*
\*trace == IODeserialize("ApuHandshake_TTrace_1794723799.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE ApuHandshake_TETrace ----
EXTENDS ApuHandshake, TLC

trace == 
    <<
    ([p0 |-> 3,p1 |-> 0,a |-> 0,p2 |-> 0,c |-> "start",last |-> 0,log |-> <<>>,cnt |-> 3,dead |-> FALSE,r |-> 0,s |-> "boot",v |-> 0,out0 |-> 3,w |-> 1,out1 |-> 0]),
    ([p0 |-> 3,p1 |-> 0,a |-> 0,p2 |-> 0,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 3,dead |-> FALSE,r |-> 0,s |-> "boot",v |-> 0,out0 |-> 3,w |-> 1,out1 |-> 0]),
    ([p0 |-> 3,p1 |-> 0,a |-> 0,p2 |-> 0,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 3,dead |-> FALSE,r |-> 0,s |-> "p1",v |-> 0,out0 |-> 3,w |-> 1,out1 |-> 0]),
    ([p0 |-> 3,p1 |-> 1,a |-> 0,p2 |-> 0,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 3,dead |-> FALSE,r |-> 0,s |-> "p2",v |-> 0,out0 |-> 3,w |-> 1,out1 |-> 0]),
    ([p0 |-> 3,p1 |-> 1,a |-> 0,p2 |-> 1,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 3,dead |-> FALSE,r |-> 0,s |-> "p0",v |-> 0,out0 |-> 3,w |-> 1,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 1,a |-> 0,p2 |-> 1,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 4,dead |-> FALSE,r |-> 0,s |-> "spin",v |-> 0,out0 |-> 3,w |-> 1,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 1,a |-> 0,p2 |-> 1,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 4,dead |-> FALSE,r |-> 0,s |-> "p1",v |-> 0,out0 |-> 3,w |-> 2,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 2,a |-> 0,p2 |-> 1,c |-> "poll",last |-> 3,log |-> <<>>,cnt |-> 4,dead |-> FALSE,r |-> 0,s |-> "p2",v |-> 0,out0 |-> 3,w |-> 2,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 2,a |-> 4,p2 |-> 1,c |-> "rd1",last |-> 3,log |-> <<>>,cnt |-> 4,dead |-> FALSE,r |-> 0,s |-> "p2",v |-> 0,out0 |-> 3,w |-> 2,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 2,a |-> 4,p2 |-> 1,c |-> "rd2",last |-> 4,log |-> <<>>,cnt |-> 4,dead |-> FALSE,r |-> 2,s |-> "p2",v |-> 0,out0 |-> 3,w |-> 2,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 2,a |-> 4,p2 |-> 1,c |-> "dsp",last |-> 4,log |-> <<>>,cnt |-> 4,dead |-> FALSE,r |-> 2,s |-> "p2",v |-> 1,out0 |-> 3,w |-> 2,out1 |-> 0]),
    ([p0 |-> 4,p1 |-> 2,a |-> 4,p2 |-> 1,c |-> "echo",last |-> 4,log |-> <<<<2, 1>>>>,cnt |-> 4,dead |-> FALSE,r |-> 2,s |-> "p2",v |-> 1,out0 |-> 3,w |-> 2,out1 |-> 0])
    >>
----


=============================================================================

---- CONFIG ApuHandshake_TTrace_1794723799 ----
CONSTANTS
    FIXED = FALSE
    N = 3
    TIMEOUTS = TRUE

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
\* Generated on Sun Nov 15 06:23:19 UTC 2026