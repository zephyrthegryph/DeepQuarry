


///When a carbon slips. Called on /turf/open/handle_slip()
#define COMSIG_ON_CARBON_SLIP "carbon_slip"
// /mob/living/carbon physiology signals


///Called when someone attempts to cuff a carbon
#define COMSIG_CARBON_CUFF_ATTEMPTED "carbon_attempt_cuff"
	#define COMSIG_CARBON_CUFF_PREVENT (1<<0)
	// Prevents the breath
	// Prevents the breath

// /mob/living/carbon/human signals

///from /datum/species/handle_fire. Called when the human is set on fire and burning clothes and stuff
#define COMSIG_HUMAN_BURNING "human_burning"

///from /mob/living/carbon/human/get_visible_name(), not sent if the mob has TRAIT_UNKNOWN: (identity)
#define COMSIG_HUMAN_GET_VISIBLE_NAME "human_get_visible_name"
	#define COMPONENT_VISIBLE_NAME_CHANGED (1<<0)
	//Index for the name of the face
	#define VISIBLE_NAME_FACE 1
	//Index for the name of the id
	#define VISIBLE_NAME_ID 2
	//Index for whether their name is being overridden instead of obfuscated
	#define VISIBLE_NAME_FORCED 3

// Mob transformation signals


//from base of [/obj/effect/particle_effect/fluid/smoke/proc/smoke_mob]: (seconds_per_tick)

//NON TG Signals
///When the mob's dna and species have been fully applied
#define COMSIG_HUMAN_DNA_FINALIZED "human_dna_finished"
///from the base of mob/living/carbon/human/hitby(): (atom/movable/source, speed)
#define COMSIG_HUMAN_ON_CATCH_THROW "human_on_catch_throw"


// Organ specific signals

///From /obj/item/organ/external/proc/embed(W, silent)
#define COMSIG_EMBED_OBJECT "embed_object"
///Return this in response if you don't want the embed to go through.
	#define COMSIG_CANCEL_EMBED (1<<0)

//NON TG Signals:
///called when being electrocuted, from /mob/living/carbon/electrocute_act(shock_damage, source, siemens_coeff, def_zone, stun)
#define COMSIG_BEING_ELECTROCUTED "being_electrocuted"
	#define COMPONENT_CARBON_CANCEL_ELECTROCUTE (1<<0) //If this is set, the carbon will be not be electrocuted.
