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
	var/last_taste_time = 0
	var/last_taste_text = ""

	///Only used by humans. Kept by the slot signals (inventory_slot_changed()).
	var/list/worn_clothing	//Contains all CLOTHING items worn. Lazy.

// bloodstr is the same holder as /atom's owned `reagents` (deleted first, so this only lets go of it):
// left set, it and the holder's my_atom would keep each other alive.
REF_OWNED(/mob/living/carbon, list("ingested", "touching", "bloodstr", "pose_indicator"))
REF_STATIC(/mob/living/carbon, "species")
