/obj/item/grenade/supermatter
	name = "supermatter grenade"
	icon_state = "banana"
	item_state = "emergency_engi"
	arm_sound = SFX_EFFECTS_3
	EXPIRY_DECLARE(implode_at)
	/// TRUE from detonation: the slow step pulls everything in until the grenade implodes.
	var/tmp/imploding = FALSE
TRACKED(/obj/item/grenade/supermatter, imploding)

CAPABILITIES(/obj/item/grenade/supermatter)
	every(2 SECONDS, then(PROC_REF(pull_step)), when = nameof(imploding))

/obj/item/grenade/supermatter/detonate()
	..()
	set_imploding(TRUE)
	EXPIRY_SET(src, implode_at, 10 SECONDS, CLOCK_WORLD)
	after(src, 10 SECONDS, PROC_REF(implode))
	play_sfx(src, SFX_WEAPONS_WAVE, volume = 100)

/obj/item/grenade/supermatter/draw(datum/look/look)
	..()
	if(implode_at)
		look.overlay(image(icon = 'icons/rust.dmi', icon_state = "emfield_s1"))

/obj/item/grenade/supermatter/proc/pull_step(datum/act/A)
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
