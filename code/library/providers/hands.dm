// Hands (doc/rewrite/final_api.html, section 8 "Origin, reach, provider, authority and channel", section 11 "Mobs").
//
// There is no hand provider on /mob/living. A species with hands declares hands() in its CAPABILITIES and grants it through the relation scope
// (rel_grants(nameof(species)), scopes.dm) while the mob's species names it; a mob without a species declares its own providers. hands() is gated
// by has_working_hand(): a body that had hands and lost every one of them (the limbs of its hand slots are gone) provides none, so hand ops stop
// being candidates ("You can't do that without hands.") until a hand is back.

/// The key hands_refresh() publishes when the answer of has_working_hand() state_changed (the reads of the hands() condition).

/datum/rx_state
	/// What has_working_hand() answered last time hands_refresh() asked (null: not asked yet).
	var/hands_known

/// Does this body have a working hand? A body that declares hand slots has one while any of them is usable (its limb is there, the species and the
/// mob allow it); a body that declares none (an abstract fixture, a mob whose plan has no hands) is not missing any, so its species' hands() stands.
/// A condition: it reads and writes nothing.
/mob/living/proc/has_working_hand(datum/act/A)
	var/list/defs = dq_slot_defs_for(src)
	var/declared = FALSE
	for(var/datum/om/relation/slot/body/hand/def in defs)
		declared = TRUE
		if(!body_slot_refusal(def))
			return TRUE
	return !declared

/// A limb was attached or lost, or hands changed some other way: when has_working_hand() answers differently now, the provider set state_changed (the
/// provider set generation bumps and the key is published). Cheap when nothing changed.
/mob/living/proc/hands_refresh()
	if(QDELETED(src))
		return
	var/now = has_working_hand()
	var/datum/rx_state/state = rx_of(src)
	if(now == state.hands_known)
		return
	var/first = isnull(state.hands_known)
	state.hands_known = now
	if(first)
		return // the first answer is the baseline, not a change
	log_world("HANDS: [src] ([type]) now [now ? "has" : "has no"] working hands")
	provider_set_changed(src)
	publish_change(src, HANDS_KEY)

// ---- species_capabilities(): who gets hands ----

/// A carbon mob grants what its species declares while its species relation names it (the relation scope, scopes.dm): a species change is a write
/// of the var and everything the old species gave goes in the same step.
CAPABILITIES(/mob/living/carbon)
	every(PROC_REF(dream_interval), then(PROC_REF(dream_sequence)), when = nameof(dream_fragments))
	rel_grants(nameof(species))
	owns_one(nameof(cozyloop), /datum/looping_sound/mob/cozyloop)
	owns_one(nameof(hallucinations), /datum/hallucinations)
	owns_one(nameof(ingested), /datum/reagents/metabolism/ingested)
	owns_one(nameof(touching), /datum/reagents/metabolism/touch)
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

/// Every species has hands (has_working_hand() drops them when the body has lost them all). A species without hands overrides this list with
/// without(); a mob with no species (a carp, a borg, the AI) declares its own providers.
CAPABILITIES(/datum/species)
	hands()
	owns_one(nameof(hud), /datum/hud_data)
	owns_many(nameof(unarmed_attacks))

/mob/living/can_provide_hands(datum/act/A)
	return has_working_hand(A)
