// Form-trigger wiring for substance-infused gear.
//
// A substance forged into a material item discharges its effect wherever its
// trigger condition is met in that form. This file is the single home for mapping
// real game events on /obj/item/material to the substance trigger conditions; the
// /datum/component/substance_infusion on the item only reacts to the one condition
// matching its substance's trigger, so emitting several per event is safe and cheap.
//
// Event -> condition map (so every SUB_TRIG_* has a way to fire):
//   melee strike        -> IMPACT + CONTACT      (apply_hit_effect, material_weapons.dm)
//   thrown impact       -> IMPACT + PRESSURE     (throw_impact, material_weapons.dm)
//   burned / welded      -> HEAT                  (fire_act, material_weapons.dm)
//   struck by projectile -> IMPACT + PRESSURE (+ ENERGY for energy shots)
//   EMP                  -> ENERGY
//   handled bare-handed  -> CONTACT

// General emitter: announce one or more SUB_TRIG_* conditions on any atom A. The
// /datum/component/substance_infusion (present only on infused forms — a blade, a
// forged round's bullet, ...) reacts to the one condition matching its substance's
// trigger; an atom with no infusion just ignores the signal, so this is cheap to call
// from any form. `where` is the effect turf (defaults to A's turf); `cause` is the
// responsible atom (for logs / blowback).
/proc/substance_emit_form_trigger(atom/A, turf/where, atom/cause, ...)
	if(!A)
		return
	if(!where)
		where = get_turf(A)
	if(!where)
		return
	for(var/i in 4 to length(args))
		SEND_SIGNAL(A, COMSIG_SUBSTANCE_FORM_TRIGGER, args[i], where, cause)

// Convenience wrapper for /obj/item/material forms (blades, thrown charges, armour):
// fast-out when the item isn't a substance material, then delegate to the general
// emitter on src. Keeps the many existing material call sites unchanged.
/obj/item/material/proc/substance_form_trigger(turf/where, atom/cause, ...)
	if(!istype(material, /datum/material/substance))
		return
	substance_emit_form_trigger(arglist(list(src) + args))

/obj/item/material/bullet_act(obj/item/projectile/P, def_zone)
	. = ..()
	if(P && P.damage_type == BURN)
		substance_form_trigger(get_turf(src), P, SUB_TRIG_IMPACT, SUB_TRIG_PRESSURE, SUB_TRIG_ENERGY)
	else
		substance_form_trigger(get_turf(src), P, SUB_TRIG_IMPACT, SUB_TRIG_PRESSURE)

/obj/item/material/emp_act(severity, recursive)
	. = ..()
	substance_form_trigger(get_turf(src), src, SUB_TRIG_ENERGY)

/obj/item/material/fire_act(exposed_temperature, exposed_volume)
	. = ..()
	// HEAT-triggered infusions (THERMAL-family substances) discharge when burned. The
	// legacy fire_act that did this was tied to the removed health model; this clean
	// override only emits the trigger (substance_form_trigger fast-outs on non-substance
	// material items), closing the previously-dead SUB_TRIG_HEAT path.
	substance_form_trigger(get_turf(src), src, SUB_TRIG_HEAT)

/obj/item/material/attack_hand(mob/living/user)
	. = ..()
	substance_form_trigger(get_turf(src), user, SUB_TRIG_CONTACT)

// (Armour-struck IMPACT is emitted from /obj/item/clothing/material_impact in
// material_armor.dm — substance clothing carries the infusion via its set_material.)

// ---- Structures / walls (destroyed) ----------------------------------------
// A substance-material object (structure, machine, or item) discharges its effect
// when it is destroyed — no component needed, read straight from the material. This
// is the form-trigger for built things: a discharge wall zaps the room when breached.

// Fire a material's embodied substance effect on a turf (used by destruction hooks).
/proc/substance_discharge_from_material(turf/T, datum/material/m, atom/cause)
	if(!isturf(T) || !istype(m, /datum/material/substance))
		return
	var/datum/material/substance/sm = m
	if(!sm.infused_substance)
		return
	var/datum/substance/S = sm.infused_substance
	// Deferred: this fires from destruction hooks (walls.dm, /atom/atom_destruction).
	// The effect can destroy other substance objs, which re-enter this proc — so a
	// room of substance structures collapsing in one explosion() must not cascade
	// synchronously through a single call stack. INVOKE_ASYNC breaks the recursion for
	// every family (the corrode/blast in-effect deferral only covered those two).
	INVOKE_ASYNC(GLOBAL_PROC_REF(substance_apply_effect), T, S.family, S.energy, S.volatility, cause)

// Called from /atom/atom_destruction for any obj made of a substance material.
/proc/substance_on_destruction(atom/A)
	if(!isobj(A))
		return
	var/obj/O = A
	substance_discharge_from_material(get_turf(O), O.get_material(), O)
