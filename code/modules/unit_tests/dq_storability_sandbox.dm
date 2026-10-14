// Verified storability (roadmap C10, doc/rewrite/containment.md §4.7).
//
// The hand-kept latent_safe list (latent_safe_types.dm) drifts: someone adds a
// registration to Initialize() and nothing notices until a saved blob goes
// stale. This sandbox derives the storable set instead, the same way
// dq_lifecycle_sandbox (dq_lifecycle_tests.dm, state.md §6) already verifies
// Initialize() side effects for the types already marked latent_safe -- this
// test runs the same checks over every *candidate* type, plus a full
// serialize/apply/compare round-trip, and verifies every type the codebase
// currently declares latent_safe = TRUE against it instead of trusting the
// declaration by hand.

/// Candidate roots: types where instantiating one in isolation is cheap and
/// meaningful (movables that plausibly sit in a holder's contents). Mobs,
/// machinery and anything that starts processing are out of scope here --
/// they are never latent-safe, and dq_lifecycle_sandbox already covers the
/// on_materialize() path for the handful of registries that move there (L3).
GLOBAL_LIST_INIT(dq_storability_candidate_roots, list(
	/obj/item,
))

/// One sandbox verdict.
/datum/storability_verdict
	var/path
	var/storable = FALSE
	/// Why it isn't, when it isn't: the first problem found, or the opt-out reason.
	var/reason

/**
 * Runs the three checks (containment.md §4.7) on one candidate type:
 *   1. Initialize() has no global side effects (dq_lifecycle_snapshot diff);
 *   2. qdel() leaves no trace (the same diff, after deletion);
 *   3. its state round-trips: serialize, make a fresh instance, apply, and
 *      the two serialized blobs must hash equal.
 * Returns a /datum/storability_verdict. Does not consult latent_safe or any
 * hand-kept list -- this is what the generated file is checked against.
 */
/proc/dq_storability_check(path)
	var/datum/storability_verdict/verdict = new
	verdict.path = path
	if(is_abstract(path))
		verdict.reason = "abstract type"
		return verdict

	// Warm up per-type caches (element singletons, schemas, static lists) so
	// they don't show up as a false-positive registration on the real pass.
	var/atom/movable/warm = new path
	var/warm_reason = warm.latent_unsafe_reason()
	qdel(warm)
	if(warm_reason)
		verdict.reason = warm_reason
		return verdict

	var/list/before = dq_lifecycle_snapshot()
	var/atom/movable/sandboxed = new_unmaterialized(path, null)
	var/list/initialized = dq_lifecycle_snapshot()
	var/list/problems = dq_lifecycle_snapshot_diff(before, initialized)
	problems += dq_lifecycle_running(sandboxed)
	if(length(problems))
		qdel(sandboxed)
		verdict.reason = "Initialize() changed the world: [jointext(problems, ", ")]"
		return verdict

	var/list/errors = list()
	var/list/before_blob = state_serialize(sandboxed, STATE_FULL, errors)
	if(!before_blob)
		qdel(sandboxed)
		verdict.reason = "does not serialize: [jointext(errors, "; ")]"
		return verdict
	var/before_hash = state_hash(before_blob)

	qdel(sandboxed)
	var/list/after_delete = dq_lifecycle_snapshot()
	var/list/leak = dq_lifecycle_snapshot_diff(initialized, after_delete)
	if(length(leak))
		verdict.reason = "qdel() left a trace: [jointext(leak, ", ")]"
		return verdict

	// Round-trip: a fresh instance, apply the blob back, and compare.
	var/atom/movable/roundtrip = new_unmaterialized(path, null)
	errors = list()
	if(!state_apply(roundtrip, before_blob, STATE_FULL, errors))
		qdel(roundtrip)
		verdict.reason = "does not apply its own blob: [jointext(errors, "; ")]"
		return verdict
	errors = list()
	var/list/after_blob = state_serialize(roundtrip, STATE_FULL, errors)
	qdel(roundtrip)
	if(!after_blob)
		verdict.reason = "does not re-serialize after apply: [jointext(errors, "; ")]"
		return verdict
	if(state_hash(after_blob) != before_hash)
		verdict.reason = "state does not round-trip"
		return verdict

	verdict.storable = TRUE
	return verdict

/// Every candidate type under the declared roots, is_abstract() excluded.
/proc/dq_storability_candidates()
	. = list()
	for(var/root in GLOB.dq_storability_candidate_roots)
		for(var/atom/movable/path as anything in typesof(root))
			if(!is_abstract(path))
				. += path

/datum/unit_test/dq_storability_sandbox

/**
 * Verifies rather than trusts: every type the codebase currently declares
 * latent_safe = TRUE (by hand, in latent_safe_types.dm, or by inheriting a
 * TRUE root) must actually pass the sandbox. A type that no longer passes is
 * exactly the drift this test exists to catch -- someone added a
 * registration or a non-serializing var since the list was last checked by
 * hand. An explicit latent_unsafe_reason() override (a semantic opt-out) is
 * honoured either way: it isn't a failure for a semantically-excluded type
 * to also fail the mechanical checks.
 */
/datum/unit_test/dq_storability_sandbox/Run()
	var/list/candidates = dq_storability_candidates()
	TEST_ASSERT(length(candidates) > 0, "no storability candidates found")
	var/list/failures = list()
	var/checked = 0
	for(var/path in candidates)
		var/atom/movable/typed = path
		if(!latent_type_safe(typed))
			continue
		checked++
		var/datum/storability_verdict/verdict = dq_storability_check(path)
		if(!verdict.storable)
			failures += "[path]: declared latent_safe = TRUE but [verdict.reason]"
		qdel(verdict)
	TEST_ASSERT(checked > 0, "no latent_safe = TRUE candidates found")
	if(length(failures))
		TEST_FAIL("[length(failures)] type(s) declared latent_safe but fail the sandbox:\n[jointext(failures, "\n")]")

/// Regenerates latent_safe_generated.dm's *contents* in memory (as text),
/// for tools/ci/generate_latent_safe.sh to write out. Not run in ordinary
/// test builds: GENERATE_LATENT_SAFE gates it, since it's a one-way sandbox
/// pass meant to be reviewed as a diff, not asserted against itself.
#ifdef GENERATE_LATENT_SAFE
/datum/unit_test/dq_storability_generate

/datum/unit_test/dq_storability_generate/Run()
	var/list/candidates = dq_storability_candidates()
	var/list/lines = list()
	lines += "// GENERATED by dq_storability_sandbox (GENERATE_LATENT_SAFE)."
	lines += "// Run tools/ci/generate_latent_safe.sh to refresh. Do not hand-edit."
	lines += "// containment.md §4.7: types the sandbox verified storable that are"
	lines += "// not already registered latent-safe by hand. Review as a diff"
	lines += "// before folding a row into register_defaults() in latent_safe_types.dm."
	lines += ""
	for(var/path in candidates)
		var/atom/movable/typed = path
		if(latent_type_safe(typed))
			continue // already declared; nothing new to report
		var/datum/storability_verdict/verdict = dq_storability_check(path)
		if(verdict.storable)
			lines += "\tregister([path], TYPE_META_LATENT_SAFE, TRUE)"
			lines += ""
		qdel(verdict)
	var/out = "code/datums/state/latent_safe_candidates.dm"
	fdel(out)
	text2file(jointext(lines, "\n"), out)
	TEST_ASSERT(TRUE, "generated [out]")
#endif
