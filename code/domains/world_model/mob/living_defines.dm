/mob/living
	see_invisible = SEE_INVISIBLE_LIVING


	var/hud_updateflag = 0

	// Health lives in the body (/datum/body, code/modules/body/) — there are no
	// damage pools on the mob. See doc/body_architecture.md.





	var/now_pushing = null





	var/evasion = 0 // Makes attacks harder to land. Negative numbers increase hit chance. The evasion stat (code/contracts/ids/body_stats.dm): the type's own value here, plus body factors.


	// Edge-detection cache for status alerts so throw_alert/clear_alert only fire on state transition.

	var/see_invisible_default = SEE_INVISIBLE_LIVING


	var/list/hud_list		//Holder for health hud, status hud, wanted hud, etc (not like inventory slots)





	// The inventory panel window datum is the LK_INVENTORY_PANEL link (inventory_panel()).

	var/static/list/fear_message_self = list(
									"Your heart is racing, it feels like it's going burst from your chest.",
									"Your stomach clenches and churns with anxiety.",
									"It's getting hard to breathe, you're panting heavily.",
									"You feel your eyes straining.",
									"A sharp shiver runs down your spine.",
									"You feel like you are drowning.",
									"You feel your palms clamming up.",
									"Your legs feel weak, you can barely control them.",
									"You have difficulty even swallowing."
									)
	var/static/list/fear_message_other = list(
									"'s eyes are darting around the room rapidly.",
									" looks like they are shivering, literally shaking.",
									" is breathing rapidly.",
									" looks profoundly uncomfortable.",
									"s literally trembling in front of you.",
									"'s hands are shaking.",
									" is rocking slightly from side to side."
									)



	/// Whether that mind's body held its key (a key move follows it).


	///a list of all status effects the mob has
	var/list/status_effects


/mob
/mob/living
	appearance_flags = TILE_BOUND|PIXEL_SCALE|KEEP_TOGETHER|LONG_GLIDE


// The mob owns its panel; the panel's host points back, so leaving it set would keep both alive.

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
/// The HUD-list bits (who sees what above this mob's head): flag_hud_update() sets them and publishes MOB_KEY_HUD_FLAGS.
PUBLISHED_BY(/mob/living, hud_updateflag, MOB_KEY_HUD_FLAGS)
/// The body's derived state (injury, pain, factors) changes through body.invalidate(), which publishes MOB_KEY_HEALTH.
PUBLISHED_BY(/mob/living, body, MOB_KEY_HEALTH)

/// Custom heat- and cold-discomfort messages (character preferences); unset for most mobs. Lists, read null-safe.
sparse(/mob/living, custom_heat, type = list)
sparse(/mob/living, custom_cold, type = list)
// Shapeshift forms and nests are sparse links, not vars on /mob/living (code/combat_ai/integration/mob_living.dm declares them).
/// The form a shapeshifter took (Shapeshifter shenanigans), or null.
/proc/tf_form_of(mob/living/L) as /mob/living
	return link_get(L, LK_TF_FORM)

/proc/set_tf_form(mob/living/L, mob/living/form)
	return link_set_one(L, LK_TF_FORM, form)

/// The mind that occupied this shapeshift form before its owner took it, or null.
/proc/tf_form_mind_of(mob/living/L) as /datum/mind
	return link_get(L, LK_TF_FORM_MIND)

/proc/set_tf_form_mind(mob/living/L, datum/mind/M)
	return link_set_one(L, LK_TF_FORM_MIND, M)

/// The nest a mob came from (the prop nest, a blob factory or a mob spawner; not specific), or null.
/proc/nest_of(mob/living/L)
	return link_get(L, LK_NEST)

/proc/set_nest(mob/living/L, atom/nest)
	return link_set_one(L, LK_NEST, nest)


/// Flight: TRUE while anything holds the mob aloft (wings, a flying ability, a dragon's charge). Read stat_value(L, STAT_FLYING); write set_flying().
STAT(/mob/living, flying, ANY, virtual = TRUE)
SOURCE_DEF(flight)

/// Starts (TRUE) or stops (FALSE) the mob's own flight, the SRC_FLIGHT hold on STAT_FLYING.
/proc/set_flying(mob/living/L, on)
	if(on)
		hold(L, STAT_FLYING, TRUE, SRC_FLIGHT)
	else
		release(L, STAT_FLYING, SRC_FLIGHT)
	return on

/// Burning: TRUE while one of the mob's fire-stack status effects is lit (its SRC_FIRE_STACKS hold). Read stat_value(L, STAT_ON_FIRE).
STAT(/mob/living, on_fire, ANY, virtual = TRUE)
SOURCE_DEF(fire_stacks)

/// The mob's fire stacks: the sum over its fire-handler status effects (wet stacks count negative). Nothing caches it on the mob.
/proc/fire_stacks_of(mob/living/L)
	READS_FROM(L)
	. = 0
	for(var/datum/status_effect/fire_handler/F in L?.status_effects)
		. += F.stacks * F.stack_modifier

/// Fire stacks this mob sheds per second while it burns (negative). Silicons shed theirs faster.
/mob/living/proc/fire_stack_decay_rate()
	return -0.05

CAPABILITIES(/mob/living)
	section(lazy_state, "Rare state, one lazy datum per feature (storage contract): autofire, body_effect, bodyweight, breath_hazard, capture, footstep, gut_disability, living_misc, melee_swing, omen, passtable, rad_countdown, slosh, tm_instability, trait_injection, vent_crawl, vore_fx")
	owns_one(nameof(autofire), /datum/autofire_state, lazy = TRUE)
	owns_one(nameof(body_effect), /datum/body_effect_state, lazy = TRUE)
	owns_one(nameof(bodyweight), /datum/bodyweight_state, lazy = TRUE)
	owns_one(nameof(breath_hazard), /datum/breath_hazard_state, lazy = TRUE)
	owns_one(nameof(capture), /datum/capture_state, lazy = TRUE)
	owns_one(nameof(footfall), /datum/footfall_state, lazy = TRUE)
	owns_one(nameof(gut_disability), /datum/gut_disability_state, lazy = TRUE)
	owns_one(nameof(living_misc), /datum/living_misc_state, lazy = TRUE)
	owns_one(nameof(melee_swing), /datum/melee_swing_state, lazy = TRUE)
	owns_one(nameof(omen), /datum/omen_state, lazy = TRUE)
	owns_one(nameof(passtable), /datum/passtable_state, lazy = TRUE)
	owns_one(nameof(rad_countdown), /datum/rad_countdown_state, lazy = TRUE)
	owns_one(nameof(slosh), /datum/slosh_state, lazy = TRUE)
	owns_one(nameof(tm_instability), /datum/tm_instability_state, lazy = TRUE)
	owns_one(nameof(trait_injection), /datum/trait_injection_state, lazy = TRUE)
	owns_one(nameof(vent_crawl), /datum/vent_crawl_state, lazy = TRUE)
	owns_one(nameof(vore_fx), /datum/vore_fx_state, lazy = TRUE)
	ref_one(nameof(default_language), /datum/language)
	op("mob_sleep", menu(), label("Sleep"), needs(req_self()), then(PROC_REF(mob_sleep_op)))
	op("check_default_language", menu(), label("Check Default Language"), needs(req_self()), then(PROC_REF(check_default_language_op)))
	op("give", menu(), label("Give"), needs(req_self()), asks(/datum/prompt/choice, fields = list("question" = "Give to whom?", "title" = "Give", "choices" = computed(PROC_REF(give_recipients)), "timeout" = 0), step = "recipient"), then(PROC_REF(give_op)))
	op("look_up", menu(desc = "Look above you, and hope there's no ceiling spiders."), label("Look Up"), needs(req_self()), then(PROC_REF(look_up_op)))
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	setup(PROC_REF(prime_hud_list))
	living_rules(vore_icon_bellies = list("stomach"), use_modern_ai = FALSE, has_huds = FALSE, max_nutrition = MAX_NUTRITION, fire_reaction = FIRE_REACTION_BURN, fire_trigger_verb = "ignited", fire_heats_body = FALSE, force_max_speed = 0, adminbus_trash = FALSE, parasitic = FALSE, appendage_color = "#e03997", vore_shred_time = 45 SECONDS, low_sorting_priority = FALSE)
	butchery_rules(meat_amount = 0)
	footstep_rules(footstep_volume = 0.1, footstep_e_range = -8)
	ref_one(nameof(own_identity))
	ref_one(nameof(tf_mob_holder))
	ref_one(nameof(identity))
	stamps(last_breath_at, climb_started) // last_breath_at: the last scheduled breath on its own (bio) clock, so a breathing step woken from sleep breathes when one is due; climb_started: when the climb op in flight began
	cooldowns(next_preyloop, hud_full_refresh_at, last_special, resist_cooldown, fear_sound_cooldown, spit_cooldown, next_sonar_ping, venom_milking_cd)
	links(LINK_END(/mob/living, LK_TF_FORM), LINK_END(/mob/living, LK_TF_ORIGIN), sparse = TRUE, b_many = TRUE)
	links(LINK_END(/mob/living, LK_TF_FORM_MIND), LINK_END(/datum/mind, LK_TF_FORM_MIND_OF), sparse = TRUE, b_many = TRUE)
	links(LINK_END(/mob/living, LK_NEST), LINK_END(/atom, LK_NEST_SPAWNS), sparse = TRUE, b_many = TRUE)
	attack_variants()
	op("touch_help", hand(), when(req_empty_hand()), stance(I_HELP), priority(OP_PRIORITY_DEFAULT - 10), label("Help"), then(PROC_REF(touch_help)))
	op("touch_disarm", hand(), when(req_empty_hand()), stance(I_DISARM), priority(OP_PRIORITY_DEFAULT - 10), label("Shove"), then(PROC_REF(touch_disarm)))
	op("touch_grab", hand(), when(req_empty_hand()), stance(I_GRAB), priority(OP_PRIORITY_DEFAULT - 10), label("Take hold"), then(PROC_REF(touch_grab)))
	op("touch_hurt", hand(), when(req_empty_hand()), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 10), label("Punch"), then(PROC_REF(touch_hurt)))
	op("hit_help", item(/obj/item), stance(I_HELP), priority(OP_PRIORITY_DEFAULT - 10), label("Use on"), then(PROC_REF(hit_help)))
	op("hit_disarm", item(/obj/item), stance(I_DISARM), priority(OP_PRIORITY_DEFAULT - 10), label("Shove with"), then(PROC_REF(hit_disarm)))
	op("hit_grab", item(/obj/item), stance(I_GRAB), priority(OP_PRIORITY_DEFAULT - 10), label("Hold with"), then(PROC_REF(hit_grab)))
	op("hit_hurt", item(/obj/item), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 10), label("Hit"), then(PROC_REF(hit_hurt)))
	living_action_status_contributions()
	// Prone posture composes density rather than overwriting the stat's served value.
	when(nameof(lying), contributes(STAT_DENSITY, FALSE, priority = PRIORITY_FORCE))
	living_abilities()
	every(PROC_REF(autofire_interval), then(PROC_REF(autofire_tick)), when = STAT_AUTOFIRE_ON)
	ref_many(nameof(shared_soul_links))
	// The attached limbs (rel_add() in body/parts/attach.dm): a look follows them attaching and leaving.
	ref_many(nameof(organs), /obj/item/organ/external)
	// Equipped or pump-supplied breathing tank; custody belongs to its actual slot.
	ref_one(nameof(internal))
	links(LINK_END(/mob/living, LK_FACTION_LEDGER), LINK_END(/datum/faction_reputation_ledger, LK_FACTION_LEDGER_OF), sparse = TRUE, b_many = TRUE) // the faction reputation ledger it reads and writes (faction_reputation())
	// The Life presentation reactions (code/modules/mob/living/life/living_systems.dm): each runs once per drain after one of its facts was published
	// (a MOB_KEY_* fact its producer publishes, or a var's setter); the generator adds what the handler's procs read (reaction_reads()). HUD and sight
	// run at most once a LIFE_PRESENT_MIN_INTERVAL, the first change at once and the rest in one trailing run (a walking player raises a location change most ticks) and only for the mobs their gate wants.
	on_change(cond_published(MOB_KEY_STATUS, nameof(stat)), ANY, when(PROC_REF(life_canmove_wanted)), then(PROC_REF(life_canmove_changed)))
	on_change(cond_published(MOB_KEY_HEALTH, MOB_KEY_STATUS, MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_CLIENT, MOB_KEY_VIEW, MOB_KEY_HUD_FLAGS, MOB_KEY_NUTRITION, "stat:[STAT_ON_FIRE]", nameof(stat), nameof(sdisabilities), nameof(ear_damage)), ANY, when(PROC_REF(life_hud_wanted)), coalesce(LIFE_PRESENT_MIN_INTERVAL, leading = TRUE), then(PROC_REF(life_hud_changed)))
	on_change(cond_published(MOB_KEY_STATUS, MOB_KEY_EQUIPMENT, MOB_KEY_CONDITIONS, MOB_KEY_HEALTH, MOB_KEY_CLIENT, MOB_KEY_VIEW, nameof(stat), nameof(sdisabilities), nameof(tf_mob_holder), nameof(virtual_reality_mob)), ANY, when(PROC_REF(life_vision_wanted)), coalesce(LIFE_PRESENT_MIN_INTERVAL, leading = TRUE), then(PROC_REF(life_vision_changed)))
	owns_one(nameof(aiming), /obj/aiming_overlay)
	// a human builds its body in set_species(), before init, so its organs have part slots to attach into; the var then holds it and nothing is made here
	owns_one(nameof(body), /datum/body, starts = nameof(body_type))
	owns_one(nameof(changeling_state), /datum/changeling)
	links(LINK_END(/mob/living, LK_SETUP_BUTTON), LINK_END(/datum/character_setup_button, LK_SETUP_BUTTON_OF), sparse = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // the character setup HUD button, gone with the mob (character_setup_button())
	owns_one(nameof(deaf_loop), /datum/looping_sound/mob/deafened, starts = /datum/looping_sound/mob/deafened, starts_args = list(FALSE))
	links(LINK_END(/mob/living, LK_INVENTORY_PANEL), LINK_END(/datum/inventory_panel, LK_INVENTORY_PANEL_OF), sparse = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // the inventory window datum, gone with the mob (inventory_panel())
	owns_one(nameof(say_list), /datum/say_list, starts = PROC_REF(make_say_list))
	owns_one(nameof(shadekin), /datum/shadekin)
	links(LINK_END(/mob/living, LK_TURFSLIP), LINK_END(/datum/turfslip, LK_TURFSLIP_OF), sparse = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // the slide the mob is on, gone with it (current_turfslip())
	owns_many(nameof(owned_soul_links), /datum/soul_link)
	owns_many(nameof(status_effects))
	owns_many(nameof(trait_states))
	owns_many(nameof(body_effect_origins))
	owns_many(nameof(hud_list))
	owns_many(nameof(stasis_sources))
	// What holds the biological clock rate down (a sleeper, a stasis bed) is the body's stasis (code/modules/medical/stabilisation/stasis.dm).
	on_change(STAT_CLOCK_RATE_BIO, ANY, then(PROC_REF(clock_rate_bio_changed)))
	drag_onto(PROC_REF(drop_input))
	links(LINK_END(/mob/living, LK_AUTOFIRE_GUN), LINK_END(/obj/item/gun, LK_AUTOFIRE_USERS), sparse = TRUE, b_many = TRUE) // the gun a held trigger fires (autofire_gun())
