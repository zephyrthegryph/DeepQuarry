// Material emissions (was /datum/component/material_behaviors), applied by
// /datum/material/proc/dq_apply_material_behaviors() (code/modules/materials/material_behaviors.dm).

// ---- The emission behaviour ------------------------------------------------
// (was /datum/component/material_behaviors). The magnitudes live on the item;
// the light is set once, and an item that irradiates or poisons carries the
// shared material_emission behaviour, which ticks every 2 s while attached.

/obj/item
	var/mat_luminescence = 0
	var/mat_radioactivity = 0
	var/mat_toxicity = 0

/datum/om/behaviour/material_emission
	every = 2 SECONDS

/// Sets `I`'s emission magnitudes: light now; the behaviour while it irradiates or poisons.
/proc/configure_item_emissions(obj/item/I, _lum = 0, _rad = 0, _tox = 0, colour = null)
	var/old_luminescence = I.mat_luminescence
	I.mat_luminescence = _lum
	I.mat_radioactivity = _rad
	I.mat_toxicity = _tox
	if(I.mat_luminescence > 0)
		var/range = clamp(I.mat_luminescence / 20, 0.5, 4)
		var/power = clamp(I.mat_luminescence / 30, 0.3, 2)
		I.set_light(range, power, colour)
	else if(old_luminescence > 0)
		I.set_light(0)
	if(I.mat_radioactivity > 0 || I.mat_toxicity > 0)
		om_attach(I, /datum/om/behaviour/material_emission)
	else
		om_detach(I, /datum/om/behaviour/material_emission)

/// TRUE while `I`'s material irradiates or poisons.
/proc/item_emitting(obj/item/I)
	return om_attached(I, /datum/om/behaviour/material_emission)

/datum/om/behaviour/material_emission/tick(obj/item/I, dt)
	item_emission_step(I)

/proc/item_emission_step(obj/item/I)
	if(QDELETED(I))
		return
	var/mat_radioactivity = I.mat_radioactivity
	var/mat_toxicity = I.mat_toxicity
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
