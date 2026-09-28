


// /mob/living/carbon physiology signals


	// Prevents the breath
	// Prevents the breath

// /mob/living/carbon/human signals

///from /datum/species/handle_fire. Called when the human is set on fire and burning clothes and stuff
#define COMSIG_HUMAN_BURNING "human_burning"

///from /mob/living/carbon/human/get_visible_name(), not sent if the mob has TRAIT_UNKNOWN: (identity)
#define COMSIG_HUMAN_GET_VISIBLE_NAME "human_get_visible_name"
	//Index for the name of the face
	//Index for the name of the id
	//Index for whether their name is being overridden instead of obfuscated

// Mob transformation signals


//from base of [/obj/effect/particle_effect/fluid/smoke/proc/smoke_mob]: (seconds_per_tick)

//NON TG Signals
///When the mob's dna and species have been fully applied
#define COMSIG_HUMAN_DNA_FINALIZED "human_dna_finished"


// Organ specific signals


//NON TG Signals:
