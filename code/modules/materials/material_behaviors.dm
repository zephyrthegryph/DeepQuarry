// Material behaviours — the working implementation.
//
// A material's three active behaviours (luminescence, radioactivity, toxicity)
// are plain numeric magnitudes on /datum/material (see _materials.dm). This file
// owns: the read API, the item-side application, and the component that actually
// makes the behaviour happen. It replaces the earlier half-wired component layer
// (which only carried magnitudes and never irradiated/poisoned anything). The old
// material-synergy system was removed outright — no shims remain.

// ---- Read API --------------------------------------------------------------
// Canonical accessors; structural readers (walls, girders, doors, fuel) go
// through these so the storage can change without touching every site.

/proc/dq_material_luminescence(datum/material/M)
	return M ? M.luminescence : 0

/proc/dq_material_radioactivity(datum/material/M)
	return M ? M.radioactivity : 0

/proc/dq_material_toxicity(datum/material/M)
	return M ? M.toxicity : 0

// ---- Item application ------------------------------------------------------
// Called from each material item's set_material once the material is assigned.
// Attaches the behaviour component if the material does anything active.

/datum/material/proc/dq_apply_material_behaviors(obj/item/I)
	if(!I)
		return
	if(luminescence > 0 || radioactivity > 0 || toxicity > 0)
		I.AddComponent(/datum/component/material_behaviors, luminescence, radioactivity, toxicity, icon_colour)

// ---- The behaviour component -----------------------------------------------
// Lights the item once, and (if it irradiates or poisons) self-processes to do
// so while it is carried. One per item.

/datum/component/material_behaviors
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/luminescence = 0
	var/radioactivity = 0
	var/toxicity = 0
	var/processing = FALSE

/datum/component/material_behaviors/Initialize(_lum = 0, _rad = 0, _tox = 0, colour = null)
	. = ..()
	if(!isitem(parent))
		return COMPONENT_INCOMPATIBLE
	luminescence = _lum
	radioactivity = _rad
	toxicity = _tox
	var/obj/item/I = parent
	if(luminescence > 0)
		var/range = clamp(luminescence / 20, 0.5, 4)
		var/power = clamp(luminescence / 30, 0.3, 2)
		I.set_light(range, power, colour)
	if(radioactivity > 0 || toxicity > 0)
		START_PROCESSING(SSobj, src)
		processing = TRUE

/datum/component/material_behaviors/Destroy(force)
	if(processing)
		STOP_PROCESSING(SSobj, src)
	var/obj/item/I = parent
	if(istype(I) && luminescence > 0)
		I.set_light(0)
	return ..()

/datum/component/material_behaviors/process(seconds_per_tick)
	var/obj/item/I = parent
	if(QDELETED(I))
		return PROCESS_KILL
	if(radioactivity > 0)
		radiation_pulse(
			I,
			max_range = 3,
			threshold = RAD_LIGHT_INSULATION,
			chance = round(radioactivity * 0.5, 1),
			minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
			strength = radioactivity,
		)
	if(toxicity > 0)
		// Sub-lethal but real, only while held bare in hand (loc is the mob). Dose is
		// per fixed SSobj tick (wait = 20 ds); SSobj passes a deciseconds delta, not
		// seconds, so this is deliberately NOT multiplied by the process arg.
		var/mob/living/carbon/human/H = I.loc
		if(istype(H))
			H.adjustToxLoss(toxicity * 0.01)
