// Substance -> material bridge.
//
// The substance datum is the base grammar; a substance becomes a REAL thing in the
// game by being cast into a material. This wraps a substance's hidden profile in a
// /datum/material so it flows through the entire existing manufacturing pipeline —
// stack recipes, the autolathe/protolathe, walls, weapons, armour — and any item
// forged from it carries the substance's effect (via /datum/component/substance_infusion,
// applied through the standard material-behaviour seam).
//
// It mirrors the round-rolled /datum/material/dynamic pattern exactly: a unique
// generated `name` registered at runtime in GLOB.name_to_material, so every reader
// that resolves a material by name works without knowing it was minted this round.

/datum/material/substance
	// No default `name` — abstract; only runtime-registered instances get one, so
	// populate_material_list() skips this base type (it ignores nameless materials).
	stack_type = /obj/item/stack/material/substance
	/// The substance this material embodies (its effect + hidden profile). Shared
	/// across every item made of this material; per-item state lives in the
	/// infusion component.
	var/datum/substance/infused_substance
	/// How many times an item forged from this material can discharge the effect.
	var/effect_charges = SUBSTANCE_INFUSION_CHARGES

/datum/material/substance/Destroy()
	QDEL_NULL(infused_substance)
	return ..()

// Mint (or reuse) a registered material embodying `S` and return its registry key.
// The key is stable for the round and usable anywhere a material name is accepted.
/proc/substance_register_material(datum/substance/S)
	if(!istype(S))
		return null
	var/key = "substance_mat_[substance_next_material_id()]"
	var/datum/material/substance/M = new()
	M.name = key
	M.infused_substance = S.Clone()
	var/fam = substance_family_name(S.family)
	M.display_name = "[lowertext(fam)] alloy"
	M.use_name = M.display_name
	M.icon_colour = substance_family_colour(S.family)
	M.material_class = substance_family_material_class(S.family)
	// Cargo's axis: potent substances are worth more than the flat base.
	M.supply_conversion_value = clamp(round(4 + (S.energy + S.purity) / 25), 4, 20)
	substance_derive_material_stats(M, S)
	substance_derive_material_behaviors(M, S)
	GLOB.name_to_material[key] = M
	return key

// Drive the (now working) material behaviour axes from the substance: radiant/discharge
// substances glow, hot radiant/void ones irradiate, corrosive/spore ones are toxic.
// So substance gear passively glows / irradiates / poisons through the standard pipeline
// on top of its triggered discharge effect.
/proc/substance_derive_material_behaviors(datum/material/substance/M, datum/substance/S)
	switch(S.family)
		if(SUBFAM_RADIANT)
			M.luminescence = clamp(round(S.energy * 0.6), 0, 80)
			M.radioactivity = clamp(round((S.energy - 50) * 0.4), 0, 40)
		if(SUBFAM_DISCHARGE)
			M.luminescence = clamp(round(S.energy * 0.35), 0, 60)
		if(SUBFAM_VOID)
			M.radioactivity = clamp(round((S.energy - 40) * 0.4), 0, 40)
		if(SUBFAM_CORROSIVE, SUBFAM_SPORE)
			M.toxicity = clamp(round(S.energy * 0.4), 0, 50)

// Monotonic per-round id source for unique material keys.
/proc/substance_next_material_id()
	var/static/counter = 0
	counter++
	return counter

// Derive the eleven core material stats from the five substance axes, so a cast
// substance forges into a believable material: high-affinity bonds hard and holds
// integrity; energy conducts; volatility reacts; purity resists corrosion/heat.
/proc/substance_derive_material_stats(datum/material/substance/M, datum/substance/S)
	M.hardness             = clamp(round(S.affinity * 0.6 + S.energy * 0.4), 1, 100)
	M.integrity            = clamp(round(20 + S.affinity * 0.8), 1, 100)
	M.density              = clamp(round(40 + S.energy * 0.4), 1, 100)
	M.elasticity           = clamp(round(S.affinity * 0.5), 1, 100)
	M.brittleness          = clamp(round((100 - S.purity) * 0.3), 0, 100)
	M.heat_resistance      = clamp(round(S.purity * 0.7), 1, 100)
	M.thermal_insulation   = clamp(round(30 + (100 - S.volatility) * 0.3), 1, 100)
	M.conductivity         = clamp(round(S.energy * 0.7), 1, 100)
	M.magnetism            = clamp(round(S.volatility * 0.4), 0, 100)
	M.reactivity           = clamp(round(S.volatility * 0.8), 1, 100)
	M.corrosion_resistance = clamp(round(S.purity * 0.8), 1, 100)

// Family -> material class (so a cast substance feels like the right stuff).
/proc/substance_family_material_class(fam)
	switch(fam)
		if(SUBFAM_DISCHARGE, SUBFAM_RADIANT) return MATCLASS_CRYSTAL
		if(SUBFAM_FORCE, SUBFAM_FIELD)       return MATCLASS_METAL
		if(SUBFAM_SPORE)                     return MATCLASS_ORGANIC
	return MATCLASS_CERAMIC // thermal / corrosive / void

// Family -> a themed tint for the alloy and everything forged from it.
/proc/substance_family_colour(fam)
	switch(fam)
		if(SUBFAM_DISCHARGE) return "#6fd0ff"
		if(SUBFAM_THERMAL)   return "#ff7a3c"
		if(SUBFAM_FORCE)     return "#b0b6c0"
		if(SUBFAM_FIELD)     return "#7affc0"
		if(SUBFAM_SPORE)     return "#8fcf5a"
		if(SUBFAM_CORROSIVE) return "#caff4d"
		if(SUBFAM_RADIANT)   return "#fff36f"
		if(SUBFAM_VOID)      return "#a86fff"
	return "#888888"

// Apply this material's behaviours to a forged item: the standard component
// behaviours first (light/rad/tox), then the substance infusion that makes the
// item discharge its effect at its form's trigger.
/datum/material/substance/dq_apply_material_behaviors(obj/item/I)
	. = ..()
	apply_substance_infusion(I)

// Attach ONLY the discharge infusion (no persistent light/rad/tox processing). Used
// for forms where the item is a transient effect-carrier rather than carried gear —
// e.g. a forged round's bullet, which fires the effect on impact then is destroyed.
/datum/material/substance/proc/apply_substance_infusion(obj/item/I)
	if(I && infused_substance)
		I.AddComponent(/datum/component/substance_infusion, infused_substance, effect_charges)

// ---- The manufacturing feedstock -------------------------------------------
// A stack of cast substance. Works with every existing material stack recipe and
// the lathes, exactly like the round-rolled exotic stack it mirrors.

/obj/item/stack/material/substance
	icon = 'icons/obj/mining.dmi'
	icon_state = "ore_diamond"
	default_type = MAT_STEEL // placeholder for a bare instantiation; real spawns pass a key
	no_variants = TRUE
	pass_color = TRUE
	strict_color_stacking = TRUE
	// Runtime-generated per-round alloy; no static autolathe design (forge via the
	// material-selectable lathe design or the in-hand stack recipes instead).
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/substance/Initialize(mapload, _amount, _material_name)
	if(_material_name)
		default_type = _material_name
	. = ..(mapload, _amount)
	if(material)
		color = material.icon_colour

/obj/item/stack/material/substance/examine(mob/user)
	. = ..()
	var/datum/substance/S = substance_stack_substance(src)
	if(S)
		. += span_notice("Substance: <b>[substance_family_name(S.family)]</b>, discharges [substance_trigger_name(S.trigger)].")
		. += span_notice("<i>Forge or print it into gear and it carries that effect. Its hidden properties are learned by combining it.</i>")

// Read the substance embodied by a stack (null if it is not a substance material).
/proc/substance_stack_substance(obj/item/stack/material/stack)
	if(!istype(stack) || !istype(stack.material, /datum/material/substance))
		return null
	var/datum/material/substance/M = stack.material
	return M.infused_substance

// Mint a material for `S` and spawn a stack of it. The universal way a substance
// becomes a real, workable object (there is no vial — a substance is always
// material). Returns the stack, or null.
/proc/substance_spawn_stack(turf/T, datum/substance/S, amount = 1)
	if(!T || !istype(S))
		return null
	var/key = substance_register_material(S)
	if(!key)
		return null
	return new /obj/item/stack/material/substance(T, clamp(round(amount), 1, 50), key)

// ---- Field find: raw substance sheets --------------------------------------
// What expeditions bring back instead of a bespoke container — a stack of raw
// substance alloy from a xenoarchaeology source, minted fresh per spawn.
/obj/item/stack/material/substance/random_field/Initialize(mapload, _amount, _material_name)
	if(!_material_name)
		var/list/ids = substance_archetype_ids_by_category("field")
		if(length(ids))
			var/datum/substance/S = substance_from_archetype(pick(ids), 5)
			_material_name = substance_register_material(S)
			qdel(S) // register_material took a clone
	return ..(mapload, _amount || rand(3, 6), _material_name)
