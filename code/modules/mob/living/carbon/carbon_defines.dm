/mob/living/carbon
	gender = MALE
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE // BLEH, this could be improved for transparent species and stuff! And blocks glowing eyes?!
	var/datum/species/species //Contains icon generation and language information, set during New().
	var/list/antibodies = list() // ALLOW(instance_list): d: per-mob antibodies, filled at runtime; mobs are few

	var/life_tick = 0      // The amount of life ticks that have processed on this mob.

	/// Zones a surgical step is currently being performed on (lazy).
	//Active emote/pose
	var/pose = null
	var/pose_move = FALSE
	var/image/pose_indicator
	var/datum/reagents/metabolism/bloodstream/bloodstr = null
	var/datum/reagents/metabolism/ingested/ingested = null
	var/datum/reagents/metabolism/touch/touching = null

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

// A mob's species is copy-on-write (doc/rewrite/ownership.md sec 3): the registered
// GLOB.all_species singleton until traits or a custom base make it a private copy, which the mob
// owns. proto_set() deletes the private copy it replaces; teardown deletes it with the mob.
/mob/living/carbon/ownership()
	. = ..()
	. += rel_one(nameof(species), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)
