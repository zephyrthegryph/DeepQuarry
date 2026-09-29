/mob/living/carbon
	gender = MALE
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE // BLEH, this could be improved for transparent species and stuff! And blocks glowing eyes?!
	var/datum/species/species //Contains icon generation and language information, set during New().
	var/list/antibodies = list() // ALLOW(instance_list): mob: 15 mobs at boot; per-instance state, see audit

	var/life_tick = 0      // The amount of life ticks that have processed on this mob.

	// total amount of wounds on mob, used to spread out healing and the like over all wounds
	var/number_wounds = 0
	/// Zones a surgical step is currently being performed on (lazy).
	var/list/surgery_zones_in_progress
	//Active emote/pose
	var/pose = null
	var/pose_move = FALSE
	var/image/pose_indicator
	var/datum/reagents/metabolism/bloodstream/bloodstr = null
	var/datum/reagents/metabolism/ingested/ingested = null
	var/datum/reagents/metabolism/touch/touching = null
	var/toxin_gut = FALSE

	var/pulse = PULSE_NORM	//current pulse level

	var/does_not_breathe = 0 //Used for specific mobs that can't take advantage of the species flags (changelings)

	VAR_PROTECTED/list/addictions = null // contains currently addicted chem reagent IDs
	VAR_PROTECTED/list/addiction_counters = null // contains counters by reagent ID

	//these two help govern taste. The first is the last time a taste message was shown to the plaer.
	//the second is the message in question.
	COOLDOWN_DECLARE(taste_cooldown)
	COOLDOWN_DECLARE(taste_repeat_cooldown)
	var/last_taste_text = ""


// bloodstr is the same holder as /atom's owned `reagents` (deleted first, so this only lets go of it):
// left set, it and the holder's my_atom would keep each other alive.
DECLARE_REF(/mob/living/carbon, "ingested", OWNED, null)
DECLARE_REF(/mob/living/carbon, "touching", OWNED, null)
DECLARE_REF(/mob/living/carbon, "bloodstr", OWNED, null)
DECLARE_REF(/mob/living/carbon, "pose_indicator", OWNED, null)
// OWNED: a per-mob produceCopy() species belongs to this mob and is deleted with it or when it
// adopts another species (adopt_species/release_species_copy). A shared GLOB.all_species
// singleton refuses the delete (/datum/species/lifecycle_keep).
DECLARE_REF(/mob/living/carbon, "species", OWNED, null)

/// The one way to set `species`: returns the previous datum. Callers hand that to
/// release_species_copy() once they are done reading it. In test builds a value that is
/// neither a registered singleton nor a per-mob copy fails loudly here.
/mob/living/carbon/proc/adopt_species(datum/species/new_species)
	var/datum/species/old = species
#ifdef UNIT_TESTS
	if(new_species && !new_species.per_mob_copy && GLOB.all_species[new_species.name] != new_species)
		stack_trace("adopt_species: [new_species.type] ([new_species.name]) is neither the registered singleton nor a per-mob copy")
#endif
	species = new_species
	return old

/// Deletes `old` when it was this mob's own per-mob copy and is no longer its species.
/// Without this the copy was dropped without qdel(): BYOND freed it on refcount and every
/// handle to it (organ data, trait timers) reported HANDLE TARGET COLLECTED WITHOUT QDEL.
/mob/living/carbon/proc/release_species_copy(datum/species/old)
	if(!old || old == species || !old.per_mob_copy || QDELETED(old))
		return
	qdel(old) // ALLOW(lifecycle): the owner deleting its replaced per-mob species copy; not an entity verb
