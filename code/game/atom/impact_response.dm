// Material response (doc/rewrite/damage.md §4 step 4, roadmap D2).
//
// What an object is made of changes how much of a hit it takes:
//   hardness                          resists blunt (and blast) impacts
//   yield strength                    resists cuts
//   yield strength and toughness      resist punctures
//   melting point                     resists thermal damage
// Each axis reduces damage only above steel, the reference material, and never
// adds any: steel, glass, wood and plastic objects take what they always took;
// plasteel, titanium, diamond and the like shrug some of it off. Reductions cap at
// IMPACT_RESIST_CAP. Values come from the object's material template
// (get_material()), else P1 properties (items: PROP_HARDNESS & co.), else its
// material totals. Responses are interned by value like armour.

/// Hardness at and below which a material resists nothing extra (steel).
#define IMPACT_HARDNESS_FLOOR 60
/// Hardness above the floor per whole of damage resisted.
#define IMPACT_HARDNESS_SCALE 200
#define IMPACT_YIELD_FLOOR 300
#define IMPACT_YIELD_SCALE 1500
#define IMPACT_TOUGHNESS_FLOOR 25
#define IMPACT_TOUGHNESS_SCALE 200
/// Melting point (K) at and below which heat meets no extra resistance (steel).
#define IMPACT_MELTING_FLOOR 1800
#define IMPACT_MELTING_SCALE 8000
/// Most any one axis can take off a hit.
#define IMPACT_RESIST_CAP 0.5

/// Fraction of a hit resisted on one axis: 0 at or below `floor`, rising by
/// one per `scale` above it, capped.
/proc/dq_impact_resist(value, floor, scale)
	if(isnull(value) || value <= floor)
		return 0
	return min((value - floor) / scale, IMPACT_RESIST_CAP)

/// The interned response of a material with these strengths. Null arguments
/// resist nothing on their axes.
/proc/dq_impact_response(hardness, yield_strength, toughness, melting_point)
	var/static/list/interned = list()
	var/canonical = "[hardness]|[yield_strength]|[toughness]|[melting_point]"
	. = interned[canonical]
	if(!.)
		. = new /datum/impact_response(hardness, yield_strength, toughness, melting_point)
		interned[canonical] = .

/// The response of material template `M`.
/proc/dq_impact_response_for_material(datum/material/M)
	if(!M)
		return null
	return dq_impact_response(M.hardness, M.yield_strength, M.fracture_toughness, M.melting_point)

/// The response of a matter list (material name -> amount): each axis is the
/// weakest material's, as the P1 properties fold them.
/proc/dq_impact_response_for_matter(list/matter)
	var/hardness
	var/yield_strength
	var/toughness
	var/melting_point
	for(var/name in matter)
		var/datum/material/M = GLOB.name_to_material[name]
		if(!M)
			continue
		hardness = isnull(hardness) ? M.hardness : min(hardness, M.hardness)
		yield_strength = isnull(yield_strength) ? M.yield_strength : min(yield_strength, M.yield_strength)
		toughness = isnull(toughness) ? M.fracture_toughness : min(toughness, M.fracture_toughness)
		if(!isnull(M.melting_point))
			melting_point = isnull(melting_point) ? M.melting_point : min(melting_point, M.melting_point)
	if(isnull(hardness))
		return null
	return dq_impact_response(hardness, yield_strength, toughness, melting_point)

/// DAMAGE_* kind a bare object damage flag stands for, for take_damage() calls
/// that come without a packet. 0 when no material axis applies.
/proc/dq_damage_kind_for_flag(damage_flag)
	switch(damage_flag)
		if(MELEE)
			return DAMAGE_BLUNT
		if(BULLET)
			return DAMAGE_PIERCE
		if(LASER, FIRE)
			return DAMAGE_THERMAL
		if(BOMB)
			return DAMAGE_BLAST
		if(ACID)
			return DAMAGE_CORROSIVE
	return 0


/datum/impact_response
	/// DAMAGE_* -> multiplier on what gets through (1 = unchanged).
	var/list/factors

/datum/impact_response/New(hardness, yield_strength, toughness, melting_point)
	..()
	factors = new /list(DAMAGE_KIND_COUNT)
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		factors[kind] = 1
	var/blunt = dq_impact_resist(hardness, IMPACT_HARDNESS_FLOOR, IMPACT_HARDNESS_SCALE)
	var/cut = dq_impact_resist(yield_strength, IMPACT_YIELD_FLOOR, IMPACT_YIELD_SCALE)
	var/tough = dq_impact_resist(toughness, IMPACT_TOUGHNESS_FLOOR, IMPACT_TOUGHNESS_SCALE)
	factors[DAMAGE_BLUNT] = 1 - blunt
	factors[DAMAGE_BLAST] = 1 - blunt
	factors[DAMAGE_SHARP] = 1 - cut
	factors[DAMAGE_PIERCE] = 1 - (cut + tough) / 2
	factors[DAMAGE_THERMAL] = 1 - dq_impact_resist(melting_point, IMPACT_MELTING_FLOOR, IMPACT_MELTING_SCALE)

/datum/impact_response/Destroy(force)
	if(!force)
		return QDEL_HINT_LETMELIVE
	return ..()

/// Multiplier on `kind` (DAMAGE_*): what gets through.
/datum/impact_response/proc/factor(kind)
	if(kind < 1 || kind > DAMAGE_KIND_COUNT)
		return 1
	return factors[kind]


// ---- Objects ----

/// Multiplier this atom's make-up puts on a hit of `kind` (DAMAGE_*).
/atom/proc/impact_factor(kind)
	return 1

/obj/impact_factor(kind)
	if(!kind)
		return 1
	var/datum/impact_response/response = impact_response()
	return response ? response.factor(kind) : 1

/// This object's material response, or null for none.
/obj/proc/impact_response()
	var/datum/material/M = get_material()
	if(M)
		return dq_impact_response_for_material(M)
	return dq_impact_response_for_matter(material_totals())

/obj/item/impact_response()
	var/datum/material/M = get_material()
	if(M)
		return dq_impact_response_for_material(M)
	var/hardness = PROPERTY(src, PROP_HARDNESS)
	if(isnull(hardness))
		return null
	return dq_impact_response(hardness, PROPERTY(src, PROP_YIELD_STRENGTH), PROPERTY(src, PROP_FRACTURE_TOUGHNESS), PROPERTY(src, PROP_MELTING_POINT))

#undef IMPACT_HARDNESS_FLOOR
#undef IMPACT_HARDNESS_SCALE
#undef IMPACT_YIELD_FLOOR
#undef IMPACT_YIELD_SCALE
#undef IMPACT_TOUGHNESS_FLOOR
#undef IMPACT_TOUGHNESS_SCALE
#undef IMPACT_MELTING_FLOOR
#undef IMPACT_MELTING_SCALE
#undef IMPACT_RESIST_CAP
