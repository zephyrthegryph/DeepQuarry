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

SETTER(/mob/living/carbon, life_tick)
/mob/living/carbon/proc/set_life_tick(value)
	life_tick = value
	tracked_changed(src, "life_tick")

/// A carbon mob grants what its species declares while its species relation names it (the relation scope, scopes.dm): a species change is a write
/// of the var and everything the old species gave goes in the same step.
CAPABILITIES(/mob/living/carbon)
	section(lazy_state, "Rare state, one lazy datum per feature (storage contract): carbon_misc, dream_seq, posing")
	owns_one(nameof(carbon_misc), /datum/carbon_misc_state, lazy = TRUE)
	owns_one(nameof(dream_seq), /datum/dream_seq_state, lazy = TRUE)
	owns_one(nameof(posing), /datum/posing_state, lazy = TRUE)
	op("showoff", menu(), label("Show Held Item"), needs(req_self()), then(PROC_REF(showoff_op)))
	configure(movable_motion(blocks_emissive = EMISSIVE_BLOCK_UNIQUE))
	configure(footstep_rules(footstep_type = FOOTSTEP_MOB_SHOE, footstep_volume = 1, footstep_e_range = -6))
	configure(living_rules(fire_heats_body = TRUE))
	setup(PROC_REF(alias_bloodstream))
	ref_one(nameof(bloodstr), /datum/reagents/metabolism/bloodstream)
	cooldowns(taste_cooldown, taste_repeat_cooldown)
	every(PROC_REF(dream_interval), then(PROC_REF(dream_sequence)), when = STAT_DREAMING)
	links(LINK_END(/mob/living/carbon, LK_COZY_LOOP), LINK_END(/datum/looping_sound/mob/cozyloop, LK_COZY_LOOP_OF), sparse = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // the sleep music it plays for itself, gone with it (cozy_loop())
	owns_one(nameof(hallucinations), /datum/hallucinations)
	// its reagent holders: the bloodstream (`reagents`), the stomach and the skin, 500 units each
	reagents(500, holder = /datum/reagents/metabolism/bloodstream)
	owns_one(nameof(ingested), /datum/reagents/metabolism/ingested, starts = /datum/reagents/metabolism/ingested, starts_args = list(NO_LOC, 500, OWNER))
	owns_one(nameof(touching), /datum/reagents/metabolism/touch, starts = /datum/reagents/metabolism/touch, starts_args = list(NO_LOC, 500, OWNER))
	derives(nameof(default_language), PROC_REF(species_default_language))
	on_change(nameof(internal), ANY, then(PROC_REF(internal_changed)))
	footstep()
	on_notice(/datum/notice/hit/emp, then(PROC_REF(species_emp_effects)))
	// Resisting (resist.dm): resist_restraints() / resist_buckle() start these by key; the resister has to stand still. A throat cut from a neck grab (carbon_defense.dm).
	op("cuff_remove", ai(), begins(PROC_REF(cuff_remove_text)), wait(PROC_REF(cuff_breakout_time)), then(PROC_REF(cuff_remove_done)))
	op("cuff_break", ai(), begins(PROC_REF(cuff_break_text)), wait(5 SECONDS), on_interrupt(PROC_REF(cuff_break_failed)), then(PROC_REF(cuff_break_done)))
	op("buckle_escape", ai(), begins(PROC_REF(buckle_escape_text)), wait(2 MINUTES), then(PROC_REF(buckle_escape_done)))
	op("slit_throat", ai(), begins(MSG(throat/slit)), wait(2 SECONDS), then(PROC_REF(attack_throat_carbon_done)))
	op("pat_out_flames", ai(), begins(MSG(pat_out/begin)), wait(1.5 SECONDS), then(PROC_REF(help_shake_act_carbon_done)))
	// A trait injection (station_special_abilities.dm): five seconds next to the one injected, the injector's reagent and verb.
	op("trait_injection", ai(), reach(REACH_ADJACENT), takes("synth"), wait(5 SECONDS), then(PROC_REF(injection_living_done)))
	op("vv_addorgan", topic_in(VV_TOPIC, VV_HK_ADDORGAN), needs(req_rights(R_SPAWN)), asks(/datum/prompt/choice/vv_spawn, fields = list("title" = "Organ", "question" = "Please choose an organ to add.", "choices" = computed(PROC_REF(vv_organ_type_choices))), step = "organ"), then(PROC_REF(vv_organ_added_apply)))
	op("vv_remorgan", topic_in(VV_TOPIC, VV_HK_REMOVEORGAN), needs(req_rights(R_SPAWN)), asks(/datum/prompt/choice/vv_spawn, fields = list("title" = "Organ", "question" = "Please choose an organ to remove.", "choices" = computed(PROC_REF(vv_organ_choices))), step = "organ"), then(PROC_REF(vv_organ_removed_apply)))
	owns_one(nameof(species), on_destroy = ON_DESTROY_PRIVATE_COPY, copy_on_write = TRUE)
