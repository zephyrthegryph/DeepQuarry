// preset(target, PROC_REF(compute), from =, when =): a value computed from the instance's own place or params, set before its init code reads it
// (doc/rewrite/proposals/init_phase0.md, N1). The deterministic sibling of rolls(): a roll is random, a preset is not.
//
//	CAPABILITIES(/obj/machinery/atmospherics/pipe)
//		preset(nameof(level), PROC_REF(start_level))                              // was `level = 1` before `..()` when the pipe sits on a wall
//	CAPABILITIES(/obj/effect/overmap/visitable/sector/temporary)
//		preset(nameof(start_x), PROC_REF(start_at_x))
//		preset(nameof(start_y), PROC_REF(start_at_y))
//	CAPABILITIES(/obj/machinery/camera/intcircuit)
//		preset(nameof(c_tag), PROC_REF(start_tag), from = list(nameof(network)), when = nameof(network_id))
//
// The generator is a holder proc x(target) that answers the value: it reads and never writes (a condition-like proc), so a preset has no effect
// of its own; a claim on a resource (a z-level, a registry slot) is an effect and stays a setup() hook. It runs at the root of the Initialize()
// chain (lifeform_preinit(), after the params and before the rolls), before any type's code after `. = ..()`.
//
// A map-edited or param-given value suppresses the preset, as it does a roll: a target whose value differs from its compiled default is left
// alone. `when =` gates one preset on a condition (section 5), read after the presets before it. `from =` names other presets whose targets must be
// set first; the engine orders them and a cycle is a declaration error (reported, the presets on the cycle are not run).

/proc/preset(target, generator, from = null, when = null)
	if(!istext(target))
		declare_report("preset(): the target is nameof(var), got [target]")
		return null
	if(!istext(generator))
		declare_report("preset([target]): the generator is PROC_REF(x), got [generator]")
		return null
	if(!islist(from) && !isnull(from))
		from = list(from)
	return entry_make(ENTRY_PRESET, "preset:[target]", list("target" = target, "gen" = generator, "when" = when, "from" = from))

/// Sets every preset() of the type on `holder`, in dependency order.
/proc/presets_run(datum/holder, datum/lifeform_plan/P, mapload)
	var/list/pending = P.presets.Copy()
	var/list/done = list()
	var/guard = length(pending) + 1
	while(length(pending) && guard-- > 0)
		for(var/datum/centry/C as anything in pending.Copy())
			var/datum/entry/E = C.item
			var/ready = TRUE
			for(var/dep in E.args["from"])
				if(!done[dep] && presets_target_declared(P, dep))
					ready = FALSE
					break
			if(!ready)
				continue
			pending -= C
			done[E.args["target"]] = TRUE
			preset_one(holder, C)
	for(var/datum/centry/C as anything in pending)
		var/datum/entry/E = C.item
		declare_report("[C.origin]: preset([E.args["target"]]) on [holder.type]: its from = makes a cycle; it was not set")

/proc/presets_target_declared(datum/lifeform_plan/P, target)
	for(var/datum/centry/C as anything in P.presets)
		var/datum/entry/E = C.item
		if(E.args["target"] == target)
			return TRUE
	return FALSE

/proc/preset_one(datum/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/target = E.args["target"]
	if(!(target in holder.vars))
		declare_report("[C.origin]: preset([target]) on [holder.type]: no such var")
		return
	if(!hascall(holder, E.args["gen"]))
		declare_report("[C.origin]: preset([target]) on [holder.type]: no proc [E.args["gen"]]")
		return
	if(!roll_target_untouched(holder, target))
		return // a map edit or a param gave it
	if(C.whens && !op_whens_hold(holder, C.whens))
		return
	if(!isnull(E.args["when"]) && !condition_holds(holder, E.args["when"]))
		return
	var/value = call(holder, E.args["gen"])(target)
	holder.vars[target] = value // ALLOW(api): a preset writes its declared target before init, as a map edit would
