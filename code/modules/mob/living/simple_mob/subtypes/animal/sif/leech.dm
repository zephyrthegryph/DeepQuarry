// Small creatures that will embed themselves in unsuspecting victim's bodies, drink their blood, and/or eat their organs. Steals some things from borers.

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
	var/last_feeding = 0


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

	if(istype(L.buckled, /obj/vehicle) || dq_get_hovering(L) || L.flying) // Ignore people dq_get_hovering(src) or on boats.
		return TRUE

	if(!.)
		var/has_organ = FALSE
		var/obj/item/organ/internal/O = H.get_active_hand()
		if(istype(O) && O.robotic < ORGAN_ROBOT && !(O.status & ORGAN_DEAD))
			has_organ = TRUE
		return has_organ

/datum/say_list/leech
	speak = list("...", "Sss..", ". . .","Gss..")
	emote_see = list("vibrates","looks around", "stares", "extends a proboscis")
	emote_hear = list("chitters", "clicks", "gurgles")

/mob/living/simple_mob/animal/sif/leech/Initialize(mapload)
	. = ..()

	add_verb(src, /mob/living/proc/ventcrawl)
	add_verb(src, /mob/living/proc/hide)

	ADD_TRAIT(src, TRAIT_AMBIENT_PEST_MOB, ROUNDSTART_TRAIT)

/mob/living/simple_mob/animal/sif/leech/get_status_tab_items()
	. = ..()
	. += "Chemicals: [chemicals]"

/mob/living/simple_mob/animal/sif/leech/do_special_attack(atom/A)
	. = TRUE
	if(istype(A, /mob/living/carbon))
		switch(use_stance())
			if(I_DISARM) // Poison
				if(ai_brain) ai_brain.busy = TRUE
				poison_inject(src, A)
				if(ai_brain) ai_brain.busy = FALSE
			if(I_GRAB) // Infesting!
				if(ai_brain) ai_brain.busy = TRUE
				do_infest(src, A)
				if(ai_brain) ai_brain.busy = FALSE
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
			if(self.host.injury_load(INJURY_CATEGORY_PHYSICAL) >= 30 && self.chemicals > 50)
				self.host.reagents.add_reagent(REAGENT_ID_BICARIDINE, 5)
				self.chemicals -= 30

			if(self.host.injury_load(INJURY_CATEGORY_TOXIC) >= 30 && self.chemicals > 50)
				var/randomchem = pickweight(list(REAGENT_ID_TRAMADOL = 7, REAGENT_ID_ANTITOXIN = 15, REAGENT_ID_FROSTOIL = 3))
				self.host.reagents.add_reagent(randomchem, 5)
				self.chemicals -= 50

			if(self.host.injury_load(INJURY_CATEGORY_THERMAL) >= 30 && self.chemicals > 50)
				self.host.reagents.add_reagent(REAGENT_ID_KELOTANE, 5)
				self.host.reagents.add_reagent(REAGENT_ID_LEPORAZINE, 2)
				self.chemicals -= 50

			if(self.host.oxygen_debt() >= 30 && self.chemicals > 50)
				self.host.reagents.add_reagent(REAGENT_ID_IRON, 10)
				self.chemicals -= 40

			if(self.host.injury_load(INJURY_CATEGORY_NEURAL) >= 10 && self.chemicals > 100)
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
				INVOKE_ASYNC(self, TYPE_VERB_REF(/mob/living/simple_mob/animal/sif/leech, feed_on_organ))
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

		M = tgui_input_list(src, "Who do we wish to infest?", "Target Choice", choices)

	if(!M || !src) return

	if(!(src.Adjacent(M))) return

	if(!istype(M) || M.isSynthetic())
		to_chat(user, "\The [M] cannot be infested.")
		return

	if(ishuman(M))
		var/mob/living/carbon/human/H = M

		var/obj/item/organ/external/E = H.organs_by_name[infest_target]
		if(!E || E.is_stump() || E.robotic >= ORGAN_ROBOT)
			to_chat(src,"\The [H] does not have an infestable [infest_target]!")
			return

		var/list/covering_clothing = E.get_covering_clothing()
		for(var/obj/item/clothing/C in covering_clothing)
			if(C.get_armor().value("melee") >= 20 + attack_armor_pen)
				to_chat(user, span_notice("We cannot get through that host's protective gear."))
				return

	if(!do_after(src, 2, target))
		to_chat(user, span_notice("As [M] moves away, we are dislodged and fall to the ground."))
		return

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
			host_bodypart.implants |= src

		return
	else
		to_chat(user, span_notice("They are no longer in range."))
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
		host_bodypart.implants -= src
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

		M = tgui_input_list(src, "Who do we wish to inject?", "Target Choice", choices)

	if(!M || stat)
		return

	poison_inject(src, M)

/mob/living/simple_mob/animal/sif/leech/proc/poison_inject(mob/living/user, mob/living/carbon/L)
	if(!L || !Adjacent(L) || stat)
		return

	var/mob/living/carbon/human/H = L

	if(!istype(H) || H.isSynthetic())
		to_chat(user, span_warning("You cannot inject this target..."))
		return

	var/obj/item/organ/external/E = H.organs_by_name[infest_target]
	if(!E || E.is_stump() || E.robotic >= ORGAN_ROBOT)
		to_chat(src,"\The [H] does not have an infestable [infest_target]!")
		return

	var/list/covering_clothing = E.get_covering_clothing()
	for(var/obj/item/clothing/C in covering_clothing)
		if(C.get_armor().value("melee") >= 40 + attack_armor_pen)
			to_chat(user, span_notice("You cannot get through that host's protective gear."))
			return

	H.add_modifier(/datum/modifier/poisoned/paralysis, 15 SECONDS)

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
		var/chem = tgui_input_list(src, "Select a chemical to produce.", "Chemicals", produceable_chemicals)
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

	if(host && world.time >= last_feeding + feeding_delay)
		var/list/host_internal_organs = host.internal_organs

		for(var/obj/item/organ/internal/O in host_internal_organs)	// Remove organs with maximum damage.
			if(O.damage >= O.max_damage)
				host_internal_organs -= O

		var/target
		if(client)
			target = tgui_input_list(src, "Select an organ to feed on.", "Organs", host_internal_organs)
			if(!target)
				to_chat(src, span_alien("We decide not to feed."))
				return

		if(!target)
			target = pick(host_internal_organs)

		if(target)
			bite_organ(target)

	else
		to_chat(src, span_warning("We cannot feed now."))

/mob/living/simple_mob/animal/sif/leech/proc/bite_organ(obj/item/organ/internal/O)
	last_feeding = world.time

	if(O)
		to_chat(src, span_alien("We feed on [O]."))
		O.owner?.injure(INJURY_PIERCE, 2, O, src, flags = prob(10) ? INJURE_SILENT : NONE)
		chemicals = min(max_chemicals, chemicals + 60)
		host.add_modifier(/datum/modifier/grievous_wounds, 60 SECONDS)
		mend(TREAT_TISSUE_REPAIR, rand(10,60))
		mend(TREAT_BURN_CARE, rand(10,60))

/datum/decl/mob_organ_names/leech
	hit_zones = list("mouthparts", "central segment", "tail segment")
