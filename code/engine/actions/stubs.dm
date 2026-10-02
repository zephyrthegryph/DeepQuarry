// E0 stubs for E4's public surface (doc/rewrite/final_api.html, section 8 "World actions"; section 19 "E4, actions and hooks"):
// ACT_TRY and its pairing verbs. Signatures are the final ones; a body reports what it needs through ENGINE_STUB and returns null
// until E4 lands. No runtime behaviour here.

/// The expression behind ACT_TRY(E, token, fields...): the final act after every adjusts(); ACT_PASS when nothing hooks the action
/// and no listener wants its notice; null when refused or taken over. E4 turns the call into a macro with a table lookup first;
/// until then a fixture calls this with the act type.
/proc/e0_act_try(datum/holder, act_type, ...)
	ENGINE_STUB(ENGINE_E4, "actions: ACT_TRY (the hook index, the pooled act, adjusts and instead)")
	return null

/// Ends an action ACT_COMMITTED, publishes its notice and releases the context; a no-op for ACT_PASS.
/proc/act_done(datum/act/A)
	ENGINE_STUB(ENGINE_E4, "actions: act_done (the committed notice and the release)")

/// Releases an action's context and ends it ACT_REFUSED, publishing to nobody who has not asked.
/proc/act_cancel(datum/act/A)
	ENGINE_STUB(ENGINE_E4, "actions: act_cancel")

/// Maps an act's outcome to an op effect report: committed is OP_OK, refused OP_REFUSED, replaced OP_REPLACED.
/proc/act_outcome_to_op(datum/act/A)
	ENGINE_STUB(ENGINE_E4, "actions: act_outcome_to_op")
	return OP_FAILED
