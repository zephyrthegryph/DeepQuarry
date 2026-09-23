// SEE code/modules/materials/materials.dm FOR DETAILS ON INHERITED DATUM.
// This class of weapons takes force and appearance data from a material datum.
// They are also fragile based on material data and many can break/smash apart.
/obj/item/material
	hitsound = 'sound/weapons/bladeslice.ogg'
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

/obj/item/material/Initialize(mapload, material_key)
	. = ..()
	if(!material_key)
		material_key = default_material
	set_material(material_key)
	if(!material)
		return INITIALIZE_HINT_QDEL

	matter = material.get_matter()
	if(matter.len)
		for(var/material_type in matter)
			if(!isnull(matter[material_type]))
				matter[material_type] *= force_divisor // May require a new var instead.

	if(!(material.conductive))
		src.flags |= NOCONDUCT

/obj/item/material/get_material()
	return material

/obj/item/material/proc/update_force()
	if(edge || sharp)
		force = material.get_edge_damage()
	else
		force = material.get_blunt_damage()
	force = round(force*force_divisor)
	if(dulled)
		force = round(force*dulled_divisor)
	throwforce = round(material.get_blunt_damage()*thrown_force_divisor)
	//spawn(1)
	//	to_world("[src] has force [force] and throwforce [throwforce] when made from default material [material.name]")

/obj/item/material/proc/set_material(new_material)
	material = get_material_by_name(new_material)
	if(!material)
		qdel(src)
	else
		if(named_from_material)
			name = "[material.display_name] [initial(name)]"
		max_integrity = max(1, round(material.integrity/10)) * MATERIAL_WEAR_UNIT
		update_integrity(max_integrity)
		if(applies_material_colour)
			color = material.icon_colour
		material.dq_apply_material_behaviors(src) // light + a self-processing rad/tox component.
		update_force()

/obj/item/material/Destroy()
	STOP_PROCESSING(SSobj, src)
	. = ..()

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

/obj/item/material/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/whetstone))
		var/obj/item/whetstone/whet = W
		repair(whet.repair_amount, whet.repair_time, user)
	if(istype(W, /obj/item/material/sharpeningkit))
		var/obj/item/material/sharpeningkit/SK = W
		repair(SK.repair_amount, SK.repair_time, user)
	..()

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
	var/turf/T = get_turf(src)
	T.visible_message(span_danger("\The [src] [material.destruction_desc]!"))
	if(isliving(loc))
		var/mob/living/M = loc
		M.drop_from_inventory(src)
	playsound(src, "shatter", 70, 1)
	if(!consumed && drops_debris) material.place_shard(T)
	qdel(src)

/obj/item/material/proc/dull()
	var/turf/T = get_turf(src)
	T.visible_message(span_danger("\The [src] goes dull!"))
	playsound(src, "shatter", 70, 1)
	dulled = 1
	if(is_sharp(src) || has_edge(src))
		sharp = FALSE
		edge = FALSE

/obj/item/material/proc/repair(repair_amount, repair_time, mob/living/user)
	if(!fragile)
		if(get_integrity() < max_integrity)
			user.visible_message("[user] begins repairing \the [src].", "You begin repairing \the [src].")
			if(do_after(user, repair_time, target = src))
				user.visible_message("[user] has finished repairing \the [src]", "You finish repairing \the [src].")
				repair_damage(repair_amount * MATERIAL_WEAR_UNIT)
				dulled = 0
				sharp = initial(sharp)
				edge = initial(edge)
		else
			to_chat(user, span_notice("[src] doesn't need repairs."))
	else
		to_chat(user, span_warning("You can't repair \the [src]."))
		return

/obj/item/material/proc/sharpen(material, sharpen_time, kit, mob/living/M)
	if(!fragile && src.material.can_sharpen)
		if(get_integrity() < max_integrity)
			to_chat(M, "You should repair [src] first. Try using [kit] on it.")
			return FALSE
		M.visible_message("[M] begins to replace parts of [src] with [kit].", "You begin to replace parts of [src] with [kit].")
		if(do_after(M, sharpen_time, target = src))
			M.visible_message("[M] has finished replacing parts of [src].", "You finish replacing parts of [src].")
			src.set_material(material)
			return TRUE
	else
		to_chat(M, span_warning("You can't sharpen and re-edge [src]."))
		return FALSE

