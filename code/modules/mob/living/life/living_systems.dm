// Living core stages: the old /mob/living/Life() sequence, one stage per step. Orders and run_if
// facts reproduce the old control flow (doc/rewrite/life_on_om.md §4):
//
//	type_pre variants          (subtype code that ran before ..(); may ctx.abort())
//	trait stages               (the old COMSIG_LIVING_LIFE listeners)
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

/// Category for component-provided stages (the old COMSIG_LIVING_LIFE listeners). A component
/// adds its stage with om_stage_add() when it attaches and removes it when it detaches.
/datum/om/stage/life/trait
	order = LIFE_PHASE_INPUT + 10
	category = /datum/om/stage/life/trait
	extra = TRUE
	wake_on = 0
	/// The component type this system ticks.
	var/component_type

/datum/om/stage/life/trait/perform(mob/living/self, datum/om/frame/life/ctx)
	for(var/datum/component/C as anything in self.GetComponents(component_type))
		tick_component(self, C)

/// Tick one instance of the component.
/datum/om/stage/life/trait/proc/tick_component(mob/living/self, datum/component/C)
	return

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
	return !length(self.following_mobs) && !LAZYLEN(self.spell_masters)

// --- Light --------------------------------------------------------------------------------------

/// Mob glow (glow_toggle, technomancer instability). Also run on demand by refresh_glow().
/datum/om/stage/life/light
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
	if(SEND_SIGNAL(self, COMSIG_HANDLE_MUTATIONS) & COMPONENT_BLOCK_LIVING_MUTATIONS)
		return COMPONENT_BLOCK_LIVING_MUTATIONS

/// The root only feeds its signal's listeners.
/datum/om/stage/life/mutations/idle(mob/living/self)
	return type == /datum/om/stage/life/mutations && !self._listen_lookup?[COMSIG_HANDLE_MUTATIONS]

/// Radiation dose decay and effects.
/datum/om/stage/life/radiation
	order = LIFE_PHASE_INPUT + 110
	name = "radiation"
	wake_on = 0
	run_if = LIFE_RUN_IF_PLACED_ALIVE

/datum/om/stage/life/radiation/perform(mob/living/self, datum/om/frame/life/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(SEND_SIGNAL(self, COMSIG_HANDLE_RADIATION) & COMPONENT_BLOCK_LIVING_RADIATION)
		return COMPONENT_BLOCK_LIVING_RADIATION

/// The root only feeds its signal's listeners (the radiation effects component).
/datum/om/stage/life/radiation/idle(mob/living/self)
	return type == /datum/om/stage/life/radiation && !self._listen_lookup?[COMSIG_HANDLE_RADIATION]

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
/mob/living/proc/process_chemicals()
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
		G.process()

/// Busy while pulling or grabbing. Gravity is re-read on Moved, and on a timer for players.
/datum/om/stage/life/movement/idle(mob/living/self)
	return !self.pulling && !(locate(/obj/item/grab) in self)

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
	return !always_evaluate && !LAZYLEN(afflictions) && !factors && !(dirty & (BODY_DIRTY_VITALS | BODY_DIRTY_FACTORS))

/// The simple plan's life_tick() ignores factors: it works only on afflictions and vitals.
/datum/body/simple/life_settled()
	return !LAZYLEN(afflictions) && !(dirty & BODY_DIRTY_VITALS)

// --- Status block -----------------------------------------------------------------------------

/// Eye and ear damage recovery.
/datum/om/stage/life/disabilities
	order = LIFE_PHASE_MIND + 10
	name = "disabilities"
	wake_on = CHANGE_MOB_STATUS
	run_if = LIFE_RUN_IF_STATUS_OK
	woken_by = "status changes (blindness starting or ending); set_stat; body invalidate"

/// Temporary blindness, blur and deafness end on their own (timed statuses); this keeps the
/// ones that don't (a disability, unconsciousness) topped up and heals ear damage.
/datum/om/stage/life/disabilities/perform(mob/living/self, datum/om/frame/life/ctx)
	SEND_SIGNAL(self, COMSIG_HANDLE_DISABILITIES)
	//Eyes: blindness from disability or unconsciousness doesn't get better on its own
	if(self.sdisabilities & BLIND || self.stat)
		self.status_at_least(EFFECT_BLINDED, 1)
	if(self.has_status(EFFECT_BLINDED))
		self.throw_alert("blind", /atom/movable/screen/alert/blind)
	else
		self.clear_alert("blind")

	//Ears
	if(self.sdisabilities & DEAF)		//disabled-deaf, doesn't get better on its own
		self.status_at_least(EFFECT_DEAFENED, 1)
	else if(self.ear_damage < 100)
		// ear damage heals slowly over time, unless it is over 100
		self.adjustEarDamage(-0.05, 0)

/// Busy while a disability or unconsciousness keeps blindness or deafness up, ears are healing,
/// a disability component listens, or the blind alert doesn't match the status yet.
/datum/om/stage/life/disabilities/idle(mob/living/self)
	if(type != /datum/om/stage/life/disabilities)
		return FALSE
	if(self._listen_lookup?[COMSIG_HANDLE_DISABILITIES])
		return FALSE
	if(self.stat || (self.sdisabilities & (BLIND | DEAF)))
		return FALSE
	if(self.ear_damage > 0 && self.ear_damage < 100)
		return FALSE
	return !!self.alerts?["blind"] == self.has_status(EFFECT_BLINDED)

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

/// The root's health icon is event-driven; darksight re-adapts on a timer for players.
/datum/om/stage/life/hud/idle(mob/living/self)
	return type == /datum/om/stage/life/hud && !self._listen_lookup?[COMSIG_MOB_HANDLE_HUD]

/datum/om/stage/life/hud/rewake_delay(mob/living/self)
	return self.client ? 5 SECONDS : 0

/// Health doll / health icon. Returns FALSE when a component draws it instead.
/datum/om/stage/life/hud/proc/health_icons(mob/living/self)
	SHOULD_CALL_PARENT(TRUE)
	if(SEND_SIGNAL(self,COMSIG_MOB_HANDLE_HUD_HEALTH_ICON) & COMSIG_COMPONENT_HANDLED_HEALTH_ICON)
		return FALSE
	return TRUE

/// Adapts the darkness overlay to the light level and the mob's darksight.
/datum/om/stage/life/hud/proc/darksight(mob/living/self)
	SEND_SIGNAL(self,COMSIG_MOB_HANDLE_HUD_DARKSIGHT)
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
	SEND_SIGNAL(self,COMSIG_MOB_HANDLE_VISION)

/// The root only notifies listeners (remote view); sight inputs wake it.
/// Every variant's inputs are channel-reported (see wake_on), so all of them idle once they have
/// run, unless a listener (remote view) wants the signal every cycle.
/datum/om/stage/life/vision/idle(mob/living/self)
	return !self._listen_lookup?[COMSIG_MOB_HANDLE_VISION]

/datum/om/stage/life/vision/rewake_delay(mob/living/self)
	return self.client ? 5 SECONDS : 0
