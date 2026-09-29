// Small creatures that will embed themselves in unsuspecting victim's bodies, drink their blood, and/or eat their organs. Steals some things from borers.

/// A leech doses its host once a demand is at least this urgent (_dq_band_rank).
#define LEECH_TREAT_URGENCY 2

/datum/category_item/catalogue/fauna/iceleech
	name = "Sivian Fauna - River Leech"
	desc = "Classification: S Hirudinea phorus \
	<br><br>\
	An incredibly dangerous species of worm phorogenically mutated from a Sivian river leech, \
	believed to have resulted from corporate mining in the Ullran Expanse; these accusations are \
	unfounded, however speculation remains.\
	<br>\
	The creatures' heads hold four long prehensile tendrils surrounding a central beak, which are \
	used as locomotive and grappling appendages. Each is capped in a hollow tooth, capable of pumping \
	chemicals into an unsuspecting host. \
	<br>\
	The rear half of the creature is entirely musculature, capped with a sharp, arrowhead-shaped fin."
	value = CATALOGUER_REWARD_MEDIUM

/mob/living/simple_mob/animal/sif/leech
	name = "river leech"
	desc = "What appears to be an oversized leech."
	tt_desc = "S Hirudinea phorus"
	catalogue_data = list(/datum/category_item/catalogue/fauna/iceleech)

	faction = FACTION_LEECH

	icon_state = "leech"
	item_state = "brainslug"
	icon_living = "leech"
	icon_dead = "leech_dead"
	icon = 'icons/mob/animal.dmi'

	density = FALSE	// Non-dense, so things can pass over them.

	status_flags = CANPUSH
	pass_flags = PASSTABLE
	minbodytemp = 175
	endurance = 100

	universal_understand = 1

	special_attack_min_range = 0
	special_attack_max_range = 1

	var/obj/item/organ/external/host_bodypart	// Where in the body we are infesting.
	var/docile = FALSE
	var/chemicals = 0
	var/max_chemicals = 400
	var/static/list/bodypart_targets = list(BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_TORSO,BP_GROIN,BP_HEAD)
	var/infest_target = BP_TORSO	// The currently chosen bodypart to infest.
	var/mob/living/carbon/host		// Our humble host.
	var/static/list/produceable_chemicals = list(REAGENT_ID_INAPROVALINE,REAGENT_ID_ANTITOXIN,REAGENT_ID_ALKYSINE,REAGENT_ID_BICARIDINE,REAGENT_ID_TRAMADOL,REAGENT_ID_KELOTANE,REAGENT_ID_LEPORAZINE,REAGENT_ID_IRON,REAGENT_ID_PHORON,REAGENT_ID_CONDENSEDCAPSAICINV,REAGENT_ID_FROSTOIL)
	var/randomized_reagent = REAGENT_ID_IRON	// The reagent chosen at random to be produced, if there's no one piloting the worm.
	var/passive_reagent = REAGENT_ID_PARACETAMOL	// Reagent passively produced by the leech. Should usually be a painkiller.

	var/feeding_delay = 30 SECONDS	// How long do we have to wait to bite our host's organs?
	COOLDOWN_DECLARE(feeding_cooldown)


	holder_type = /obj/item/holder/leech

	movement_cooldown = -2
	aquatic_movement = -2

	melee_damage_lower = 1
	melee_damage_upper = 5
	attack_armor_pen = 15
	attack_injury_kind = INJURY_PIERCE
	attacktext = list("nipped", "bit", "pinched")

	organ_names = /datum/decl/mob_organ_names/leech

	armor_spec = "melee=10;bullet=15;laser=-10;bomb=10;bio=100;rad=100"

	say_list_type = /datum/say_list/leech

/mob/living/simple_mob/animal/sif/leech/IIsAlly(mob/living/L)
	. = ..()

	var/mob/living/carbon/human/H = L
	if(!istype(H))
		return .

	if(istype(L?.buckled_to(), /obj/vehicle) || dq_get_hovering(L) || L.flying) // Ignore people dq_get_hovering(src) or on boats.
		return TRUE

	if(!.)
		var/has_organ = FALSE
		var/obj/item/organ/internal/O = H.get_active_hand()
		if(istype(O) && !O.is_robotic() && !(O.status & ORGAN_DEAD))
			has_organ = TRUE
		return has_organ

/datum/say_list/leech
	speak = list("...", "Sss..", ". . .","Gss..")
	emote_see = list("vibrates","looks around", "stares", "extends a proboscis")
	emote_hear = list("chitters", "clicks", "gurgles")

/mob/living/simple_mob/animal/sif/leech/Initialize(mapload)
	. = ..()

	om_grant(src, GRANT_VERB, /mob/living/proc/ventcrawl, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/hide, src)

	add_trait(src, TRAIT_AMBIENT_PEST_MOB, ROUNDSTART_TRAIT)

/mob/living/simple_mob/animal/sif/leech/get_status_tab_items()
	. = ..()
	. += "Chemicals: [chemicals]"

/mob/living/simple_mob/animal/sif/leech/do_special_attack(atom/A, stance)
	. = TRUE
	if(istype(A, /mob/living/carbon))
		switch(stance)
			if(I_DISARM) // Poison
				ai_busy_begin()
				poison_inject(src, A)
				ai_busy_end()
			if(I_GRAB) // Infesting!
				ai_busy_begin()
				do_infest(src, A)
				ai_busy_end()
/datum/om/stage/life/special/animal/sif/leech
	of = /mob/living/simple_mob/animal/sif/leech

/datum/om/stage/life/special/animal/sif/leech/perform(mob/living/simple_mob/animal/sif/leech/self, datum/om/frame/life/ctx)
	if(prob(5))
		self.randomized_reagent = pick(self.produceable_chemicals)

	var/turf/T = get_turf(self)
	if(istype(T, /turf/simulated/floor/water) && self.loc == T && !self.stat)	// Are we sitting in water, and alive?
		self.alpha = max(5, self.alpha - 10)
		if(self.chemicals + 1 < self.max_chemicals / 3)
			self.chemicals++
	else
		self.alpha = min(255, self.alpha + 20)

	if(!self.client && !self.host)
		self.infest_target = pick(self.bodypart_targets)

	if(self.host && !self.stat && !self.host.stat)
		if(self.ai_brain)
			self.ai_brain.set_hostile(FALSE)
			self.ai_brain.lose_target()
		self.alpha = 5
		if(self.host.reagents.has_reagent(REAGENT_ID_CORDRADAXON) && !self.docile)	// Overwhelms the leech with food.
			var/message = "We feel the rush of cardiac pluripotent cells in your host's blood, lulling us into docility."
			to_chat(self, span_warning(message))
			self.docile = TRUE
			if(self.chemicals + 5 <= self.max_chemicals)
				self.chemicals += 5

		else if(self.docile)
			var/message = "We shake off our lethargy as the pluripotent cell count declines in our host's blood."
			to_chat(self, span_notice(message))
			self.docile = FALSE

		if(!self.host.reagents.has_reagent(self.passive_reagent))
			self.host.reagents.add_reagent(self.passive_reagent, 5)
			self.chemicals -= 3

		if(!self.docile && ishuman(self.host) && self.chemicals < self.max_chemicals)
			var/mob/living/carbon/human/H = self.host
			H.remove_blood(1)
			if(!H.reagents.has_reagent(REAGENT_ID_INAPROVALINE))
				H.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 1)
			self.chemicals += 2

		if(!self.client && !self.docile)	// Automatic 'AI' to manage damage levels.
			// The leech lives in its host: it senses every affliction (no profile).
			var/list/demand = self.host.treatment_demand()
			if(demand_urgency(demand, list(TREAT_TISSUE_REPAIR, TREAT_HEMOSTATIC)) >= LEECH_TREAT_URGENCY && self.chemicals > 50)
				self.host.reagents.add_reagent(REAGENT_ID_BICARIDINE, 5)
				self.chemicals -= 30

			if(demand_urgency(demand, list(TREAT_ANTITOXIN)) >= LEECH_TREAT_URGENCY && self.chemicals > 50)
				var/randomchem = pickweight(list(REAGENT_ID_TRAMADOL = 7, REAGENT_ID_ANTITOXIN = 15, REAGENT_ID_FROSTOIL = 3))
				self.host.reagents.add_reagent(randomchem, 5)
				self.chemicals -= 50

			if(demand_urgency(demand, list(TREAT_BURN_CARE)) >= LEECH_TREAT_URGENCY && self.chemicals > 50)
				self.host.reagents.add_reagent(REAGENT_ID_KELOTANE, 5)
				self.host.reagents.add_reagent(REAGENT_ID_LEPORAZINE, 2)
				self.chemicals -= 50

			if(demand_urgency(demand, list(TREAT_OXYGENATION)) >= LEECH_TREAT_URGENCY && self.chemicals > 50)
				self.host.reagents.add_reagent(REAGENT_ID_IRON, 10)
				self.chemicals -= 40

			if(demand?[TREAT_NEURAL_REPAIR] && self.chemicals > 100)
				self.host.reagents.add_reagent(REAGENT_ID_ALKYSINE, 5)
				self.host.reagents.add_reagent(REAGENT_ID_TRAMADOL, 3)
				self.chemicals -= 100

			if(prob(30) && self.chemicals > 50)
				self.inject_meds(self.randomized_reagent)

			var/heartless_mod = 0
			if(ishuman(self.host))	// Species without hearts mean the worm gets hungry faster, if AI controlled.
				var/mob/living/carbon/human/H = self.host
				if(!H.species.has_organ[O_HEART])
					heartless_mod = 1

			if(prob(15 + (20 * heartless_mod)))
				self.feed_on_random_organ()
	//legacy else-clause emptied (was ai_holder reset).
	if(self.host && self.host.stat == DEAD && istype(get_turf(self.host), /turf/simulated/floor/water))
		self.leave_host()

/mob/living/simple_mob/animal/sif/leech/verb/infest()
	set category = "Abilities.Leech"
	set name = "Infest"
	set desc = "Infest a suitable humanoid host."

	if(docile)
		to_chat(src, span_alium("We are too tired to do this..."))
		return

	do_infest(src)

/mob/living/simple_mob/animal/sif/leech/proc/do_infest(mob/living/user, mob/living/target = null)
	if(host)
		to_chat(user, span_alien("We are already within a host."))
		return

	if(stat)
		to_chat(user, span_warning("We cannot infest a target in your current state."))
		return

	var/mob/living/carbon/M = target

	if(!M && src.client)
		var/list/choices = list()
		for(var/mob/living/carbon/C in view(1,src))
			if(src.Adjacent(C))
				choices += C

		if(!choices.len)
			to_chat(user, span_warning("There are no viable hosts within range..."))
			return

		om_ask(src, /datum/om/prompt/choice, PROC_REF(infest_target_answered), title = "Target Choice", message = "Who do we wish to infest?", choices = choices, ask_flags = ASK_CONSCIOUS)
		return
	infest_target_chosen(user, M)

/mob/living/simple_mob/animal/sif/leech/proc/infest_target_answered(datum/om/prompt/choice/ask)
	infest_target_chosen(ask.answerer, ask.choice)

/mob/living/simple_mob/animal/sif/leech/proc/infest_target_chosen(mob/living/user, mob/living/carbon/M)
	if(!M || host) return

	if(!(src.Adjacent(M))) return

	if(!istype(M) || HAS_SYNTHETIC_BIOLOGY(M))
		to_chat(user, "\The [M] cannot be infested.")
		return

	if(ishuman(M))
		var/mob/living/carbon/human/H = M

		var/obj/item/organ/external/E = H.organs_by_name[infest_target]
		if(!E || E.is_stump() || E.is_robotic())
			to_chat(src,"\The [H] does not have an infestable [infest_target]!")
			return

		if(H.body.worn_armor(E.body_part, MELEE) >= 20 + attack_armor_pen)
			to_chat(user, span_notice("We cannot get through that host's protective gear."))
			return

	om_task_start(/datum/om/task/timed/leech_do_infest_leech, src, M, user = user, M = M)
	return TRUE

/datum/om/task/timed/leech_do_infest_leech
	duration = 2
	complete_proc = /mob/living/simple_mob/animal/sif/leech/proc/do_infest_leech_done
	cancel_proc = /mob/living/simple_mob/animal/sif/leech/proc/do_infest_leech_failed
	var/mob/living/user
	var/mob/living/carbon/M

/mob/living/simple_mob/animal/sif/leech/proc/do_infest_leech_done(datum/om/task/timed/leech_do_infest_leech/task)
	var/mob/living/user = task.user
	var/mob/living/carbon/M = task.M

	if(!M || !src)
		return

	if(src.stat)
		to_chat(user, span_warning("We cannot infest a target in your current state."))
		return

	if(M in view(1, src))
		to_chat(user,span_alien("We burrow into [M]'s flesh."))
		if(!M.stat)
			to_chat(M, span_critical("You feel a sharp pain as something digs into your flesh!"))

		src.host = M
		src.forceMove(M)
		if(ai_brain)
			ai_brain.set_hostile(FALSE)
			ai_brain.lose_target()

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			host_bodypart = H.get_organ(infest_target)
			LAZYOR(host_bodypart.implants, src)

		return
	else
		to_chat(user, span_notice("They are no longer in range."))
		return

/mob/living/simple_mob/animal/sif/leech/proc/do_infest_leech_failed(datum/om/task/timed/leech_do_infest_leech/task)
	var/mob/living/user = task.user
	var/mob/living/carbon/M = task.M
	to_chat(user, span_notice("As [M] moves away, we are dislodged and fall to the ground."))
	return

/mob/living/simple_mob/animal/sif/leech/verb/uninfest()
	set category = "Abilities.Leech"
	set name = "Uninfest"
	set desc = "Leave your current host."

	if(docile)
		to_chat(src, span_alium("We are too tired to do this..."))
		return

	leave_host()

/mob/living/simple_mob/animal/sif/leech/proc/leave_host()
	if(!host)
		return

	if(host_bodypart)
		LAZYREMOVE(host_bodypart.implants, src)
		host_bodypart = null

	forceMove(get_turf(host))

	host = null

/mob/living/simple_mob/animal/sif/leech/verb/inject_victim()
	set category = "Abilities.Leech"
	set name = "Incapacitate Potential Host"
	set desc = "Inject an organic host with an incredibly painful mixture of chemicals."

	if(docile)
		to_chat(src, span_alium("We are too tired to do this..."))
		return

	var/mob/living/carbon/M
	if(src.client)
		var/list/choices = list()
		for(var/mob/living/carbon/C in view(1,src))
			if(src.Adjacent(C))
				choices += C

		if(!choices.len)
			to_chat(src, span_warning("There are no viable hosts within range..."))
			return

		om_ask(src, /datum/om/prompt/choice, PROC_REF(poison_inject_answered), title = "Target Choice", message = "Who do we wish to inject?", choices = choices, ask_flags = ASK_CONSCIOUS)
		return

	if(!M || stat)
		return

	poison_inject(src, M)

/mob/living/simple_mob/animal/sif/leech/proc/poison_inject_answered(datum/om/prompt/choice/ask)
	poison_inject(ask.answerer, ask.choice)

/mob/living/simple_mob/animal/sif/leech/proc/poison_inject(mob/living/user, mob/living/carbon/L)
	if(!L || !Adjacent(L) || stat)
		return

	var/mob/living/carbon/human/H = L

	if(!istype(H) || HAS_SYNTHETIC_BIOLOGY(H))
		to_chat(user, span_warning("You cannot inject this target..."))
		return

	var/obj/item/organ/external/E = H.organs_by_name[infest_target]
	if(!E || E.is_stump() || E.is_robotic())
		to_chat(src,"\The [H] does not have an infestable [infest_target]!")
		return

	if(H.body.worn_armor(E.body_part, MELEE) >= 40 + attack_armor_pen)
		to_chat(user, span_notice("You cannot get through that host's protective gear."))
		return

	H.lingering_poison(0.75, 15 SECONDS, src, TRUE)
	H.status_at_least(EFFECT_PARALYZED, 4)

/mob/living/simple_mob/animal/sif/leech/verb/medicate_host()
	set category = "Abilities.Leech"
	set name = "Produce Chemicals (50)"
	set desc = "Inject your host with possibly beneficial chemicals, to keep the blood flowing."

	if(docile)
		to_chat(src, span_alium("We are too tired to do this..."))
		return

	if(!host || chemicals <= 50)
		to_chat(src, span_alien("We cannot produce any chemicals right now."))
		return

	if(host)
		om_ask(src, /datum/om/prompt/choice, PROC_REF(meds_chosen), title = "Chemicals", message = "Select a chemical to produce.", choices = produceable_chemicals)

/mob/living/simple_mob/animal/sif/leech/proc/meds_chosen(datum/om/prompt/choice/ask)
	var/chem = ask.choice
	if(chemicals > 50 && !docile)
		inject_meds(chem)

/mob/living/simple_mob/animal/sif/leech/proc/inject_meds(chem)
	if(host)
		chemicals = max(1, chemicals - 50)
		host.reagents.add_reagent(chem, 5)
		to_chat(src, span_alien("We injected \the [host] with five units of [chem]."))

/mob/living/simple_mob/animal/sif/leech/verb/feed_on_organ()
	set category = "Abilities.Leech"
	set name = "Feed on Organ"
	set desc = "Extend probosci to feed on a piece of your host's organs."

	if(docile)
		to_chat(src, span_alium("We are too tired to do this..."))
		return

	if(host && COOLDOWN_FINISHED(src, feeding_cooldown))
		var/list/host_internal_organs = host.internal_organ_list()

		for(var/obj/item/organ/internal/O in host_internal_organs)	// Remove organs with maximum damage.
			if(O.damage >= O.max_damage)
				host_internal_organs -= O

		if(client)
			om_ask(src, /datum/om/prompt/choice/leech_feed_organ, PROC_REF(feed_organ_chosen), choices = host_internal_organs)
			return

		if(length(host_internal_organs))
			bite_organ(pick(host_internal_organs))

	else
		to_chat(src, span_warning("We cannot feed now."))

/datum/om/prompt/choice/leech_feed_organ
	title = "Organs"
	message = "Select an organ to feed on."

/datum/om/prompt/choice/leech_feed_organ/cancelled()
	to_chat(answerer, span_alien("We decide not to feed."))

/mob/living/simple_mob/animal/sif/leech/proc/feed_organ_chosen(datum/om/prompt/choice/leech_feed_organ/ask)
	var/obj/item/organ/internal/target = ask.choice
	if(host && target.owner == host && !docile && COOLDOWN_FINISHED(src, feeding_cooldown))
		bite_organ(target)

/// Feeds on an organ of the host without asking (the leech's own Life): never sleeps.
/mob/living/simple_mob/animal/sif/leech/proc/feed_on_random_organ()
	if(docile || !host || !COOLDOWN_FINISHED(src, feeding_cooldown))
		return
	var/list/organs = list()
	for(var/obj/item/organ/internal/O in host.internal_organ_list())
		if(O.damage < O.max_damage)
			organs += O
	if(length(organs))
		bite_organ(pick(organs))

/mob/living/simple_mob/animal/sif/leech/proc/bite_organ(obj/item/organ/internal/O)
	COOLDOWN_START(src, feeding_cooldown, feeding_delay)

	if(O)
		to_chat(src, span_alien("We feed on [O]."))
		O.owner?.injure(INJURY_PIERCE, 2, O, src, flags = prob(10) ? INJURE_SILENT : NONE)
		chemicals = min(max_chemicals, chemicals + 60)
		host.apply_body_effect(/datum/body_effect/grievous_wounds, 60 SECONDS)
		mend(TREAT_TISSUE_REPAIR, rand(10,60))
		mend(TREAT_BURN_CARE, rand(10,60))

/datum/decl/mob_organ_names/leech
TYPE_TABLE(/datum/decl/mob_organ_names/leech, mob_organ_hit_zones, list("mouthparts", "central segment", "tail segment"))

#undef LEECH_TREAT_URGENCY

DECLARE_REF(/mob/living/simple_mob/animal/sif/leech, "host_bodypart", HELD, null)
DECLARE_REF(/mob/living/simple_mob/animal/sif/leech, "host", HELD, null)
