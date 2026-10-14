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

CAPABILITIES(/obj/effect/illusionary_fall)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/effect/illusionary_fall/proc/roll_icon_state(datum/roller/R)
	return "[R.number(1, 33)]"

/obj/effect/illusionary_fall/end_fall(crushing = FALSE)
	for(var/mob/living/L in contents_of(loc))
		var/target_zone = ran_zone()
		if(!L.injure(INJURY_BLUNT, 35, target_zone, src, flags = INJURE_ARMORED))
			break
	play_sfx(src, SFX_EFFECTS_CLANG2)
	consume(src)
