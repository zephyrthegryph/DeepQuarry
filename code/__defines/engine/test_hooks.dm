// The seam between the engines and the test driver (doc/rewrite/final_api.html, section 15 "Test driver").
//
// Test builds carry one driver, in code/tests/driver/, and one recorder. The engine verbs report to the recorder through
// the TEST_REC_* macros below; in a production build every one of them expands to nothing, so an engine writes them
// unguarded and pays nothing. The driver's own bookkeeping (the roll counter, the notice and spill counters, the lane
// budgets) is read the same way, through TEST_ROLL and TEST_LANE_BUDGET.
//
// Who calls what (the contract E1-E6 build against):
//   E2 parts    TEST_REC_OUTCOME / TEST_REC_LOG when an op ends; TEST_REC_RESOURCE on reserve, commit and release;
//               TEST_REC_TRANSFER for a slot move an effect part makes
//
// The recorder's STORE belongs to E6 (round 5): E0 fixes the report calls below and the test_record()/test_recorded() API,
// and ships a placeholder store (code/tests/driver/recorder.dm) that E6 replaces behind test_rec_event().
//   E1 declare  TEST_REC_ACTIVATION on attach and detach
//   E4 actions  TEST_REC_NOTICE when a notice is delivered (or queued past ACT_MAX_DEPTH)
//   E3 stats    TEST_LANE_BUDGET and TEST_EVAL_COST in the drain; TEST_REC_SPILL when a marked pass stops at its budget;
//               TEST_REC_DELTA when a tracked var or stat of an entity the test named in test_record() changes
//   E4 / E2     TEST_ROLL in chance() and prob()-like draws

/// A stat evaluation costs this many microseconds in test builds, instead of a clock read, so budgets and spills are
/// deterministic: a lane budget of 200 lets 20 evaluations through per drain.
#define TEST_EVAL_COST 10

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// An engine entry point that does not exist yet: the stub reports the missing piece, and a proof that touches it fails
/// with "E1-E6 not implemented: <what>" instead of running on a null.
#define ENGINE_STUB(engine, what) e0_pending(engine, what)
/// Ends an E0 proof with "E1-E6 not implemented: <what>" when a driver form or a stub it called reached an engine piece that
/// does not exist yet. A proof reads what it needs into locals as it drives, calls this once, then asserts: the proof is the
/// same text before and after the engines land, and while any stub is hit it fails by name instead of running on a null.
#define E0_GATE if(e0_pending_any()) { return e0_fail_pending(__FILE__, __LINE__) }
#define TEST_REC_OUTCOME(key, outcome, reason, actor) test_rec_outcome(key, outcome, reason, actor)
#define TEST_REC_NOTICE(notice_type, outcome, queued) test_rec_notice(notice_type, outcome, queued)
#define TEST_REC_LOG(key, outcome, origin, actor, target, text) test_rec_log(key, outcome, origin, actor, target, text)
#define TEST_REC_TRANSFER(item, source_holder, dest_holder, slot) test_rec_transfer(item, source_holder, dest_holder, slot)
#define TEST_REC_RESOURCE(event, resource, holder, amount, op_key) test_rec_resource(event, resource, holder, amount, op_key)
#define TEST_REC_ACTIVATION(event, definition, source, holder) test_rec_activation(event, definition, source, holder)
#define TEST_REC_DELTA(entity, key, old_value, new_value) test_rec_delta(entity, key, old_value, new_value)
#define TEST_REC_SPILL(key_chain) test_rec_spill(key_chain)
/// The roll behind chance(p): seeded by test_rng(), counted by test_rolls(). TRUE when the roll succeeds.
#define TEST_ROLL(percent) test_roll(percent)
/// The budget test_budget() set for a lane, in microseconds, or null when the test set none.
#define TEST_LANE_BUDGET(lane) test_lane_budget(lane)
#else
#define ENGINE_STUB(engine, what)
#define TEST_REC_OUTCOME(key, outcome, reason, actor)
#define TEST_REC_NOTICE(notice_type, outcome, queued)
#define TEST_REC_LOG(key, outcome, origin, actor, target, text)
#define TEST_REC_TRANSFER(item, source_holder, dest_holder, slot)
#define TEST_REC_RESOURCE(event, resource, holder, amount, op_key)
#define TEST_REC_ACTIVATION(event, definition, source, holder)
#define TEST_REC_DELTA(entity, key, old_value, new_value)
#define TEST_REC_SPILL(key_chain)
#define TEST_ROLL(percent) prob(percent)
#define TEST_LANE_BUDGET(lane) null
#endif

// Recorder event kinds: the `kind` of a /datum/test_event row. A resource row's kind is its event, an activation row's too.
#define TEST_EVENT_RESERVE "reserve"
#define TEST_EVENT_COMMIT "commit"
#define TEST_EVENT_RELEASE "release"
#define TEST_EVENT_ATTACH "attach"
#define TEST_EVENT_DETACH "detach"
#define TEST_EVENT_OUTCOME "outcome"
#define TEST_EVENT_NOTICE "notice"
#define TEST_EVENT_NOTICE_QUEUED "notice_queued"
#define TEST_EVENT_LOG "log"
#define TEST_EVENT_TRANSFER "transfer"
#define TEST_EVENT_DELTA "delta"
#define TEST_EVENT_SPILL "spill"

// Engine names an ENGINE_STUB reports (section 19, "The seven workers").
#define ENGINE_E1 "E1 declarations"
#define ENGINE_E2 "E2 parts"
#define ENGINE_E3 "E3 stats"
#define ENGINE_E4 "E4 actions and hooks"
#define ENGINE_E5 "E5 semantic queries"
#define ENGINE_E6 "E6 kernel completion"
