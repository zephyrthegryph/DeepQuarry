// Component behavior wiring.
//
// /datum/material carries three /datum/component subtypes (luminescent,
// radioactive, toxic) — see material_components.dm. The component
// magnitudes are read directly via dq_material_<x> helpers, but the
// *behavior* (emit light, irradiate, harm holders) needs to be applied
// to each item that's made from a material that carries the component.
//
// This file owns the apply-behavior hook on /datum/material plus the
// per-component apply procs. /obj/item/material's set_material upstream
// is patched to call dq_apply_material_behaviors once the material is
// assigned, so any item with applies_material_colour or similar gets the
// component-driven behavior set up at creation time.
//
// process() override for /obj/item/material adds radiation pulse +
// toxic damage ticks driven by the magnitudes — replacing the
// previously-commented-out upstream uranium-irradiation block.

/// Walk the material's components and apply each to the item that's
/// just been assigned this material. Called from
/// /obj/item/material/set_material via DQEdit.
/datum/material/proc/dq_apply_material_behaviors(obj/item/I)
	if(!I)
		return
	var/datum/component/material_luminescent/lum = GetComponent(/datum/component/material_luminescent)
	if(lum)
		// set_light: range, power, color. Scale magnitude (0-80) into a
		// reasonable light range (0-4 tiles). Color picks up the
		// material's tint.
		var/range = clamp(lum.magnitude / 20, 0.5, 4)
		var/power = clamp(lum.magnitude / 30, 0.3, 2)
		I.set_light(range, power, icon_colour)


/// Radiation tick. Called from /obj/item/material/process() (added
/// below) when the material has a /datum/component/material_radioactive
/// attached. Pulse strength scales with magnitude.
/datum/material/proc/dq_radiation_tick(obj/item/I)
	if(!I)
		return
	var/datum/component/material_radioactive/rad = GetComponent(/datum/component/material_radioactive)
	if(!rad || !rad.magnitude)
		return
	radiation_pulse(
		I,
		max_range = 3,
		threshold = RAD_LIGHT_INSULATION,
		chance = round(rad.magnitude * 0.5, 1),
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = rad.magnitude
	)


/// Toxic tick. Apply low-grade toxin damage to a mob holding the item.
/// Magnitude scales the per-tick dose.
/datum/material/proc/dq_toxic_tick(obj/item/I)
	if(!I)
		return
	var/datum/component/material_toxic/tox = GetComponent(/datum/component/material_toxic)
	if(!tox || !tox.magnitude)
		return
	var/mob/living/carbon/human/H = I.loc
	if(!istype(H))
		return
	// Sub-lethal but real: a high-toxicity material (70) gives ~0.7 tox
	// per tick. Stacks if a player carries multiple toxic items.
	H.adjustToxLoss(tox.magnitude * 0.01)


// --- Item-side process tick -------------------------------------------------
//
// /obj/item/material/process is the per-tick handler that fires while the
// item's material declares products_need_process. Walks the material's
// behavior components and applies each.

/obj/item/material/process()
	if(!material)
		STOP_PROCESSING(SSobj, src)
		return
	material.dq_radiation_tick(src)
	material.dq_toxic_tick(src)


// --- products_need_process gets toxic in the picture ------------------------
//
// Upstream's products_need_process was rewired in _materials.dm to
// query dq_material_radioactivity. Extend it here so toxic also
// counts (luminescence doesn't need ticking — light is set once).

/datum/material/products_need_process()
	return (dq_material_radioactivity(src) > 0) || (dq_material_toxicity(src) > 0)
