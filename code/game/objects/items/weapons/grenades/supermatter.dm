/obj/item/grenade/supermatter
	name = "supermatter grenade"
	icon_state = "banana"
	item_state = "emergency_engi"
	arm_sound = 'sound/effects/3.wav'
	var/implode_at
	/// REACT_AT token for the implosion deadline; null when none.
	var/tmp/implode_timer

/obj/item/grenade/supermatter/Destroy()
	if(implode_at)
		REACT_PROCESS_STOP(src)
	. = ..()

/obj/item/grenade/supermatter/detonate()
	..()
	REACT_PROCESS(src, 2 SECONDS, "pulls in nearby atoms with the supermatter field every period while primed")
	implode_at = world.time + 10 SECONDS
	implode_timer = REACT_REARM(src, implode_timer, implode_at)
	update_icon()
	playsound(src, 'sound/weapons/wave.ogg', 100)

/obj/item/grenade/supermatter/on_react(reason, source, source_kind)
	implode_timer = null
	explosion(loc, 1, 3, 5, 4)
	qdel(src)

/obj/item/grenade/supermatter/update_icon()
	cut_overlays()
	if(implode_at)
		add_overlay(image(icon = 'icons/rust.dmi', icon_state = "emfield_s1"))

/obj/item/grenade/supermatter/process()
	if(!isturf(loc))
		if(ismob(loc))
			var/mob/M = loc
			M.drop_from_inventory(src)
		forceMove(get_turf(src))
	playsound(src, 'sound/effects/supermatter.ogg', 100)
	supermatter_pull(src, world.view, STAGE_THREE)
