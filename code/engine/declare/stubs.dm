// E0 stubs for E1's public surface (doc/rewrite/final_api.html, sections 4, 5, 11 and 12; section 19 "E1, declarations"):
// grants and activations, state-graph reads, schema text and the explain tools. Signatures are the final ones; a body reports
// what it needs through ENGINE_STUB and returns null until E1 lands. No runtime behaviour here.
//
// Name clashes. grant(), revoke() and granted() are live on master with the legacy om-store shapes (code/datums/reactions/state.dm),
// so the stubs carry an e0_ prefix and the proofs reach them through the test-only aliases in
// code/modules/unit_tests/dq_e0_aliases.dm. cap_of(E, CAP_X, selector) is not stubbed: master has a live cap_of(atom, key) with a
// different key, and E1 replaces it in one change. E1 deletes the legacy procs, renames these and deletes the aliases.

/// The final grant(): creates an activation of `what` (a capability type or constructor call) on `holder` from `source`, for
/// `lasts` deciseconds when given. Returns the activation, or null with the reason logged when the attach fails.
/proc/e0_grant(datum/holder, what, source, lasts, bound = FALSE)
	RETURN_TYPE(/datum/activation)
	ENGINE_STUB(ENGINE_E1, "scoped activation: grant (the record, the one attach path, stacking)")
	return null

/// The final revoke(): marks the activation `source` made of `what` dead at once and runs the one teardown path.
/proc/e0_revoke(datum/holder, what, source)
	ENGINE_STUB(ENGINE_E1, "scoped activation: revoke (the one teardown path)")
	return FALSE

/// The final granted(): TRUE while `what` is granted to `holder` by any source.
/proc/e0_granted(datum/holder, what)
	ENGINE_STUB(ENGINE_E1, "scoped activation: granted (the holder activation set)")
	return FALSE

/// TRUE when `stage` is the current stage of `E`'s state graph or is on the path from the start to it through E's history.
/proc/built(datum/E, stage)
	ENGINE_STUB(ENGINE_E1, "state graphs: built (the per-instance stage and history)")
	return FALSE

/// The material actually used at `stage`, from E's ledger; null if it took none.
/proc/built_material(datum/E, stage)
	ENGINE_STUB(ENGINE_E1, "state graphs: built_material (the per-instance ledger)")
	return null

/// The merged compiled table of `type`, each part tagged with its origin (file:line).
/proc/explain_type(type)
	ENGINE_STUB(ENGINE_E1, "table builder: explain_type")
	return null

/// Every activation on `E` with its source, scope and contributions.
/proc/explain_activations(datum/E)
	ENGINE_STUB(ENGINE_E1, "scoped activation: explain_activations")
	return null

/// The range text of a declared schema, as the generated UI type doc comment spells it: "num 0..MAX_PUMP_PRESSURE step 1".
/// `type` and `var_name` name the tracked var the schema is on.
/proc/schema_range_text(type, var_name)
	ENGINE_STUB(ENGINE_E1, "value schemas: schema_range_text (the schema's own range text)")
	return null
