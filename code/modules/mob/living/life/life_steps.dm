// Life steps (doc/rewrite/life_sequences.md, doc/rewrite/om_retirement.md L1).
//
// Each mob type declares the Life steps it runs. A step is a proc on the mob type (life_<step>(F)), overridden by
// subtypes; `after =` edges reproduce the old stage order (derived by tools/dx/codemods/life_stage_steps.py; the
// solver breaks ties by key). `when =` names the frame conditions (/datum/sequence/life/conditions()), `reads =` the
// change channels that wake a sleeping step, `should_run =` says it has work, `rewake =` wakes it anyway after a
// delay. `woken_by =` lists, for each read, who raises it (read key = producers): a step that sleeps is woken the
// moment an input changes, and a rewake under LIFE_SAFETY_RESAMPLE is allowed only for work that drifts with time
// (LIFE_WOKEN_BY_TIME) or an input no producer publishes yet (LIFE_WOKEN_BY_POLL, a known gap):
// life_om/steps_declare_their_wakes checks it. A later declaration of the same step on a subtype replaces the parent's. A step runs only for the Life set
// (life_set) it serves: preview dummies and delisted mobs keep none of the living steps.

/// Breathing (carbons, fish): the air watch hears its air cross a level it acts on; moving re-arms it on the new turf.
#define LIFE_BREATHING_WOKEN_BY list(MOB_KEY_AIR = "its air watch (air_watch.dm): oxygen, toxins, N2O, CO2, temperature or pressure crossing a level", MOB_KEY_LOC = "Moved", MOB_KEY_EQUIPMENT = "masks, internals, suits")
/// The environment exchange: the air watch, the body heat watch, moving and clothing.
#define LIFE_ENVIRONMENT_WOKEN_BY list(MOB_KEY_AIR = "its air watch: temperature, pressure or a gas limit crossing a level", MOB_KEY_BODY_HEAT = "its body heat watch: the body temperature crossing a level", MOB_KEY_LOC = "Moved", MOB_KEY_EQUIPMENT = "clothing (protection)")
/// Radiation: the one set of writers publishes the dose.
#define LIFE_RADIATION_WOKEN_BY list(MOB_KEY_RADIATION = "add_radiation(), purge_radiation(), decay_radiation(), clear_radiation()")
/// Chemicals: a reagent added or removed invalidates the body; hunger drifts with time on the rewake.
#define LIFE_CHEMICALS_WOKEN_BY list(MOB_KEY_HEALTH = "reagents added or removed (on_reagent_change(): body invalidate)", LIFE_WOKEN_BY_TIME = "hunger is charged over the idle time")

/mob/living/life_steps()
	. = ..()
	if(life_set & LIFE_SET_DELIST)
		. += seq_step(PROC_REF(life_delist), after = LIFE_INPUT, reads = list(MOB_KEY_LOC) + LIFE_CONDITION_READS)
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_upkeep), after = LIFE_INPUT, reads = list(MOB_KEY_LOC) + LIFE_CONDITION_READS, should_run = PROC_REF(life_upkeep_due), woken_by = list(MOB_KEY_LOC = "Moved", MOB_KEY_CONDITIONS = "ghosts following; spells learned"))
		. += seq_step(PROC_REF(life_light), after = list(LIFE_INPUT, "life_instability"), when = "placed", reads = list(MOB_KEY_LOC) + LIFE_CONDITION_READS, should_run = PROC_REF(life_light_due), woken_by = list(MOB_KEY_CONDITIONS = "refresh_glow() runs it; the glow and instability setters", MOB_KEY_LOC = "Moved (ventcrawling)"))
		. += seq_step(PROC_REF(life_mutations), after = list(LIFE_INPUT, "life_breathing"), when = list("placed", "alive"), reads = LIFE_STATUS_READS, should_run = PROC_REF(life_mutations_due), woken_by = list(MOB_KEY_STATUS = "status setters"))
		if(life_radiation_applies())
			. += seq_step(PROC_REF(life_radiation), after = list(LIFE_INPUT, "life_mutations"), when = list("placed", "alive"), reads = list(MOB_KEY_RADIATION), should_run = PROC_REF(life_radiation_due), rewake = PROC_REF(life_radiation_rewake), woken_by = LIFE_RADIATION_WOKEN_BY)
		. += seq_step(PROC_REF(life_afk), after = list(LIFE_BODY, "life_random_events"), when = list("placed", "alive"), once = TRUE, rewake = PROC_REF(life_afk_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "the client's idle time grows by itself"))
		. += seq_step(PROC_REF(life_environment), after = list(LIFE_BODY, "life_chemicals"), when = "placed", reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_AIR, MOB_KEY_BODY_HEAT), should_run = PROC_REF(life_environment_due), rewake = PROC_REF(life_environment_rewake), woken_by = LIFE_ENVIRONMENT_WOKEN_BY)
		. += seq_step(PROC_REF(life_ambience), after = list(LIFE_BODY, "life_environment"), when = "placed", once = TRUE, rewake = PROC_REF(life_ambience_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "an ambience replay is due after the client's interval"))
		. += seq_step(PROC_REF(life_movement), after = list(LIFE_BODY, "life_ambience"), when = "placed", reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_GROUND) + LIFE_STATUS_READS, should_run = PROC_REF(life_movement_due), woken_by = list(MOB_KEY_LOC = "Moved", MOB_KEY_EQUIPMENT = "equipping a grab", MOB_KEY_STATUS = "start_pulling(); status setters", MOB_KEY_GROUND = "ChangeTurf() under it; /area/gravitychange()"))
		if(life_physiology_applies())
			. += seq_step(PROC_REF(life_physiology), after = list(LIFE_BODY, "life_movement"), when = list("placed", "!in_stasis", "alive"), reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_physiology_due), rewake = PROC_REF(life_physiology_rewake), woken_by = list(MOB_KEY_HEALTH = "body invalidate(): factors, organs, breath quality, blood volume, supports", LIFE_WOKEN_BY_TIME = "a timed support expires"))
		. += seq_step(PROC_REF(life_status), after = LIFE_BODY, when = "placed", reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_status_due), rewake = PROC_REF(life_status_rewake), woken_by = list(MOB_KEY_HEALTH = "injure, mend, afflictions, factors and reagents (body invalidate); set_stat"))
		. += seq_step(PROC_REF(life_disabilities), after = LIFE_MIND, when = list("placed", "status_ok"), reads = LIFE_STATUS_READS, should_run = PROC_REF(life_disabilities_due), woken_by = list(MOB_KEY_STATUS = "status changes (blindness starting or ending); set_stat"))
		. += seq_step(PROC_REF(life_tf_holder), after = LIFE_OUTPUT, when = "placed", reads = list(MOB_KEY_LOC) + LIFE_CONDITION_READS, should_run = PROC_REF(life_tf_holder_due), woken_by = list(MOB_KEY_LOC = "Moved", MOB_KEY_CONDITIONS = "the tf_mob_holder setter"))
		. += seq_step(PROC_REF(life_vr_derez), after = LIFE_OUTPUT, when = "placed", reads = list(MOB_KEY_LOC) + LIFE_CONDITION_READS, should_run = PROC_REF(life_vr_derez_due), woken_by = list(MOB_KEY_LOC = "Moved (a VR mob can only leave the VR area by moving)", MOB_KEY_CONDITIONS = "the virtual_reality_mob setter"))
	if(life_set & (LIFE_SET_LIVING | LIFE_SET_ROBOT))
		. += seq_step(PROC_REF(life_instability), after = list(LIFE_INPUT, "life_type_pre", "life_robot_cycle", "life_trait_burninlight", "life_robot_senses", "life_trait_crowd_detection", "life_trait_diabetic", "life_trait_drippy", "life_trait_forms", "life_trait_gargoyle", "life_trait_nutrition_size_change", "life_trait_photosynth", "life_trait_promethean_biology", "life_trait_radiation_glow", "life_trait_schizophrenia", "life_trait_shadekin", "life_trait_using_machine_shim", "life_trait_weaver", "life_upkeep"), reads = list(MOB_KEY_LOC) + LIFE_CONDITION_READS, should_run = PROC_REF(life_instability_due), woken_by = list(MOB_KEY_CONDITIONS = "adjust_instability() (the instability setter)"))

/mob/living/bot/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_bot_core), after = LIFE_TAIL)
		. += seq_step(PROC_REF(life_type_post), after = list(LIFE_TAIL, "life_weight", "life_visible_name"), should_run = PROC_REF(life_type_post_due), rewake = PROC_REF(life_type_post_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "a type's own periodic tail work (its rewake)"))

/mob/living/carbon/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_breathing), after = list(LIFE_INPUT, "life_light"), when = list("placed", "alive"), reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_AIR), should_run = PROC_REF(life_breathing_due), rewake = PROC_REF(life_breathing_rewake), woken_by = LIFE_BREATHING_WOKEN_BY)
		. += seq_step(PROC_REF(life_addictions), after = list(LIFE_MIND, "life_disabilities"), when = list("placed", "status_ok"), reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_addictions_due), rewake = PROC_REF(life_addictions_rewake), woken_by = list(MOB_KEY_HEALTH = "reagent changes (on_reagent_change(): body invalidate)"))
		. += seq_step(PROC_REF(life_germs), after = LIFE_TAIL, reads = list(MOB_KEY_HEALTH), once = TRUE, rewake = PROC_REF(life_germs_rewake), woken_by = list(MOB_KEY_HEALTH = "body invalidate", LIFE_WOKEN_BY_TIME = "germs creep up toward the ambient level"))
		. += seq_step(PROC_REF(life_type_post), after = list(LIFE_TAIL, "life_weight", "life_visible_name"), should_run = PROC_REF(life_type_post_due), rewake = PROC_REF(life_type_post_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "a type's own periodic tail work (its rewake)"))

/mob/living/dominated_brain/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_post), after = list(LIFE_TAIL, "life_weight", "life_visible_name"), should_run = PROC_REF(life_type_post_due), rewake = PROC_REF(life_type_post_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "a type's own periodic tail work (its rewake)"))

/mob/living/simple_mob/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_environment), after = list(LIFE_BODY, "life_chemicals"), when = list("placed", "!in_stasis"), reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_AIR, MOB_KEY_BODY_HEAT, MOB_KEY_HEALTH), should_run = PROC_REF(life_environment_due), rewake = PROC_REF(life_environment_rewake), woken_by = LIFE_ENVIRONMENT_WOKEN_BY + list(MOB_KEY_HEALTH = "injure (afflictions)"))
		. += seq_step(PROC_REF(life_simple_vitals), after = LIFE_TAIL, reads = list(MOB_KEY_HEALTH), once = TRUE, woken_by = list(MOB_KEY_HEALTH = "injure, mend, body invalidate (health); set_stat"))
		. += seq_step(PROC_REF(life_supernatural), after = LIFE_TAIL, when = "alive", reads = LIFE_STATUS_READS, should_run = PROC_REF(life_supernatural_due), woken_by = list(MOB_KEY_STATUS = "status setters; the purge setter"))
		. += seq_step(PROC_REF(life_guts), after = list(LIFE_TAIL, "life_special"), when = "alive", should_run = PROC_REF(life_guts_due), woken_by = list(LIFE_WOKEN_BY_POLL = "organ objects given to a simple mob (nothing publishes it)"))
		. += seq_step(PROC_REF(life_simple_healing), after = list(LIFE_TAIL, "life_guts"), when = "alive", reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_simple_healing_due), woken_by = list(MOB_KEY_HEALTH = "injure; feeding"))
		. += seq_step(PROC_REF(life_type_post), after = list(LIFE_TAIL, "life_weight", "life_visible_name"), should_run = PROC_REF(life_type_post_due), rewake = PROC_REF(life_type_post_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "a type's own periodic tail work (its rewake)"))

/mob/living/voice/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_pre), after = LIFE_INPUT, should_run = PROC_REF(life_type_pre_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's own pre work: its due() reads state no producer publishes"))

/mob/living/carbon/alien/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_pre), after = LIFE_INPUT, should_run = PROC_REF(life_type_pre_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's own pre work: its due() reads state no producer publishes"))
		. += seq_step(PROC_REF(life_alien_growth), after = list(LIFE_TAIL, "life_germs"), reads = list(MOB_KEY_HEALTH))

/mob/living/carbon/brain/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_chemicals), after = list(LIFE_BODY, "life_afk"), when = "placed", reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_chemicals_due), rewake = PROC_REF(life_chemicals_rewake), woken_by = LIFE_CHEMICALS_WOKEN_BY)
		. += seq_step(PROC_REF(life_status), after = LIFE_BODY, when = "placed", reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_status_due), rewake = PROC_REF(life_status_rewake), woken_by = list(MOB_KEY_HEALTH = "injure/mend (refresh_host_status), brain removal/insertion, MMI emp_act", LIFE_WOKEN_BY_TIME = "tissue drift"))

/mob/living/carbon/human/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_pre), after = LIFE_INPUT, should_run = PROC_REF(life_type_pre_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's own pre work: its due() reads state no producer publishes"))
		. += seq_step(PROC_REF(life_breathing), after = list(LIFE_INPUT, "life_light"), when = list("placed", "!in_stasis", "alive"), reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_AIR), should_run = PROC_REF(life_breathing_due), rewake = PROC_REF(life_breathing_rewake), woken_by = LIFE_BREATHING_WOKEN_BY)
		. += seq_step(PROC_REF(life_mutations), after = list(LIFE_INPUT, "life_breathing"), when = list("placed", "!in_stasis", "alive"), reads = LIFE_STATUS_READS, should_run = PROC_REF(life_mutations_due), woken_by = list(MOB_KEY_STATUS = "status setters"))
		if(life_radiation_applies())
			. += seq_step(PROC_REF(life_radiation), after = list(LIFE_INPUT, "life_mutations"), when = list("placed", "!in_stasis", "alive"), reads = list(MOB_KEY_RADIATION), should_run = PROC_REF(life_radiation_due), rewake = PROC_REF(life_radiation_rewake), woken_by = LIFE_RADIATION_WOKEN_BY)
		. += seq_step(PROC_REF(life_random_events), after = LIFE_BODY, when = list("placed", "!in_stasis", "alive"), reads = LIFE_STATUS_READS, should_run = PROC_REF(life_random_events_due), woken_by = list(MOB_KEY_STATUS = "status setters"))
		. += seq_step(PROC_REF(life_chemicals), after = list(LIFE_BODY, "life_afk"), when = list("placed", "!in_stasis"), reads = list(MOB_KEY_HEALTH, MOB_KEY_NUTRITION), should_run = PROC_REF(life_chemicals_due), rewake = PROC_REF(life_chemicals_rewake), woken_by = LIFE_CHEMICALS_WOKEN_BY + list(MOB_KEY_NUTRITION = "set_nutrition() (digestion noises past their levels)"))
		. += seq_step(PROC_REF(life_status), after = LIFE_BODY, when = "placed", reads = list(MOB_KEY_HEALTH, MOB_KEY_EQUIPMENT) + LIFE_STATUS_READS, should_run = PROC_REF(life_status_due), rewake = PROC_REF(life_status_rewake), woken_by = list(MOB_KEY_HEALTH = "injure/mend and body invalidate; set_stat", MOB_KEY_STATUS = "status setters (sleep, blindness, drowsiness, fear, tiredness)", MOB_KEY_EQUIPMENT = "equipment (blindfolds, rig visors)", LIFE_WOKEN_BY_POLL = "Login/Logout (SSD); fear and tiredness drain by time while they last"))
		. += seq_step(PROC_REF(life_stasis_sleep), after = LIFE_TAIL, reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_stasis_sleep_due), woken_by = list(MOB_KEY_HEALTH = "factor changes (body invalidate)"))
		. += seq_step(PROC_REF(life_fall), after = list(LIFE_TAIL, "life_stasis_sleep"), reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_GROUND) + LIFE_STATUS_READS, once = TRUE, rewake = PROC_REF(life_fall_rewake), woken_by = list(MOB_KEY_LOC = "Moved", MOB_KEY_EQUIPMENT = "equipment (jetpacks, magboots)", MOB_KEY_STATUS = "status setters (flying)", MOB_KEY_GROUND = "ChangeTurf() under it or below it (a floor removed); /area/gravitychange()", LIFE_WOKEN_BY_TIME = "flying over open space tires the flier every frame"))
		. += seq_step(PROC_REF(life_changeling), after = list(LIFE_TAIL, "life_fall"), when = list("!in_stasis", "alive"), should_run = PROC_REF(life_changeling_due), rewake = PROC_REF(life_changeling_rewake), woken_by = list(LIFE_WOKEN_BY_POLL = "becoming a changeling; a login's HUD (nothing publishes them)"))
		. += seq_step(PROC_REF(life_thermoregulation), after = list(LIFE_TAIL, "life_changeling"), when = list("!in_stasis", "alive"), reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_BODY_HEAT, MOB_KEY_HEALTH), should_run = PROC_REF(life_thermoregulation_due), rewake = PROC_REF(life_thermoregulation_rewake), woken_by = list(MOB_KEY_LOC = "Moved", MOB_KEY_EQUIPMENT = "equipment", MOB_KEY_BODY_HEAT = "the body heat watch (the body leaves its comfort band around the set point)", MOB_KEY_HEALTH = "factor changes (BF_TEMPERATURE fevers and chills), set_stat"))
		. += seq_step(PROC_REF(life_weight), after = LIFE_TAIL, when = list("!in_stasis", "alive"), reads = list(MOB_KEY_NUTRITION), should_run = PROC_REF(life_weight_due), rewake = PROC_REF(life_weight_rewake), woken_by = list(MOB_KEY_NUTRITION = "set_nutrition() / adjust_nutrition()"))
		. += seq_step(PROC_REF(life_shock), after = list(LIFE_TAIL, "life_weight"), when = list("!in_stasis", "alive"), reads = list(MOB_KEY_HEALTH), should_run = PROC_REF(life_shock_due), rewake = PROC_REF(life_shock_rewake), woken_by = list(MOB_KEY_HEALTH = "injure/mend and body invalidate (pain, analgesia); adjust_shock()/set_shock()"))
		. += seq_step(PROC_REF(life_medical), after = list(LIFE_TAIL, "life_shock"), when = list("!in_stasis", "alive"), reads = list(MOB_KEY_HEALTH, MOB_KEY_BODY_HEAT, MOB_KEY_RADIATION), should_run = PROC_REF(life_medical_due), rewake = PROC_REF(life_medical_rewake), woken_by = list(MOB_KEY_HEALTH = "body invalidate (conditions, chems, factors, metrics, oxygen debt via tissue hypoxia)", MOB_KEY_BODY_HEAT = "the body heat watch (the metric thresholds)", MOB_KEY_RADIATION = "the radiation writers"))
		. += seq_step(PROC_REF(life_heartbeat), after = list(LIFE_TAIL, "life_medical"), when = list("!in_stasis", "alive"), reads = list(MOB_KEY_HEALTH, MOB_KEY_LOC), should_run = PROC_REF(life_heartbeat_due), rewake = PROC_REF(life_heartbeat_rewake), woken_by = list(MOB_KEY_HEALTH = "body invalidate", MOB_KEY_LOC = "movement (space)", LIFE_WOKEN_BY_POLL = "pulse is written raw by the heart and reagents"))
		. += seq_step(PROC_REF(life_nif), after = list(LIFE_TAIL, "life_heartbeat"), when = list("!in_stasis", "alive"), should_run = PROC_REF(life_nif_due), rewake = PROC_REF(life_nif_rewake), woken_by = list(LIFE_WOKEN_BY_POLL = "a NIF installed (nothing publishes it)"))
		. += seq_step(PROC_REF(life_phobias), after = list(LIFE_TAIL, "life_nif"), when = list("!in_stasis", "alive"), should_run = PROC_REF(life_phobias_due), rewake = PROC_REF(life_phobias_rewake), woken_by = list(LIFE_WOKEN_BY_POLL = "phobias gained (nothing publishes it)"))
		. += seq_step(PROC_REF(life_npc), after = list(LIFE_TAIL, "life_phobias"), when = list("!in_stasis", "alive"), should_run = PROC_REF(life_npc_due), rewake = PROC_REF(life_npc_rewake), woken_by = list(LIFE_WOKEN_BY_TIME = "NPC behaviour runs on its own cadence"))
		. += seq_step(PROC_REF(life_species_components), after = list(LIFE_TAIL, "life_npc"))
		. += seq_step(PROC_REF(life_visible_name), after = list(LIFE_TAIL, "life_species_components"), reads = list(MOB_KEY_HEALTH, MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_CONDITIONS, MOB_KEY_IDENTITY, nameof(/mob::real_name)), once = TRUE, woken_by = list(MOB_KEY_EQUIPMENT = "masks, hats and the ID slot", MOB_KEY_HEALTH = "body invalidate; set_stat", MOB_KEY_LOC = "Moved", MOB_KEY_CONDITIONS = "add_mutation()/remove_mutation() (husking)", MOB_KEY_IDENTITY = "set_disfigured(), the worn ID's set_registered_name(), the PDA's set_owner(), the shadekin phase setters", "real_name" = "set_real_name()"))
		. += seq_step(PROC_REF(life_pulse), after = list(LIFE_TAIL, "life_visible_name"), reads = list(MOB_KEY_HEALTH), once = TRUE, woken_by = list(MOB_KEY_HEALTH = "body invalidate"))

/mob/living/silicon/ai/life_steps()
	. = ..()
	if(life_set & LIFE_SET_AI)
		. += seq_step(PROC_REF(life_ai_power), after = LIFE_INPUT)
		. += seq_step(PROC_REF(life_ai_body), after = list(LIFE_INPUT, "life_ai_power"), reads = list(MOB_KEY_HEALTH))
		. += seq_step(PROC_REF(life_ai_upkeep), after = LIFE_BODY)

/mob/living/silicon/decoy/life_steps()
	. = ..()
	if(life_set & LIFE_SET_DECOY)
		. += seq_step(PROC_REF(life_decoy_body), after = LIFE_BODY, reads = list(MOB_KEY_HEALTH))

/mob/living/silicon/pai/life_steps()
	. = ..()
	if(life_set & LIFE_SET_PAI)
		. += seq_step(PROC_REF(life_pai_cable), after = LIFE_INPUT)
		. += seq_step(PROC_REF(life_pai_body), after = list(LIFE_INPUT, "life_pai_cable"), reads = list(MOB_KEY_HEALTH))
		. += seq_step(PROC_REF(life_pai_silence), after = LIFE_OUTPUT)
		. += seq_step(PROC_REF(life_pai_repair), after = list(LIFE_OUTPUT, "life_pai_silence"), reads = list(MOB_KEY_HEALTH))

/mob/living/silicon/robot/life_steps()
	. = ..()
	if(life_set & LIFE_SET_ROBOT)
		. += seq_step(PROC_REF(life_robot_cycle), after = LIFE_INPUT)
		. += seq_step(PROC_REF(life_robot_senses), after = LIFE_INPUT, reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT) + LIFE_STATUS_READS, should_run = PROC_REF(life_robot_senses_due), woken_by = list(MOB_KEY_LOC = "Moved", MOB_KEY_EQUIPMENT = "modules equipped", MOB_KEY_STATUS = "status setters"))
		. += seq_step(PROC_REF(life_robot_power), after = LIFE_BODY)
		. += seq_step(PROC_REF(life_robot_body), after = list(LIFE_BODY, "life_robot_power"), reads = list(MOB_KEY_HEALTH))
		. += seq_step(PROC_REF(life_robot_alarms), after = LIFE_OUTPUT)

/mob/living/simple_mob/clockwork/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/slime/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/ysbryd/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_pre), after = LIFE_INPUT, should_run = PROC_REF(life_type_pre_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's own pre work: its due() reads state no producer publishes"))

/mob/living/carbon/brain/caught_soul/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_pre), after = LIFE_INPUT, should_run = PROC_REF(life_type_pre_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's own pre work: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/borer/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/blob/spore/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/homunculus/evil/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_type_pre), after = LIFE_INPUT, should_run = PROC_REF(life_type_pre_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's own pre work: its due() reads state no producer publishes"))

/mob/living/simple_mob/mechanical/mecha/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/mechanical/mining_drone/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/metroid/juvenile/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/bigdragon/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/demonAI/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/fossiltank/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/giant_spider/lurker/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/giant_spider/nurse/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/passive/cat/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/passive/fish/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_breathing), after = list(LIFE_INPUT, "life_light"), when = list("placed", "alive"), reads = list(MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_AIR), should_run = PROC_REF(life_breathing_due), rewake = PROC_REF(life_breathing_rewake), woken_by = LIFE_BREATHING_WOKEN_BY)

/mob/living/simple_mob/animal/sif/frostfly/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/sif/kururak/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/sif/leech/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/sif/savik/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/sif/tymisian/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/space/bear/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/space/goose/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/space/space_worm/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/tyr/rainbow_fly/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/mechanical/cyber_horror/tajaran/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/mechanical/ward/monitor/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/candy/bluecabold/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/candy/orangecabold/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/candy/purplecabold/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/candy/yellowcabold/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/spacecritter/livingice/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/spacecritter/radcrab/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/space/mouse_army/stealth/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/tyr/mineral_ants/builder/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/animal/tyr/mineral_ants/queen/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/humanoid/astral_collective/soul/shield_projector/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/mechanical/hivebot/support/commander/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/mechanical/hivebot/support/logistics/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))

/mob/living/simple_mob/vore/aggressive/panther/thor/life_steps()
	. = ..()
	if(life_set & LIFE_SET_LIVING)
		. += seq_step(PROC_REF(life_special), after = list(LIFE_TAIL, "life_supernatural"), when = "alive", should_run = PROC_REF(life_special_due), woken_by = list(LIFE_WOKEN_BY_POLL = "a type's special behaviour: its due() reads state no producer publishes"))
