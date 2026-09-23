// Material-driven stock parts.
//
// The upstream tier system (.../adv, .../super, .../hyper, .../omni and
// the per-type variants like /nano /pico /phasic /high /ultra) has been
// removed. /obj/item/stock_parts now carries a `material_id` that
// points into GLOB.name_to_material; get_rating() derives the rating
// from a per-part-type formula over the material's properties.
//
// Unimbued parts (material_id = null) ride the upstream `rating = 1`
// baseline — they work, they're just bad. Players upgrade a part by
// applying a real material sheet; processed alloys retain their batch identity.
//
// Per-part-type formulas live in dq_part_rating_for. They're calibrated
// so a stat in the 50-range yields ~rating 2, stats in the 80-range
// yield ~rating 4, and the 100+ exotic ceiling lands at rating 5 — the
// same 1-5 envelope the old tier system occupied.

/obj/item/stock_parts
	// name of the /datum/material this part is made from
	// (lowertext, e.g. "processed_alloy_a1b2c3"). Null = unmodified baseline.
	var/material_id


/obj/item/stock_parts/proc/dq_get_material()
	if(!material_id)
		return null
	return GLOB.name_to_material[material_id]


/// Resolve the rating from the assigned material via the part-type
/// formula. Unimbued parts chain to upstream so any future upstream
/// get_rating() override stays wired through us.
/obj/item/stock_parts/get_rating()
	if(has_functional_construction())
		var/derived_composite = dq_composite_part_rating(src)
		if(derived_composite > 0)
			return derived_composite
	if(material_id)
		var/datum/material/M = dq_get_material()
		if(M)
			var/derived = dq_part_rating_for(src, M)
			if(derived > 0)
				return derived
	return ..()

/// Every named part of a multipart stock component participates in its rating.
/// This deliberately uses role-specific physics rather than averaging the
/// recipe into one decorative "core" material.
/proc/dq_composite_part_rating(obj/item/stock_parts/part)
	var/raw = 0
	if(istype(part, /obj/item/stock_parts/capacitor))
		var/datum/material/electrode = part.material_for_role(MATERIAL_ROLE_ELECTRODE)
		var/datum/material/dielectric = part.material_for_role(MATERIAL_ROLE_DIELECTRIC)
		var/datum/material/contacts = part.material_for_role(MATERIAL_ROLE_CONTACTS)
		var/datum/material/casing = part.material_for_role(MATERIAL_ROLE_STRUCTURE)
		if(!electrode || !dielectric || !contacts || !casing) return 0
		raw = electrode.conductivity * 0.35 + dielectric.dielectric_strength * 0.3 + contacts.conductivity * 0.2 + casing.heat_resistance * 0.15
	if(istype(part, /obj/item/stock_parts/manipulator))
		var/datum/material/actuator = part.material_for_role(MATERIAL_ROLE_ACTUATOR)
		var/datum/material/bearings = part.material_for_role(MATERIAL_ROLE_BEARINGS)
		var/datum/material/frame = part.material_for_role(MATERIAL_ROLE_FRAME)
		var/datum/material/insulation = part.material_for_role(MATERIAL_ROLE_INSULATION)
		if(!actuator || !bearings || !frame || !insulation) return 0
		raw = actuator.conductivity * 0.3 + bearings.elasticity * 0.25 + frame.integrity * 0.25 + insulation.dielectric_strength * 0.2
	if(istype(part, /obj/item/stock_parts/matter_bin))
		var/datum/material/chamber = part.material_for_role(MATERIAL_ROLE_STRUCTURE)
		var/datum/material/liner = part.material_for_role(MATERIAL_ROLE_LINER)
		var/datum/material/frame = part.material_for_role(MATERIAL_ROLE_FRAME)
		if(!chamber || !liner || !frame) return 0
		raw = chamber.integrity * 0.45 + liner.corrosion_resistance * 0.25 + frame.integrity * 0.3
	if(istype(part, /obj/item/stock_parts/scanning_module))
		var/datum/material/sensor = part.material_for_role(MATERIAL_ROLE_SENSOR)
		var/datum/material/optics = part.material_for_role(MATERIAL_ROLE_OPTICAL)
		var/datum/material/traces = part.material_for_role(MATERIAL_ROLE_CONDUCTOR)
		var/datum/material/housing = part.material_for_role(MATERIAL_ROLE_STRUCTURE)
		if(!sensor || !optics || !traces || !housing) return 0
		raw = (sensor.magnetism + sensor.reactivity) * 0.2 + optics.purity_equivalent() * 0.25 + traces.conductivity * 0.25 + housing.integrity * 0.1
	if(istype(part, /obj/item/stock_parts/micro_laser))
		var/datum/material/emitter = part.material_for_role(MATERIAL_ROLE_EMITTER)
		var/datum/material/optics = part.material_for_role(MATERIAL_ROLE_OPTICAL)
		var/datum/material/thermal = part.material_for_role(MATERIAL_ROLE_THERMAL)
		var/datum/material/mount = part.material_for_role(MATERIAL_ROLE_STRUCTURE)
		if(!emitter || !optics || !thermal || !mount) return 0
		raw = (dq_material_luminescence(emitter) + emitter.conductivity) * 0.2 + optics.purity_equivalent() * 0.25 + thermal.conductivity * (1 - thermal.thermal_insulation / 125) * 0.2 + mount.integrity * 0.15
	return raw > 0 ? _dq_part_rating_value(raw / 25) : 0


/// Per-part-type formula. Each part type returns a rating in roughly
/// the 1-5 range from the material's property profile. The bucketed
/// type checks keep things simple — extending with a new part type
/// just means adding another `istype` branch here.
/proc/dq_part_rating_for(obj/item/stock_parts/P, datum/material/M)
	if(istype(P, /obj/item/stock_parts/capacitor))
		// Capacitor stores charge — driven by conductivity.
		return _dq_part_rating_value(M.conductivity / 25)
	if(istype(P, /obj/item/stock_parts/scanning_module))
		// Scanning module senses fields — magnetism + reactivity.
		return _dq_part_rating_value((M.magnetism + M.reactivity) / 50)
	if(istype(P, /obj/item/stock_parts/manipulator))
		// Manipulator moves matter — density + elasticity.
		return _dq_part_rating_value((M.density + M.elasticity) / 50)
	if(istype(P, /obj/item/stock_parts/micro_laser))
		// Laser emits coherent light — luminescence + conductivity.
		return _dq_part_rating_value((dq_material_luminescence(M) + M.conductivity) / 50)
	if(istype(P, /obj/item/stock_parts/matter_bin))
		// Matter bin holds compressed matter — density + integrity.
		// Operator precedence fix: the prior formula was
		// `(M.density + M.integrity / 50) / 30` which DM parses as
		// `(M.density + (M.integrity / 50)) / 30`. Every sibling
		// formula uses `(a + b) / 50`, the parens belong around the
		// add.
		return _dq_part_rating_value((M.density + M.integrity) / 50)
	return 0


/// Clamp the raw formula output to a 1-5 envelope matching the old
/// tier scale. Below 1 still works at rating 1; above 5 caps without
/// explicit synergy effects.
/proc/_dq_part_rating_value(raw)
	if(raw <= 0)
		return 1
	return clamp(round(raw, 0.1), 1, 5)


// --- Material core ---------------------------------------------------------
//
// One sheet is consumed; the part absorbs the material id, takes on its
// color, and re-derives its rating. The part creates its own required geometry.

/obj/item/stock_parts/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/stack/material))
		var/obj/item/stack/material/S = W
		if(material_id)
			to_chat(user, span_warning("\The [src] already has a material core. Use a fresh part."))
			return ..()
		if(!S.material || S.get_amount() < 1)
			return ..()
		material_id = S.material.name
		S.use(1)
		var/datum/material/M = dq_get_material()
		if(M)
			name = "[M.display_name] [initial(name)]"
			color = M.icon_colour
			// sync the upstream `rating` var to the
			// material-derived value so legacy callers that read
			// `part.rating` directly (instead of get_rating()) see
			// the new rating.
			rating = get_rating()
			// Apply any component-driven behaviors (luminescent
			// glow etc.) from the imbued material.
			M.dq_apply_material_behaviors(src)
			to_chat(user, span_notice("You install a [M.display_name] material core in \the [initial(name)]. Effective rating: [rating]."))
		return ..() // Chain so upstream attackby side-effects (sound, fingerprint, etc.) still run
	return ..()


/obj/item/stock_parts/examine(mob/user)
	. = ..()
	if(material_id)
		var/datum/material/M = dq_get_material()
		if(M)
			. += span_notice("Material core: <b>[M.display_name]</b>. Effective rating: [get_rating()].")
	else
		. += span_notice("Unmodified — baseline rating [rating]. Apply a suitably formed material sheet to upgrade it.")
