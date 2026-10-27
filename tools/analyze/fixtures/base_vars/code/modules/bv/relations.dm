/mob/var/datum/homed_by_ref
/mob/var/list/homed_by_owns
/mob/var/datum/homed_by_link
/mob/var/datum/declared_on_subtype
/mob/var/datum/not_a_relation

CAPABILITIES(/mob)
	ref_one(nameof(homed_by_ref))
	owns_many(nameof(/mob::homed_by_owns))

CAPABILITIES(/mob/living/fixture)
	ref_one(nameof(declared_on_subtype))

/datum/peer/var/datum/other_end
CAPABILITIES(/datum/peer)
	links(/datum/peer::other_end, /mob::homed_by_link)
