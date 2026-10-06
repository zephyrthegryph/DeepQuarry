//Barricades!
/obj/structure/barricade
	name = "barricade"
	desc = "This space is blocked off by a barricade."
	icon = 'icons/obj/structures.dmi'
	icon_state = "barricade"
	anchored = TRUE
	density = TRUE
	max_integrity = 100
	var/datum/material/material

CAPABILITIES(/obj/structure/barricade)
	param(nameof(barricade_material), pos = 1, apply = PROC_REF(build_of))

/// The barricade's material (its constructor param; a subtype's default).
/obj/structure/barricade/var/barricade_material = MAT_WOOD

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/structure/barricade/proc/build_of(material_name)
	material = get_material_by_name("[material_name || MAT_WOOD]")
	if(!material)
		spent(src)
		return
	name = "[material.display_name] barricade"
	desc = "This space is blocked off by a barricade made of [material.display_name]."
	color = material.icon_colour
	max_integrity = material.integrity
	update_integrity(max_integrity)

/obj/structure/barricade/get_material()
	return material

/// Barricades are cover: small rounds mostly bury themselves, heavy ones and beams bite.
/obj/structure/barricade/projectile_damage(obj/item/projectile/P, def_zone)
	var/heavy = P.get_structure_damage() > 30
	if(P.obj_damage_type() == BURN)
		return receive_projectile(P, def_zone, heavy ? 0.5 : 0.25)
	return receive_projectile(P, def_zone, heavy ? 0.25 : 0.1)

EXTEND_INTERACTIONS(/obj/structure/barricade, \
	INTERACT_ITEM("Use", PROC_REF(interaction_item)), \
)

/obj/structure/barricade/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed(W))
	if(istype(W, /obj/item/stack))
		var/obj/item/stack/D = W
		if(D.get_material_name() != material.name)
			return TRUE //hitting things with the wrong type of stack usually doesn't produce messages, and probably doesn't need to.
		if(get_integrity() < max_integrity)
			if(D.get_amount() < 1)
				to_chat(user, span_warning("You need one sheet of [material.display_name] to repair \the [src]."))
				return TRUE
			act_message(user, src, others = span_notice("%U% begins to repair %T%."))
			om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, D))
			return TRUE
		return TRUE

	if(material == get_material_by_name(MAT_WOOD) || material == get_material_by_name(MAT_SIFWOOD))
		play_sfx(src, SFX_EFFECTS_WOODCUTTING)
	else
		play_sfx(src, SFX_WEAPONS_SMASH)
	switch(W.obj_damage_type())
		if(BURN)
			receive_weapon_hit(W, user, W.force, INJURY_BURN)
		if(BRUTE)
			receive_weapon_hit(W, user, W.force * 0.75)
	return TRUE

/obj/structure/barricade/proc/attackby_timed_done(mob/user, obj/item/stack/D)
	if(!(get_integrity() < max_integrity))
		return
	if(D.use(1))
		repair_damage(max_integrity)
		act_message(user, src, others = span_notice("%U% repairs %T%."))
	return

/obj/structure/barricade/atom_destruction(damage_flag)
	dismantle()
	return ..()

/obj/structure/barricade/attack_generic(mob/user, damage, attack_verb)
	act_message(user, src, others = span_danger("%U% [attack_verb] %T%!"))
	if(material == get_material_by_name(MAT_RESIN))
		play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	else if(material == get_material_by_name(MAT_CLOTH) || material == get_material_by_name(MAT_SYNCLOTH))
		play_sfx(src, SFX_ITEMS_DROP_CLOTHING)
	else if(material == get_material_by_name(MAT_WOOD) || material == get_material_by_name(MAT_SIFWOOD))
		play_sfx(src, SFX_EFFECTS_WOODCUTTING)
	else
		play_sfx(src, SFX_WEAPONS_SMASH)
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)
	return

/obj/structure/barricade/proc/dismantle()
	material.place_dismantled_product(get_turf(src))
	visible_message(span_danger("\The [src] falls apart!"))
	consume(src)
	return

/obj/structure/barricade/CanPass(atom/movable/mover, turf/target)//So bullets will fly over and stuff.
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return FALSE

/obj/structure/barricade/planks
	name = "crude barricade"
	icon_state = "barricade_planks"
	max_integrity = 50

/obj/structure/barricade/sandbag
	name = "sandbags"
	desc = "Bags. Bags of sand. It's rough and coarse and somehow stays in the bag."
	icon = 'icons/obj/sandbags.dmi'
	icon_state = "blank"

/obj/structure/barricade/sandbag
	barricade_material = MAT_CLOTH

CAPABILITIES(/obj/structure/barricade/sandbag)
	smoothing()

/obj/structure/barricade/sandbag/build_of(material_name)
	..()
	if(QDELETED(src))
		return
	name = "[material.display_name] [initial(name)]"
	color = null
	max_integrity = material.integrity * 2	// These things are, commonly, used to stop bullets where possible.
	update_integrity(max_integrity)
	update_connections(1)

DESTROY_EFFECTS(/obj/structure/barricade/sandbag, new /datum/destroy_effects_data(neighbor_type = /obj/structure/barricade/sandbag))

/obj/structure/barricade/sandbag/dismantle()
	update_connections(1, src)
	material.place_dismantled_product(get_turf(src))
	visible_message(span_danger("\The [src] falls apart!"))
	consume(src)
	return

/obj/structure/barricade/sandbag/draw(datum/look/look)
	..()
	if(!material)
		return

	var/image/I

	for(var/i = 1 to 4)
		var/connect = connections?[i] || 0
		I = image('icons/obj/sandbags.dmi', "sandbags[connect]", dir = 1<<(i-1))
		I.color = material.icon_colour
		look.overlay(I)

/obj/structure/barricade/sandbag/update_connections(propagate = 0, obj/structure/barricade/sandbag/ignore = null)
	if(!material)
		return
	var/list/dirs = list()
	for(var/obj/structure/barricade/sandbag/S in orange(src, 1))
		if(!S.material)
			continue
		if(S == ignore)
			continue
		if(propagate >= 1)
			S.update_connections(propagate - 1, ignore)
		if(can_join_with(S))
			dirs += get_dir(src, S)

	connections = string_list(dirs_to_corner_states(dirs))

	changed(src)

/obj/structure/barricade/sandbag/proc/can_join_with(obj/structure/barricade/sandbag/S)
	if(material == S.material)
		return 1
	return 0

/obj/structure/barricade/sandbag/CanPass(atom/movable/mover, turf/target)
	. = ..()

	if(.)
		if(istype(mover, /obj/item/projectile))
			var/obj/item/projectile/P = mover

			if(P.firer && get_dist(P.firer, src) > 1)	// If you're firing from adjacent turfs, you are unobstructed.
				if(P.armor_penetration < (material.protectiveness + material.hardness) || prob(33))
					return FALSE
