// Basically see-through walls. Used for windows
// If nothing has been built on the low wall, you can climb on it

/obj/structure/low_wall
	name = "low wall"
	desc = "A low wall section which serves as the base of windows, amongst other things."
	layer = TURF_LAYER
	icon = null
	icon_state = "frame"

	//atom_flags = ATOM_FLAG_NO_TEMP_CHANGE | ATOM_FLAG_CLIMBABLE | ATOM_FLAG_CAN_BE_PAINTED | ATOM_FLAG_ADJACENT_EXCEPTION
	anchored = TRUE
	density = TRUE
	throwpass = 1
	layer = TABLE_LAYER

	var/frame_masks = 'icons/obj/wall_frame_bay.dmi'

	max_integrity = 100
	var/stripe_color

	// blend_objects defined on subtypes
	noblend_objects = list(/obj/machinery/door/window, /obj/machinery/door/firedoor)

	var/default_material = DEFAULT_WALL_MATERIAL
	var/datum/material/material
	var/grille_type

TRACKED(/obj/structure/low_wall, material)

/obj/structure/low_wall/draw(datum/look/look)
	..()
	low_wall_look(look)

/// The sprite of the frame: the base type has none of its own (a blank), each style draws its corners over the connections.
/obj/structure/low_wall/proc/low_wall_look(datum/look/look)
	look.state("blank")

/// The tint of the wall's material (a shared definition that never changes: the draw hears of a new material through the tracked `material`).
/obj/structure/low_wall/proc/material_colour()
	return material?.icon_colour

CAPABILITIES(/obj/structure/low_wall)
	smoothing()
	climb()
	op("use_wrench", tool(TOOL_WRENCH), needs(req(PROC_REF(nothing_on_the_wall), because = PROC_REF(fixture_refusal))), begins(MSG(low_wall/disassembling)),
		plays(SFX_ITEMS_RATCHET, at_start = TRUE, volume = 2), wait(4 SECONDS), then(PROC_REF(wrench_act_done)))
	param(nameof(default_material), pos = 1, apply = PROC_REF(build_of))
	op("build_grille", stack(/obj/item/stack/rods, 2), label("Use"), needs(req(PROC_REF(grille_supported), because = MSG(low_wall/no_grille)), req(PROC_REF(grille_clear), because = MSG(low_wall/window_in_the_way))),
		starts(PROC_REF(fingerprinted)), begins(MSG(low_wall/assembling_grille)), wait(1 SECOND), then(PROC_REF(grille_built)))
	op("build_window", stack(/obj/item/stack/material/glass, 4), label("Use"), needs(req(PROC_REF(window_supported), because = MSG(low_wall/no_window)), req(PROC_REF(window_clear), because = MSG(low_wall/window_here))),
		starts(PROC_REF(fingerprinted)), begins(MSG(low_wall/assembling_window)), wait(4 SECONDS), then(PROC_REF(window_built)))
	op("build_window_cyborg", stack(/obj/item/stack/material/cyborg/glass, 4), label("Use"), needs(req(PROC_REF(window_supported), because = MSG(low_wall/no_window)), req(PROC_REF(window_clear), because = MSG(low_wall/window_here))),
		starts(PROC_REF(fingerprinted)), begins(MSG(low_wall/assembling_window)), wait(4 SECONDS), then(PROC_REF(window_built)))
	op("place", item(/obj/item), label("Use"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(interaction_item)))
	op("place_drag", item(/atom/movable), gesture(GESTURE_DRAG), label("Place on wall"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(interaction_drag)))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A low wall stands only on open floor.
/obj/structure/low_wall/proc/build_of(materialtype)
	var/turf/T = loc
	if(!isturf(T) || T.density || T.opacity)
		WARNING("[src] on invalid turf [T] at [x],[y],[z]")
		spent(src)
		return
	set_material(get_material_by_name(materialtype))
	max_integrity = material.integrity
	update_integrity(max_integrity)


DESTROY_EFFECTS(/obj/structure/low_wall, new /datum/destroy_effects_data(neighbor_type = /obj/structure/low_wall))

MSG_DEF_SELF(low_wall/disassembling, span_notice("Now disassembling the low wall..."))
MSG_DEF_SELF(low_wall/no_grille, span_notice("This type of wall frame doesn't support grilles."))
MSG_DEF_SELF(low_wall/window_in_the_way, span_notice("There is a window in the way."))
MSG_DEF_SELF(low_wall/assembling_grille, span_notice("Assembling grille..."))
MSG_DEF_SELF(low_wall/no_window, span_notice("You can't build that type of window on this type of low wall."))
MSG_DEF_SELF(low_wall/window_here, span_notice("There is already a window here."))
MSG_DEF_SELF(low_wall/assembling_window, span_notice("Assembling window..."))

/// The start of a build: the builder leaves a print.
/obj/structure/low_wall/proc/fingerprinted(datum/act/op/A)
	add_fingerprint(A.actor)

/// Old attackby: drop an item on the wall (a cyborg's module stays with it: the op is not a cyborg's).
/obj/structure/low_wall/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	add_fingerprint(user)
	if(W.loc != user) // This should stop mounted modules ending up outside the module.
		return OP_OK
	if(can_place_items() && user.unEquip(W, 0, src.loc) && user.client?.prefs?.read_preference(/datum/preference/toggle/precision_placement))
		auto_align(W, dq_interaction_click_params(user))
	return OP_OK

/// The first structure fixed to the wall (a window or a grille), or null; what stands on a tile does not change while a click is decided.
/obj/structure/low_wall/proc/fixture_on_the_wall()
	for(var/obj/structure/S in read_once(turf_contents_of_type(loc, /obj/structure)))
		if(istype(S, /obj/structure/window) || istype(S, /obj/structure/grille))
			return S
	return null

/obj/structure/low_wall/proc/nothing_on_the_wall(datum/act/op/A)
	return isnull(fixture_on_the_wall())

/obj/structure/low_wall/proc/fixture_refusal(datum/act/op/A)
	if(istype(fixture_on_the_wall(), /obj/structure/window))
		return span_notice("There is still a window on the low wall!")
	return span_notice("There is still a grille on the low wall!")

/obj/structure/low_wall/proc/wrench_act_done(datum/act/op/A)
	to_chat(A.actor, span_notice("You disassembled the low wall!"))
	dismantle()

/obj/structure/low_wall/proc/can_place_items()
	for(var/obj/structure/S in turf_contents_of_type(loc, /obj/structure))
		if(S == src)
			continue
		if(S.density)
			return FALSE
	return TRUE

/// Old MouseDrop_T: hoist a window up, or place or push an item onto the wall (climbing is the climb capability's own drag).
/// Items align to the click through dq_interaction_click_params(). A cyborg's drag is not this op's.
/obj/structure/low_wall/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/AM = A.held
	if(AM == user) // climbing is the climb capability's own drag
		return OP_PASS
	var/obj/O = AM
	if(!istype(O))
		return OP_PASS
	if(istype(O, /obj/structure/window))
		var/obj/structure/window/W = O
		if(Adjacent(W) && !W.anchored)
			to_chat(user, span_notice("You hoist [W] up onto [src]."))
			W.forceMove(loc)
			return OP_PASS
	if(can_place_items())
		if(ismob(O.loc)) //If placing an item
			if(!isitem(O) || user.get_active_hand() != O)
				return OP_DECLINE
			user.drop_item()
			if(O.loc != src.loc)
				step(O, get_dir(O, src))

		else if(isturf(O.loc) && isitem(O)) //If pushing an item on the tabletop
			var/obj/item/I = O
			if(I.anchored)
				return OP_PASS

			if((isliving(user)) && (Adjacent(user)) && !(user.incapacitated()))
				if(O.w_class <= user.can_pull_size)
					O.forceMove(loc)
					auto_align(I, dq_interaction_click_params(user), TRUE)
				else
					to_chat(user, span_warning("\The [I] is too big for you to move!"))
				return OP_PASS
	return OP_PASS

/obj/structure/low_wall/proc/grille_supported(datum/act/op/A)
	return !!read_once(grille_type)

/// A window facing the builder is in the way of a grille.
/obj/structure/low_wall/proc/grille_clear(datum/act/op/A)
	return !window_facing(A.actor)

/obj/structure/low_wall/proc/window_facing(mob/user)
	for(var/obj/structure/window/WINDOW in read_once(turf_contents_of_type(loc, /obj/structure/window)))
		if(read_once(WINDOW.dir) == read_once(get_dir(src, user)))
			return WINDOW
	return null

/obj/structure/low_wall/proc/grille_built(datum/act/op/A)
	new grille_type(loc)

/obj/structure/low_wall/proc/window_supported(datum/act/op/A)
	return !!read_once(get_window_build_type(A.actor, A.held))

/obj/structure/low_wall/proc/window_clear(datum/act/op/A)
	return !window_facing(A.actor)

/obj/structure/low_wall/proc/window_built(datum/act/op/A)
	var/window_type = get_window_build_type(A.actor, A.held)
	if(window_type)
		new window_type(loc, null, TRUE)

/obj/structure/low_wall/proc/get_window_build_type(mob/user, obj/item/stack/material/glass/G)
	return null

/obj/structure/low_wall/CanPass(atom/movable/mover, turf/target)
	if(istype(mover,/obj/item/projectile))
		return TRUE
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return FALSE

// Bay's version: the mapped sprite, with the frame drawn corner by corner over the connections.
/obj/structure/low_wall/bay/low_wall_look(datum/look/look)
	if(!length(connections) || !length(other_connections))
		return
	var/main_color = material_colour()
	for(var/i = 1 to 4)
		if(other_connections[i] != "0")
			look.overlay(look_overlay_image(icon, "frame_other[other_connections[i]]", dir = 1<<(i-1), color = main_color))
		else
			look.overlay(look_overlay_image(icon, "frame[connections[i]]", dir = 1<<(i-1), color = main_color))

	if(stripe_color)
		for(var/i = 1 to 4)
			if(other_connections[i] != "0")
				look.overlay(look_overlay_image(icon, "stripe_other[other_connections[i]]", dir = 1<<(i-1), color = stripe_color))
			else
				look.overlay(look_overlay_image(icon, "stripe[connections[i]]", dir = 1<<(i-1), color = stripe_color))

// Eris's version
/obj/structure/low_wall/eris/low_wall_look(datum/look/look)
	if(!length(connections) || !length(other_connections))
		return
	var/main_color = material_colour()
	for(var/i = 1 to 4)
		look.overlay(look_overlay_image(icon, "frame[connections[i]]", dir = 1<<(i-1), color = main_color))
		if(other_connections[i] != "0")
			look.overlay(look_overlay_image(icon, "frame_other[other_connections[i]]", plane = ABOVE_OBJ_PLANE, layer = ABOVE_WINDOW_LAYER, dir = 1<<(i-1), color = main_color))

/// Emitters and the like can't take a low wall down in one shot.
/obj/structure/low_wall/projectile_damage(obj/item/projectile/P, def_zone)
	var/structure_damage = P.get_structure_damage()
	return receive_projectile(P, def_zone, structure_damage > 100 ? 100 / structure_damage : 1)
/// Light throws bounce off.
/obj/structure/low_wall/thrown_damage(atom/movable/source, datum/thrownthing/throwingdatum)
	if(source.thrown_impact_force(throwingdatum) < 15)
		return 0
	return ..()

/obj/structure/low_wall/atom_destruction(damage_flag)
	dismantle()
	return ..()

/obj/structure/low_wall/attack_generic(mob/user, damage, attack_verb)
	act_message(user, src, others = span_danger("%U% [attack_verb] %T%!"))
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)
	return ..()

/obj/structure/low_wall/proc/dismantle()
	var/stacktype = material?.stack_type
	if(stacktype)
		new stacktype(get_turf(src), 3)
	// If we were violently dismantled
	for(var/obj/structure/window/W in turf_contents_of_type(loc, /obj/structure/window))
		if(W.anchored)
			W.shatter()
	for(var/obj/structure/grille/G in turf_contents_of_type(loc, /obj/structure/grille))
		if(G.anchored)
			G.take_damage(G.max_integrity, BRUTE, MELEE) // Smash it apart with the wall.
	consume(src)

/**
 * The two 'real' types
 */
/obj/structure/low_wall/bay
	icon = 'icons/obj/wall_frame_bay.dmi'
	grille_type = /obj/structure/grille/bay
	blend_objects = list(/obj/machinery/door, /turf/simulated/wall/bay, /turf/simulated/wall/tgmc)

/obj/structure/low_wall/bay/reinforced
	default_material = MAT_PLASTEEL

/obj/structure/low_wall/bay/get_window_build_type(mob/user, obj/item/stack/material/glass/G)
	switch(G.material.name)
		if(MAT_GLASS)
			return /obj/structure/window/bay
		if(MAT_RGLASS)
			return /obj/structure/window/bay/reinforced
		if(MAT_PGLASS)
			return /obj/structure/window/bay/phoronbasic
		if(MAT_RPGLASS)
			return /obj/structure/window/bay/phoronreinforced

/obj/structure/low_wall/eris
	icon = 'icons/obj/wall_frame_eris.dmi'
	grille_type = null
	blend_objects = list(/obj/machinery/door, /turf/simulated/wall/eris, /turf/simulated/wall/tgmc)

/obj/structure/low_wall/eris/reinforced
	default_material = MAT_PLASTEEL

/obj/structure/low_wall/eris/get_window_build_type(mob/user, obj/item/stack/material/glass/G)
	switch(G.material.name)
		if(MAT_GLASS)
			return /obj/structure/window/eris
		if(MAT_RGLASS)
			return /obj/structure/window/eris/reinforced
		if(MAT_PGLASS)
			return /obj/structure/window/eris/phoronbasic
		if(MAT_RPGLASS)
			return /obj/structure/window/eris/phoronreinforced

/**
 * Bay's fancier icon grilles
 */
/obj/structure/grille/bay
	icon = 'icons/obj/bay_grille.dmi'
	blend_objects = list(/obj/machinery/door, /turf/simulated/wall/bay) // Objects which to blend with
	noblend_objects = list(/obj/machinery/door/window)
	color = "#666666"

CAPABILITIES(/obj/structure/grille/bay)
	smoothing()

DESTROY_EFFECTS(/obj/structure/grille/bay, new /datum/destroy_effects_data(neighbor_type = /obj/structure/grille))

/obj/structure/grille/bay/draw(datum/look/look)
	..()
	// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers
	look.state(null)
	var/on_frame = locate_on(loc, /obj/structure/low_wall/bay)

	if(destroyed)
		if(on_frame)
			look.state("broke_onframe")
		else
			look.state("broken")
	else
		var/image/I
		look.state("")
		if(on_frame)
			for(var/i = 1 to 4)
				if(other_connections[i] != "0")
					I = image(icon, "grille_other_onframe[connections[i]]", dir = 1<<(i-1))
				else
					I = image(icon, "grille_onframe[connections[i]]", dir = 1<<(i-1))
				look.overlay(I)
		else
			for(var/i = 1 to 4)
				if(other_connections[i] != "0")
					I = image(icon, "grille_other[connections[i]]", dir = 1<<(i-1))
				else
					I = image(icon, "grille[connections[i]]", dir = 1<<(i-1))
				look.overlay(I)

/**
 * The window types for both types of short walls
 */
/obj/structure/window/bay
	icon = 'icons/obj/bay_window.dmi'
	blend_objects = list(/obj/machinery/door, /turf/simulated/wall/bay)
	noblend_objects = list(/obj/machinery/door/window, /obj/machinery/door/firedoor)
	icon_state = "preview_glass"
	basestate = "window"
	alpha = 180
	flags = NONE
	fulltile = TRUE
	max_integrity = 24
	glasstype = /obj/item/stack/material/glass

/obj/structure/window/bay/Initialize(mapload)
	. = ..()
	var/obj/item/stack/material/glass/G = glasstype
	var/datum/material/M = get_material_by_name(initial(G.default_type))
	color = M.icon_colour

CAPABILITIES(/obj/structure/window/bay)
	after_init(0, then(PROC_REF(connect_after_init)))

/// Draws against its neighbours, once they exist.
/obj/structure/window/bay/proc/connect_after_init(datum/act/timer/A)
	update_connections()

/obj/structure/window/bay/look_parts(datum/look/look)
	look.state("")
	if(length(connections) < 4 || length(other_connections) < 4)
		return
	var/percent_damage = 0 // Used for icon state of damage layer
	var/damage_alpha = 0 // Used for alpha blending of damage layer
	if(max_integrity && get_integrity_damage() > 0)
		percent_damage = round(get_integrity_damage() / max_integrity, 0.25) // Percentage of damage received (Not health remaining), to the nearest multiple of 25
		damage_alpha = 256 * percent_damage - 1

	var/img_dir
	for(var/i = 1 to 4)
		img_dir = 1<<(i-1)
		if(other_connections[i] != "0")
			look.overlay(look_overlay_image(icon, "[basestate]_other_onframe[other_connections[i]]", dir = img_dir, color = color))
		else
			look.overlay(look_overlay_image(icon, "[basestate]_onframe[connections[i]]", dir = img_dir, color = color))

	if(damage_alpha)
		look.overlay(look_overlay_image(icon, "window0_damage", dir = img_dir, alpha = damage_alpha, blend_mode = BLEND_MULTIPLY))

/obj/structure/window/bay/reinforced
	name = "reinforced window"
	desc = "It looks rather strong. Might take a few good hits to shatter it."
	icon_state = "preview_rglass"
	basestate = "rwindow"
	max_integrity = 80
	reinf = 1
	maximal_heat = T0C + 750
	damage_per_fire_tick = 2.0
	glasstype = /obj/item/stack/material/glass/reinforced
	force_threshold = 6

/obj/structure/window/bay/phoronbasic
	name = "phoron window"
	desc = "A borosilicate alloy window. It seems to be quite strong."
	icon_state = "preview_phoron"
	shardtype = /obj/item/material/shard/phoron
	glasstype = /obj/item/stack/material/glass/phoronglass
	maximal_heat = T0C + 2000
	damage_per_fire_tick = 1.0
	max_integrity = 40.0
	force_threshold = 5
	max_integrity = 80

/obj/structure/window/bay/phoronreinforced
	name = "reinforced borosilicate window"
	desc = "A borosilicate alloy window, with rods supporting it. It seems to be very strong."
	icon_state = "preview_rphoron"
	basestate = "rwindow"
	shardtype = /obj/item/material/shard/phoron
	glasstype = /obj/item/stack/material/glass/phoronrglass
	reinf = 1
	maximal_heat = T0C + 4000
	damage_per_fire_tick = 1.0 // This should last for 80 fire ticks if the window is not damaged at all. The idea is that borosilicate windows have something like ablative layer that protects them for a while.
	max_integrity = 160
	force_threshold = 10

/obj/structure/window/eris
	icon = 'icons/obj/eris_window.dmi'
	blend_objects = list(/obj/machinery/door, /turf/simulated/wall/eris)
	noblend_objects = list(/obj/machinery/door/window, /obj/machinery/door/firedoor)
	icon_state = "preview_glass"
	basestate = "window"
	fulltile = TRUE
	max_integrity = 24
	alpha = 150

CAPABILITIES(/obj/structure/window/eris)
	after_init(0, then(PROC_REF(connect_after_init)))

/// Draws against its neighbours, once they exist.
/obj/structure/window/eris/proc/connect_after_init(datum/act/timer/A)
	update_connections()

/obj/structure/window/eris/look_parts(datum/look/look)
	look.state("")
	if(length(connections) < 4 || length(other_connections) < 4)
		return
	for(var/i = 1 to 4)
		if(other_connections[i] != "0")
			look.overlay(look_overlay_image(icon, "[basestate][other_connections[i]]", dir = 1<<(i-1)))
		else
			look.overlay(look_overlay_image(icon, "[basestate][connections[i]]", dir = 1<<(i-1)))

/obj/structure/window/eris/reinforced
	name = "reinforced window"
	desc = "It looks rather strong. Might take a few good hits to shatter it."
	icon_state = "preview_rglass"
	basestate = "rwindow"
	max_integrity = 80
	reinf = 1
	maximal_heat = T0C + 750
	damage_per_fire_tick = 2.0
	glasstype = /obj/item/stack/material/glass/reinforced
	force_threshold = 6

/obj/structure/window/eris/phoronbasic
	name = "phoron window"
	desc = "A borosilicate alloy window. It seems to be quite strong."
	basestate = "preview_phoron"
	icon_state = "pwindow"
	shardtype = /obj/item/material/shard/phoron
	glasstype = /obj/item/stack/material/glass/phoronglass
	maximal_heat = T0C + 2000
	damage_per_fire_tick = 1.0
	max_integrity = 40.0
	force_threshold = 5
	max_integrity = 80

/obj/structure/window/eris/phoronreinforced
	name = "reinforced borosilicate window"
	desc = "A borosilicate alloy window, with rods supporting it. It seems to be very strong."
	basestate = "preview_rphoron"
	icon_state = "rpwindow"
	shardtype = /obj/item/material/shard/phoron
	glasstype = /obj/item/stack/material/glass/phoronrglass
	reinf = 1
	maximal_heat = T0C + 4000
	damage_per_fire_tick = 1.0 // This should last for 80 fire ticks if the window is not damaged at all. The idea is that borosilicate windows have something like ablative layer that protects them for a while.
	max_integrity = 160
	force_threshold = 10

/**
 * Spawner helpers for mapping these in
 */

/obj/effect/low_wall_spawner
	name = "low wall spawner"

	var/low_wall_type
	var/window_type
	var/grille_type

	icon = null

CAPABILITIES(/obj/effect/low_wall_spawner)
	map_resolver(GLOBAL_PROC_REF(resolve_low_wall_spawner), vars = list("grille_type", "low_wall_type", "window_type"))

/// MAP_RESOLVER for low wall spawners: the low wall, grille and window (once per tile).
/proc/resolve_low_wall_spawner(atom/loc, path, list/varedits)
	var/obj/effect/low_wall_spawner/P = path
	var/turf/T = get_turf(loc)
	if(!T)
		return TRUE
	if(map_loading())
		if(T in GLOB.map_resolve_scratch["low_wall_spawner"])
			WARNING("Duplicate low wall spawners in [T.x],[T.y],[T.z]!")
			return TRUE
		LAZYADD(GLOB.map_resolve_scratch["low_wall_spawner"], T)
	var/low_wall_type = MAP_VAR(P, varedits, low_wall_type)
	var/grille_type = MAP_VAR(P, varedits, grille_type)
	var/window_type = MAP_VAR(P, varedits, window_type)
	if(low_wall_type)
		new low_wall_type(T)
	if(grille_type)
		new grille_type(T)
	if(window_type)
		new window_type(T)
	return TRUE

// Bay types
/obj/effect/low_wall_spawner/bay
	icon = 'icons/obj/wall_frame_bay.dmi'
	icon_state = "sp_glass"
	low_wall_type = /obj/structure/low_wall/bay
	window_type = /obj/structure/window/bay

/obj/effect/low_wall_spawner/bay/rglass
	icon_state = "sp_rglass"
	window_type = /obj/structure/window/bay/reinforced

/obj/effect/low_wall_spawner/bay/phoron
	icon_state = "sp_phoron"
	window_type = /obj/structure/window/bay/phoronbasic

/obj/effect/low_wall_spawner/bay/rphoron
	icon_state = "sp_rphoron"
	window_type = /obj/structure/window/bay/phoronreinforced

/obj/effect/low_wall_spawner/bay/reinforced
	icon_state = "spr_glass_g"
	low_wall_type = /obj/structure/low_wall/bay/reinforced
	grille_type = /obj/structure/grille/bay
	window_type = /obj/structure/window/bay

/obj/effect/low_wall_spawner/bay/reinforced/rglass
	icon_state = "spr_rglass_g"
	window_type = /obj/structure/window/bay/reinforced

/obj/effect/low_wall_spawner/bay/reinforced/phoron
	icon_state = "spr_phoron_g"
	window_type = /obj/structure/window/bay/phoronbasic

/obj/effect/low_wall_spawner/bay/reinforced/rphoron
	icon_state = "spr_rphoron_g"
	window_type = /obj/structure/window/bay/phoronreinforced

// Eris types
/obj/effect/low_wall_spawner/eris
	icon = 'icons/obj/wall_frame_eris.dmi'
	icon_state = "sp_glass"
	low_wall_type = /obj/structure/low_wall/eris
	window_type = /obj/structure/window/eris

/obj/effect/low_wall_spawner/eris/rglass
	icon_state = "sp_rglass"
	window_type = /obj/structure/window/eris/reinforced

/obj/effect/low_wall_spawner/eris/phoron
	icon_state = "sp_phoron"
	window_type = /obj/structure/window/eris/phoronbasic

/obj/effect/low_wall_spawner/eris/rphoron
	icon_state = "sp_rphoron"
	window_type = /obj/structure/window/eris/phoronreinforced

/obj/effect/low_wall_spawner/eris/reinforced
	icon_state = "spr_glass"
	low_wall_type = /obj/structure/low_wall/eris/reinforced
	window_type = /obj/structure/window/eris

/obj/effect/low_wall_spawner/eris/reinforced/rglass
	icon_state = "spr_rglass"
	window_type = /obj/structure/window/eris/reinforced

/obj/effect/low_wall_spawner/eris/reinforced/phoron
	icon_state = "spr_phoron"
	window_type = /obj/structure/window/eris/phoronbasic

/obj/effect/low_wall_spawner/eris/reinforced/rphoron
	icon_state = "spr_rphoron"
	window_type = /obj/structure/window/eris/phoronreinforced
