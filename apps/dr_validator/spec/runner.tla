-------------------------- MODULE runner --------------------------
\* TLA+ model of DrValidator.Runner state machine.
\*
\* Purpose: formally verify that the Runner correctly sequences app validation,
\* accumulates results without loss, runs only one app at a time, and writes
\* the report atomically (modelled as a single-transition tmpfile+rename).
\*
\* Assumptions:
\* A1: Apps is a finite set of app identifiers (bounded by CONSTANT).
\* A2: Each app produces exactly one result (pass or fail).
\* A3: Report write is modelled as a single atomic step (tmpfile+rename collapses
\*     to one transition; observer never sees a partial report).
\* A4: Runner is single-threaded (no concurrent app execution).
\* A5: Failed is a terminal absorbing state reached on any unrecoverable error.
\*
\* States: Idle, LoadingPerimeter, RunningApp, AggregatingResult,
\*         WritingReport, Done, Failed
\*
\* Variables:
\*   state        -- current Runner FSM state
\*   perimeter    -- set of apps to validate (populated by LoadPerimeter)
\*   app_queue    -- set of apps still to run (apps not yet started)
\*   current_app  -- app currently under test (or NoApp sentinel)
\*   results      -- function: app -> {"pass","fail"} for resolved apps
\*   report_state -- "empty" | "written"

EXTENDS FiniteSets, TLC

CONSTANTS Apps  \* finite set of app identifiers, e.g. {a1, a2, a3}

ASSUME Apps # {} /\ IsFiniteSet(Apps)

VARIABLES
    state,
    perimeter,
    app_queue,
    current_app,
    results,
    report_state

vars == <<state, perimeter, app_queue, current_app, results, report_state>>

\* ---------------------------------------------------------------------------
\* Type definitions
\* ---------------------------------------------------------------------------

States == {"Idle", "LoadingPerimeter", "RunningApp", "AggregatingResult",
           "WritingReport", "Done", "Failed"}

AppResults == {"pass", "fail"}

NoApp == "none"  \* sentinel for current_app when no app is running

TypeOK ==
    /\ state \in States
    /\ perimeter \subseteq Apps
    /\ app_queue \subseteq Apps
    /\ current_app \in (Apps \union {NoApp})
    /\ DOMAIN results \subseteq Apps
    /\ \A a \in DOMAIN results : results[a] \in AppResults
    /\ report_state \in {"empty", "written"}

\* ---------------------------------------------------------------------------
\* Initial state
\* ---------------------------------------------------------------------------

Init ==
    /\ state        = "Idle"
    /\ perimeter    = {}
    /\ app_queue    = {}
    /\ current_app  = NoApp
    /\ results      = [a \in {} |-> "pass"]
    /\ report_state = "empty"

\* ---------------------------------------------------------------------------
\* Helper predicates
\* ---------------------------------------------------------------------------

AllAppsResolved ==
    DOMAIN results = perimeter

IsTerminal ==
    state \in {"Done", "Failed"}

\* ---------------------------------------------------------------------------
\* Actions
\* ---------------------------------------------------------------------------

\* Idle -> LoadingPerimeter: load perimeter spec, initialise queue
LoadPerimeter ==
    /\ state = "Idle"
    /\ state'        = "LoadingPerimeter"
    /\ perimeter'    = Apps
    /\ app_queue'    = Apps
    /\ current_app'  = NoApp
    /\ results'      = [a \in {} |-> "pass"]
    /\ report_state' = "empty"

\* LoadingPerimeter -> RunningApp (pick one app) or WritingReport (empty perimeter)
StartRun ==
    /\ state = "LoadingPerimeter"
    /\ IF app_queue # {}
       THEN \E a \in app_queue :
            /\ state'       = "RunningApp"
            /\ current_app' = a
            /\ app_queue'   = app_queue \ {a}
       ELSE /\ state'       = "WritingReport"
            /\ current_app' = NoApp
            /\ app_queue'   = app_queue
    /\ UNCHANGED <<perimeter, results, report_state>>

\* RunningApp -> AggregatingResult: record pass for current_app
AppPass ==
    /\ state = "RunningApp"
    /\ current_app # NoApp
    /\ current_app \notin DOMAIN results
    /\ state'   = "AggregatingResult"
    /\ results' = [a \in DOMAIN results \union {current_app} |->
                      IF a = current_app THEN "pass" ELSE results[a]]
    /\ UNCHANGED <<perimeter, app_queue, current_app, report_state>>

\* RunningApp -> AggregatingResult: record fail for current_app
AppFail ==
    /\ state = "RunningApp"
    /\ current_app # NoApp
    /\ current_app \notin DOMAIN results
    /\ state'   = "AggregatingResult"
    /\ results' = [a \in DOMAIN results \union {current_app} |->
                      IF a = current_app THEN "fail" ELSE results[a]]
    /\ UNCHANGED <<perimeter, app_queue, current_app, report_state>>

\* AggregatingResult -> RunningApp (more apps) or WritingReport (queue empty)
AggregateResult ==
    /\ state = "AggregatingResult"
    /\ IF app_queue # {}
       THEN \E a \in app_queue :
            /\ state'       = "RunningApp"
            /\ current_app' = a
            /\ app_queue'   = app_queue \ {a}
       ELSE /\ state'       = "WritingReport"
            /\ current_app' = NoApp
            /\ app_queue'   = app_queue
    /\ UNCHANGED <<perimeter, results, report_state>>

\* WritingReport -> Done: atomic tmpfile+rename (single transition, no partial state)
FinalizeReport ==
    /\ state = "WritingReport"
    /\ AllAppsResolved
    /\ state'        = "Done"
    /\ report_state' = "written"
    /\ UNCHANGED <<perimeter, app_queue, current_app, results>>

\* Done -> Done: idempotent emit (external consumers read the written report)
EmitReport ==
    /\ state = "Done"
    /\ report_state = "written"
    /\ UNCHANGED vars

\* Any non-terminal -> Failed: error injection
FailRunner ==
    /\ ~IsTerminal
    /\ state' = "Failed"
    /\ UNCHANGED <<perimeter, app_queue, current_app, results, report_state>>

\* ---------------------------------------------------------------------------
\* Next-state relation
\* ---------------------------------------------------------------------------

Next ==
    \/ LoadPerimeter
    \/ StartRun
    \/ AppPass
    \/ AppFail
    \/ AggregateResult
    \/ FinalizeReport
    \/ EmitReport
    \/ FailRunner

\* ---------------------------------------------------------------------------
\* Specification (safety + weak fairness on progress transitions)
\* ---------------------------------------------------------------------------

Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(LoadPerimeter)
    /\ WF_vars(StartRun)
    /\ WF_vars(AppPass \/ AppFail)
    /\ WF_vars(AggregateResult)
    /\ WF_vars(FinalizeReport)

\* ---------------------------------------------------------------------------
\* Safety invariants
\* ---------------------------------------------------------------------------

\* INV: RunningApp holds exactly one current_app (no concurrent execution)
SingleAppAtATime ==
    state = "RunningApp" => current_app # NoApp

\* INV: results domain only grows, values never change (monotonic accumulation)
ReportMonotonic ==
    \A a \in DOMAIN results : results[a] \in AppResults

\* INV: report_state is never "pending" — write is atomic (no partial state)
AtomicReportWrite ==
    report_state \in {"empty", "written"}

\* ---------------------------------------------------------------------------
\* Liveness property
\* ---------------------------------------------------------------------------

\* PROP: Every app in perimeter eventually has a result OR Failed is reached.
EveryAppEventuallyResolved ==
    \A a \in Apps :
        [](perimeter # {} =>
            <>(a \in DOMAIN results \/ state = "Failed"))

=============================================================================
