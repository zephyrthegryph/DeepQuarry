// /datum/component/substance_infusion — effects-as-material-property, the general way.
//
// Attached to any item forged from a /datum/material/substance (applied through the
// material-behaviour seam, dq_apply_material_behaviors). It holds the substance's
// effect and a finite charge count, and listens for the item's form-trigger signal:
// when the form presents a condition (a melee strike, a thrown impact, ...) that
// matches the substance's own trigger, it discharges the effect in the world.
//
// One property, many forms, zero per-form code: a discharge/on-impact substance
// forged into a blade discharges on a strike; forged into anything thrown, on
// impact. New forms just emit COMSIG_SUBSTANCE_FORM_TRIGGER with their condition.

/datum/component/substance_infusion
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// A private copy of the infused substance (the material's template is shared).
	var/datum/substance/substance
	/// Remaining discharges before the infusion is spent.
	var/charges = 0
	/// world.time the next discharge is allowed.
	var/next_fire = 0

/datum/component/substance_infusion/Initialize(datum/substance/S, _charges = SUBSTANCE_INFUSION_CHARGES)
	. = ..()
	if(!istype(S))
		return COMPONENT_INCOMPATIBLE
	substance = S.Clone()
	charges = _charges

/datum/component/substance_infusion/Destroy(force)
	QDEL_NULL(substance)
	return ..()

/datum/component/substance_infusion/RegisterWithParent()
	RegisterSignal(parent, COMSIG_SUBSTANCE_FORM_TRIGGER, PROC_REF(on_form_trigger))
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))

/datum/component/substance_infusion/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_SUBSTANCE_FORM_TRIGGER, COMSIG_ATOM_EXAMINE))

// Discharge if this form's condition matches the substance's trigger and we still
// have a charge off cooldown. The effect carries the substance's full character
// (magnitude from energy, downside from volatility) — same as it behaved in the lab.
/datum/component/substance_infusion/proc/on_form_trigger(datum/source, condition, turf/where, atom/cause)
	SIGNAL_HANDLER
	if(charges <= 0 || !substance)
		return
	if(substance.trigger != condition)
		return
	if(world.time < next_fire)
		return
	if(!isturf(where))
		where = get_turf(parent)
	if(!where)
		return
	next_fire = world.time + SUBSTANCE_INFUSION_COOLDOWN
	charges--
	// substance_apply_effect can fan out (sparks/explosion); keep it off the signal stack.
	INVOKE_ASYNC(GLOBAL_PROC_REF(substance_apply_effect), where, substance.family, substance.energy, substance.volatility, cause)

/datum/component/substance_infusion/proc/on_examine(datum/source, mob/user, list/examine_text)
	SIGNAL_HANDLER
	if(!substance)
		return
	if(charges > 0)
		examine_text += span_notice("It is infused with <b>[substance_family_name(substance.family)]</b>, discharging [substance_trigger_name(substance.trigger)] ([charges] charge\s left).")
	else
		examine_text += span_notice("Its substance infusion is spent.")
