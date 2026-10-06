/obj/item/grenade/supermatter
	name = "supermatter grenade"
	icon_state = "banana"
	item_state = "emergency_engi"
	arm_sound = SFX_EFFECTS_3
	EXPIRY_DECLARE(implode_at)

/obj/item/grenade/supermatter/detonate()
	..()
	om_task_periodic(src, PERIODIC_SLOW)
	EXPIRY_SET(src, implode_at, 10 SECONDS, CLOCK_WORLD)
	after(src, 10 SECONDS, PROC_REF(implode))
	update_icon()
	play_sfx(src, SFX_WEAPONS_WAVE, volume = 100)

DECLARE_APPEARANCE_PROC(/obj/item/grenade/supermatter, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/grenade/supermatter/appearance_overlays()
	. = list()
	if(implode_at)
		. += image(icon = 'icons/rust.dmi', icon_state = "emfield_s1")

/obj/item/grenade/supermatter/periodic_step()
	if(!isturf(loc))
		if(ismob(loc))
			var/mob/M = loc
			M.drop_from_inventory(src)
		forceMove(get_turf(src))
	play_sfx(src, SFX_EFFECTS_SUPERMATTER, 2, vary = FALSE)
	supermatter_pull(src, world.view, STAGE_THREE)

/// after() callback from detonate(): the pull ends in the implosion.
/obj/item/grenade/supermatter/proc/implode()
	explosion(loc, 1, 3, 5, 4)
	spent(src)
