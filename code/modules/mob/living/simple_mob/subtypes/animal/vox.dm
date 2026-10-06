/mob/living/simple_mob/vox
	min_oxy = 0
	max_oxy = 0
	min_tox = 5
	max_tox = 0
	min_co2 = 0
	max_co2 = 5
	min_n2 = 0 //breathe N2
	max_n2 = 0

	species_sounds = "Vox"
	pain_emote_1p = list("shriek")
	pain_emote_3p = list("shrieks")

/mob/living/simple_mob/vox/armalis
	name = "serpentine alien"
	real_name = "serpentine alien"
	desc = "A one-eyed, serpentine creature, half-machine, easily nine feet from tail to beak!"
	icon = 'icons/mob/vox.dmi'
	icon_state = "armalis"
	icon_living = "armalis"
	endurance = 500
	response_harm = "slashes at the"
	harm_intent_damage = 0
	melee_damage_lower = 30
	melee_damage_upper = 40
	attacktext = "slammed its enormous claws into"
	movement_cooldown = 2
	attack_sound = SFX_WEAPONS_BLADESLICE
	status_flags = 0
	max_oxy = 0

	var/armour = null
	var/amp = null
	var/quills = 3

/mob/living/simple_mob/vox/armalis
	delete_on_death = TRUE
	death_message = DEATHGASP_NO_MESSAGE

/mob/living/simple_mob/vox/armalis/on_death(gibbed)
	. = ..()
	var/turf/gloc = get_turf(loc)
	act_message(src, null, MSG_SELF(span_warning("You feel your body rupture!")), MSG_OTHERS(span_bolddanger("%U% shudders violently and explodes!")))
	gib()
	explosion(gloc, -1, -1, 3, 5)

/mob/living/simple_mob/vox/armalis/verb/fire_quill(mob/target as mob in oview())


	set name = "Fire quill"
	set desc = "Fires a viciously pointed quill at a high speed."
	set category = VERB_CAT_ALIEN

	if(quills<=0)
		return

	to_chat(src, span_warning("You launch a razor-sharp quill at [target]!"))
	for(var/mob/O in oviewers())
		if ((O.client && !( O.blinded )))
			to_chat(O, span_warning("[src] launches a razor-sharp quill at [target]!"))

	var/obj/item/arrow/quill/Q = new(loc)
	Q.add_fingerprint(ckey)
	Q.throw_at(target,10,30)
	quills--

	after(src, 10 SECONDS, PROC_REF(regrow_quill))

/mob/living/simple_mob/vox/armalis/verb/message_mob()
	set category = VERB_CAT_ALIEN
	set name = "Commune with creature"
	set desc = "Send a telepathic message to an unlucky recipient."

	var/datum/armalis_commune_review/review = new
	rel_set(review, nameof(review.actor), src)
	review.start()

/datum/armalis_commune_review
	parent_type = /datum/prompt_workflow
	var/mob/living/simple_mob/vox/armalis/actor
	/// The chosen mob's getmobs() name, resolved again after the text is entered.
	var/recipient

CAPABILITIES(/datum/armalis_commune_review)
	ref_one(nameof(actor), /mob/living/simple_mob/vox/armalis)

/datum/prompt/choice/armalis_commune_target
	timeout = 0
	title = "Speak to creature"
	question = "Select a creature!"

/datum/prompt/choice/armalis_commune_target/prepare(datum/act/A)
	choices = getmobs()
	return ..()

/datum/prompt/text/armalis_commune_text
	timeout = 0
	title = "Speak to creature"
	question = "What would you like to say?"

/datum/armalis_commune_review/proc/start()
	if(QDELETED(actor))
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(start_step))
	if(!result.ok)
		stack_trace("[type] start_step: [result.error]")
		retire()

/datum/armalis_commune_review/proc/start_step()
	open_request(src, /datum/prompt/choice/armalis_commune_target, PROC_REF(recipient_entered), answerer = actor, asker = actor)

/datum/armalis_commune_review/proc/run_step(step, datum/act/request/A)
	if(!A.answer || QDELETED(actor))
		retire()
		return
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("Armalis commune step [step]: [result.error]")
		retire()

/datum/armalis_commune_review/proc/recipient_entered(datum/act/request/A)
	run_step(PROC_REF(recipient_step), A)

/datum/armalis_commune_review/proc/recipient_step(datum/act/request/A)
	recipient = A.answer.value
	open_request(src, /datum/prompt/text/armalis_commune_text, PROC_REF(text_entered), answerer = actor, asker = actor)

/datum/armalis_commune_review/proc/text_entered(datum/act/request/A)
	run_step(PROC_REF(text_step), A)

/datum/armalis_commune_review/proc/text_step(datum/act/request/A)
	actor.message_mob_answered(recipient, A.answer.value)
	retire()

/mob/living/simple_mob/vox/armalis/proc/message_mob_answered(recipient, text)
	var/list/targets = getmobs()
	var/mob/M = targets[recipient]
	if(!M)
		return

	if(istype(M, /mob/observer/dead) || M.stat == DEAD)
		to_chat(src, "Not even the armalis can speak to the dead.")
		return

	to_chat(M, span_notice("Like lead slabs crashing into the ocean, alien thoughts drop into your mind: [text]"))
	if(istype(M,/mob/living/carbon/human))
		var/mob/living/carbon/human/H = M
		if(H.species.name == "Vox")
			return
		to_chat(H, span_warning("Your nose begins to bleed..."))
		H.drip(1)

/mob/living/simple_mob/vox/armalis/verb/shriek()
	set category = VERB_CAT_ALIEN
	set name = "Shriek"
	set desc = "Give voice to a psychic shriek."

EXTEND_INTERACTIONS(/mob/living/simple_mob/vox/armalis, INTERACT_ITEM(null, PROC_REF(armalis_interaction_item)))

/// Old attackby: armour/amp fitting, and its own weapon resistance (never reaches the normal attack).
/mob/living/simple_mob/vox/armalis/proc/armalis_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	. = TRUE
	if(istype(O,/obj/item/vox/armalis_armour))
		user.drop_item(O)
		armour = O
		movement_cooldown = 4
		endurance += 200
		act_message(src, O, MSG_SELF(span_notice("You quickly outfit %U% in %T%.")), MSG_OTHERS(span_notice("%U% is quickly outfitted in %T% by [user].")))
		regenerate_icons()
		return
	if(istype(O,/obj/item/vox/armalis_amp))
		user.drop_item(O)
		amp = O
		act_message(src, O, MSG_SELF(span_notice("You quickly outfit %U% in %T%.")), MSG_OTHERS(span_notice("%U% is quickly outfitted in %T% by [user].")))
		regenerate_icons()
		return

	base_attack_cooldown = 5
	if(O.force)
		if(O.force >= 25)
			var/damage = O.force
			if (O.injury_kind == INJURY_PAIN)
				damage = 0
			injure(O.injury_kind, damage, null, O)
			for(var/mob/M in viewers(src, null))
				if ((M.client && !( M.blinded )))
					M.show_message(span_danger("[src] has been attacked with the [O] by [user]. "))
		else
			for(var/mob/M in viewers(src, null))
				if ((M.client && !( M.blinded )))
					M.show_message(span_danger("The [O] bounces harmlessly off of [src]. "))
	else
		to_chat(user, span_warning("This weapon is ineffective, it does no damage."))
		for(var/mob/M in viewers(src, null))
			if ((M.client && !( M.blinded )))
				M.show_message(span_warning("[user] gently taps [src] with the [O]. "))

/mob/living/simple_mob/vox/armalis/regenerate_icons()
	..()
	overlays = list()
	if(armour)
		var/icon/armour = image('icons/mob/vox.dmi',"armour")
		movement_cooldown = 4
		overlays += armour
	if(amp)
		var/icon/amp = image('icons/mob/vox.dmi',"amplifier")
		overlays += amp
	return

/obj/item/vox/armalis_armour

	name = "strange armour"
	desc = "Hulking reinforced armour for something huge."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "armalis_armour"
	item_state = "armalis_armour"

/obj/item/vox/armalis_amp

	name = "strange lenses"
	desc = "A series of metallic lenses and chains."
	icon = 'icons/inventory/head/item.dmi'
	icon_state = "amp"
	item_state = "amp"

/mob/living/simple_mob/vox/armalis/proc/regrow_quill()
	to_chat(src, span_warning("You feel a fresh quill slide into place."))
	quills++

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/vox/armalis)
	immune_to_incapacitation()
