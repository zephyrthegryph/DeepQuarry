///The schizophrenia / 'episodic hallucinations' trait, as a trait state.
///There is a lot of math that I don't even want to try to fathom in this.
///There was also almost 0 commentation.
/datum/trait_state/schizophrenia
	///The maximum amount of hallucinations we can have.
	var/hallucination_max = 60
	///The amount of hallucinations to increase by each tick during an episode.
	var/hallucination_increase = 3

	var/episode_length_nomeds_avg = 4000
	var/episode_length_nomeds_dev = 100

	var/episode_length_meds_avg = 2000
	var/episode_length_meds_dev = 500

	var/break_length_nomeds_avg = 3000
	var/break_length_nomeds_dev = 600

	var/break_length_meds_avg = 30000
	var/break_length_meds_dev = 7000

	///When the next episode begins and when it ends.
	EXPIRY_DECLARE(next_episode_begin)
	EXPIRY_DECLARE(next_episode_end)
	//Holds the info if we're in an episode and the medication around it.
	var/list/episode = list("in_episode" = FALSE) // ALLOW(instance_list): d: edited in place per instance (21 writers)

/datum/trait_state/schizophrenia/setup()
	if(!ishuman(owner))
		return FALSE
	EXPIRY_SET(src, next_episode_begin, 10 MINUTES, CLOCK_WORLD)
	EXPIRY_SET(src, next_episode_end, 15 MINUTES, CLOCK_WORLD)
	return TRUE

/datum/trait_state/schizophrenia/life_tick()
	var/mob/living/carbon/human/human_guy = owner
	if(QDELETED(human_guy))
		return
	///How much medication we currently have in our system.
	var/med_vol = get_med_volume(human_guy)

	if(!episode["in_episode"])
		if(ELAPSED(src, next_episode_begin, CLOCK_WORLD) > 0)
			episode["meds_at_beginning"] = med_vol
			episode["in_episode"] = TRUE

		else if(episode["meds_at_end"] && !med_vol)	//Meds ran out
			var/episode_span = next_episode_end - next_episode_begin
			EXPIRY_SET(src, next_episode_begin, EXPIRY_LEFT(src, next_episode_begin, CLOCK_WORLD)/10, CLOCK_WORLD)
			next_episode_end = next_episode_begin + episode_span
			episode["meds_at_end"] = FALSE

		else if(!episode["meds_at_end"] && med_vol) //Meds were taken between episodes
			var/episode_span = next_episode_end - next_episode_begin
			EXPIRY_SET(src, next_episode_begin, EXPIRY_LEFT(src, next_episode_begin, CLOCK_WORLD)*10, CLOCK_WORLD)
			next_episode_end = next_episode_begin + episode_span
			episode["meds_at_end"] = TRUE

	else
		if(ELAPSED(src, next_episode_end, CLOCK_WORLD) > 0)
			episode["meds_at_end"] = med_vol
			episode["in_episode"] = FALSE
			var/break_length_dev = med_vol ? break_length_meds_dev : break_length_nomeds_dev
			var/break_length_avg = med_vol ? break_length_meds_avg : break_length_nomeds_avg
			var/episode_length_dev = med_vol ? episode_length_meds_dev : episode_length_nomeds_dev
			var/episode_length_avg = med_vol ? episode_length_meds_avg : episode_length_nomeds_avg
			EXPIRY_SET(src, next_episode_begin, max(120,GAUSSIAN_RANDOM() * break_length_dev + break_length_avg), CLOCK_WORLD)
			next_episode_end = next_episode_begin + max(120,GAUSSIAN_RANDOM() * episode_length_dev + episode_length_avg)
		else
			if(!episode["meds_at_beginning"] && med_vol)
				EXPIRY_SET(src, next_episode_end, EXPIRY_LEFT(src, next_episode_end, CLOCK_WORLD)/8, CLOCK_WORLD)
			human_guy.status_set(STAT_HALLUCINATING, min(hallucination_max,human_guy.status_units(STAT_HALLUCINATING) + hallucination_increase))

///Checks to see if we have tercozolam in our systeem and returns how much if so.
/datum/trait_state/schizophrenia/proc/get_med_volume(mob/living/carbon/human/human_guy)
	var/total_vol = 0
	for(var/datum/reagent/reagent in human_guy.bloodstr.reagent_list)
		if(istype(reagent,/datum/reagent/tercozolam))
			total_vol += reagent.volume
	for(var/datum/reagent/reagent in human_guy.ingested.reagent_list)
		if(istype(reagent,/datum/reagent/tercozolam))
			total_vol += reagent.volume
	return total_vol

/// Trait system: hallucination episodes.
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/schizophrenia/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_schizophrenia"))
