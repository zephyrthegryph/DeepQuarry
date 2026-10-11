// stages(nameof(state), stage_step(from, to, parts...), ...): a state machine over one tracked var of the holder (doc/rewrite/final_api.html,
// section 12 "Construction", "A state var's steps: stages()").
//
// Each stage_step() is one op: it is a candidate only while the var holds `from` (when(req_stage(var, from))), its parts are an op's parts (an input
// binding such as tool(TOOL_X), lit_welder(fuel =) or stack(T, n), and any needs(), wait(), begins(), says(), then() ...), and when it runs the var
// becomes `to` before the step's own effects run (sets(var, to) is its first effect), so then() and says() see the new stage. The op's key is
// "<var>_<from>_<to>" unless key = names it; it is an ordinary op, listed in the menu with its label() and pinned like any other.
//
//   CAPABILITIES(/obj/item/camera_assembly)
//       stages(nameof(state),
//           stage_step(0, 1, tool(TOOL_WRENCH), label("Wrench into place"), needs(req(PROC_REF(on_floor))), then(PROC_REF(fastened))),
//           stage_step(1, 0, tool(TOOL_WRENCH), label("Unfasten"), then(PROC_REF(unfastened))),
//           stage_step(1, 2, lit_welder(fuel = 0), label("Weld into place"), wait(2 SECONDS), says(MSG(camera_assembly/welded))))
//
// It is the light form of the state graph (construction(), STAGE_DEF): a type whose steps are a plain number or text var with no ledger, no undo and
// no refunds writes stages(); a build that takes materials in and gives them back on the way down is a construction() graph. The var must be TRACKED
// (the guards and the write go through its key), and a type that also writes it elsewhere does so through its setter.

/// One transition of a stages() machine: from the stage `from` to the stage `to`, through an op made of `parts`. `key` names the op ("<var>_<from>_<to>"
/// by default).
/proc/stage_step(from_stage, to_stage, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, key = null)
	var/datum/stage_step/S = new
	S.from_stage = from_stage
	S.to_stage = to_stage
	S.key = key
	S.parts = entry_flatten(list(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12))
	return S

/// A declared step, read by stages() and then discarded.
/datum/stage_step
	var/from_stage
	var/to_stage
	var/key
	var/list/parts

/// stages(nameof(var), stage_step(...), ...): the ops of a state machine over the holder's tracked `var` (above).
/proc/stages(var_key, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16)
	if(!istext(var_key) || !length(var_key))
		declare_report("stages(): the first argument is the state var (nameof(v)), got [isnull(var_key) ? "null" : "[var_key]"]")
		return null
	. = list()
	for(var/datum/stage_step/S in list(s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16))
		var/key = S.key || "[var_key]_[S.from_stage]_[S.to_stage]"
		. += op(key, when(req_stage(var_key, S.from_stage)), sets(var_key, S.to_stage), S.parts)

