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

DECLARE_APPEARANCE(/obj/structure/low_wall, null, list(APPEARANCE_ANY = list(APPEARANCE_ICON_STATE = "blank")))

CAPABILITIES(/obj/structure/low_wall)
	smoothing()
	climb()
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	param(nameof(default_material), pos = 1, apply = PROC_REF(build_of))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A low wall stands only on open floor.
/obj/structure/low_wall/proc/build_of(materialtype)
	var/turf/T = loc
	if(!isturf(T) || T.density || T.opacity)
		WARNING("[src] on invalid turf [T] at [x],[y],[z]")
		spent(src)
		return
	material = get_material_by_name(materialtype)
	max_integrity = material.integrity
	update_integrity(max_integrity)


DESTROY_EFFECTS(/obj/structure/low_wall, new /datum/destroy_effects_data(neighbor_type = /obj/structure/low_wall))

/obj/structure/low_wall/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/low_wall_item,
		/datum/interaction/entry_drag/low_wall_drag,
	)
	..()

/// Old attackby: build a grille from rods, a window from glass, or drop an item on the wall.
/datum/interaction/entry_item/low_wall_item
	id = "low_wall_item"
	name = "Use"
	effect = /obj/structure/low_wall/proc/interaction_item

/obj/structure/low_wall/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	src.add_fingerprint(user)

	// Making grilles (only works on Bay ones currently)
	if(istype(W, /obj/item/stack/rods))
		handle_rod_use(user, W)
		return TRUE

	// Making windows, different per subtype
	else if(istype(W, /obj/item/stack/material/glass) || istype(W, /obj/item/stack/material/cyborg/glass))
		handle_glass_use(user, W)
		return TRUE

	// Handle placing things
	if(isrobot(user))
		return TRUE

	if(W.loc != user) // This should stop mounted modules ending up outside the module.
		return TRUE

	if(can_place_items() && user.unEquip(W, 0, src.loc) && user.client?.prefs?.read_preference(/datum/preference/toggle/precision_placement))
		auto_align(W, dq_interaction_click_params(user))
		return TRUE

	return TRUE

/obj/structure/low_wall/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	for(var/obj/structure/S in turf_contents_of_type(loc, /obj/structure))
		if(istype(S, /obj/structure/window))
			to_chat(user, span_notice("There is still a window on the low wall!"))
			return OP_OK
		if(istype(S, /obj/structure/grille))
			to_chat(user, span_notice("There is still a grille on the low wall!"))
			return OP_OK
	play_sfx(loc, SFX_ITEMS_RATCHET, 2)
	to_chat(user, span_notice("Now disassembling the low wall..."))
	om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user))
	return OP_OK

/obj/structure/low_wall/proc/wrench_act_timed_done(mob/user)
	to_chat(user, span_notice("You disassembled the low wall!"))
	dismantle()

/obj/structure/low_wall/proc/can_place_items()
	for(var/obj/structure/S in turf_contents_of_type(loc, /obj/structure))
		if(S == src)
			continue
		if(S.density)
			return FALSE
	return TRUE

/// Old MouseDrop_T: climb, hoist a window up, or place or push an item onto the wall.
/// Items align to the click through dq_interaction_click_params().
/datum/interaction/entry_drag/low_wall_drag
	id = "low_wall_drag"
	name = "Place on wall"
	effect = /obj/structure/low_wall/proc/interaction_drag

/obj/structure/low_wall/proc/interaction_drag(mob/user, atom/movable/AM, datum/interaction/interaction)
	if(AM == user) // climbing is the climb capability's own drag
		return INTERACTION_HANDLED_PASS
	var/obj/O = AM
	if(!istype(O))
		return INTERACTION_HANDLED_PASS
	if(istype(O, /obj/structure/window))
		var/obj/structure/window/W = O
		if(Adjacent(W) && !W.anchored)
			to_chat(user, span_notice("You hoist [W] up onto [src]."))
			W.forceMove(loc)
			return INTERACTION_HANDLED_PASS
	if(isrobot(user))
		return INTERACTION_HANDLED_PASS
	if(can_place_items())
		if(ismob(O.loc)) //If placing an item
			if(!isitem(O) || user.get_active_hand() != O)
				return FALSE
			if(isrobot(user))
				return INTERACTION_HANDLED_PASS
			user.drop_item()
			if(O.loc != src.loc)
				step(O, get_dir(O, src))

		else if(isturf(O.loc) && isitem(O)) //If pushing an item on the tabletop
			var/obj/item/I = O
			if(I.anchored)
				return INTERACTION_HANDLED_PASS

			if((isliving(user)) && (Adjacent(user)) && !(user.incapacitated()))
				if(O.w_class <= user.can_pull_size)
					O.forceMove(loc)
					auto_align(I, dq_interaction_click_params(user), TRUE)
				else
					to_chat(user, span_warning("\The [I] is too big for you to move!"))
				return INTERACTION_HANDLED_PASS
	return INTERACTION_HANDLED_PASS

/obj/structure/low_wall/proc/handle_rod_use(mob/user, obj/item/stack/rods/R)
	if(!grille_type)
		to_chat(user, span_notice("This type of wall frame doesn't support grilles."))
		return
	for(var/obj/structure/window/WINDOW in turf_contents_of_type(loc, /obj/structure/window))
		if(WINDOW.dir == get_dir(src, user))
			to_chat(user, span_notice("There is a window in the way."))
			return
	if(R.get_amount() < 2)
		to_chat(user, span_warning("You need at least two rods to do this."))
		return
	to_chat(user, span_notice("Assembling grille..."))
	om_task_timed(user, 1 SECONDS, target = R, receiver = src, on_done = PROC_REF(handle_rod_use_timed_done), done_args = list(R))
	return TRUE

/obj/structure/low_wall/proc/handle_rod_use_timed_done(obj/item/stack/rods/R)
	if(!R.use(2))
		return
	new grille_type(loc)
	return

/obj/structure/low_wall/proc/handle_glass_use(mob/user, obj/item/stack/material/glass/G)
	var/window_type = get_window_build_type(user, G)
	if(!window_type)
		to_chat(user, span_notice("You can't build that type of window on this type of low wall."))
		return
	for(var/obj/structure/window/WINDOW in turf_contents_of_type(loc, /obj/structure/window))
		if(WINDOW.dir == get_dir(src, user))
			to_chat(user, span_notice("There is already a window here."))
			return
	if(G.get_amount() < 4)
		to_chat(user, span_warning("You need at least four sheets of glass to do this."))
		return
	to_chat(user, span_notice("Assembling window..."))
	om_task_timed(user, 4 SECONDS, target = G, receiver = src, on_done = PROC_REF(handle_glass_use_timed_done), done_args = list(G, window_type))
	return TRUE

/obj/structure/low_wall/proc/handle_glass_use_timed_done(obj/item/stack/material/glass/G, window_type)
	if(!G.use(4))
		return
	new window_type(loc, null, TRUE)
	return

/obj/structure/low_wall/proc/get_window_build_type(mob/user, obj/item/stack/material/glass/G)
	return null

/obj/structure/low_wall/CanPass(atom/movable/mover, turf/target)
	if(istype(mover,/obj/item/projectile))
		return TRUE
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return FALSE

// Bay's version
/// Draws itself entirely: drop the parent's keyed declarations.
APPEARANCE_NONE(/obj/structure/low_wall/bay)
DECLARE_APPEARANCE_PROC(/obj/structure/low_wall/bay, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/low_wall/bay/appearance_overlays()
	. = list()

	var/image/I
	var/main_color = material.icon_colour
	for(var/i = 1 to 4)
		if(other_connections[i] != "0")
			I = image(icon, "frame_other[other_connections[i]]", dir = 1<<(i-1))
			I.color = main_color
		else
			I = image(icon, "frame[connections[i]]", dir = 1<<(i-1))
			I.color = main_color
		. += I

	if(stripe_color)
		for(var/i = 1 to 4)
			if(other_connections[i] != "0")
				I = image(icon, "stripe_other[other_connections[i]]", dir = 1<<(i-1))
			else
				I = image(icon, "stripe[connections[i]]", dir = 1<<(i-1))
			I.color = stripe_color
			. += I

// Eris's version
/// Draws itself entirely: drop the parent's keyed declarations.
APPEARANCE_NONE(/obj/structure/low_wall/eris)
DECLARE_APPEARANCE_PROC(/obj/structure/low_wall/eris, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/low_wall/eris/appearance_overlays()
	. = list()

	var/image/I
	var/main_color = material.icon_colour
	for(var/i = 1 to 4)
		I = image(icon, "frame[connections[i]]", dir = 1<<(i-1))
		I.color = main_color
		. += I

		if(other_connections[i] != "0")
			I = image(icon, "frame_other[other_connections[i]]", dir = 1<<(i-1))
			I.plane = ABOVE_OBJ_PLANE
			I.layer = ABOVE_WINDOW_LAYER
			I.color = main_color
			. += I

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
	icon_state = ""
	update_icon()

DECLARE_APPEARANCE_PROC(/obj/structure/window/bay, TYPE_PROC_REF(/atom, appearance_overlays), list("get_integrity"))
/obj/structure/window/bay/appearance_overlays()
	. = list()
	if(!anchored)
		connections = string_list(list("0","0","0","0"))
		other_connections = string_list(list("0","0","0","0"))
	else
		update_connections()

	var/percent_damage = 0 // Used for icon state of damage layer
	var/damage_alpha = 0 // Used for alpha blending of damage layer
	if (max_integrity && get_integrity() < max_integrity)
		percent_damage = (max_integrity - get_integrity()) / max_integrity // Percentage of damage received (Not health remaining)
		percent_damage = round(percent_damage, 0.25) // Round to nearest multiple of 25
		damage_alpha = 256 * percent_damage - 1

	var/img_dir
	var/image/I
	for(var/i = 1 to 4)
		img_dir = 1<<(i-1)
		if(other_connections[i] != "0")
			I = image(icon, "[basestate]_other_onframe[other_connections[i]]", dir = img_dir)
			I.color = color
		else
			I = image(icon, "[basestate]_onframe[connections[i]]", dir = img_dir)
			I.color = color
		. += I

	if(damage_alpha)
		var/image/D
		D = image(icon, "window0_damage", dir = img_dir)
		D.blend_mode = BLEND_MULTIPLY
		D.alpha = damage_alpha
		. += D

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
	icon_state = ""
	update_icon()

DECLARE_APPEARANCE_PROC(/obj/structure/window/eris, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/window/eris/appearance_overlays()
	. = list()
	if(!anchored)
		connections = string_list(list("0","0","0","0"))
		other_connections = string_list(list("0","0","0","0"))
	else
		update_connections()

	var/img_dir
	var/image/I
	for(var/i = 1 to 4)
		img_dir = 1<<(i-1)
		if(other_connections[i] != "0")
			I = image(icon, "[basestate][other_connections[i]]", dir = img_dir)
		else
			I = image(icon, "[basestate][connections[i]]", dir = img_dir)
		. += I

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

MAP_RESOLVER(/obj/effect/low_wall_spawner, GLOBAL_PROC_REF(resolve_low_wall_spawner))
MAP_RESOLVER_VARS(/obj/effect/low_wall_spawner, "grille_type;low_wall_type;window_type")

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
