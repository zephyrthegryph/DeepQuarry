/obj/effect/calldown_attack
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	mouse_opacity = 0
	icon = 'icons/effects/effects.dmi'
	icon_state = "drop_marker"

/obj/effect/calldown_attack/Initialize(mapload)
	. = ..()
	var/delay = rand(2.5 SECONDS, 3 SECONDS)
	after(src, delay - 0.7 SECONDS, PROC_REF(spawn_object)) // ALLOW(decl): the delay is rolled at random per instance, which a declaration cannot express

/obj/effect/calldown_attack/proc/spawn_object()
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
