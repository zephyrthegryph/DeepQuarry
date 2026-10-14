// synthesizer(...) (doc/rewrite/final_api.html, section 11; section 16.5): a cyborg's hypospray or drink synthesizer: it makes what it is set to make
// from its own store and puts it into what it is clicked on. On top of reagent_container(); what is made, from which store and how it is told is the
// holder type's own: it extends the ops, `extend("synthesizer.inject", then(PROC_REF(injected)))`.
//
// Ops (all "synthesizer.<name>"):
//   inject    a click on a living thing (a type that never injects refuses it in its effect)
//   dispense  (`containers` = TRUE) a click on an open container

CAPABILITY_TYPE(synthesizer, CAP_SYNTHESIZER, /datum/capability/lib/synthesizer, key = NONE, containers = FALSE)

/datum/capability/lib/synthesizer/entries()
	return list(
		op("inject", at_target(/mob/living), priority(OP_PRIORITY_PART), label("Inject")),
		containers ? op("dispense", at_target(), when(CAP_PROC(target_is_open_holder)), priority(OP_PRIORITY_PART), label("Dispense")) : null)

/// The clicked thing is an open holder (a beaker with its lid off, a glass).
/datum/capability/lib/synthesizer/proc/target_is_open_holder(datum/act/op/A)
	var/atom/target = A.target
	return !isnull(target?.reagents) && target.is_open_container()
