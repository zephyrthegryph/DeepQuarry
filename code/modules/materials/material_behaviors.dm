// Material behaviours — the working implementation.
//
// A material's three active behaviours (luminescence, radioactivity, toxicity)
// are plain numeric magnitudes on /datum/material (see material.dm). This file
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
// Configures the item's emissions (light now; rad/tox while carried).

/datum/material/proc/dq_apply_material_behaviors(obj/item/I)
	if(!I)
		return
	// Geometry-specific consumers can override thickness; ordinary fabricated
	// items use a five-millimeter representative path through their material.
	I.set_rad_insulation(radiation_transmission(5))
	I.configure_material_behaviors(luminescence, radioactivity, toxicity, icon_colour)
	dq_apply_material_responses(I)

// ---- The emission behaviour ------------------------------------------------
//. The magnitudes live on the item;
// the light is set once, and an item that irradiates or poisons carries the
// material_emission capability, which ticks every 2 s while granted.

/obj/item
	var/mat_luminescence = 0
	var/mat_radioactivity = 0
	var/mat_toxicity = 0

CAPABILITY_TYPE(material_emission, CAP_MATERIAL_EMISSION, /datum/capability/material_emission, key = NONE)
/datum/capability/material_emission

/datum/capability/material_emission/entries()
	return list(every(2 SECONDS, then(CAP_PROC(emission_tick))))

/datum/capability/material_emission/proc/emission_tick(datum/act/timer/A)
	var/obj/item/I = A.holder
	I.material_emission_step()

/obj/item/proc/configure_material_behaviors(_lum = 0, _rad = 0, _tox = 0, colour = null)
	var/old_luminescence = mat_luminescence
	mat_luminescence = _lum
	mat_radioactivity = _rad
	mat_toxicity = _tox
	if(mat_luminescence > 0)
		var/range = clamp(mat_luminescence / 20, 0.5, 4)
		var/power = clamp(mat_luminescence / 30, 0.3, 2)
		set_light(range, power, colour)
	else if(old_luminescence > 0)
		set_light(0)
	if(mat_radioactivity > 0 || mat_toxicity > 0)
		grant(src, /datum/capability/material_emission, src)
	else
		revoke(src, /datum/capability/material_emission, src)

/// TRUE while the item's material irradiates or poisons.
/obj/item/proc/material_emitting()
	return granted(src, /datum/capability/material_emission)

/obj/item/proc/material_emission_step()
	var/obj/item/I = src
	if(QDELETED(I))
		return
	if(mat_radioactivity > 0)
		radiation_pulse(
			I,
			max_range = 3,
			threshold = RAD_LIGHT_INSULATION,
			chance = round(mat_radioactivity * 0.5, 1),
			minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
			strength = mat_radioactivity,
		)
	if(mat_toxicity > 0)
		// Sub-lethal but real, only while held bare in hand (loc is the mob). Dose is
		// per fixed 2 s tick; deliberately not scaled by dt.
		var/mob/living/carbon/human/H = I.loc
		if(istype(H))
			H.injure(INJURY_TOXIN, mat_toxicity * 0.01, null, I, 0, null, INJURE_SILENT)
