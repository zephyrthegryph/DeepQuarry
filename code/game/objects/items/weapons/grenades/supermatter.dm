/obj/item/grenade/supermatter
	name = "supermatter grenade"
	icon_state = "banana"
	item_state = "emergency_engi"
	arm_sound = SFX_EFFECTS_3
	var/implode_at

/obj/item/grenade/supermatter/detonate()
	..()
	om_task_periodic(src, PERIODIC_SLOW)
	implode_at = world.time + 10 SECONDS
	update_icon()
	play_sfx(src, SFX_WEAPONS_WAVE, volume = 100)

/obj/item/grenade/supermatter/update_icon()
	cut_overlays()
	if(implode_at)
		add_overlay(image(icon = 'icons/rust.dmi', icon_state = "emfield_s1"))

/obj/item/grenade/supermatter/periodic_step()
	if(!isturf(loc))
		if(ismob(loc))
			var/mob/M = loc
			M.drop_from_inventory(src)
		forceMove(get_turf(src))
	play_sfx(src, SFX_EFFECTS_SUPERMATTER, 2, vary = FALSE)
	supermatter_pull(src, world.view, STAGE_THREE)
	if(world.time > implode_at)
		explosion(loc, 1, 3, 5, 4)
		qdel(src)
