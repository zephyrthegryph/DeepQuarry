//Common breathing procs

/// Life cycles since this mob's last scheduled breath. Breathing runs on the
/// mob's own cadence, independent of how often the atmos subsystem fires.
/mob/living/carbon/var/breath_cycle = 0

/// The last breath carried a gas that acts on every breath (a poison, N2O, methane, the exhaled gas building up): breathing
/// stays awake and keeps breathing on its cadence while it does. Set by the breath exchange.
/mob/living/carbon/var/tmp/breath_hazard = FALSE

/// A scheduled breath is taken every this many Life cycles.
#define BREATH_CYCLE_PERIOD 4

//Start of a breath chain, calls breathe()
// The cadence is time, not runs of this step: the step sleeps in steady air and a wake (its
// rewake, the air changing, moving) must take a breath when one is due. Counting runs made a
// sleeping breather take one breath per BREATH_CYCLE_PERIOD wakes (every two minutes), so a room
// filling with phoron, N2O or CO2 went unnoticed.
/mob/living/carbon/life_breathing(datum/seq_frame/life/F)
	src.breath_cycle = (src.breath_cycle + 1) % BREATH_CYCLE_PERIOD
	var/datum/physiology/P = src.body?.physiology
	var/breath_due = !src.breath_cycle || (P && ELAPSED_SINCE(src, P.last_breath_at, CLOCK_OWN) >= (BREATH_CYCLE_PERIOD - 0.5) * LIFE_CYCLE)
	if(breath_due || P?.air_stale || src.failed_last_breath || src.is_critical()) // First, resolve location and get a breath
		if(P)
			P.last_breath_at = EXPIRY_NOW(src, CLOCK_OWN)
			P.air_stale = FALSE
		life_breathing_breathe()
	src.air_watch_arm()

#undef BREATH_CYCLE_PERIOD

/// Breathing can't stop, but in steady air a breath changes nothing: the physiology holds the
/// last breath quality between breaths. Idle while the last breath was full quality from the
/// turf's air (no internals, no losebreath, not critical, no breath alerts, no gas in it that acts
/// on every breath). Moving and equipment (masks, internals) wake it (MOB_KEY_LOC, MOB_KEY_EQUIPMENT);
/// its air watch wakes it the moment the turf's air crosses a level the breath acts on (MOB_KEY_AIR,
/// physiology air_stale: oxygen, CO2, phoron, N2O, methane, temperature, pressure). The rewake is a fallback.
/mob/living/carbon/life_breathing_due()
	if(!src.breathes())
		return FALSE
	if(src.body?.physiology?.air_stale || src.breath_hazard || src.losebreath || src.failed_last_breath || src.internal || !isturf(src.loc))
		return TRUE
	if(src.alerts?["oxy"] || src.alerts?["tox_in_air"] || src.alerts?["methane_in_air"])
		return TRUE
	var/datum/physiology/P = src.body?.physiology
	if(P && P.breath_quality < 1)
		return TRUE
	return src.is_critical()

/mob/living/carbon/life_breathing_rewake()
	return src.breathes() ? BREATH_STEADY_RESAMPLE : 0

/// One breath, taken the way the body breathes (P2-S7: its breath profile; none, no breath).
/mob/living/carbon/proc/life_breathing_breathe()
	var/datum/breath_profile/profile = src.breath_profile()
	profile?.take_breath(src)

/// A breath through the lungs: pick the breath source, exchange gas, exhale.
/mob/living/carbon/proc/life_breathing_lung_breath()

	var/datum/gas_mixture/breath = null

	//First, check if we can breathe at all
	if(src.is_critical() && !src.factor(BF_STABILIZATION)) //crit aka circulatory shock
		src.AdjustLosebreath(1)

	if(src.losebreath>0) //Suffocating so do not take a breath
		src.AdjustLosebreath(-1)
		if (prob(10) && !isbelly(src.loc)) //Gasp per 10 ticks? Sounds about right.
			src.emote("gasp")
	else if(src.breath_blocked()) //No ventilation (closed airway, apnea): no gas exchange at all.
		if(prob(10) && !isbelly(src.loc))
			src.emote("gasp")
	else
		//Okay, we can breathe, now check if we can get air
		breath = src.get_breath_from_internal() //First, check for air from internals
		if(!breath && ishuman(src))
			var/mob/living/carbon/human/H = src
			if(H.nif && H.nif.flag_check(NIF_H_SPAREBREATH,NIF_FLAGS_HEALTH))
				var/datum/nifsoft/spare_breath/SB = H.nif.imp_check(NIF_SPAREBREATH)
				breath = SB.resp_breath()
		if(!breath)
			breath = life_breathing_breath_from_environment() //No breath from internals so let's try to get air from our location
		if(!breath)
			var/static/datum/gas_mixture/vacuum //avoid having to create a new gas mixture for each breath in space
			if(!vacuum) vacuum = new

			breath = vacuum //still nothing? must be vacuum

	life_breathing_exchange(breath)
	life_breathing_exhale(breath)

/mob/living/carbon/proc/get_breath_from_internal(volume_needed=BREATH_VOLUME) //hopefully this will allow overrides to specify a different default volume without breaking any cases where volume is passed in.
	if(internal)
		if (!contents.Find(internal))
			rel_clear(src, nameof(internal))
		if (!(get_equipped_item(SLOT_ID_MASK) && (worn_of(get_equipped_item(SLOT_ID_MASK)).flags & AIRTIGHT)))
			rel_clear(src, nameof(internal))
		if(internal)
			if (hud_used?.internals)
				hud_used?.internals?.icon_state = "internal1"
			return internal.remove_air_volume(volume_needed)
		else
			if (hud_used?.internals)
				hud_used?.internals?.icon_state = "internal0"
	return null

/mob/living/carbon/proc/life_breathing_breath_from_environment(volume_needed=BREATH_VOLUME)
	var/datum/gas_mixture/breath = null

	var/datum/gas_mixture/environment
	if(src.loc)
		environment = src.loc.return_air_for_internal_lifeform(src)

	if(environment)
		breath = environment.remove_volume(volume_needed)
		life_breathing_inhale_smoke(environment) //handle chemical smoke while we're at it

	if(breath)
		//handle mask filtering
		if(istype(src.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask) && breath)
			var/obj/item/clothing/mask/M = src.get_equipped_item(SLOT_ID_MASK)
			var/datum/gas_mixture/gas_filtered = M.filter_air(breath)
			src.loc.assume_air(gas_filtered)
		return breath
	return null

//Handle possble chem smoke effect
/mob/living/carbon/proc/life_breathing_inhale_smoke(datum/gas_mixture/environment)
	if(src.get_equipped_item(SLOT_ID_MASK) && (worn_of(src.get_equipped_item(SLOT_ID_MASK)).flags & BLOCK_GAS_SMOKE_EFFECT))
		return

	for(var/obj/effect/effect/smoke/chem/smoke in view(1, src))
		if(smoke.reagents.total_volume)
			smoke.reagents.trans_to_mob(src, 10, CHEM_INGEST, copy = 1)
			//maybe check air pressure here or something to see if breathing in smoke is even possible.
			// I dunno, maybe the reagents enter the blood stream through the lungs?
			break // If they breathe in the nasty stuff once, no need to continue checking

/// Gas exchange for one breath (species breath and poison gases, oxygenation).
/mob/living/carbon/proc/life_breathing_exchange(datum/gas_mixture/breath)
	return

/mob/living/carbon/proc/life_breathing_exhale(datum/gas_mixture/breath)
	if(breath)
		src.loc.assume_air(breath) //by default, exhale
