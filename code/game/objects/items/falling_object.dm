/obj/effect/falling_effect
	resistance_flags = BOMB_PROOF
	name = DEVELOPER_WARNING_NAME
	desc = "no data"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	var/falling_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita
	var/crushing = TRUE
	var/admin_spawned = FALSE

MAP_RESOLVER(/obj/effect/falling_effect, GLOBAL_PROC_REF(resolve_falling_effect))
MAP_RESOLVER_VARS(/obj/effect/falling_effect, "admin_spawned;crushing;falling_type")

/// MAP_RESOLVER for falling effects (mapped, or `new` at runtime): drops its falling_type.
/proc/resolve_falling_effect(atom/loc, path, list/varedits)
	var/obj/effect/falling_effect/P = path
	drop_from_sky(get_turf(loc), MAP_VAR(P, varedits, falling_type), MAP_VAR(P, varedits, crushing), MAP_VAR(P, varedits, admin_spawned))
	return TRUE

/// Drops `falling_type` (a type, or a loot declaration such as an /obj/random) onto `T` from the
/// sky; `crushing` flattens what it lands on.
/proc/drop_from_sky(turf/T, falling_type, crushing = TRUE, admin_spawned = FALSE)
	if(!T || !falling_type)
		return
	var/list/made = loot_spawn(falling_type, T)
	var/atom/movable/dropped
	for(var/atom/movable/AM as anything in made)
		if(!QDELETED(AM))
			dropped = AM
			break
	if(!dropped)
		return
	var/initial_x = dropped.pixel_x
	var/initial_y = dropped.pixel_y
	dropped.plane = 1
	dropped.pixel_x = rand(-150, 150)
	dropped.pixel_y = 500 // When you think that pixel_z is height but you are wrong
	dropped.set_density(FALSE)
	dropped.set_opacity(FALSE)
	if(admin_spawned)
		dropped.flags |= ADMIN_SPAWNED
	animate(dropped, pixel_y = initial_y, pixel_x = initial_x , time = 7)
	after(dropped, 0.7 SECONDS, TYPE_PROC_REF(/atom/movable,end_fall), with = list(crushing), keeps_dead = TRUE)

/atom/movable/proc/end_fall(crushing = FALSE)
	if(isliving(src))
		var/mob/living/L = src
		for(var/mob/living/P in contents_of(loc))
			if(can_drop_vore(L, P))
				L.feed_grabbed_to_self_falling_nom(L,P)
				act_message(L, null, others = span_vdanger("%U% falls right onto \the [P]!"))

	if(crushing)
		for(var/atom/movable/AM in contents_of(loc))
			if(AM != src)
				AM.ex_act(1)

	for(var/mob/living/M in oviewers(3, src))
		shake_camera(M, 2, 2)

	play_sfx(src, SFX_EFFECTS_METEORIMPACT, 1.25)
	set_density(initial(density))
	set_opacity(initial(opacity))
	plane = initial(plane)

/obj/effect/falling_effect/singularity_act()
	return

/obj/effect/falling_effect/singularity_pull()
	return

