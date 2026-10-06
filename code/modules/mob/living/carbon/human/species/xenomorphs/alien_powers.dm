/proc/alien_queen_exists(ignore_self,mob/living/carbon/human/self)
	for(var/mob/living/carbon/human/Q in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		if(self && ignore_self && self == Q)
			continue
		if(Q.species.name != SPECIES_XENO_QUEEN)
			continue
		if(!Q.key || !Q.client || Q.stat)
			continue
		return 1
	return 0

/mob/living/carbon/human/proc/gain_plasma(amount)

	var/obj/item/organ/internal/xenos/plasmavessel/I = organ_in(O_PLASMA)
	if(!istype(I)) return

	if(amount)
		I.stored_plasma += amount
	I.stored_plasma = max(0,min(I.stored_plasma,I.max_plasma))

/mob/living/carbon/human/proc/check_alien_ability(cost,needs_foundation,needs_organ)	//Returns 1 if the ability is clear for usage.

	var/obj/item/organ/internal/xenos/plasmavessel/P = organ_in(O_PLASMA)
	if(!istype(P))
		to_chat(src, span_danger("Your plasma vessel has been removed!"))
		return

	if(needs_organ)
		var/obj/item/organ/internal/I = organ_in(needs_organ)
		if(!I)
			to_chat(src, span_danger("Your [needs_organ] has been removed!"))
			return
		else if((I.status & ORGAN_CUT_AWAY) || I.is_broken())
			to_chat(src, span_danger("Your [needs_organ] is too damaged to function!"))
			return

	if(P.stored_plasma < cost)
		to_chat(src, span_danger("We lack the plasma reserves to perform that task.")) // It's PLASMA, not PHORON. Fuck I hate mass edits.
		return 0

	if(needs_foundation)
		var/turf/T = get_turf(src)
		var/has_foundation
		if(T)
			//TODO: Work out the actual conditions this needs.
			if(!(istype(T,/turf/space)))
				has_foundation = 1
		if(!has_foundation)
			to_chat(src, span_danger("You need a solid foundation to do that on."))
			return 0

	P.stored_plasma -= cost
	return 1

// Free abilities.
/mob/living/carbon/human/proc/transfer_plasma(mob/living/carbon/human/M as mob in oview())
	set name = "Transfer Plasma"
	set desc = "Transfer Plasma to another alien"
	set category = VERB_CAT_ABILITIES_ALIEN

	if (get_dist(src,M) <= 1)
		to_chat(src, span_alium("You need to be closer."))
		return

	var/obj/item/organ/internal/xenos/plasmavessel/I = M.organ_in(O_PLASMA)
	if(!istype(I))
		to_chat(src, span_alium("Their plasma vessel is missing."))
		return

	open_request(src, /datum/prompt/number/plasma_transfer, PROC_REF(plasma_amount_chosen), answerer = src, recipient = M)

/// How much plasma to give. Re-checked on the answer: still conscious, and the recipient still exists.
/datum/prompt/number/plasma_transfer
	question = "Amount:"
	ask_flags = ASK_CONSCIOUS
	timeout = 0
	min_value = null
	max_value = null
	step = 1
	default = 0
	var/mob/living/carbon/human/recipient

CAPABILITIES(/datum/prompt/number/plasma_transfer)
	ref_one(nameof(recipient), /mob/living/carbon/human)

/datum/prompt/number/plasma_transfer/prepare(datum/act/context)
	. = ..()
	var/mob/living/carbon/human/captured = recipient
	rel_clear(src, nameof(recipient))
	rel_set(src, nameof(recipient), captured)
	title = "Transfer Plasma to [recipient]"

/datum/prompt/number/plasma_transfer/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(recipient) ? "recipient gone" : null

/mob/living/carbon/human/proc/plasma_amount_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/plasma_transfer/ask = A.request
	var/mob/living/carbon/human/M = ask.recipient
	var/amount = abs(round(ask.value))
	if(amount && check_alien_ability(amount,0,O_PLASMA))
		M.gain_plasma(amount)
		to_chat(M, span_alium("[src] has transfered [amount] plasma to you."))
		to_chat(src, span_alium("You have transferred [amount] plasma to [M]."))

// Queen verbs.
/mob/living/carbon/human/proc/lay_egg()

	set name = "Lay Egg (500)" //Cost is entire queen reserve, to compensate being able to reproduce on it's own
	set desc = "Lay an egg that will eventually hatch into a new xenomorph larva. Life finds a way."
	set category = VERB_CAT_ABILITIES_ALIEN

	if(!CONFIG_GET(flag/aliens_allowed))
		to_chat(src, "You begin to lay an egg, but hesitate. You suspect it isn't allowed.")
		grant(src, granted_verb(/mob/living/carbon/human/proc/lay_egg, hidden = TRUE), verb_source(VERB_SOURCE_CONFIG))
		return

	if(locate_within(get_turf(src), /obj/structure/ghost_pod/automatic/xenomorph_egg))
		to_chat(src, "There's already an egg here.")
		return

	if(check_alien_ability(500,1,O_EGG))
		act_message(src, null, others = span_alium(span_bold("%U% has laid an egg!")))
		new /obj/structure/ghost_pod/automatic/xenomorph_egg(loc)

	return

// Drone verbs.
/mob/living/carbon/human/proc/evolve()
	set name = "Evolve (500)"
	set desc = "Produce an internal egg sac capable of spawning children. Only one queen can exist at a time."
	set category = VERB_CAT_ABILITIES_ALIEN

	if(alien_queen_exists())
		to_chat(src, span_notice("We already have an active queen."))
		return

	if(check_alien_ability(500))
		act_message(src, null, MSG_SELF(span_alium("You begin to evolve!")), MSG_OTHERS(span_alium(span_bold("%U% begins to twist and contort!"))))
		src.set_species("Xenomorph Queen")

	return

/mob/living/carbon/human/proc/plant()
	set name = "Plant Weeds (50)"
	set desc = "Plants some alien weeds"
	set category = VERB_CAT_ABILITIES_ALIEN

	if(check_alien_ability(50,1,O_RESIN))
		act_message(src, null, others = span_alium(span_bold("%U% has planted some alien weeds!")))
		new /obj/effect/alien/weeds/node(get_turf(src), null, "#321D37")
	return

/mob/living/carbon/human/proc/Spit(atom/A)
	if(!COOLDOWN_FINISHED(src, spit_cooldown)) //To prevent YATATATATATAT spitting.
		to_chat(src, span_warning("You have not yet prepared your chemical glands. You must wait before spitting again."))
		return
	else
		COOLDOWN_START(src, spit_cooldown, 1 SECONDS)

	if(spitting && incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, "You cannot spit in your current state.")
		spitting = 0
		return
	else if(spitting)
		if(!check_alien_ability(20,0,O_ACID))
			spitting = 0
			return
		act_message(src, A, MSG_SELF(span_alium("You spit [spit_name] at %T%.")), MSG_OTHERS(span_warning("%U% spits [spit_name] at %T%!")))
		var/obj/item/projectile/P = new spit_projectile(get_turf(src))
		rel_set(P, nameof(P.firer), src)
		P.old_style_target(A)
		P.fire()
		play_sfx(src, SFX_WEAPONS_ALIEN_SPITACID)

/mob/living/carbon/human/proc/corrosive_acid(O as obj|turf in oview(1)) //If they right click to corrode, an error will flash if its an invalid target./N
	set name = "Corrosive Acid (200)"
	set desc = "Drench an object in acid, destroying it over time."
	set category = VERB_CAT_ABILITIES_ALIEN

	if(!(O in oview(1)))
		to_chat(src, span_alium("[O] is too far away."))
		return

	// OBJ CHECK
	var/cannot_melt
	if(isobj(O))
		var/obj/I = O //Gurgs : Melts pretty much any object that isn't considered unacidable = TRUE
		if(I.unacidable)
			cannot_melt = 1
	else
		if(istype(O, /turf/simulated/wall))
			var/turf/simulated/wall/W = O //Gurgs : Walls are deconstructed into girders.
			if(W.material.flags & MATERIAL_UNMELTABLE)
				cannot_melt = 1
		else if(istype(O, /turf/simulated/floor))
			var/turf/simulated/floor/F = O	//Gurgs : Floors are destroyed with ex_act(1), turning them into whatever tile it would be if empty. Z-Level Friendly, does not destroy pipes.
			if(F.flooring && (F.flooring.flags & TURF_ACID_IMMUNE))
				cannot_melt = 1
		else
			cannot_melt = 1 //Gurgs : Everything that isn't a object, simulated wall, or simulated floor is assumed to be acid immune. Includes weird things like unsimulated floors and space.

	if(cannot_melt)
		to_chat(src, span_alium("You cannot dissolve this object."))
		return

	if(check_alien_ability(200,0,O_ACID))
		new /obj/effect/alien/acid(get_turf(O), O)
		act_message(src, null, others = span_alium(span_bold("%U% vomits globs of vile stuff all over [O]. It begins to sizzle and melt under the bubbling mess of acid!")))

	return

/mob/living/carbon/human/proc/neurotoxin()
	set name = "Toggle Neurotoxic Spit (40)"
	set desc = "Readies a neurotoxic spit, which paralyzes the target for a short time if they are not wearing protective gear."
	set category = VERB_CAT_ABILITIES_ALIEN

	if(spitting)
		to_chat(src, span_alium("You stop preparing to spit."))
		spitting = 0
		return

	if(!check_alien_ability(40,0,O_ACID))
		spitting = 0
		return

	else
		COOLDOWN_START(src, spit_cooldown, 1 SECONDS)
		spitting = 1
		spit_projectile = /obj/item/projectile/energy/neurotoxin
		spit_name = "neurotoxin"
		to_chat(src, span_alium("You prepare to spit neurotoxin."))

/mob/living/carbon/human/proc/acidspit()
	set name = "Toggle Acid Spit (50)"
	set desc = "Readies an acidic spit, which burns the target if they are not wearing protective gear."
	set category = VERB_CAT_ABILITIES_ALIEN

	if(spitting)
		to_chat(src, span_alium("You stop preparing to spit."))
		spitting = 0
		return

	if(!check_alien_ability(50,0,O_ACID))
		spitting = 0
		return

	else
		COOLDOWN_START(src, spit_cooldown, 1 SECONDS)
		spitting = 1
		spit_projectile = /obj/item/projectile/energy/acid
		spit_name = "acid"
		to_chat(src, span_alium("You prepare to spit acid."))

/mob/living/carbon/human/proc/resin() //Gurgs : Refactored resin ability, big thanks to Jon.
	set name = "Secrete Resin (75)"
	set desc = "Secrete tough malleable resin."
	set category = VERB_CAT_ABILITIES_ALIEN

	var/list/options = list("resin door","resin wall","resin membrane","nest","resin blob")
	for(var/option in options)
		LAZYSET(options, option, new /image('icons/mob/alien.dmi', option)) // based off 'icons/effects/thinktank_labels.dmi'

	open_request(src, /datum/prompt/choice, PROC_REF(resin_chosen), answerer = src, choices = options, anchor = src, radius = 42, require_near = TRUE, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/// Radial answer: secrete the picked resin structure in front of us.
/mob/living/carbon/human/proc/resin_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/choice = A.answer.value
	if(!choice || QDELETED(src) || src.incapacitated())
		return

	var/targetLoc = get_step(src, dir)

	if(iswall(targetLoc))
		targetLoc = get_turf(src)

	var/obj/O

	switch(choice)
		if("resin door")
			if(!check_alien_ability(75,1,O_RESIN))
				return
			else O = new /obj/structure/simple_door/resin(targetLoc)
		if("resin wall")
			if(!check_alien_ability(75,1,O_RESIN))
				return
			else O = new /obj/structure/alien/wall(targetLoc)
		if("resin membrane")
			if(!check_alien_ability(75,1,O_RESIN))
				return
			else O = new /obj/structure/alien/membrane(targetLoc)
		if("nest")
			if(!check_alien_ability(75,1,O_RESIN))
				return
			else O = new /obj/structure/bed/nest(targetLoc)
		if("resin blob")
			if(!check_alien_ability(75,1,O_RESIN))
				return
			else O = new /obj/item/stack/material/resin(targetLoc)

	if(O)
		act_message(src, null, MSG_SELF(span_alium("You shape a [choice].")), \
			MSG_OTHERS(span_boldwarning("%U% vomits up a thick purple substance and begins to shape it!")))
		play_sfx(src, SFX_EFFECTS_BLOBATTACK, volume = 40)

	return

/mob/living/carbon/human/proc/leap()
	set category = VERB_CAT_ABILITIES_ALIEN
	set name = "Leap"
	set desc = "Leap at a target and grab them aggressively."

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying || restrained() || src?.buckled_to())
		to_chat(src, "You cannot leap in your current state.")
		return

	var/list/choices = list()
	for(var/mob/living/M in view(6,src))
		if(!istype(M,/mob/living/silicon))
			choices += M
	choices -= src

	open_request(src, /datum/prompt/choice, PROC_REF(alien_leap_target_chosen), answerer = src, title = "Target Choice", question = "Who do you wish to leap at?", choices = choices, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/alien_leap_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/T = A.answer.value

	if(get_dist(get_turf(T), get_turf(src)) > 4) return

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying || restrained() || src?.buckled_to())
		to_chat(src, "You cannot leap in your current state.")
		return

	COOLDOWN_START(src, last_special, 7.5 SECONDS)
	set_status_flags(status_flags | LEAPING)

	act_message(src, T, others = span_danger("%U% leaps at %T%!"))
	src.throw_at(get_step(get_turf(T),get_turf(src)), 4, 1, src)
	play_sfx(src, SFX_VOICE_HISS5)
	after(src, 0.5 SECONDS, PROC_REF(leap_land), with = list(T))

/mob/living/carbon/human/proc/leap_land(mob/living/T)

	if(status_flags & LEAPING) set_status_flags(status_flags & ~LEAPING)

	if(!src.Adjacent(T))
		to_chat(src, span_warning("You miss!"))
		return

	T.status_at_least(STAT_WEAKENED, 3)

	var/use_hand = "left"
	if(get_equipped_item(SLOT_ID_HAND_L))
		if(get_equipped_item(SLOT_ID_HAND_R))
			to_chat(src, span_danger("You need to have one hand free to grab someone."))
			return
		else
			use_hand = "right"

	act_message(src, T, others = span_boldwarning("%U%") + " seizes %T% aggressively!")

	var/obj/item/grab/G = new(src,T)
	if(!move_into(src, use_hand == "left" ? SLOT_ID_HAND_L : SLOT_ID_HAND_R, G, src))
		spent(G)
		return

	G.state = GRAB_PASSIVE
	G.icon_state = "grabbed1"
	G.synch()

/mob/living/carbon/human/proc/gut()
	set category = VERB_CAT_ABILITIES_ALIEN
	set name = "Slaughter"
	set desc = "While grabbing someone aggressively, rip their guts out or tear them apart."

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying)
		to_chat(src, span_danger("You cannot do that in your current state."))
		return

	var/obj/item/grab/G = locate_within(src, /obj/item/grab)
	if(!G || !istype(G))
		to_chat(src, span_danger("You are not grabbing anyone."))
		return

	if(G.state < GRAB_AGGRESSIVE)
		to_chat(src, span_danger("You must have an aggressive grab to slaughter your prey!"))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	act_message(src, null, others = span_warning(span_bold("%U%") + " rips viciously at \the [G?.grab_target()]'s body with its claws!"))

	if(ishuman(G?.grab_target()))
		var/mob/living/carbon/human/H = G?.grab_target()
		H.injure(INJURY_CUT, 50, null, src)
		if(H.stat == 2)
			H.gib()

	else
		var/mob/living/M = G?.grab_target()
		if(!istype(M)) return //wut
		M.injure(INJURY_CUT, 50, null, src)
		if(M.stat == 2)
			M.gib()
