/mob/living/carbon
	gender = MALE
	var/datum/species/species //Contains icon generation and language information, set during New().

	var/life_tick = 0      // The amount of life ticks that have processed on this mob.

	/// Zones a surgical step is currently being performed on (lazy).
	//Active emote/pose: pose (the text) is a sparse slot (code/datums/sparse_vars/mob_state.dm)
	var/image/pose_indicator
	var/datum/reagents/metabolism/bloodstream/bloodstr = null
	var/datum/reagents/metabolism/ingested/ingested = null
	var/datum/reagents/metabolism/touch/touching = null

	var/pulse = PULSE_NORM	//current pulse level

	var/does_not_breathe = 0 //Used for specific mobs that can't take advantage of the species flags (changelings)


	//these two help govern taste. The first is the last time a taste message was shown to the plaer.
	//the second is the message in question.


// bloodstr is the same holder as /atom's owned `reagents` (deleted first, so this only lets go of it):
// left set, it and the holder's my_atom would keep each other alive.

// A mob's species is copy-on-write (doc/rewrite/ownership.md sec 3): the registered
// GLOB.all_species singleton until traits or a custom base make it a private copy, which the mob
// owns. proto_set() deletes the private copy it replaces; teardown deletes it with the mob.

/// The pulse level: the heartbeat step reads it.
