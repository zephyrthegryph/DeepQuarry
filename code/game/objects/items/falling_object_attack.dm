/obj/effect/calldown_attack
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	mouse_opacity = 0
	icon = 'icons/effects/effects.dmi'
	icon_state = "drop_marker"

CAPABILITIES(/obj/effect/calldown_attack)
	after_init(PROC_REF(strike_delay), then(PROC_REF(spawn_object)))

/// The strike falls 1.8 to 2.3 seconds after the marker appears (rolled per marker).
/obj/effect/calldown_attack/proc/strike_delay(datum/act/timer/A)
	return rand(2.5 SECONDS, 3 SECONDS) - 0.7 SECONDS

/obj/effect/calldown_attack/proc/spawn_object(datum/act/timer/A)
	new /obj/effect/falling_effect/calldown_attack(loc)
	expire(0.7 SECONDS)

/obj/effect/falling_effect/calldown_attack
	falling_type = /obj/effect/illusionary_fall
	crushing = FALSE


/obj/effect/illusionary_fall
	anchored = TRUE
	density = FALSE
	mouse_opacity = 0
	icon = 'icons/effects/random_stuff_vr.dmi'

// ALLOW(init/INSTANCE_STATE): icon_state rolled at random for each instance
/obj/effect/illusionary_fall/Initialize(mapload)
	. = ..()
	icon_state = "[rand(1,33)]" // ALLOW(decl): Initialize rolls a random pick per instance; a declaration has no random form

/obj/effect/illusionary_fall/end_fall(crushing = FALSE)
	for(var/mob/living/L in contents_of(loc))
		var/target_zone = ran_zone()
		if(!L.injure(INJURY_BLUNT, 35, target_zone, src, flags = INJURE_ARMORED))
			break
	play_sfx(src, SFX_EFFECTS_CLANG2)
	consume(src)
