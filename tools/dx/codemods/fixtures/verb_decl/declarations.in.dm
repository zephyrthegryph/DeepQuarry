/mob/living/thing
	var/shaggy = FALSE

CAPABILITIES(/mob/living/thing)
	owns_one(nameof(bag), /obj/item/storage)

DECLARE_VERB(/mob/living/thing, /mob/living/proc/hide)
DECLARE_LOGIN_VERB(/mob/living/thing, /mob/living/proc/set_size)
DECLARE_VERB_IF(/mob/living/thing, /mob/living/thing/proc/groom, "shaggy") // while it is shaggy
DECLARE_VERB_HIDE(/mob/living/thing, /mob/verb/toggle_gun_mode)

DECLARE_VERB(/datum/thing, /datum/proc/nothing)

/turf/plain
	name = "plain"

DECLARE_VERB_IF(/turf/plain, /turf/plain/proc/climb, "climbable")
