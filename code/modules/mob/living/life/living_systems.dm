// Living core steps: the old /mob/living/Life() sequence, one step per concern (declared in life_steps.dm). The edges
// and `when =` conditions reproduce the old control flow (doc/rewrite/life_sequences.md):
//
//	type_pre overrides         (subtype code that ran before ..(); may F.abort())
//	trait steps                (per-trait Life work, contributed by trait states)
//	upkeep, instability, modifiers
//	[placed]                   light
//	[placed, alive]            breathing, mutations, radiation, blood, random events, AFK
//	[placed]                   chemicals, diseases, environment, ambience, movement,
//	                           status (the body tick; it re-reads "alive" afterwards)
//	[placed, alive]            disabilities, addictions
//	[placed]                   TF holder, VR derez
//	subtype tails (carbon germs, human, alien, simple mob, bot), then type_post overrides
//
// canmove, HUD and vision are on_change() reactions on /mob/living ("Reactive output" below).
//
// Sleeping: each step's life_<step>_due() (its should_run) says it has work, and `woken_by` names the producers that
// raise the channels in its `reads`. A subtype that overrides a step's proc overrides its _due() too when its own
// work differs.

// --- Per-type pre and post chains ---------------------------------------------------------------

/// Code a mob subtype ran before calling ..() in its old Life() override. A variant runs its own
/// code, then `return ..()`. `return ctx.abort()` without calling ..() ends the frame, as the
/// old early `return` before ..() did.
/mob/living/proc/life_type_pre(datum/seq_frame/life/F)
	return

/// The root is a no-op; a variant's pre code runs every cycle.
/mob/living/proc/life_type_pre_due()
	return FALSE

/// Code a mob subtype ran after ..() in its old Life() override. A variant starts with `..()`,
/// which runs its parent's post code, then runs its own; code that only runs for a living mob
/// checks `ctx.fact("alive")`.
/mob/living/proc/life_type_post_rewake()
	return 0

/mob/living/proc/life_type_post(datum/seq_frame/life/F)
	return

/// The root and the carbon and simple mob variants do nothing.
/mob/living/proc/life_type_post_due()
	return FALSE

/mob/living/carbon/life_type_post_due()
	return FALSE

/// Mobs whose Life() only takes them out of the mob lists (preview dummies, announcers).
/mob/living/proc/life_delist(datum/seq_frame/life/F)
	return

// --- Trait systems ------------------------------------------------------------------------------

// Per-trait Life work is contributed: a trait state (code/modules/mob/living/carbon/human/species/station/traits/states/_trait_state.dm) declares its
// step in its own life_steps() and joins the mob's Life table while attached (seq_extra_add()).

// --- Upkeep ---------------------------------------------------------------------------------------

/// Every mob's base upkeep (the old /mob/Life() chain): followers and spell buttons.
/mob/living/proc/life_upkeep(datum/seq_frame/life/F)
	// to catch teleports etc which directly set loc
	src.update_following()
	src.update_spell_masters()

/// Followers are dragged along on Moved; spell buttons only matter for casters.
/mob/living/proc/life_upkeep_due()
	return LAZYLEN(src?.follower_list()) || LAZYLEN(src.spell_masters)

// --- Light --------------------------------------------------------------------------------------

/// Mob glow (glow_toggle, technomancer instability). Also run on demand by refresh_glow().
/mob/living/proc/life_light(datum/seq_frame/life/F)
	if(src.glow_override)
		return FALSE

	// Determine the desired light params, then only call set_light() if they changed
	// since last tick (this runs every Life() tick for every glowing mob).
	var/want_range
	var/want_intensity
	var/want_color
	. = FALSE

	if(src.instability >= TECHNOMANCER_INSTABILITY_MIN_GLOW)
		var/distance = round(sqrt(src.instability / 2))
		if(distance)
			want_range = distance
			want_intensity = distance * 4
			want_color = "#660066"
			. = TRUE
		else
			return FALSE // Preserve old behavior: distance 0 leaves the existing light untouched.

	else if(src.glow_toggle && !src.is_ventcrawling) // Hide the light in vents
		want_range = src.glow_range
		want_intensity = src.glow_intensity
		want_color = src.glow_color

	else
		want_range = 0

	if(want_range != src.last_glow_range || want_intensity != src.last_glow_intensity || want_color != src.last_glow_color)
		if(want_range)
			src.set_light(want_range, want_intensity, want_color)
		else
			src.set_light(0)
		src.last_glow_range = want_range
		src.last_glow_intensity = want_intensity
		src.last_glow_color = want_color

/// Re-evaluates this mob's glow now (light system).
/mob/living/proc/refresh_glow()
	return run_step_now(src, PROC_REF(life_light), /datum/sequence/life)

/// Idle once the applied light matches what tick() would ask for.
/mob/living/proc/life_light_due()
	if(src.glow_override)
		return FALSE
	if(src.instability >= TECHNOMANCER_INSTABILITY_MIN_GLOW)
		return TRUE
	if(src.glow_toggle && !src.is_ventcrawling)
		return src.last_glow_range != src.glow_range || src.last_glow_intensity != src.glow_intensity || src.last_glow_color != src.glow_color
	return src.last_glow_range

// --- Alive block -----------------------------------------------------------------------------------

/// Breathing. The carbon variant takes a breath on its own cadence (breathe()).
/mob/living/proc/life_breathing_rewake()
	return 0

/mob/living/proc/life_breathing(datum/seq_frame/life/F)
	return

/mob/living/proc/life_breathing_due()
	return FALSE

/// Genetic mutation effects.
/mob/living/proc/life_mutations(datum/seq_frame/life/F)
	SHOULD_CALL_PARENT(TRUE)
	return

/// The root has nothing to do (humans override it).
/mob/living/proc/life_mutations_due()
	return FALSE

/// Radiation dose decay and effects.
/mob/living/proc/life_radiation_rewake()
	return 0

/mob/living/proc/life_radiation_applies()
	return TRUE

/mob/living/proc/life_radiation(datum/seq_frame/life/F)
	SHOULD_CALL_PARENT(TRUE)
	var/datum/act/live_radiation/tick = ACT_TRY(src, live_radiation)
	if(!tick)
		return COMPONENT_BLOCK_LIVING_RADIATION
	act_cancel(tick)

/// The root only feeds its signal's listeners (the radiation effects component).
/mob/living/proc/life_radiation_due()
	return act_wanted(src, /datum/act/live_radiation)

/// Random episodes (vomiting, ...).
/mob/living/proc/life_random_events(datum/seq_frame/life/F)
	return

/mob/living/proc/life_random_events_due()
	return FALSE

/// Automatic AFK marking for idle clients.
/mob/living/proc/life_afk(datum/seq_frame/life/F)
	var/client/C = src.client
	if(!C)
		return
	var/idle_limit = 10 MINUTES
	if(C.inactivity >= idle_limit && !src.away_from_keyboard && C.prefs?.read_preference(/datum/preference/toggle/auto_afk))	//if we're not already afk and we've been idle too long, and we have automarking enabled... then automark it
		src.add_status_indicator("afk")
		to_chat(src, span_notice("You have been idle for too long, and automatically marked as AFK."))
		src.away_from_keyboard = TRUE
	else if(src.away_from_keyboard && C.inactivity < idle_limit && !src.manual_afk) //if we're afk but we do something AND we weren't manually flagged as afk, unmark it
		src.remove_status_indicator("afk")
		to_chat(src, span_notice("You have been automatically un-marked as AFK."))
		src.away_from_keyboard = FALSE

/// Lazy: a client's idle time is checked on a timer, not every cycle.

/mob/living/proc/life_afk_rewake()
	return src.client ? 30 SECONDS : 0

// --- Core -------------------------------------------------------------------------------------

/// Chemicals in the body. Runs dead or alive, so blood can be added after death.
/mob/living/proc/life_chemicals_rewake()
	return 0

/mob/living/proc/life_chemicals(datum/seq_frame/life/F)
	return

/mob/living/proc/life_chemicals_due()
	return FALSE

/// Runs the chemicals system now (extra circulation from CPR, horror modifiers, ...).
/// A run-now frame has no stasis fact of its own, so the paused biology clock is honoured here:
/// extra circulation can't metabolise faster than stasis allows (P2-S6).
/mob/living/proc/process_chemicals()
	if(body?.stasis_paused)
		return null
	return run_step_now(src, PROC_REF(life_chemicals), /datum/sequence/life)

/// Environment: temperature and pressure differences between body and surroundings.
/mob/living/proc/life_environment_rewake()
	return 0

/mob/living/proc/life_environment(datum/seq_frame/life/F)
	if(F.environment())
		life_environment_exchange(F.environment())

/// Handle temperature/pressure differences between body and environment.
/mob/living/proc/life_environment_exchange(datum/gas_mixture/environment)
	return

/mob/living/proc/life_environment_due()
	return FALSE

/// Re-plays area ambience to a client that has stayed in one area.
/mob/living/proc/life_ambience(datum/seq_frame/life/F)
	if(!src.client)
		return
	// If you're in an ambient area and have not moved out of it for x time as configured per-client, and do not have it disabled, we're going to play ambience again to you, to help break up the silence.
	var/pref = src.read_preference(/datum/preference/numeric/ambience_freq)
	if(!pref)
		return

	if(ELAPSED(src, lastareachange, CLOCK_WORLD) >= pref MINUTES) // Every 5 minutes (by default, set per-client), we're going to run a 35% chance (by default, also set per-client) to play ambience.
		var/area/A = get_area(src)
		if(A)
			EXPIRY_STAMP(src, lastareachange, CLOCK_WORLD) // This will refresh the last area change to prevent this call happening LITERALLY every life tick.
			A.play_ambience(src, initial = FALSE)

/// Lazy: sleeps until the next replay is due.

/mob/living/proc/life_ambience_rewake()
	if(!src.client)
		return 0
	var/pref = src.read_preference(/datum/preference/numeric/ambience_freq)
	if(!pref)
		return 0
	return max(1 SECONDS, src.lastareachange + pref MINUTES - world.time)

/// Gravity, pulling and grabs.
/mob/living/proc/life_movement(datum/seq_frame/life/F)
	src.update_gravity(src.mob_get_gravity())

	src.update_pulling()

	FOR_CONTENTS(var/obj/item/grab/G, src)
		G.periodic_step()

/// Busy while pulling or grabbing. Gravity is re-read on Moved, and on a timer for players.
/mob/living/proc/life_movement_due()
	return src?.pulling_target() || (locate_in_list(src, /obj/item/grab))

/mob/living/proc/life_movement_rewake()
	return src.client ? 30 SECONDS : 0

/// Status & health update: are we dead or alive, conscious or not. When it returns false the
/// disabilities and addictions systems skip this cycle.
/mob/living/proc/life_status_rewake()
	return 0

/// The body tick decides death: "alive" is read again for the stages after this one, and
/// "status_ok" (what update_status() returned) gates disabilities and addictions.
/mob/living/proc/life_status(datum/seq_frame/life/F)
	F.status_ok = !!life_status_update_status()
	F.forget("alive")

/// This updates the health and status of the mob (conscious, unconscious, dead).
/mob/living/proc/life_status_update_status()
	src.body?.life_tick()
	if(src.stat != DEAD)
		src.set_stat(CONSCIOUS)
		return TRUE

/// The root sleeps while the mob is conscious (or dead) and its body has nothing to tick.
/mob/living/proc/life_status_due()
	if(src.stat == UNCONSCIOUS)
		return TRUE
	return src.body && !src.body.life_settled()

/// TRUE when life_tick() has nothing to do: no afflictions, no factor effects, nothing
/// stale. Plans that evaluate every tick (humanoids) never settle.
/datum/body/proc/life_settled()
	return !always_evaluate && !LAZYLEN(afflictions) && !factors && !(dirty & BODY_DIRTY_VITALS) && !factors_stale()

/// The simple plan's life_tick() ignores factors: it works only on afflictions and vitals.
/datum/body/simple/life_settled()
	return !LAZYLEN(afflictions) && !(dirty & BODY_DIRTY_VITALS)

// --- Status block -----------------------------------------------------------------------------

/// Eye and ear damage recovery.
/// Temporary blindness, blur and deafness end on their own (timed statuses); this keeps the
/// ones that don't (a disability, unconsciousness) topped up and heals ear damage.
/mob/living/proc/life_disabilities(datum/seq_frame/life/F)
	//Eyes: blindness from disability or unconsciousness doesn't get better on its own. It is an
	// untimed hold while the cause lasts, not a one-cycle top-up: re-topping a timed status every
	// frame raised a status change on the mob's own frame and kept it from ever parking.
	life_disability_hold(src, STAT_BLINDED, SRC_DISABILITY_BLIND, (src.sdisabilities & BLIND) || src.stat)
	if(src.has_status(STAT_BLINDED))
		src.throw_alert("blind", /atom/movable/screen/alert/blind)
	else
		src.clear_alert("blind")

	//Ears
	life_disability_hold(src, STAT_DEAFENED, SRC_DISABILITY_DEAF, src.sdisabilities & DEAF) //disabled-deaf, doesn't get better on its own
	if(!(src.sdisabilities & DEAF) && src.ear_damage > 0 && src.ear_damage < 100)
		// ear damage heals slowly over time, unless it is over 100
		src.adjustEarDamage(-0.05, 0)

/// Busy while a disability or unconsciousness keeps blindness or deafness up, ears are healing,
/// or the blind alert doesn't match the status yet. (Trait disabilities tick on their own every(): disability.dm.)
/mob/living/proc/life_disabilities_due()
	if(!life_disability_hold_matches(src, STAT_BLINDED, SRC_DISABILITY_BLIND, (src.sdisabilities & BLIND) || src.stat))
		return TRUE
	if(!life_disability_hold_matches(src, STAT_DEAFENED, SRC_DISABILITY_DEAF, src.sdisabilities & DEAF))
		return TRUE
	if(src.ear_damage > 0 && src.ear_damage < 100)
		return TRUE
	return !src.alerts?["blind"] == src.has_status(STAT_BLINDED)

/// Holds status `status_id` on `self` under `source` (a disability) while `wanted`, releases it otherwise.
/// Holding what is already held and releasing what isn't are no-ops, so no change is raised.
/proc/life_disability_hold(mob/living/self, status_id, source, wanted)
	if(life_disability_hold_matches(self, status_id, source, wanted))
		return
	if(wanted)
		hold(self, status_id, 1, source)
	else
		release(self, status_id, source)

/proc/life_disability_hold_matches(mob/living/self, status_id, source, wanted)
	return held_by_source(self, status_id, source) == !!wanted

// --- Output -----------------------------------------------------------------------------------

// --- Reactive output: canmove, HUD and sight (doc/rewrite/life_sequences.md S2) -------------------
// Three on_change() reactions on /mob/living, not Life steps: each runs when one of its keys is published
// (the mob's tracked stat, or a MOB_KEY_* fact its producer publishes: PUBLISH_CHANGE), coalesced per drain.
// HUD and sight run at most every
// LIFE_PRESENT_MIN_INTERVAL (a walking player raises a location change most ticks and the HUD needs only
// the latest state). The HUD reaction's `when` is life_hud_wanted(): a mob without a client queues
// nothing. Rewakes (darksight re-adapting, a fading overlay, a remote-view listener) are keyed after()
// timers. There is no manual refresh: each reaction declares the facts below by hand (published keys), and
// tools/ci/derived_reads_lint.py generates the rest from what its procs and their helpers read
// (reaction_reads() in code/_generated/reads.dm: every such var is tracked, a relation, or PUBLISHED_BY a key).

/// The Life sets that derive canmove / draw a HUD and sight (the decoy and delisted mobs do neither).
#define LIFE_CANMOVE_SETS (LIFE_SET_LIVING | LIFE_SET_ROBOT)
#define LIFE_PRESENT_SETS (LIFE_SET_LIVING | LIFE_SET_ROBOT | LIFE_SET_AI | LIFE_SET_PAI)
// What each reaction reads: the facts its old stages woke on (their wake_on channels plus their pipeline's
// wake_all), as change keys. The catch-all CHANGE_EXPLICIT is gone: a hand change that should redraw writes its
// var through a setter or publishes the fact (MOB_KEY_VIEW for what the client looks through).
/// after() keys of the rewakes.
#define LIFE_HUD_REWAKE "life_hud"
#define LIFE_VISION_REWAKE "life_vision"

/mob/living/reactions()
	. = ..()
	. += on_change(list(MOB_KEY_STATUS, nameof(stat)), PROC_REF(life_canmove_changed), when = PROC_REF(life_canmove_wanted))
	. += on_change(list(MOB_KEY_HEALTH, MOB_KEY_STATUS, MOB_KEY_LOC, MOB_KEY_EQUIPMENT, MOB_KEY_CLIENT, MOB_KEY_VIEW, \
		MOB_KEY_HUD_FLAGS, nameof(stat), nameof(sdisabilities), nameof(ear_damage)), \
		PROC_REF(life_hud_changed), at_most = LIFE_PRESENT_MIN_INTERVAL, when = PROC_REF(life_hud_wanted))
	. += on_change(list(MOB_KEY_STATUS, MOB_KEY_EQUIPMENT, MOB_KEY_CONDITIONS, MOB_KEY_HEALTH, MOB_KEY_CLIENT, MOB_KEY_VIEW, nameof(stat), \
		nameof(sdisabilities), nameof(cameraFollow), nameof(tf_mob_holder), nameof(virtual_reality_mob)), \
		PROC_REF(life_vision_changed), at_most = LIFE_PRESENT_MIN_INTERVAL, when = PROC_REF(life_vision_wanted))

/// Not transforming and somewhere (the Life frame's "placed").
/mob/living/proc/life_placed()
	return loc && !transforming

/mob/living/proc/life_canmove_wanted()
	return life_set & LIFE_CANMOVE_SETS

/// The HUD reaction's gate: only a mob with a client draws one.
/mob/living/proc/life_hud_wanted()
	return client && (life_set & LIFE_PRESENT_SETS)

/// Sight flags matter for every living mob, client or not.
/mob/living/proc/life_vision_wanted()
	return life_set & LIFE_PRESENT_SETS

/mob/living/proc/life_canmove_changed(list/keys)
	if(QDELETED(src) || !life_canmove_wanted())
		return
	life_canmove()

/// Whether the mob can move (lying, stunned, buckled, ...). Resting and buckling update canmove
/// themselves, and the statuses when they start or end.
/mob/living/proc/life_canmove()
	if(life_placed())
		update_canmove()

/mob/living/proc/life_hud_changed(list/keys)
	if(QDELETED(src) || !life_hud_wanted())
		return
	life_hud_pass()

/// One reactive HUD pass: draw it, then arm its rewake (darksight, fading overlays) or, while it
/// still has work (life_hud_idle() FALSE), run again a Life cycle later.
/mob/living/proc/life_hud_pass()
	if(!life_placed())
		return
	life_hud()
	var/delay = life_hud_idle() ? life_hud_rewake_delay() : LIFE_CYCLE
	if(delay > 0 && client)
		after(src, delay, PROC_REF(life_hud_rewake), key = LIFE_HUD_REWAKE, clock = CLOCK_WORLD)

/mob/living/proc/life_hud_rewake()
	if(QDELETED(src) || !life_hud_wanted())
		return
	life_hud_pass()

/mob/living/proc/life_vision_changed(list/keys)
	if(QDELETED(src) || !life_vision_wanted())
		return
	life_vision_pass()

/// One reactive sight pass, then its rewake (a player's view) or, while a listener (remote view)
/// wants the signal, again a Life cycle later.
/mob/living/proc/life_vision_pass()
	life_vision()
	var/delay = life_vision_idle() ? life_vision_rewake_delay() : LIFE_CYCLE
	if(delay > 0)
		after(src, delay, PROC_REF(life_vision_rewake), key = LIFE_VISION_REWAKE, clock = CLOCK_WORLD)

/mob/living/proc/life_vision_rewake()
	if(QDELETED(src) || !life_vision_wanted())
		return
	life_vision_pass()

/// The player HUD. Returns FALSE when there is no HUD to update. Only the HUD reaction runs it (life_hud_pass()).
/mob/living/proc/life_hud()
	SHOULD_CALL_PARENT(TRUE)
	if(!hud_available())
		return FALSE
	life_hud_darksight()
	life_hud_health_icons()
	return TRUE

/// A14: full-screen global HUD overlays are owned by their providers (glasses, NIF
/// vision, welder masks, NIF install static). A provider claims its overlay each
/// time it runs; the HUD stage reconciles the claims into client.screen, adding what
/// is newly claimed and removing what nobody claimed, instead of stripping and
/// re-adding every overlay every tick. Claims are an assoc set, so it stays bounded
/// while the HUD stage sleeps.
/mob
	var/tmp/list/global_hud_claims

/mob/proc/claim_global_hud(overlay)
	if(!overlay)
		return
	LAZYINITLIST(global_hud_claims)
	global_hud_claims[overlay] = TRUE

/mob/proc/reconcile_global_huds()
	var/list/claims = global_hud_claims
	global_hud_claims = null
	if(!client)
		return
	var/static/list/owned
	if(!owned)
		owned = list(GLOB.global_hud.blurry, GLOB.global_hud.druggy, GLOB.global_hud.vimpaired, GLOB.global_hud.darkMask, GLOB.global_hud.nvg, GLOB.global_hud.thermal, GLOB.global_hud.meson, GLOB.global_hud.science, GLOB.global_hud.material, GLOB.global_hud.whitense, GLOB.global_hud.heavy_whitense)
	for(var/overlay in owned)
		var/shown = islist(overlay) ? (overlay[1] in client.screen) : (overlay in client.screen)
		if(claims?[overlay])
			if(!shown)
				client.screen |= overlay
		else if(shown)
			client.screen -= overlay
	for(var/overlay in claims)
		if(!(overlay in owned))
			client.screen |= overlay

/// The root's health icon is event-driven; darksight re-adapts on a timer for players.
/// Mob types with their own HUD (life_hud() overrides) keep it awake unless they say otherwise.
/mob/living/proc/life_hud_idle()
	return !act_wanted(src, /datum/act/draw_hud)

/mob/living/proc/life_hud_rewake_delay()
	return src.client ? 5 SECONDS : 0

/// Health doll / health icon. Returns FALSE when a component draws it instead.
/mob/living/proc/life_hud_health_icons()
	SHOULD_CALL_PARENT(TRUE)
	var/datum/act/draw_health_icon/draw = ACT_TRY(src, draw_health_icon)
	if(!draw)
		return FALSE
	act_cancel(draw)
	return TRUE

/// Adapts the darkness overlay to the light level and the mob's darksight.
/mob/living/proc/life_hud_darksight()
	PUBLISH(src, mob_handle_hud_darksight)
	if(!src.seedarkness) //Cheap 'always darksight' var
		src.dsoverlay.alpha = 255
		return

	var/darksightedness = min(src.see_in_dark/world.view,1.0)	//A ratio of how good your darksight is, from 'nada' to 'really darn good'
	var/current = src.dsoverlay.alpha/255						//Our current adjustedness

	var/brightness = 0.0 //We'll assume it's superdark if we can't find something else.

	if(isturf(src.loc))
		var/turf/T = src.loc //Will be true 99% of the time, thus avoiding the whole elif chain
		brightness = T.get_lumcount()

	//Snowflake treatment of potential locations
	else if(istype(src.loc,/obj/mecha)) //I imagine there's like displays and junk in there. Use the lights!
		brightness = 1
	else if(istype(src.loc,/obj/item/holder)) //Poor carried teshari and whatnot should adjust appropriately
		var/turf/T = get_turf(src)
		brightness = T.get_lumcount()

	var/darkness = 1-brightness					//Silly, I know, but 'alpha' and 'darkness' go the same direction on a number line
	var/adjust_to = min(darkness,darksightedness)//Capped by how darksighted they are
	var/distance = abs(current-adjust_to)		//Used for how long to animate for
	if(distance < 0.01) return					//We're already all set

	animate(src.dsoverlay, alpha = (adjust_to*255), time = (distance*10 SECONDS))

/// Sight flags: SEE_TURFS, see_in_dark, see_invisible, vision planes. Only the sight reaction runs it (life_vision_pass()).

/// Variants set their sight, then call ..() last to send the vision signal.
/mob/living/proc/life_vision()
	SHOULD_CALL_PARENT(TRUE)
	PUBLISH(src, mob_handle_vision)

/// The root only notifies listeners (remote view); sight inputs wake it.
/// Every override's inputs are channel-reported (LIFE_VISION_CHANNELS), so all of them idle once they have
/// run, unless a listener (remote view) wants the signal every cycle.
/mob/living/proc/life_vision_idle()
	return !notice_wanted(src, /datum/notice/mob_handle_vision)

/mob/living/proc/life_vision_rewake_delay()
	return src.client ? 5 SECONDS : 0

// ---------------------------------------------------------------- declared fields (code/datums/om/fields.dm)
// What Life stages read to decide there is work, and the channel each raises. Written only through
// the generated set_<name>() setters; stages that read them wake on them.

/// Technomancer instability.
/mob/living/var/instability = 0 // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, instability, CHANGE_MOB_CONDITIONS)
/// Gross boolean for keeping VR mobs in VR.
/mob/living/var/virtual_reality_mob = FALSE // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, virtual_reality_mob, CHANGE_MOB_CONDITIONS)
/// If they're glowing!
/mob/living/var/glow_toggle = FALSE // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, glow_toggle, CHANGE_MOB_CONDITIONS)
/// Ignore the manual toggle.
/mob/living/var/glow_override = FALSE // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, glow_override, CHANGE_MOB_CONDITIONS)
/mob/living/var/glow_range = 2 // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, glow_range, CHANGE_MOB_CONDITIONS)
/mob/living/var/glow_intensity = null // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, glow_intensity, CHANGE_MOB_CONDITIONS)
/// The color they're glowing!
/mob/living/var/glow_color = "#FFFFFF" // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, glow_color, CHANGE_MOB_CONDITIONS)
/// The mob this one was transformed from (vore/mob_tf.dm).
/mob/living/var/mob/living/tf_mob_holder = null // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob/living, tf_mob_holder, CHANGE_MOB_CONDITIONS)
/// sdisabilities and ear_damage are /mob vars (every mob type writes them); Life reads them.
/mob/var/sdisabilities = 0 // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob, sdisabilities, CHANGE_MOB_STATUS)
/mob/var/ear_damage = 0 // ALLOW(base_vars): was an OM_FIELD on this type; moved, not added
TRACKED_BRIDGED(/mob, ear_damage, CHANGE_MOB_STATUS)
/// Cult stuff.
/mob/living/simple_mob/var/purge = 0
TRACKED_BRIDGED(/mob/living/simple_mob, purge, CHANGE_MOB_STATUS)

