/mob/living/thing
	var/shaggy = FALSE

CAPABILITIES(/mob/living/thing)
	owns_one(nameof(bag), /obj/item/storage)
	verb_entry(/mob/living/proc/hide)
	verb_entry(/mob/living/proc/set_size, login = TRUE)
	verb_entry(/mob/living/thing/proc/groom, when = nameof(shaggy)) // while it is shaggy
	verb_entry(/mob/verb/toggle_gun_mode, hidden = TRUE)

DECLARE_VERB(/datum/thing, /datum/proc/nothing)

/turf/plain
	name = "plain"

CAPABILITIES(/turf/plain)
	verb_entry(/turf/plain/proc/climb, when = nameof(climbable))
