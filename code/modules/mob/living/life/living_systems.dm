// Living core systems: the old /mob/living/Life() sequence, one system per step
// (doc/mob_life_architecture.md §4.5). Orders and segments reproduce the old control flow:
//
//	type_pre variants          (subtype code that ran before ..())
//	trait systems              (the old COMSIG_LIVING_LIFE listeners)
//	upkeep, instability
//	gate: transforming         -> LIFE_SEG_LIVING
//	modifiers
//	gate: placed (!loc)        -> LIFE_SEG_LIVING, captures the environment
//	light
//	gate: alive                -> LIFE_SEG_LIVING_ALIVE
//	breathing, mutations, radiation, blood, random events, AFK      (alive only)
//	chemicals, diseases, environment, ambience, movement
//	status (regular status updates) -> LIFE_SEG_LIVING_STATUS
//	disabilities, addictions, statuses                             (status only)
//	canmove, HUD, vision, TF holder, VR derez
//	subtype tails (carbon germs, human, alien, simple mob, bot), then type_post variants
//
// Sleep rules (doc/rewrite/life_on_om.md §5): each system's idle() says when it has
// nothing to do, and `woken_by` names the producers that raise the channels in its `wake_on`. A
// family root's rule covers only the root: a variant with its own tick code keeps its
// mob awake until it declares a rule of its own.

// --- Per-type pre and post chains ---------------------------------------------------------------

/// Code a mob subtype ran before calling ..() in its old Life() override. A variant runs its own
/// code, then `return ..()`. Returning LIFE_HALT without calling ..() ends the cycle, as the old
/// early `return` before ..() did.
/datum/life_system/type_pre
	name = "type pre"
	wake_on = LIFE_WAKE_ON_BEHAVIOUR
	phase = LIFE_PHASE_INPUT
	order = 0

/datum/life_system/type_pre/tick(mob/living/self, datum/life_context/ctx)
	return

/// The root is a no-op; a variant's pre code runs every cycle.
/datum/life_system/type_pre/idle(mob/living/self)
	return type == /datum/life_system/type_pre

/// Code a mob subtype ran after ..() in its old Life() override. A variant starts with
/// `. = ..()`, which runs its parent's post code and yields what the parent's old Life()
/// returned, then runs its own code. The roots yield the core's legacy return value.
/datum/life_system/type_post
	name = "type post"
	wake_on = LIFE_WAKE_ON_BEHAVIOUR
	phase = LIFE_PHASE_TAIL
	order = 1000

/datum/life_system/type_post/tick(mob/living/self, datum/life_context/ctx)
	return ctx?.living_result

/// The root and the carbon and simple mob variants only yield a return value.
/datum/life_system/type_post/idle(mob/living/self)
	var/static/list/value_only = list(
		/datum/life_system/type_post,
		/datum/life_system/type_post/carbon,
		/datum/life_system/type_post/simple_mob,
	)
	return type in value_only

/// Carbon Life() returned nothing.
/datum/life_system/type_post/carbon
	mob_type = /mob/living/carbon

/datum/life_system/type_post/carbon/tick(mob/living/carbon/self, datum/life_context/ctx)
	return

/// Mobs whose Life() only takes them out of the mob lists (preview dummies, announcers).
/datum/life_system/delist
	name = "delist"
	wake_on = LIFE_WAKE_ON_UPKEEP
	phase = LIFE_PHASE_INPUT
	life_sets = LIFE_SET_DELIST

/datum/life_system/delist/tick(mob/living/self, datum/life_context/ctx)
	return

// --- Trait systems ------------------------------------------------------------------------------

/// Category for component-provided systems (the old COMSIG_LIVING_LIFE listeners). A component
/// adds its system with add_life_system() when it attaches and removes it when it detaches.
/datum/life_system/trait
	category = TRUE
	extra = TRUE
	wake_on = LIFE_WAKE_ON_TRAITS
	phase = LIFE_PHASE_INPUT
	order = 10
	/// The component type this system ticks.
	var/component_type

/datum/life_system/trait/tick(mob/living/self, datum/life_context/ctx)
	for(var/datum/component/C as anything in self.GetComponents(component_type))
		tick_component(self, C)

/// Tick one instance of the component.
/datum/life_system/trait/proc/tick_component(mob/living/self, datum/component/C)
	return

// --- Upkeep ---------------------------------------------------------------------------------------

/// Every mob's base upkeep (the old /mob/Life() chain): followers and spell buttons.
/datum/life_system/upkeep
	name = "upkeep"
	phase = LIFE_PHASE_INPUT
	order = 20
	woken_by = "Moved; ghosts following; spells learned"

/datum/life_system/upkeep/tick(mob/living/self, datum/life_context/ctx)
	// to catch teleports etc which directly set loc
	self.update_following()
	self.update_spell_masters()

/// Followers are dragged along on Moved; spell buttons only matter for casters.
/datum/life_system/upkeep/idle(mob/living/self)
	return !length(self.following_mobs) && !LAZYLEN(self.spell_masters)

// --- Gates ------------------------------------------------------------------------------------------

/// Category for gates. A gate evaluates one old `if(...) return` (or an `if` around a block of
/// hooks) once per cycle and blocks the segment that code guarded.
/datum/life_system/gate
	category = TRUE
	gate = TRUE

/// Gates run whenever the mob runs and never keep it awake on their own.
/datum/life_system/gate/idle(mob/living/self)
	return TRUE

/// `if(transforming) return` in /mob/living/Life().
/datum/life_system/gate/transforming
	name = "gate: transforming"
	phase = LIFE_PHASE_INPUT
	order = 40

/datum/life_system/gate/transforming/tick(mob/living/self, datum/life_context/ctx)
	if(self.transforming)
		ctx.blocked |= LIFE_SEG_LIVING
		ctx.no_sleep = TRUE

/// `if(!loc) return` in /mob/living/Life(); captures the environment for the cycle.
/datum/life_system/gate/placed
	name = "gate: placed"
	phase = LIFE_PHASE_INPUT
	order = 60
	segment = LIFE_SEG_LIVING

/datum/life_system/gate/placed/tick(mob/living/self, datum/life_context/ctx)
	if(!self.loc)
		ctx.blocked |= LIFE_SEG_LIVING
		ctx.no_sleep = TRUE
		return
	if(isbelly(self.loc))
		ctx.environment = self.loc.return_air_for_internal_lifeform(self)
	else
		ctx.environment = self.loc.return_air()

/// `if(stat != DEAD)` around breathing .. AFK in /mob/living/Life().
/datum/life_system/gate/alive
	name = "gate: alive"
	phase = LIFE_PHASE_INPUT
	order = 80
	segment = LIFE_SEG_LIVING

/datum/life_system/gate/alive/tick(mob/living/self, datum/life_context/ctx)
	if(self.stat == DEAD)
		ctx.blocked |= LIFE_SEG_LIVING_ALIVE
	else
		ctx.living_result = 1

// --- Light --------------------------------------------------------------------------------------

/// Mob glow (glow_toggle, technomancer instability). Also run on demand by refresh_glow().
/datum/life_system/light
	name = "light"
	phase = LIFE_PHASE_INPUT
	order = 70
	segment = LIFE_SEG_LIVING
	woken_by = "refresh_glow(); instability"

/datum/life_system/light/tick(mob/living/self, datum/life_context/ctx)
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
	return run_life_system(/datum/life_system/light)

/// Idle once the applied light matches what tick() would ask for.
/datum/life_system/light/idle(mob/living/self)
	if(type != /datum/life_system/light)
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
/datum/life_system/breathing
	name = "breathing"
	wake_on = LIFE_WAKE_ON_BREATHING
	phase = LIFE_PHASE_INPUT
	order = 90
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_ALIVE

/datum/life_system/breathing/tick(mob/living/self, datum/life_context/ctx)
	return

/datum/life_system/breathing/idle(mob/living/self)
	return type == /datum/life_system/breathing

/// Genetic mutation effects.
/datum/life_system/mutations
	name = "mutations"
	wake_on = LIFE_WAKE_ON_GENETICS
	phase = LIFE_PHASE_INPUT
	order = 100
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_ALIVE

/datum/life_system/mutations/tick(mob/living/self, datum/life_context/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(SEND_SIGNAL(self, COMSIG_HANDLE_MUTATIONS) & COMPONENT_BLOCK_LIVING_MUTATIONS)
		return COMPONENT_BLOCK_LIVING_MUTATIONS

/// The root only feeds its signal's listeners.
/datum/life_system/mutations/idle(mob/living/self)
	return type == /datum/life_system/mutations && !self._listen_lookup?[COMSIG_HANDLE_MUTATIONS]

/// Radiation dose decay and effects.
/datum/life_system/radiation
	name = "radiation"
	wake_on = LIFE_WAKE_ON_RADIATION
	phase = LIFE_PHASE_INPUT
	order = 110
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_ALIVE

/datum/life_system/radiation/tick(mob/living/self, datum/life_context/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(SEND_SIGNAL(self, COMSIG_HANDLE_RADIATION) & COMPONENT_BLOCK_LIVING_RADIATION)
		return COMPONENT_BLOCK_LIVING_RADIATION

/// The root only feeds its signal's listeners (the radiation effects component).
/datum/life_system/radiation/idle(mob/living/self)
	return type == /datum/life_system/radiation && !self._listen_lookup?[COMSIG_HANDLE_RADIATION]

/// Blood volume and bleeding.
/datum/life_system/blood
	name = "blood"
	wake_on = LIFE_WAKE_ON_BLOOD
	phase = LIFE_PHASE_BODY
	order = 10
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_ALIVE

/datum/life_system/blood/tick(mob/living/self, datum/life_context/ctx)
	return

/datum/life_system/blood/idle(mob/living/self)
	return type == /datum/life_system/blood

/// Random episodes (vomiting, ...).
/datum/life_system/random_events
	name = "random events"
	wake_on = LIFE_WAKE_ON_GENETICS
	phase = LIFE_PHASE_BODY
	order = 20
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_ALIVE

/datum/life_system/random_events/tick(mob/living/self, datum/life_context/ctx)
	return

/datum/life_system/random_events/idle(mob/living/self)
	return type == /datum/life_system/random_events

/// Automatic AFK marking for idle clients.
/datum/life_system/afk
	name = "afk"
	wake_on = LIFE_WAKE_ON_CLIENT
	phase = LIFE_PHASE_BODY
	order = 30
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_ALIVE
	woken_by = "Login, Logout; its own timer"

/datum/life_system/afk/tick(mob/living/self, datum/life_context/ctx)
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
/datum/life_system/afk/idle(mob/living/self)
	return TRUE

/datum/life_system/afk/rewake_delay(mob/living/self)
	return self.client ? 30 SECONDS : 0

// --- Core -------------------------------------------------------------------------------------

/// Chemicals in the body. Runs dead or alive, so blood can be added after death.
/datum/life_system/chemicals
	name = "chemicals"
	wake_on = LIFE_WAKE_ON_METABOLISM
	phase = LIFE_PHASE_BODY
	order = 40
	segment = LIFE_SEG_LIVING

/datum/life_system/chemicals/tick(mob/living/self, datum/life_context/ctx)
	return

/datum/life_system/chemicals/idle(mob/living/self)
	return type == /datum/life_system/chemicals

/// Runs the chemicals system now (extra circulation from CPR, horror modifiers, ...).
/mob/living/proc/process_chemicals()
	return run_life_system(/datum/life_system/chemicals)

/// Environment: temperature and pressure differences between body and surroundings.
/datum/life_system/environment
	name = "environment"
	wake_on = LIFE_WAKE_ON_THERMAL
	phase = LIFE_PHASE_BODY
	order = 60
	segment = LIFE_SEG_LIVING

/datum/life_system/environment/tick(mob/living/self, datum/life_context/ctx)
	if(ctx?.environment)
		exchange(self, ctx.environment)

/// Handle temperature/pressure differences between body and environment.
/datum/life_system/environment/proc/exchange(mob/living/self, datum/gas_mixture/environment)
	return

/datum/life_system/environment/idle(mob/living/self)
	return type == /datum/life_system/environment

/// Re-plays area ambience to a client that has stayed in one area.
/datum/life_system/ambience
	name = "ambience"
	wake_on = LIFE_WAKE_ON_CLIENT
	phase = LIFE_PHASE_BODY
	order = 70
	segment = LIFE_SEG_LIVING
	woken_by = "Login; its own timer"

/datum/life_system/ambience/tick(mob/living/self, datum/life_context/ctx)
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
/datum/life_system/ambience/idle(mob/living/self)
	return TRUE

/datum/life_system/ambience/rewake_delay(mob/living/self)
	if(!self.client)
		return 0
	var/pref = self.read_preference(/datum/preference/numeric/ambience_freq)
	if(!pref)
		return 0
	return max(1 SECONDS, self.lastareachange + pref MINUTES - world.time)

/// Gravity, pulling and grabs.
/datum/life_system/movement
	name = "movement"
	wake_on = LIFE_WAKE_ON_MOVEMENT
	phase = LIFE_PHASE_BODY
	order = 80
	segment = LIFE_SEG_LIVING
	woken_by = "Moved; start_pulling; equipping a grab; status setters"

/datum/life_system/movement/tick(mob/living/self, datum/life_context/ctx)
	self.update_gravity(self.mob_get_gravity())

	self.update_pulling()

	for(var/obj/item/grab/G in self)
		G.process()

/// Busy while pulling or grabbing. Gravity is re-read on Moved, and on a timer for players.
/datum/life_system/movement/idle(mob/living/self)
	return !self.pulling && !(locate(/obj/item/grab) in self)

/datum/life_system/movement/rewake_delay(mob/living/self)
	return self.client ? 30 SECONDS : 0

/// Status & health update: are we dead or alive, conscious or not. When it returns false the
/// disabilities, addictions and statuses systems skip this cycle.
/datum/life_system/status
	name = "status"
	wake_on = LIFE_WAKE_ON_BODY
	phase = LIFE_PHASE_BODY
	order = 90
	segment = LIFE_SEG_LIVING
	woken_by = "injure, mend, afflictions, factors and reagents (body invalidate); set_stat"

/datum/life_system/status/tick(mob/living/self, datum/life_context/ctx)
	if(!update_status(self))
		ctx?.blocked |= LIFE_SEG_LIVING_STATUS

/// This updates the health and status of the mob (conscious, unconscious, dead).
/datum/life_system/status/proc/update_status(mob/living/self)
	self.body?.life_tick()
	if(self.stat != DEAD)
		self.set_stat(CONSCIOUS)
		return TRUE

/// The root sleeps while the mob is conscious (or dead) and its body has nothing to tick.
/datum/life_system/status/idle(mob/living/self)
	if(type != /datum/life_system/status)
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
/datum/life_system/disabilities
	name = "disabilities"
	wake_on = LIFE_WAKE_ON_GENETICS
	phase = LIFE_PHASE_MIND
	order = 10
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_STATUS
	woken_by = "Blind/SetBlinded/AdjustBlinded; set_stat; body invalidate"

/datum/life_system/disabilities/tick(mob/living/self, datum/life_context/ctx)
	SEND_SIGNAL(self, COMSIG_HANDLE_DISABILITIES)
	//Eyes
	if(self.sdisabilities & BLIND || self.stat)	//blindness from disability or unconsciousness doesn't get better on its own
		self.SetBlinded(1)
		self.throw_alert("blind", /atom/movable/screen/alert/blind)
	else if(self.eye_blind)			//blindness, heals slowly over time
		self.AdjustBlinded(-1)
		self.throw_alert("blind", /atom/movable/screen/alert/blind)
	else
		self.clear_alert("blind")

	if(self.eye_blurry)			//blurry eyes heal slowly
		self.eye_blurry = max(self.eye_blurry-1, 0)

	//Ears
	if(self.sdisabilities & DEAF)		//disabled-deaf, doesn't get better on its own
		self.setEarDamage(-1, max(self.ear_deaf, 1))
	else
		// deafness heals slowly over time, unless ear_damage is over 100
		if(self.ear_damage < 100)
			self.adjustEarDamage(-0.05,-1)

/// Busy while eyes or ears are recovering, a disability component listens, or the blind
/// alert is still up.
/datum/life_system/disabilities/idle(mob/living/self)
	if(type != /datum/life_system/disabilities)
		return FALSE
	if(self._listen_lookup?[COMSIG_HANDLE_DISABILITIES])
		return FALSE
	if(self.stat || (self.sdisabilities & (BLIND | DEAF)))
		return FALSE
	return !self.eye_blind && !self.eye_blurry && !self.ear_deaf && self.ear_damage <= 0 && !self.alerts?["blind"]

/// Stun, weaken, paralysis, confusion and speech impairments wear off. Its helpers are also
/// called on their own by mobs that run only some of them (simple mobs, the AI, pAIs).
/datum/life_system/statuses
	name = "statuses"
	wake_on = LIFE_WAKE_ON_STATUS
	phase = LIFE_PHASE_MIND
	order = 30
	segment = LIFE_SEG_LIVING | LIFE_SEG_LIVING_STATUS
	life_sets = LIFE_SET_LIVING | LIFE_SET_ROBOT | LIFE_SET_AI | LIFE_SET_PAI
	woken_by = "Confuse and the other counter setters (CHANGE_MOB_STATUS)"

/// Counts down the per-frame status counters. Stun, weaken and paralysis are timed
/// contributions and need no ticking (doc/rewrite/life_on_om.md §7).
/datum/life_system/statuses/tick(mob/living/self, datum/life_context/ctx)
	stuttering(self)
	silent(self)
	drugged(self)
	slurring(self)
	confused(self)

/// Continuous while any counter runs or an alert is still up; asleep otherwise.
/datum/life_system/statuses/idle(mob/living/self)
	if(type != /datum/life_system/statuses)
		return FALSE
	if(self.confused || self.stuttering || self.silent || self.druggy || self.slurring)
		return FALSE
	return !self.alert_state_drugged && !self.alert_state_confused

/datum/life_system/statuses/proc/stuttering(mob/living/self)
	if(self.stuttering)
		self.stuttering = max(self.stuttering-1, 0)
	return self.stuttering

/datum/life_system/statuses/proc/silent(mob/living/self)
	if(self.silent)
		self.silent = max(self.silent-1, 0)
	return self.silent

/datum/life_system/statuses/proc/drugged(mob/living/self)
	if(self.druggy)
		self.druggy = max(self.druggy-1, 0)
		if(!self.alert_state_drugged)
			self.alert_state_drugged = TRUE
			self.throw_alert("high", /atom/movable/screen/alert/high)
	else if(self.alert_state_drugged)
		self.alert_state_drugged = FALSE
		self.clear_alert("high")
	return self.druggy

/datum/life_system/statuses/proc/slurring(mob/living/self)
	if(self.slurring)
		self.slurring = max(self.slurring-1, 0)
	return self.slurring

/datum/life_system/statuses/proc/confused(mob/living/self)
	if(self.confused)
		self.AdjustConfused(-1)
		if(!self.alert_state_confused)
			self.alert_state_confused = TRUE
			self.throw_alert("confused", /atom/movable/screen/alert/confused)
	else if(self.alert_state_confused)
		self.alert_state_confused = FALSE
		self.clear_alert("confused")
	return self.confused

/datum/life_system/statuses/proc/sleeping(mob/living/self)
	if(self.stat != DEAD && self.toggled_sleeping)
		self.Sleeping(2)
	if(self.sleeping)
		if(iscarbon(self))
			var/mob/living/carbon/C = self
			self.AdjustSleeping(-1 * C.species.waking_speed)
		else
			self.AdjustSleeping(-1)
		self.throw_alert("asleep", /atom/movable/screen/alert/asleep)
	else
		self.clear_alert("asleep")
	return self.sleeping

/// The shared statuses helpers (stunned(), sleeping(), ...) for code outside the statuses tick.
/proc/life_statuses()
	RETURN_TYPE(/datum/life_system/statuses)
	var/static/datum/life_system/statuses/statuses
	if(!statuses)
		statuses = get_life_system(/datum/life_system/statuses)
	return statuses

// --- Output -----------------------------------------------------------------------------------

/// Whether the mob can move (lying, stunned, buckled, ...).
/datum/life_system/canmove
	name = "canmove"
	wake_only = LIFE_WAKE_ONLY_DERIVE
	wake_on = LIFE_DERIVE_CHANNELS
	phase = LIFE_PHASE_OUTPUT
	order = 10
	segment = LIFE_SEG_LIVING
	life_sets = LIFE_SET_LIVING | LIFE_SET_ROBOT
	woken_by = "status setters (LIFE_WAKE_STATUS); set_stat; Moved"

/datum/life_system/canmove/tick(mob/living/self, datum/life_context/ctx)
	self.update_canmove()

/// Resting and buckling update canmove themselves; the tick only follows the counters.
/datum/life_system/canmove/idle(mob/living/self)
	return type == /datum/life_system/canmove && !self.sleeping

/// The player HUD. Returns FALSE when there is no HUD to update. Also run by refresh_hud().
/datum/life_system/hud
	name = "hud"
	wake_only = LIFE_WAKE_ONLY_PRESENT
	wake_on = LIFE_WAKE_ON_HUD
	phase = LIFE_PHASE_OUTPUT
	order = 20
	segment = LIFE_SEG_LIVING
	life_sets = LIFE_SET_LIVING | LIFE_SET_AI | LIFE_SET_PAI
	woken_by = "Login; body invalidate; equipment; Moved; its own timer (darksight)"

/datum/life_system/hud/tick(mob/living/self, datum/life_context/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	if(!self.hud_available())
		return FALSE
	darksight(self)
	health_icons(self)
	return TRUE

/// The root's health icon is event-driven; darksight re-adapts on a timer for players.
/datum/life_system/hud/idle(mob/living/self)
	return type == /datum/life_system/hud && !self._listen_lookup?[COMSIG_MOB_HANDLE_HUD]

/datum/life_system/hud/rewake_delay(mob/living/self)
	return self.client ? 5 SECONDS : 0

/// Health doll / health icon. Returns FALSE when a component draws it instead.
/datum/life_system/hud/proc/health_icons(mob/living/self)
	SHOULD_CALL_PARENT(TRUE)
	if(SEND_SIGNAL(self,COMSIG_MOB_HANDLE_HUD_HEALTH_ICON) & COMSIG_COMPONENT_HANDLED_HEALTH_ICON)
		return FALSE
	return TRUE

/// Adapts the darkness overlay to the light level and the mob's darksight.
/datum/life_system/hud/proc/darksight(mob/living/self)
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
/datum/life_system/vision
	name = "vision"
	wake_only = LIFE_WAKE_ONLY_PRESENT
	wake_on = LIFE_WAKE_ON_SENSES
	phase = LIFE_PHASE_OUTPUT
	order = 30
	segment = LIFE_SEG_LIVING
	life_sets = LIFE_SET_LIVING | LIFE_SET_AI | LIFE_SET_PAI
	woken_by = "equipment; set_stat; Moved; Login; refresh_vision()"

/// Variants set their sight, then call ..() last to send the vision signal.
/datum/life_system/vision/tick(mob/living/self, datum/life_context/ctx)
	SHOULD_CALL_PARENT(TRUE)
	..()
	SEND_SIGNAL(self,COMSIG_MOB_HANDLE_VISION)

/// The root only notifies listeners (remote view); sight inputs wake it.
/datum/life_system/vision/idle(mob/living/self)
	return type == /datum/life_system/vision && !self._listen_lookup?[COMSIG_MOB_HANDLE_VISION]

/datum/life_system/vision/rewake_delay(mob/living/self)
	return self.client ? 5 SECONDS : 0
