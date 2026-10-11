/mob/living
	see_invisible = SEE_INVISIBLE_LIVING


	var/hud_updateflag = 0

	// Health lives in the body (/datum/body, code/modules/body/) — there are no
	// damage pools on the mob. See doc/body_architecture.md.

	var/max_nutrition = MAX_NUTRITION




	var/now_pushing = null


	var/tod = null // Time of death
	/// TRUE only inside return_from_death(): the one place set_stat() may leave DEAD.
	var/tmp/revival_in_progress = FALSE


	var/failed_last_breath = 0 //This is used to determine if the mob failed a breath. If they did fail a brath, they will attempt to breathe each tick, otherwise just once per 4 ticks.

	var/evasion = 0 // Makes attacks harder to land. Negative numbers increase hit chance.
	var/force_max_speed = 0 // If 1, the mob runs extremely fast and cannot be slowed.


	// Edge-detection cache for status alerts so throw_alert/clear_alert only fire on state transition.

	var/see_invisible_default = SEE_INVISIBLE_LIVING


	var/list/hud_list		//Holder for health hud, status hud, wanted hud, etc (not like inventory slots)
	var/has_huds = FALSE	//Whether or not we should bother initializing the above list





	var/datum/inventory_panel/inventory_panel

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

	var/touch_reaction_flags


	/// Whether that mind's body held its key (a key move follows it).
	var/tf_form_holds_key = FALSE


	///a list of all status effects the mob has
	var/list/status_effects


/mob
	var/muffled = FALSE					// Used by muffling belly
	var/forced_psay = FALSE				// If true will prevent the user from speaking with normal say/emotes, and instead redirect these to a private speech mode with their predator.
	var/autowhisper = FALSE				// Automatically whisper
	var/autowhisper_mode = null			// Mode to use with autowhisper
/mob/living
	var/custom_link = null
	appearance_flags = TILE_BOUND|PIXEL_SCALE|KEEP_TOGETHER|LONG_GLIDE
	var/private_notes = null

/mob
	var/climbing_delay = 1.5 //By default, mobs climb at quarter speed. To be overriden by specific simple mobs or species speed
	var/eggs = 0

// The mob owns its panel; the panel's host points back, so leaving it set would keep both alive.
/// The mob an AI's follow-camera mode is tracking (camera/tracking.dm declares the follow loop on it). A relation view (ref_one in
/// CAPABILITIES(/mob/living)): null once the target is deleted.
/mob/living/var/mob/living/cameraFollow = null // ALLOW(base_vars): was an OM_FIELD_VIEW on this type; moved, not added

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob/living, hand)
TRACKED(/mob/living, see_invisible_default)
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
