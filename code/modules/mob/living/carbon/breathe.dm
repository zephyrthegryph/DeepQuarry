//Common breathing procs

/// Life cycles since this mob's last scheduled breath. Breathing runs on the
/// mob's own cadence, independent of how often the atmos subsystem fires.
/mob/living/carbon/var/breath_cycle = 0

/// A scheduled breath is taken every this many Life cycles.
#define BREATH_CYCLE_PERIOD 4

/datum/om/stage/life/breathing/carbon
	of = /mob/living/carbon

//Start of a breath chain, calls breathe()
/datum/om/stage/life/breathing/carbon/perform(mob/living/carbon/self, datum/om/frame/life/ctx)
	self.breath_cycle = (self.breath_cycle + 1) % BREATH_CYCLE_PERIOD
	if(!self.breath_cycle || self.failed_last_breath || self.is_critical()) // First, resolve location and get a breath
		breathe(self)

#undef BREATH_CYCLE_PERIOD

/// One breath: pick the breath source, exchange gas, exhale.
/datum/om/stage/life/breathing/carbon/proc/breathe(mob/living/carbon/self)
	//if(istype(loc, /obj/machinery/atmospherics/unary/cryo_cell)) return
	if(!self.should_have_organ(O_LUNGS)) return

	var/datum/gas_mixture/breath = null

	//First, check if we can breathe at all
	if(self.is_critical() && !self.factor(BF_STABILIZATION)) //crit aka circulatory shock
		self.AdjustLosebreath(1)

	if(self.losebreath>0) //Suffocating so do not take a breath
		self.AdjustLosebreath(-1)
		if (prob(10) && !isbelly(self.loc)) //Gasp per 10 ticks? Sounds about right.
			spawn self.emote("gasp")
	else if(self.breath_blocked()) //No ventilation (closed airway, apnea): no gas exchange at all.
		if(prob(10) && !isbelly(self.loc))
			INVOKE_ASYNC(self, TYPE_PROC_REF(/mob, emote), "gasp")
	else
		//Okay, we can breathe, now check if we can get air
		breath = self.get_breath_from_internal() //First, check for air from internals
		if(!breath && ishuman(self))
			var/mob/living/carbon/human/H = self
			if(H.nif && H.nif.flag_check(NIF_H_SPAREBREATH,NIF_FLAGS_HEALTH))
				var/datum/nifsoft/spare_breath/SB = H.nif.imp_check(NIF_SPAREBREATH)
				breath = SB.resp_breath()
		if(!breath)
			breath = breath_from_environment(self) //No breath from internals so let's try to get air from our location
		if(!breath)
			var/static/datum/gas_mixture/vacuum //avoid having to create a new gas mixture for each breath in space
			if(!vacuum) vacuum = new

			breath = vacuum //still nothing? must be vacuum

	exchange(self, breath)
	exhale(self, breath)

/mob/living/carbon/proc/get_breath_from_internal(volume_needed=BREATH_VOLUME) //hopefully this will allow overrides to specify a different default volume without breaking any cases where volume is passed in.
	if(internal)
		if (!contents.Find(internal))
			internal = null
		if (!(get_equipped_item(SLOT_ID_MASK) && (get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT)))
			internal = null
		if(internal)
			if (internals)
				internals.icon_state = "internal1"
			return internal.remove_air_volume(volume_needed)
		else
			if (internals)
				internals.icon_state = "internal0"
	return null

/datum/om/stage/life/breathing/carbon/proc/breath_from_environment(mob/living/carbon/self, volume_needed=BREATH_VOLUME)
	var/datum/gas_mixture/breath = null

	var/datum/gas_mixture/environment
	if(self.loc)
		environment = self.loc.return_air_for_internal_lifeform(self)

	if(environment)
		breath = environment.remove_volume(volume_needed)
		inhale_smoke(self, environment) //handle chemical smoke while we're at it

	if(breath)
		//handle mask filtering
		if(istype(self.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask) && breath)
			var/obj/item/clothing/mask/M = self.get_equipped_item(SLOT_ID_MASK)
			var/datum/gas_mixture/gas_filtered = M.filter_air(breath)
			self.loc.assume_air(gas_filtered)
		return breath
	return null

//Handle possble chem smoke effect
/datum/om/stage/life/breathing/carbon/proc/inhale_smoke(mob/living/carbon/self, datum/gas_mixture/environment)
	if(self.get_equipped_item(SLOT_ID_MASK) && (self.get_equipped_item(SLOT_ID_MASK).item_flags & BLOCK_GAS_SMOKE_EFFECT))
		return

	for(var/obj/effect/effect/smoke/chem/smoke in view(1, self))
		if(smoke.reagents.total_volume)
			smoke.reagents.trans_to_mob(self, 10, CHEM_INGEST, copy = 1)
			//maybe check air pressure here or something to see if breathing in smoke is even possible.
			// I dunno, maybe the reagents enter the blood stream through the lungs?
			break // If they breathe in the nasty stuff once, no need to continue checking

/// Gas exchange for one breath (species breath and poison gases, oxygenation).
/datum/om/stage/life/breathing/carbon/proc/exchange(mob/living/carbon/self, datum/gas_mixture/breath)
	return

/datum/om/stage/life/breathing/carbon/proc/exhale(mob/living/carbon/self, datum/gas_mixture/breath)
	if(breath)
		self.loc.assume_air(breath) //by default, exhale
