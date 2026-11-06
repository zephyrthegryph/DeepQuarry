/obj/item/rig_module/teleporter

	name = "teleportation module"
	desc = "A complex, sleek-looking, hardsuit-integrated teleportation module."
	icon_state = "teleporter"
	use_power_cost = 200
	redundant = 1
	usable = 1
	selectable = 1

	engage_string = "Emergency Leap"

	interface_name = "VOID-shift phase projector"
	interface_desc = "An advanced teleportation system. It is capable of pinpoint precision or random leaps forward."

/obj/item/rig_module/teleporter/proc/phase_in(mob/M,turf/T)

	if(!M || !T)
		return

	fx_sparks(holder, 5, FALSE)
	play_sfx(T, SFX_EFFECTS_PHASEIN, 0.25)
	play_sfx(T, SFX_EFFECTS_SPARKS2)
	anim(T,M,'icons/mob/mob.dmi',,"phasein",,M.dir)

/obj/item/rig_module/teleporter/proc/phase_out(mob/M,turf/T)

	if(!M || !T)
		return

	play_sfx(T, SFX_SPARKS)
	anim(T,M,'icons/mob/mob.dmi',,"phaseout",,M.dir)

/obj/item/rig_module/teleporter/engage(atom/target, notify_ai, mob/user)

	var/mob/living/carbon/human/H = holder.wearer()

	if(!istype(H.loc, /turf))
		to_chat(H, span_warning("You cannot teleport out of your current location."))
		return 0

	var/turf/T
	if(target)
		T = get_turf(target)
	else
		T = get_teleport_loc(get_turf(H), H, 6, 1, 1, 1)

	if(!T)
		to_chat(H, span_warning("No valid teleport target found."))
		return 0

	if(T.density)
		to_chat(H, span_warning("You cannot teleport into solid walls."))
		return 0

	if(T.z in using_map.admin_levels)
		to_chat(H, span_warning("You cannot use your teleporter on this Z-level."))
		return 0

	if(T.contains_dense_objects())
		to_chat(H, span_warning("You cannot teleport to a location with solid objects."))
		return 0

	if(T.z != H.z || get_dist(T, get_turf(H)) > world.view)
		to_chat(H, span_warning("You cannot teleport to such a distant object."))
		return 0

	if(!..()) return 0

	phase_out(H,get_turf(H))
	H.forceMove(T)
	phase_in(H,get_turf(H))

	for(var/obj/item/grab/G in contents_of(H))
		var/mob/grabbed = G?.grab_target()
		if(grabbed)
			phase_out(grabbed,get_turf(grabbed))
			grabbed.forceMove(locate(T.x+rand(-1,1),T.y+rand(-1,1),T.z))
			phase_in(grabbed,get_turf(grabbed))

	return 1
