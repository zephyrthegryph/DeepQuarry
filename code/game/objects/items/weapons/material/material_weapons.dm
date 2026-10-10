// SEE code/modules/materials/materials.dm FOR DETAILS ON INHERITED DATUM.
// This class of weapons takes force and appearance data from a material datum.
// They are also fragile based on material data and many can break/smash apart.
/obj/item/material
	hitsound = SFX_WEAPONS_BLADESLICE
	gender = NEUTER
	throw_speed = 3
	throw_range = 7
	w_class = ITEMSIZE_NORMAL
	sharp = FALSE
	edge = FALSE
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
			)

	var/applies_material_colour = 1
	var/unbreakable = 0		//Doesn't wear down
	var/fragile = 0			//Shatters when it dies
	var/dulled = 0			//Has gone dull
	var/can_dull = 0
	var/force_divisor = 0.5
	var/thrown_force_divisor = 0.5
	var/dulled_divisor = 0.5	//Just drops the damage by half
	var/default_material = MAT_STEEL
	var/datum/material/material
	var/drops_debris = 1
	var/named_from_material = 1 // Does it prepend the material's name to it's name?

TYPE_TABLE_DECLARE(/obj/item/material, weapon_forced_material, null)

// ALLOW(init/INSTANCE_STATE): a material weapon is made of its material (or the type's forced one), scaled by its force divisor
/obj/item/material/Initialize(mapload)
	var/forced_material = TYPE_TABLE_GET(src, weapon_forced_material)
	if(forced_material)
		default_material = forced_material
	. = ..()
	set_material(default_material)
	if(!material)
		return INITIALIZE_HINT_QDEL

	// A material weapon is made of its material, scaled by force_divisor.
	var/list/new_matter = material.get_matter()
	for(var/material_type in new_matter)
		if(!isnull(new_matter[material_type]))
			new_matter[material_type] *= force_divisor // May require a new var instead.
	if(length(new_matter) == 1)
		set_bulk_material(new_matter[1], new_matter[new_matter[1]])
	else
		set_material_mix(new_matter)

	if(!(material.conductive))
		src.flags |= NOCONDUCT

/obj/item/material/get_material()
	return material

/obj/item/material/proc/update_force()
	if(edge || sharp)
		force = material.edge_damage()
	else
		force = material.blunt_damage()
	force = round(force*force_divisor)
	if(dulled)
		force = round(force*dulled_divisor)
	throwforce = round(material.blunt_damage()*thrown_force_divisor)

/obj/item/material/proc/set_material(new_material)
	material = get_material_by_name(new_material)
	if(!material)
		spent(src)
	else
		if(named_from_material)
			name = "[material.display_name] [initial(name)]"
		max_integrity = max(1, round(material.integrity/10)) * MATERIAL_WEAR_UNIT
		update_integrity(max_integrity)
		if(applies_material_colour)
			color = material.icon_colour
		material.dq_apply_material_behaviors(src) // light + a self-processing rad/tox component.
		update_force()

/obj/item/material/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier)
	. = ..()
	// A melee strike is an impact + contact form trigger; a substance-infused
	// weapon discharges here (the infusion ignores it unless its trigger matches).
	material_response_impact(get_turf(target), target)
	if(!unbreakable)
		if(material.is_brittle())
			material_wear(get_integrity())
		else if(!prob(material.hardness))
			material_wear(MATERIAL_WEAR_UNIT)

/obj/item/material/throw_impact(atom/hit_atom)
	. = ..()
	material_response_impact(get_turf(hit_atom) || get_turf(src), hit_atom)

// EXTEND, not DECLARE: many subtypes DECLARE interactions of their own, which this must not replace.
CAPABILITIES(/obj/item/material)
	op("material_interaction_item", item(/obj/item), label("Repair"), then(PROC_REF(material_interaction_item)))
	// The whetstone's repair and the sharpening kit's re-edging take the time the tool says; the amount and the new material come from the tool.
	op("repair", ai(), takes("repair_amount", "repair_time"), wait(PROC_REF(repair_wait), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(repair_timed_done)))
	op("sharpen", ai(), takes("material", "sharpen_time"), wait(PROC_REF(sharpen_wait), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(sharpen_timed_done)))
	param(nameof(default_material), pos = 1)

/// Old attackby: repairs with a whetstone or sharpening kit, then falls through as its ..() did.
/obj/item/material/proc/material_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/whetstone))
		var/obj/item/whetstone/whet = W
		repair(whet.repair_amount, whet.repair_time, user)
	if(istype(W, /obj/item/material/sharpeningkit))
		var/obj/item/material/sharpeningkit/SK = W
		repair(SK.repair_amount, SK.repair_time, user)
	return OP_DECLINE

/// Wear from use. Wear is not a blow from outside, so armour doesn't apply.
/obj/item/material/proc/material_wear(amount)
	if(amount > 0)
		take_damage(amount, BRUTE, null, FALSE)

/// Worn out: fragile things shatter, things that can dull go dull, the rest
/// stay worn out until repaired. Fire and acid destroy it outright.
/obj/item/material/atom_destruction(damage_flag)
	if(damage_flag == FIRE || damage_flag == ACID)
		return ..()
	if(fragile)
		shatter()
	else if(!dulled && can_dull)
		dull()

/obj/item/material/proc/shatter(consumed)
	if(loc?.release_refusal(src))
		return
	var/turf/T = get_turf(src)
	T.visible_message(span_danger("\The [src] [material.destruction_desc]!"))
	if(isliving(loc))
		var/mob/living/M = loc
		M.drop_from_inventory(src)
	play_sfx(src, SFX_SHATTER)
	if(!consumed && drops_debris) material.place_shard(T)
	consume(src)

/obj/item/material/proc/dull()
	var/turf/T = get_turf(src)
	T.visible_message(span_danger("\The [src] goes dull!"))
	play_sfx(src, SFX_SHATTER)
	dulled = 1
	if(is_sharp(src) || has_edge(src))
		sharp = FALSE
		edge = FALSE

/obj/item/material/proc/repair(repair_amount, repair_time, mob/living/user)
	if(!fragile)
		if(get_integrity() < max_integrity)
			act_message(user, src, MSG_SELF("You begin repairing %T%."), MSG_OTHERS("%U% begins repairing %T%."))
			perform_op(user, src, "repair", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("repair_amount" = repair_amount, "repair_time" = repair_time))
		else
			to_chat(user, span_notice("[src] doesn't need repairs."))
	else
		to_chat(user, span_warning("You can't repair \the [src]."))
		return

/obj/item/material/proc/repair_wait(datum/act/op/A)
	return A.arg("repair_time")

/obj/item/material/proc/repair_timed_done(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF("You finish repairing %T%."), MSG_OTHERS("%U% has finished repairing %T%"))
	repair_damage(A.arg("repair_amount") * MATERIAL_WEAR_UNIT)
	dulled = 0
	sharp = initial(sharp)
	edge = initial(edge)
	return OP_OK

/obj/item/material/proc/sharpen(material, sharpen_time, kit, mob/living/M)
	if(!fragile && src.material.can_sharpen)
		if(get_integrity() < max_integrity)
			to_chat(M, "You should repair [src] first. Try using [kit] on it.")
			return FALSE
		act_message(M, src, MSG_SELF("You begin to replace parts of %T% with [kit]."), MSG_OTHERS("%U% begins to replace parts of %T% with [kit]."))
		perform_op(M, src, "sharpen", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("material" = material, "sharpen_time" = sharpen_time))
		return TRUE
	else
		to_chat(M, span_warning("You can't sharpen and re-edge [src]."))
		return FALSE

/obj/item/material/proc/sharpen_wait(datum/act/op/A)
	return A.arg("sharpen_time")

/obj/item/material/proc/sharpen_timed_done(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF("You finish replacing parts of %T%."), MSG_OTHERS("%U% has finished replacing parts of %T%."))
	src.set_material(A.arg("material"))
	return OP_OK
