// Living core stages: the old /mob/living/Life() sequence, one stage per step. Orders and run_if
// facts reproduce the old control flow (doc/rewrite/life_on_om.md §4):
//
//	type_pre variants          (subtype code that ran before ..(); may ctx.abort())
//	trait stages               (per-trait Life work)
//	upkeep, instability, modifiers
//	[placed]                   light
//	[placed, alive]            breathing, mutations, radiation, blood, random events, AFK
//	[placed]                   chemicals, diseases, environment, ambience, movement,
//	                           status (the body tick; it re-reads "alive" afterwards)
//	[placed, alive]            disabilities, addictions
//	[placed]                   TF holder, VR derez
//	subtype tails (carbon germs, human, alien, simple mob, bot), then type_post variants
//
// canmove runs in the life_derive pipeline and HUD and vision in life_present (life_om.dm).
//
// Idle rules: each stage's idle() says when it has nothing to do, and `woken_by` names the
// producers that raise the channels in its `wake_on`. A family root's rule covers only the root:
// a variant with its own run() code keeps its mob awake until it declares a rule of its own.

// --- Per-type pre and post chains ---------------------------------------------------------------

/// Code a mob subtype ran before calling ..() in its old Life() override. A variant runs its own
/// code, then `return ..()`. `return ctx.abort()` without calling ..() ends the frame, as the
/// old early `return` before ..() did.
/datum/om/stage/life/type_pre
	order = LIFE_PHASE_INPUT + 0
	name = "type pre"
	wake_on = 0

/datum/om/stage/life/type_pre/perform(mob/living/self, datum/om/frame/life/ctx)
	return

/// The root is a no-op; a variant's pre code runs every cycle.
/datum/om/stage/life/type_pre/idle(mob/living/self)
	return type == /datum/om/stage/life/type_pre

/// Code a mob subtype ran after ..() in its old Life() override. A variant starts with `..()`,
/// which runs its parent's post code, then runs its own; code that only runs for a living mob
/// checks `ctx.fact("alive")`.
/datum/om/stage/life/type_post
	order = LIFE_PHASE_TAIL + 1000
	name = "type post"
	wake_on = 0

/datum/om/stage/life/type_post/perform(mob/living/self, datum/om/frame/life/ctx)
	return

/// The root and the carbon and simple mob variants do nothing.
/datum/om/stage/life/type_post/idle(mob/living/self)
	var/static/list/value_only = list(
		/datum/om/stage/life/type_post,
		/datum/om/stage/life/type_post/carbon,
		/datum/om/stage/life/type_post/simple_mob,
	)
	return type in value_only

/datum/om/stage/life/type_post/carbon
	of = /mob/living/carbon

/// Mobs whose Life() only takes them out of the mob lists (preview dummies, announcers).
/datum/om/stage/life/delist
	order = LIFE_PHASE_INPUT + 0
	name = "delist"
	wake_on = CHANGE_MOB_LOC | CHANGE_MOB_CONDITIONS
	life_sets = LIFE_SET_DELIST

/datum/om/stage/life/delist/perform(mob/living/self, datum/om/frame/life/ctx)
	return

// --- Trait systems ------------------------------------------------------------------------------

/// Category for trait stages (per-trait Life work). A trait state
/// (/datum/trait_state, code/datums/entity_state/traits/_trait_state.dm) adds its stage with
/// om_stage_add() when it attaches and removes it when it detaches. A subtype either sets
/// `state_type` (the stage then calls life_tick() on each such state each cycle) or overrides perform().
/datum/om/stage/life/trait
	order = LIFE_PHASE_INPUT + 10
	category = /datum/om/stage/life/trait
	extra = TRUE
	wake_on = 0
	/// The /datum/trait_state type this stage ticks, if any.
	var/state_type

/datum/om/stage/life/trait/perform(mob/living/self, datum/om/frame/life/ctx)
	if(!state_type)
		return
	for(var/datum/trait_state/S as anything in self.trait_states)
		if(istype(S, state_type))
			S.life_tick()

// --- Upkeep ---------------------------------------------------------------------------------------

/// Every mob's base upkeep (the old /mob/Life() chain): followers and spell buttons.
/datum/om/stage/life/upkeep
	order = LIFE_PHASE_INPUT + 20
	name = "upkeep"
	woken_by = "Moved; ghosts following; spells learned"

/datum/om/stage/life/upkeep/perform(mob/living/self, datum/om/frame/life/ctx)
	// to catch teleports etc which directly set loc
	self.update_following()
	self.update_spell_masters()

/// Followers are dragged along on Moved; spell buttons only matter for casters.
/datum/om/stage/life/upkeep/idle(mob/living/self)
	return !LAZYLEN(self?.follower_list()) && !LAZYLEN(self.spell_masters)

// --- Light --------------------------------------------------------------------------------------

/// Mob glow (glow_toggle, technomancer instability). Also run on demand by refresh_glow().
/datum/om/stage/life/light
	reads = list("glow_override", "glow_toggle", "glow_range", "glow_intensity", "glow_color", "instability")
	order = LIFE_PHASE_INPUT + 70
	name = "light"
	run_if = LIFE_RUN_IF_PLACED
	woken_by = "refresh_glow(); instability"

/datum/om/stage/life/light/perform(mob/living/self, datum/om/frame/life/ctx)
	if(self.glow_override)
		return FALSE

	// Determine the desired light params, then only call set_light() if they changed
	// since last tick (this runs every Life() tick for every glowing mob).
	var/want_range
	var/want_intensity
	var/want_color
	. = FALSE

	if(self.instability >= TECHNOMANCER_INSTABILITY_MIN_GLOW)
		var/distance = round(sqrt(self.instability / 2))
		if(distance)
			want_range = distance
			want_intensity = distance * 4
			want_color = "#660066"
			. = TRUE
		else
			return FALSE // Preserve old behavior: distance 0 leaves the existing light untouched.

	else if(self.glow_toggle && !self.is_ventcrawling) // Hide the light in vents
		want_range = self.glow_range
		want_intensity = self.glow_intensity
		want_color = self.glow_color

	else
		want_range = 0

	if(want_range != self.last_glow_range || want_intensity != self.last_glow_intensity || want_color != self.last_glow_color)
		if(want_range)
			self.set_light(want_range, want_intensity, want_color)
		else
			self.set_light(0)
		self.last_glow_range = want_range
		self.last_glow_intensity = want_intensity
		self.last_glow_color = want_color

/// Re-evaluates this mob's glow now (light system).
/mob/living/proc/refresh_glow()
	return om_stage_run_now(src, /datum/om/stage/life/light)

/// Idle once the applied light matches what tick() would ask for.
/datum/om/stage/life/light/idle(mob/living/self)
	if(type != /datum/om/stage/life/light)
		return FALSE
	if(self.glow_override)
		return TRUE
	if(self.instability >= TECHNOMANCER_INSTABILITY_MIN_GLOW)
		return FALSE
	if(self.glow_toggle && !self.is_ventcrawling)
		return self.last_glow_range == self.glow_range && self.last_glow_intensity == self.glow_intensity && self.last_glow_color == self.glow_color
	return !self.last_glow_range

// --- Alive block -----------------------------------------------------------------------------------

/// Breathing. The carbon variant takes a breath on its own cadence (breathe()).
/datum/om/stage/life/breathing
	order = LIFE_PHASE_INPUT + 90
	name = "breathing"
	wake_on = CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/datum/om/stage/life/breathing/perform(mob/living/self, datum/om/frame/life/ctx)
	return

/datum/om/stage/life/breathing/idle(mob/living/self)
	return type == /datum/om/stage/life/breathing

/// Genetic mutation effects.
/datum/om/stage/life/mutations
	order = LIFE_PHASE_INPUT + 100
	name = "mutations"
	wake_on = CHANGE_MOB_STATUS
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/datum/om/stage/life/mutations/perform(mob/living/self, datum/om/frame/life/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(OM_EMIT(self, /datum/om/event/before/handle_mutations) & COMPONENT_BLOCK_LIVING_MUTATIONS)
		return COMPONENT_BLOCK_LIVING_MUTATIONS

/// The root only feeds its signal's listeners.
/datum/om/stage/life/mutations/idle(mob/living/self)
	return type == /datum/om/stage/life/mutations && !om_wants(self, /datum/om/event/before/handle_mutations)

/// Radiation dose decay and effects.
/datum/om/stage/life/radiation
	order = LIFE_PHASE_INPUT + 110
	name = "radiation"
	wake_on = 0
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/datum/om/stage/life/radiation/perform(mob/living/self, datum/om/frame/life/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(OM_EMIT(self, /datum/om/event/before/handle_radiation) & COMPONENT_BLOCK_LIVING_RADIATION)
		return COMPONENT_BLOCK_LIVING_RADIATION

/// The root only feeds its signal's listeners (the radiation effects component).
/datum/om/stage/life/radiation/idle(mob/living/self)
	return type == /datum/om/stage/life/radiation && !om_wants(self, /datum/om/event/before/handle_radiation)

/// Blood volume and bleeding.
/datum/om/stage/life/blood
	order = LIFE_PHASE_BODY + 10
	name = "blood"
	wake_on = 0
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/datum/om/stage/life/blood/perform(mob/living/self, datum/om/frame/life/ctx)
	return

/datum/om/stage/life/blood/idle(mob/living/self)
	return type == /datum/om/stage/life/blood

/// Random episodes (vomiting, ...).
/datum/om/stage/life/random_events
	order = LIFE_PHASE_BODY + 20
	name = "random events"
	wake_on = CHANGE_MOB_STATUS
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/datum/om/stage/life/random_events/perform(mob/living/self, datum/om/frame/life/ctx)
	return

/datum/om/stage/life/random_events/idle(mob/living/self)
	return type == /datum/om/stage/life/random_events

/// Automatic AFK marking for idle clients.
/datum/om/stage/life/afk
	order = LIFE_PHASE_BODY + 30
	name = "afk"
	wake_on = 0
	run_if = LIFE_RUN_IF_PLACED_ALIVE
	woken_by = "Login, Logout; its own timer"

/datum/om/stage/life/afk/perform(mob/living/self, datum/om/frame/life/ctx)
	var/client/C = self.client
	if(!C)
		return
	var/idle_limit = 10 MINUTES
	if(C.inactivity >= idle_limit && !self.away_from_keyboard && C.prefs?.read_preference(/datum/preference/toggle/auto_afk))	//if we're not already afk and we've been idle too long, and we have automarking enabled... then automark it
		self.add_status_indicator("afk")
		to_chat(self, span_notice("You have been idle for too long, and automatically marked as AFK."))
		self.away_from_keyboard = TRUE
	else if(self.away_from_keyboard && C.inactivity < idle_limit && !self.manual_afk) //if we're afk but we do something AND we weren't manually flagged as afk, unmark it
		self.remove_status_indicator("afk")
		to_chat(self, span_notice("You have been automatically un-marked as AFK."))
		self.away_from_keyboard = FALSE

/// Lazy: a client's idle time is checked on a timer, not every cycle.
/datum/om/stage/life/afk/idle(mob/living/self)
	return TRUE

/datum/om/stage/life/afk/rewake_delay(mob/living/self)
	return self.client ? 30 SECONDS : 0

// --- Core -------------------------------------------------------------------------------------

/// Chemicals in the body. Runs dead or alive, so blood can be added after death.
/datum/om/stage/life/chemicals
	order = LIFE_PHASE_BODY + 40
	name = "chemicals"
	wake_on = CHANGE_MOB_HEALTH
	run_if = LIFE_RUN_IF_PLACED

/datum/om/stage/life/chemicals/perform(mob/living/self, datum/om/frame/life/ctx)
	return

/datum/om/stage/life/chemicals/idle(mob/living/self)
	return type == /datum/om/stage/life/chemicals

/// Runs the chemicals system now (extra circulation from CPR, horror modifiers, ...).
/// A run-now frame has no stasis fact of its own, so the paused biology clock is honoured here:
/// extra circulation can't metabolise faster than stasis allows (P2-S6).
/mob/living/proc/process_chemicals()
	if(body?.stasis_paused)
		return null
	return om_stage_run_now(src, /datum/om/stage/life/chemicals)

/// Environment: temperature and pressure differences between body and surroundings.
/datum/om/stage/life/environment
	order = LIFE_PHASE_BODY + 60
	name = "environment"
	wake_on = CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT
	run_if = LIFE_RUN_IF_PLACED

/datum/om/stage/life/environment/perform(mob/living/self, datum/om/frame/life/ctx)
	if(ctx.fact("environment"))
		exchange(self, ctx.fact("environment"))

/// Handle temperature/pressure differences between body and environment.
/datum/om/stage/life/environment/proc/exchange(mob/living/self, datum/gas_mixture/environment)
	return

/datum/om/stage/life/environment/idle(mob/living/self)
	return type == /datum/om/stage/life/environment

/// Re-plays area ambience to a client that has stayed in one area.
/datum/om/stage/life/ambience
	order = LIFE_PHASE_BODY + 70
	name = "ambience"
	wake_on = 0
	run_if = LIFE_RUN_IF_PLACED
	woken_by = "Login; its own timer"

/datum/om/stage/life/ambience/perform(mob/living/self, datum/om/frame/life/ctx)
	if(!self.client)
		return
	// If you're in an ambient area and have not moved out of it for x time as configured per-client, and do not have it disabled, we're going to play ambience again to you, to help break up the silence.
	var/pref = self.read_preference(/datum/preference/numeric/ambience_freq)
	if(!pref)
		return

	// ALLOW(cooldown): elapsed since the last area change against a per-client preference interval
	if(world.time >= (self.lastareachange + pref MINUTES)) // Every 5 minutes (by default, set per-client), we're going to run a 35% chance (by default, also set per-client) to play ambience.
		var/area/A = get_area(self)
		if(A)
			self.lastareachange = world.time // This will refresh the last area change to prevent this call happening LITERALLY every life tick.
			A.play_ambience(self, initial = FALSE)

/// Lazy: sleeps until the next replay is due.
/datum/om/stage/life/ambience/idle(mob/living/self)
	return TRUE

/datum/om/stage/life/ambience/rewake_delay(mob/living/self)
	if(!self.client)
		return 0
	var/pref = self.read_preference(/datum/preference/numeric/ambience_freq)
	if(!pref)
		return 0
	return max(1 SECONDS, self.lastareachange + pref MINUTES - world.time)

/// Gravity, pulling and grabs.
/datum/om/stage/life/movement
	order = LIFE_PHASE_BODY + 80
	name = "movement"
	wake_on = CHANGE_MOB_STATUS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT
	run_if = LIFE_RUN_IF_PLACED
	woken_by = "Moved; start_pulling; equipping a grab; status setters"

/datum/om/stage/life/movement/perform(mob/living/self, datum/om/frame/life/ctx)
	self.update_gravity(self.mob_get_gravity())

	self.update_pulling()

	for(var/obj/item/grab/G in self)
		G.periodic_step()

/// Busy while pulling or grabbing. Gravity is re-read on Moved, and on a timer for players.
/datum/om/stage/life/movement/idle(mob/living/self)
	return !self?.pulling_target() && !(locate_in_list(self, /obj/item/grab))

/datum/om/stage/life/movement/rewake_delay(mob/living/self)
	return self.client ? 30 SECONDS : 0

/// Status & health update: are we dead or alive, conscious or not. When it returns false the
/// disabilities and addictions systems skip this cycle.
/datum/om/stage/life/status
	order = LIFE_PHASE_BODY + 90
	name = "status"
	wake_on = CHANGE_MOB_HEALTH
	run_if = LIFE_RUN_IF_PLACED
	woken_by = "injure, mend, afflictions, factors and reagents (body invalidate); set_stat"

/// The body tick decides death: "alive" is read again for the stages after this one, and
/// "status_ok" (what update_status() returned) gates disabilities and addictions.
/datum/om/stage/life/status/perform(mob/living/self, datum/om/frame/life/ctx)
	ctx.set_fact("status_ok", !!update_status(self))
	ctx.forget("alive")

/// This updates the health and status of the mob (conscious, unconscious, dead).
/datum/om/stage/life/status/proc/update_status(mob/living/self)
	self.body?.life_tick()
	if(self.stat != DEAD)
		self.set_stat(CONSCIOUS)
		return TRUE

/// The root sleeps while the mob is conscious (or dead) and its body has nothing to tick.
/datum/om/stage/life/status/idle(mob/living/self)
	if(type != /datum/om/stage/life/status)
		return FALSE
	if(self.stat == UNCONSCIOUS)
		return FALSE
	return !self.body || self.body.life_settled()

/// TRUE when life_tick() has nothing to do: no afflictions, no factor effects, nothing
/// stale. Plans that evaluate every tick (humanoids) never settle.
/datum/body/proc/life_settled()
	return !always_evaluate && !LAZYLEN(afflictions) && !factors && !(dirty & BODY_DIRTY_VITALS) && !factors_stale()

/// The simple plan's life_tick() ignores factors: it works only on afflictions and vitals.
/datum/body/simple/life_settled()
	return !LAZYLEN(afflictions) && !(dirty & BODY_DIRTY_VITALS)

// --- Status block -----------------------------------------------------------------------------

/// Eye and ear damage recovery.
/datum/om/stage/life/disabilities
	reads = list("sdisabilities", "ear_damage")
	order = LIFE_PHASE_MIND + 10
	name = "disabilities"
	wake_on = 0 // only its reads' channels (CHANGE_MOB_STATUS)
	run_if = LIFE_RUN_IF_STATUS_OK
	woken_by = "status changes (blindness starting or ending); set_stat; body invalidate"

/// Temporary blindness, blur and deafness end on their own (timed statuses); this keeps the
/// ones that don't (a disability, unconsciousness) topped up and heals ear damage.
/datum/om/stage/life/disabilities/perform(mob/living/self, datum/om/frame/life/ctx)
	OM_EMIT(self, /datum/om/event/handle_disabilities)
	//Eyes: blindness from disability or unconsciousness doesn't get better on its own. It is an
	// untimed hold while the cause lasts, not a one-cycle top-up: re-topping a timed status every
	// frame raised a status change on the mob's own frame and kept it from ever parking.
	life_disability_hold(self, EFFECT_BLINDED, "disability_blind", (self.sdisabilities & BLIND) || self.stat)
	if(self.has_status(EFFECT_BLINDED))
		self.throw_alert("blind", /atom/movable/screen/alert/blind)
	else
		self.clear_alert("blind")

	//Ears
	life_disability_hold(self, EFFECT_DEAFENED, "disability_deaf", self.sdisabilities & DEAF) //disabled-deaf, doesn't get better on its own
	if(!(self.sdisabilities & DEAF) && self.ear_damage > 0 && self.ear_damage < 100)
		// ear damage heals slowly over time, unless it is over 100
		self.adjustEarDamage(-0.05, 0)

/// Busy while a disability or unconsciousness keeps blindness or deafness up, ears are healing,
/// a disability component listens, or the blind alert doesn't match the status yet.
/datum/om/stage/life/disabilities/idle(mob/living/self)
	if(type != /datum/om/stage/life/disabilities)
		return FALSE
	if(om_wants(self, /datum/om/event/handle_disabilities))
		return FALSE
	if(!life_disability_hold_matches(self, EFFECT_BLINDED, "disability_blind", (self.sdisabilities & BLIND) || self.stat))
		return FALSE
	if(!life_disability_hold_matches(self, EFFECT_DEAFENED, "disability_deaf", self.sdisabilities & DEAF))
		return FALSE
	if(self.ear_damage > 0 && self.ear_damage < 100)
		return FALSE
	return !!self.alerts?["blind"] == self.has_status(EFFECT_BLINDED)

/// Holds `effect_id` on `self` (keyed `key`, self-sourced) while `wanted`, releases it otherwise.
/// Holding what is already held and releasing what isn't are no-ops, so no change is raised.
/proc/life_disability_hold(mob/living/self, effect_id, key, wanted)
	if(life_disability_hold_matches(self, effect_id, key, wanted))
		return
	if(wanted)
		om_hold(self, effect_id, self, TRUE, key)
	else
		om_release(self, effect_id, self, key)

/proc/life_disability_hold_matches(mob/living/self, effect_id, key, wanted)
	var/datum/om/rec/rec = self.om_rec
	var/held = FALSE
	if(rec)
		var/datum/om/effect/eff = om_registry().effect(effect_id)
		held = !isnull(om_contrib_value(rec, eff.idx, self, key))
	return held == !!wanted

// --- Output -----------------------------------------------------------------------------------

/// Whether the mob can move (lying, stunned, buckled, ...).
/datum/om/stage/life/canmove
	order = LIFE_PHASE_OUTPUT + 10
	name = "canmove"
	pipeline = /datum/om/pipeline/life_derive
	wake_on = CHANGE_MOB_STATUS
	run_if = LIFE_RUN_IF_PLACED
	life_sets = LIFE_SET_LIVING | LIFE_SET_ROBOT
	woken_by = "status setters; set_stat; Moved"

/datum/om/stage/life/canmove/perform(mob/living/self, datum/om/frame/life/ctx)
	self.update_canmove()

/// Resting and buckling update canmove themselves, and the statuses when they start or end.
/datum/om/stage/life/canmove/idle(mob/living/self)
	return type == /datum/om/stage/life/canmove

/// The player HUD. Returns FALSE when there is no HUD to update. Also run by refresh_hud().
/datum/om/stage/life/hud
	order = LIFE_PHASE_OUTPUT + 20
	name = "hud"
	pipeline = /datum/om/pipeline/life_present
	wake_on = CHANGE_MOB_HEALTH | CHANGE_MOB_STATUS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT
	run_if = LIFE_RUN_IF_PLACED
	life_sets = LIFE_SET_LIVING | LIFE_SET_AI | LIFE_SET_PAI
	woken_by = "Login; body invalidate; equipment; Moved; its own timer (darksight)"

/datum/om/stage/life/hud/perform(mob/living/self, datum/om/frame/life/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(!self.hud_available())
		return FALSE
	darksight(self)
	health_icons(self)
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
/datum/om/stage/life/hud/idle(mob/living/self)
	return type == /datum/om/stage/life/hud && !om_wants(self, /datum/om/event/before/mob_handle_hud)

/datum/om/stage/life/hud/rewake_delay(mob/living/self)
	return self.client ? 5 SECONDS : 0

/// Health doll / health icon. Returns FALSE when a component draws it instead.
/datum/om/stage/life/hud/proc/health_icons(mob/living/self)
	SHOULD_CALL_PARENT(TRUE)
	if(OM_EMIT(self, /datum/om/event/before/mob_handle_hud_health_icon) & HEALTH_ICON_EVENT_HANDLED)
		return FALSE
	return TRUE

/// Adapts the darkness overlay to the light level and the mob's darksight.
/datum/om/stage/life/hud/proc/darksight(mob/living/self)
	OM_EMIT(self, /datum/om/event/mob_handle_hud_darksight)
	if(!self.seedarkness) //Cheap 'always darksight' var
		self.dsoverlay.alpha = 255
		return

	var/darksightedness = min(self.see_in_dark/world.view,1.0)	//A ratio of how good your darksight is, from 'nada' to 'really darn good'
	var/current = self.dsoverlay.alpha/255						//Our current adjustedness

	var/brightness = 0.0 //We'll assume it's superdark if we can't find something else.

	if(isturf(self.loc))
		var/turf/T = self.loc //Will be true 99% of the time, thus avoiding the whole elif chain
		brightness = T.get_lumcount()

	//Snowflake treatment of potential locations
	else if(istype(self.loc,/obj/mecha)) //I imagine there's like displays and junk in there. Use the lights!
		brightness = 1
	else if(istype(self.loc,/obj/item/holder)) //Poor carried teshari and whatnot should adjust appropriately
		var/turf/T = get_turf(self)
		brightness = T.get_lumcount()

	var/darkness = 1-brightness					//Silly, I know, but 'alpha' and 'darkness' go the same direction on a number line
	var/adjust_to = min(darkness,darksightedness)//Capped by how darksighted they are
	var/distance = abs(current-adjust_to)		//Used for how long to animate for
	if(distance < 0.01) return					//We're already all set

	animate(self.dsoverlay, alpha = (adjust_to*255), time = (distance*10 SECONDS))

/// Sight flags: SEE_TURFS, see_in_dark, see_invisible, vision planes. Also run by refresh_vision().
/datum/om/stage/life/vision
	order = LIFE_PHASE_OUTPUT + 30
	name = "vision"
	pipeline = /datum/om/pipeline/life_vision
	wake_on = CHANGE_MOB_STATUS | CHANGE_MOB_EQUIPMENT | CHANGE_MOB_CONDITIONS | CHANGE_MOB_HEALTH
	life_sets = LIFE_SET_LIVING | LIFE_SET_AI | LIFE_SET_PAI
	woken_by = "blindness and drugs (statuses); equipment (glasses, helmets); mutations, species, modifiers (conditions); set_stat; Login; refresh_vision()"

/// Variants set their sight, then call ..() last to send the vision signal.
/datum/om/stage/life/vision/perform(mob/living/self, datum/om/frame/life/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	OM_EMIT(self, /datum/om/event/mob_handle_vision)

/// The root only notifies listeners (remote view); sight inputs wake it.
/// Every variant's inputs are channel-reported (see wake_on), so all of them idle once they have
/// run, unless a listener (remote view) wants the signal every cycle.
/datum/om/stage/life/vision/idle(mob/living/self)
	return !om_wants(self, /datum/om/event/mob_handle_vision)

/datum/om/stage/life/vision/rewake_delay(mob/living/self)
	return self.client ? 5 SECONDS : 0

// ---------------------------------------------------------------- declared fields (code/datums/om/fields.dm)
// What Life stages read to decide there is work, and the channel each raises. Written only through
// the generated set_<name>() setters (or om_set()); stages that read them wake on them.

/// Technomancer instability.
OM_FIELD(/mob/living, instability, 0, CHANGE_MOB_CONDITIONS)
/// Gross boolean for keeping VR mobs in VR.
OM_FIELD(/mob/living, virtual_reality_mob, FALSE, CHANGE_MOB_CONDITIONS)
/// If they're glowing!
OM_FIELD(/mob/living, glow_toggle, FALSE, CHANGE_MOB_CONDITIONS)
/// Ignore the manual toggle.
OM_FIELD(/mob/living, glow_override, FALSE, CHANGE_MOB_CONDITIONS)
OM_FIELD(/mob/living, glow_range, 2, CHANGE_MOB_CONDITIONS)
OM_FIELD(/mob/living, glow_intensity, null, CHANGE_MOB_CONDITIONS)
/// The color they're glowing!
OM_FIELD(/mob/living, glow_color, "#FFFFFF", CHANGE_MOB_CONDITIONS)
/// The mob this one was transformed from (vore/mob_tf.dm).
OM_FIELD_TYPED(/mob/living, mob/living, tf_mob_holder, null, CHANGE_MOB_CONDITIONS)
/// sdisabilities and ear_damage are /mob vars (every mob type writes them); Life reads them.
OM_FIELD(/mob, sdisabilities, 0, CHANGE_MOB_STATUS)
OM_FIELD(/mob, ear_damage, 0, CHANGE_MOB_STATUS)
/// Cult stuff.
OM_FIELD(/mob/living/simple_mob, purge, 0, CHANGE_MOB_STATUS)

