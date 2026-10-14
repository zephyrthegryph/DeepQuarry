/datum/reagents/metabolism
	var/metabolism_class //CHEM_TOUCH, CHEM_INGEST, or CHEM_BLOOD
	var/metabolism_speed = 1	// Multiplicative, 1 is full speed, 0.5 is half, etc.
	var/mob/living/carbon/parent
	/// This cycle's uptake, while metabolize() runs: reagent -> its offset in `cycle_out` (Rust's flat answer, CHEM_CYCLE_OUT per reagent).
	var/tmp/list/cycle_at
	var/tmp/list/cycle_out
	/// This cycle's absorbed share of each reagent (ingest), in `cycle_at` order.
	var/tmp/list/cycle_absorbed


/datum/reagents/metabolism/New(max = 100, mob/living/carbon/parent_mob, met_class = null)
	..(max, parent_mob)

	if(met_class)
		metabolism_class = met_class
	if(istype(parent_mob))
		rel_set(src, nameof(parent), parent_mob)

/// One Life cycle: every reagent's uptake is worked out first, all at once (the rates here, then the dose and overdose maths in one Rust
/// call, vg_chem::metabolism::cycle), then each reagent's on_mob_life() applies its own (doc/rewrite/reagents.md §4).
/datum/reagents/metabolism/proc/metabolize()

	var/metabolism_type = 0 //non-human mobs
	if(ishuman(parent))
		var/mob/living/carbon/human/H = parent
		metabolism_type = H.species.reagent_tag

	begin_batch()
	plan_cycle(reagent_list)
	for(var/datum/reagent/current in reagent_list)
		current.on_mob_life(parent, metabolism_type, src)
	cycle_at = null
	cycle_out = null
	cycle_absorbed = null
	update_total()
	end_batch()

/// Works out this cycle's uptake of each of `reagents` that acts on the parent (cycle_taken() reads it).
/datum/reagents/metabolism/proc/plan_cycle(list/reagents)
	cycle_at = list()
	cycle_absorbed = list()
	if(!istype(parent))
		return
	var/list/body = cycle_body()
	var/list/args_flat = list()
	var/od_threshold = parent.species?.chemOD_threshold
	var/od_species_mod = 1
	if(ishuman(parent))
		var/mob/living/carbon/human/H = parent
		od_species_mod = H.species.chemOD_mod
	for(var/datum/reagent/R as anything in reagents)
		if(!R.metabolizes_in(parent))
			continue
		var/list/rate = R.cycle_rate(parent, src, body)
		cycle_at[R] = length(cycle_absorbed) * CHEM_CYCLE_OUT
		cycle_absorbed += rate[2]
		var/od_allowed = R.overdose && (metabolism_class != CHEM_TOUCH || R.can_overdose_touch)
		args_flat += R.volume
		args_flat += rate[1]
		args_flat += R.dose
		args_flat += R.max_dose
		args_flat += od_allowed ? R.overdose * od_threshold : 0
		args_flat += R.overdose
		args_flat += R.overdose_mod * od_species_mod
	cycle_out = length(args_flat) ? vg_chem_metabolism_cycle(args_flat) : list()

/// This cycle's uptake of `R`: list(removed, dose, max_dose, overdosing, overdose injury, absorbed share), CHEM_TAKEN_*. A reagent the
/// cycle did not plan (added during it, or an on_mob_life() called outside one) is worked out on its own.
/datum/reagents/metabolism/proc/cycle_taken(datum/reagent/R)
	var/at = cycle_at?[R]
	if(isnull(at))
		var/list/kept = list(cycle_at, cycle_out, cycle_absorbed)
		plan_cycle(list(R))
		var/list/taken = cycle_at[R] == 0 ? cycle_taken(R) : list(0, R.dose, R.max_dose, FALSE, 0, 1)
		cycle_at = kept[1]
		cycle_out = kept[2]
		cycle_absorbed = kept[3]
		return taken
	var/list/taken = cycle_out.Copy(at + 1, at + 1 + CHEM_CYCLE_OUT)
	taken += cycle_absorbed[at / CHEM_CYCLE_OUT + 1]
	return taken

/// The body's share of this cycle's uptake rates, the same for every reagent, indexed by CHEM_BODY_*: the factors applied in order to a
/// reagent's own metabolism (REMOVED), the stomach's rate (INGEST_REMOVED) and the share absorbed (INGEST_ABSORBED). Species, traits,
/// modifiers and afflictions (BF_METABOLISM), this holder's speed, the heart's pulse, the stomach and intestine, or a machine's pump and cycler.
/datum/reagents/metabolism/proc/cycle_body()
	var/mob/living/carbon/M = parent
	var/list/removed = list()
	var/ingest_rem_mult = 1
	var/ingest_abs_mult = 1
	var/metabolism = M.factor(BF_METABOLISM)
	removed += metabolism
	ingest_rem_mult *= metabolism
	removed += metabolism_speed
	ingest_rem_mult *= metabolism_speed
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!HAS_SYNTHETIC_BIOLOGY(H))
			if(H.species.has_organ[O_HEART] && (metabolism_class == CHEM_BLOOD))
				var/obj/item/organ/internal/heart/Pump = H.organ_in(O_HEART)
				if(!Pump)
					removed += 0.1
				else if(Pump.standard_pulse_level == PULSE_NONE)	// No pulse normally means chemicals process a little bit slower than normal.
					removed += 0.8
				else	// Otherwise, chemicals process as per percentage of your current pulse, or, if you have no pulse but are alive, by a miniscule amount.
					removed += max(0.1, H.pulse / Pump.standard_pulse_level)

			if(H.species.has_organ[O_STOMACH] && (metabolism_class == CHEM_INGEST))
				var/obj/item/organ/internal/stomach/Chamber = H.organ_in(O_STOMACH)
				if(Chamber)
					ingest_rem_mult *= max(0.1, 1 - (Chamber.damage / Chamber.max_damage))
				else
					ingest_rem_mult = 0.1

			if(H.species.has_organ[O_INTESTINE] && (metabolism_class == CHEM_INGEST))
				var/obj/item/organ/internal/intestine/Tube = H.organ_in(O_INTESTINE)
				if(Tube)
					ingest_abs_mult *= max(0.1, 1 - (Tube.damage / Tube.max_damage))
				else
					ingest_abs_mult = 0.1

		else
			var/obj/item/organ/internal/heart/machine/Pump = H.organ_in(O_PUMP)
			var/obj/item/organ/internal/stomach/machine/Cycler = H.organ_in(O_CYCLER)
			var/obj/item/organ/internal/nano/refactory/Refactory = H.organ_in(O_FACT) // Proteans

			if(metabolism_class == CHEM_BLOOD)
				if(Pump)
					removed += 1.1 - Pump.damage / Pump.max_damage
				else if(Refactory)
					removed += 1.1 - Refactory.damage / Refactory.max_damage
				else
					removed += 0.1

			else if(metabolism_class == CHEM_INGEST)	// If the pump is damaged, we waste chems from the tank.
				if(Pump)
					ingest_abs_mult *= max(0.25, 1 - Pump.damage / Pump.max_damage)
				else if(Refactory)
					ingest_abs_mult *= max(0.25, 1 - Refactory.damage / Refactory.max_damage)
				else
					ingest_abs_mult *= 0.2

				if(Cycler)	// If we're damaged, we empty our tank slower.
					ingest_rem_mult = max(0.1, 1 - (Cycler.damage / Cycler.max_damage))
				else if(Refactory)
					ingest_rem_mult = max(0.1, 1 - (Refactory.damage / Refactory.max_damage))
				else
					ingest_rem_mult = 0.1

			else if(metabolism_class == CHEM_TOUCH)	// Machines don't exactly absorb chemicals.
				removed += 0.5
	return list(removed, ingest_rem_mult, ingest_abs_mult)

// "Specialized" metabolism datums
/datum/reagents/metabolism/bloodstream
	metabolism_class = CHEM_BLOOD

/datum/reagents/metabolism/ingested
	metabolism_class = CHEM_INGEST
	metabolism_speed = 0.5

/datum/reagents/metabolism/touch
	metabolism_class = CHEM_TOUCH

// parent is a back reference to the carbon holding this metabolism.
