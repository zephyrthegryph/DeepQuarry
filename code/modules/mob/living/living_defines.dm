/mob/living
	see_invisible = SEE_INVISIBLE_LIVING

	var/mob_class = null	// A mob's "class", e.g. human, mechanical, animal, etc. Used for certain projectile effects. See __defines/mob.dm for available classes.

	var/hud_updateflag = 0

	// Health lives in the body (/datum/body, code/modules/body/) — there are no
	// damage pools on the mob. See doc/body_architecture.md.

	var/nutrition = 400
	var/max_nutrition = MAX_NUTRITION


	var/last_special = 0 //Used by the resist verb, likely used to prevent players from bypassing next_move by logging in/out.
	var/base_attack_cooldown = DEFAULT_ATTACK_COOLDOWN


	var/now_pushing = null
	var/mob_bump_flag = 0
	var/mob_swap_flags = 0
	var/mob_push_flags = 0
	var/mob_always_swap = 0


	var/tod = null // Time of death
	/// TRUE only inside return_from_death(): the one place set_stat() may leave DEAD.
	var/tmp/revival_in_progress = FALSE

	/// Helper vars for quick access to firestacks, these should be updated every time firestacks are adjusted
	var/on_fire = 0
	var/fire_stacks
	/// Rate at which fire stacks should decay from this mob
	var/fire_stack_decay_rate = -0.05

	var/failed_last_breath = 0 //This is used to determine if the mob failed a breath. If they did fail a brath, they will attempt to breathe each tick, otherwise just once per 4 ticks.
	var/lastpuke = 0

	var/evasion = 0 // Makes attacks harder to land. Negative numbers increase hit chance.
	var/force_max_speed = 0 // If 1, the mob runs extremely fast and cannot be slowed.

	var/image/dsoverlay = null //Overlay used for darksight eye adjustments

	// Last params applied by the light life system, so we can skip redundant set_light() calls each tick.
	var/last_glow_range = null
	var/last_glow_intensity = null
	var/last_glow_color = null

	// Edge-detection cache for status alerts so throw_alert/clear_alert only fire on state transition.

	var/see_invisible_default = SEE_INVISIBLE_LIVING

	var/nest				//Not specific, because a Nest may be the prop nest, or blob factory in this case.

	var/list/hud_list		//Holder for health hud, status hud, wanted hud, etc (not like inventory slots)
	var/has_huds = FALSE	//Whether or not we should bother initializing the above list

	var/makes_dirt = TRUE	//FALSE if the mob shouldn't be making dirt on the ground when it walks

	var/image/selected_image = null // Used for buildmode AI control stuff.

	var/allow_self_surgery = FALSE	// Used to determine if the mob can perform surgery on itself.


	var/flying = 0				// Allows flight
	var/inventory_panel_type = /datum/inventory_panel
	var/datum/inventory_panel/inventory_panel
	COOLDOWN_DECLARE(resist_cooldown) // world.time the next resist is allowed.
	var/tiredness = 0					//For vore draining
	var/fear = 0 						//For fear effects and phobias
	COOLDOWN_DECLARE(fear_sound_cooldown)				//For making sure the heartbeats don't play over each other

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


	var/mob/living/tf_form // Shapeshifter shenanigans
	/// The mind that occupied this shapeshift form before its owner took it.
	var/datum/mind/tf_form_mind
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
	var/hunger_rate = DEFAULT_HUNGER_FACTOR
	var/private_notes = null
//custom say verbs
	var/custom_say = null
	var/custom_ask = null
	var/custom_exclaim = null
	var/custom_whisper = null
//custom temperature discomfort vars
	/// Lazy list (null when empty) of custom heat-discomfort messages. Null-safe reads only.
	var/list/custom_heat
	/// Lazy list (null when empty) of custom cold-discomfort messages. Null-safe reads only.
	var/list/custom_cold

/mob
	var/can_climb = FALSE //Checked by turfs when using climb_wall(). Defined here for silicons and simple mobs
	var/climbing_delay = 1.5 //By default, mobs climb at quarter speed. To be overriden by specific simple mobs or species speed
	var/eggs = 0

// The mob owns its panel; the panel's host points back, so leaving it set would keep both alive.
/// The mob an AI's follow-camera mode is tracking (camera/tracking.dm declares the follow loop on it). A relation view (ref_one in
/// CAPABILITIES(/mob/living)): null once the target is deleted.
/mob/living/var/mob/living/cameraFollow = null // ALLOW(base_vars): was an OM_FIELD_VIEW on this type; moved, not added

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob/living, tiredness)
TRACKED(/mob/living, fear)
TRACKED(/mob/living, on_fire)
TRACKED(/mob/living, see_invisible_default)
/// The HUD-list bits (who sees what above this mob's head): flag_hud_update() sets them and publishes MOB_KEY_HUD_FLAGS.
PUBLISHED_BY(/mob/living, hud_updateflag, MOB_KEY_HUD_FLAGS)
/// The body's derived state (injury, pain, factors) changes through body.invalidate(), which publishes MOB_KEY_HEALTH.
PUBLISHED_BY(/mob/living, body, MOB_KEY_HEALTH)
