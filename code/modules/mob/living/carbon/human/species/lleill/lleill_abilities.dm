/datum/power/lleill

// Simple ability to become invisible. Does not phase you out of the world, you can still interact with things and can not pass through walls.
// Essentially the same as traitor cloaking, using the same proc for it.

/datum/power/lleill/invisibility
	name = "Invisibility (75)"
	desc = "Change your appearance to match your surroundings, becoming completely invisible to the naked eye."
	verbpath = /mob/living/carbon/human/proc/lleill_invisibility
	ability_icon_state = "ling_camoflage"

/mob/living/carbon/human/proc/lleill_invisibility()
	set name = "Invisibility (75)"
	set desc = "Change your appearance to match your surroundings, becoming completely invisible to the naked eye."
	set category = VERB_CAT_ABILITIES_LLEILL

	var/energy_cost = 75

	if(stat)
		to_chat(src, span_warning("You can't go invisible when weakened like this."))
		return

	if(!dq_get_cloaked(src))
		if(species.lleill_energy < energy_cost)
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
			return
		cloak()
		set_block_hud(1)
		flag_hud_update(0)
		to_chat(src, span_warning("Your fur shimmers and shifts around you, hiding you from the naked eye."))
		rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
		species.lleill_energy -= energy_cost
	else
		uncloak()
		set_block_hud(0)
		flag_hud_update(0)
		to_chat(src, span_warning("The brustling of your fur settles down and you become visible once again."))
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_select_shape()

	set name = "Select Body Shape"
	set category = VERB_CAT_ABILITIES_LLEILL

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	open_request(src, /datum/prompt/choice/shapeshifter_form, PROC_REF(lleill_shape_chosen), answerer = src, choices = species.get_valid_shapeshifter_forms(src))

/mob/living/carbon/human/proc/lleill_shape_chosen(datum/act/request/A)
	if(!A.answer)
		return
	lleill_change_shape(A.answer.value)

/mob/living/carbon/human/proc/lleill_change_shape(new_species = null)
	if(!new_species)
		return

	GLOB.wrapped_species_by_ref["\ref[src]"] = new_species
	dna.base_species = new_species
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.base_species = new_species
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " shifts and contorts, taking the form of \a [new_species]!"))
	regenerate_icons()

/mob/living/carbon/human/proc/lleill_select_colour()

	set name = "Select Body Colour"
	set category = VERB_CAT_ABILITIES_LLEILL

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	open_request(src, /datum/prompt/color, PROC_REF(lleill_colour_chosen), answerer = src, title = "Shapeshifter Colour", question = "Please select a new body color.", default = rgb(r_skin, g_skin, b_skin), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/lleill_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	lleill_set_colour(A.answer.value)

/mob/living/carbon/human/proc/lleill_set_colour(new_skin)

	r_skin =   hex2num(copytext(new_skin, 2, 4))
	g_skin =   hex2num(copytext(new_skin, 4, 6))
	b_skin =   hex2num(copytext(new_skin, 6, 8))
	r_synth = r_skin
	g_synth = g_skin
	b_synth = b_skin

	for(var/obj/item/organ/external/E in organs)
		E.sync_colour_to_human(src)

	regenerate_icons()

/datum/power/lleill/transmute
	name = "Transmute Object (50)"
	desc = "Convert an object into a piece of glamour."
	verbpath = /mob/living/carbon/human/proc/lleill_transmute
	ability_icon_state = "lleill_transmute"

/mob/living/carbon/human/proc/lleill_transmute()
	set name = "Transmute Object (50)"
	set desc = "Convert an object into a piece of glamour."
	set category = VERB_CAT_ABILITIES_LLEILL

	var/static/list/transmute_list = list(
		"Transparent Glamour" = /obj/item/potion_material/glamour_transparent,
		"Shrinking Glamour" = /obj/item/potion_material/glamour_shrinking,
		"Twinkling Glamour" = /obj/item/potion_material/glamour_twinkling,
		"Unstable Glamour" = /obj/item/glamour_unstable,
		"Glamour Shard" = /obj/item/potion_material/glamour_shard,
		"Glamour Cell" = /obj/item/capture_crystal/glamour,
		"Face of Glamour" = /obj/item/glamour_face,
		"Speaking Glamour" = /obj/item/universal_translator/glamour,
		"Glamour Bubble" = /obj/item/clothing/mask/gas/glamour,
		"Pocket of Glamour" = /obj/item/clothing/under/permit/glamour,
		"glamour arrow" = /obj/item/arrow/standard/glamour,
		"glamour bow" = /obj/item/gun/launcher/crossbow/bow/glamour
		)

	var/energy_cost = 50

	if(species.lleill_energy < energy_cost)
		to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return

	if(stat)
		to_chat(src, span_warning("You can't go do that when weakened like this."))
		return

	var/obj/item/I = get_active_hand()
	if(!I)
		to_chat(src, span_warning("You have no item in your active hand."))
		return

	open_request(src, /datum/prompt/choice/lleill_transmute, PROC_REF(lleill_transmute_chosen), answerer = src, choices = transmute_list, energy_cost = energy_cost, item = I)

/// A glamour pick: conscious, still holding its item, and enough energy to transmute.
/datum/prompt/choice/lleill_transmute
	title = "Transmutation"
	question = "Choose a glamour to transmute the item into:"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/energy_cost
	var/obj/item/item

CAPABILITIES(/datum/prompt/choice/lleill_transmute)
	ref_one(nameof(item), /obj/item)

/datum/prompt/choice/lleill_transmute/prepare(datum/act/A)
	..()
	var/obj/item/captured = item
	rel_clear(src, nameof(item))
	rel_set(src, nameof(item), captured)

/datum/prompt/choice/lleill_transmute/begin()
	if(QDELETED(item))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/lleill_transmute/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(item))
		return "gone"
	var/mob/living/carbon/human/H = answerer
	if(H.get_active_hand() != item)
		return "not in hand"
	return H.species.lleill_energy < energy_cost ? "no energy" : null

/datum/prompt/choice/lleill_beast
	title = "Choose Beast Form"
	question = "Which form would you like to take?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/energy_cost

/datum/prompt/choice/lleill_beast/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/carbon/human/H = answerer
	return H.species.lleill_energy < energy_cost ? "no energy" : null

/mob/living/carbon/human/proc/lleill_transmute_chosen(datum/act/request/A)
	var/datum/prompt/choice/lleill_transmute/ask = A.request
	if(!A.answer)
		if(!isnull(ask.value))
			if(ask.last_error == "not in hand")
				to_chat(src, span_warning("The item is no longer in your hands."))
			else if(ask.last_error == "no energy")
				to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/obj/item/I = ask.item
	var/energy_cost = ask.energy_cost
	var/obj/item/transmute_product = ask.choices[A.answer.value]
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to change the form of %I%."), item = I)
	task_start(/datum/task/timed/human_lleill_transmute_human, src, I, energy_cost = energy_cost, transmute_product = transmute_product)

/datum/task/timed/human_lleill_transmute_human
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/lleill_transmute_human_done
	cancel_proc = /mob/living/carbon/human/proc/lleill_transmute_human_failed
	var/energy_cost
	var/obj/item/transmute_product

/mob/living/carbon/human/proc/lleill_transmute_human_done(datum/task/timed/human_lleill_transmute_human/task)
	var/energy_cost = task.energy_cost
	var/obj/item/I = task.target
	var/obj/item/transmute_product = task.transmute_product
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " transmutes %I% into \the [transmute_product.name]."), item = I)
	consume(I, src)
	var/spawnloc = get_turf(src)
	var/obj/item/N = new transmute_product(spawnloc)
	put_in_active_hand(N)
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy -= energy_cost
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_transmute_human_failed(datum/task/timed/human_lleill_transmute_human/task)
	var/obj/item/I = task.target
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " leaves %I% in its original form."), item = I)
	return 0

/datum/power/lleill/rings
	name = "Glamour Rings"
	desc = "Place or teleport to a glamour ring."
	verbpath = /mob/living/carbon/human/proc/lleill_rings
	ability_icon_state = "lleill_ring"

/mob/living/carbon/human/proc/lleill_ring_interrupted(datum/act/op/A)
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to form white rings on the ground."))

/// What a new ring costs: 25 energy for every ring already placed.
/mob/living/carbon/human/proc/lleill_ring_spawn_cost()
	return 25 * length(teleporters)

/mob/living/carbon/human/proc/lleill_ring_spawn_done(datum/act/op/A)
	lleill_ring_placed(lleill_ring_spawn_cost())

/mob/living/carbon/human/proc/lleill_ring_placed(energy_cost_spawn)
	if(species.lleill_energy < energy_cost_spawn)
		return
	to_chat(src, span_warning("You place a new glamour ring at your feet."))
	var/spawnloc = get_turf(src)
	var/obj/structure/glamour_ring/R = new(spawnloc)
	R.connected_mob = src
	rel_add(src, nameof(teleporters), R)
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy -= energy_cost_spawn
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_rings()
	set name = "Place/Use Rings"
	set desc = "Place or teleport to a glamour ring."
	set category = VERB_CAT_ABILITIES_LLEILL

	var/energy_cost_multi = src.teleporters.len
	var/energy_cost_spawn = (25 * energy_cost_multi)
	var/energy_cost_tele = 50

	if(stat)
		to_chat(src, span_warning("You can't go do that when weakened like this."))
		return
	if(src?.buckled_to())
		to_chat(src,span_warning("You can't do that when restrained."))

	open_request(src, /datum/prompt/choice/lleill_ring_action, PROC_REF(lleill_ring_action_chosen), answerer = src, question = "What would you like to do with your rings? You currently have [species.lleill_energy] energy remaining.", choices = list("Spawn New Ring ([energy_cost_spawn])", "Teleport to Ring ([energy_cost_tele])", "Cancel"), energy_cost_spawn = energy_cost_spawn, energy_cost_tele = energy_cost_tele)

/// What to do with the rings; carries both costs.
/datum/prompt/choice/lleill_ring_action
	timeout = 0
	title = "Actions"
	buttons = TRUE
	ask_flags = ASK_CONSCIOUS
	var/energy_cost_spawn
	var/energy_cost_tele

/// Also re-checked: the ring is still one of ours.
/datum/prompt/choice/lleill_ring_teleport
	title = "Teleport"
	question = "Where do you wish to teleport?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/energy_cost

/datum/prompt/choice/lleill_ring_teleport/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/carbon/human/H = answerer
	if(!isnull(value))
		var/obj/structure/glamour_ring/R = value
		if(!istype(R) || QDELETED(R))
			return "gone"
		if(!(value in H.teleporters))
			return "ring gone"
	return H.species.lleill_energy < energy_cost ? "no energy" : null

/mob/living/carbon/human/proc/lleill_ring_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/lleill_ring_action/ask = A.request
	var/r_action = ask.value
	var/energy_cost_spawn = ask.energy_cost_spawn
	var/energy_cost_tele = ask.energy_cost_tele
	if(r_action == "Cancel")
		return
	if(findtext(r_action,"Spawn New Ring"))
		if(species.lleill_energy < energy_cost_spawn)
			to_chat(src, span_warning("You do not have enough energy to do that!"))
			return
		perform_op(src, src, "lleill_ring_spawn", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
		return
	if(findtext(r_action,"Teleport to Ring"))
		if(species.lleill_energy < energy_cost_tele)
			to_chat(src, span_warning("You do not have enough energy to do that!"))
			return
		if(!src.teleporters.len)
			to_chat(src, span_warning("You need to place rings to teleport to them."))
			return
		open_request(src, /datum/prompt/choice/lleill_ring_teleport, PROC_REF(lleill_ring_teleport_chosen), answerer = src, choices = src.teleporters, energy_cost = energy_cost_tele)

/mob/living/carbon/human/proc/lleill_ring_teleport_chosen(datum/act/request/A)
	var/datum/prompt/choice/lleill_ring_teleport/ask = A.request
	if(!A.answer)
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.value) && ask.last_error == "no energy")
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/obj/structure/glamour_ring/R = ask.value
	var/energy_cost_tele = ask.energy_cost
	var/T = get_turf(src)
	play_sfx(T, SFX_SPARKS)
	anim(T,src,'icons/mob/mob.dmi',,"phaseout",,src.dir)

	var/S = get_turf(R)
	src.forceMove(S)
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy -= energy_cost_tele

	fx_sparks(src, 5, FALSE)
	play_sfx(S, SFX_EFFECTS_PHASEIN, 0.25)
	play_sfx(S, SFX_EFFECTS_SPARKS2)
	anim(S,src,'icons/mob/mob.dmi',,"phasein",,src.dir)

	//Would be fun to eat people standing on your ring...
	if(can_be_drop_pred && vore_selected)
		var/list/target_list = src.living_mobs(0)
		if(target_list.len)
			for(var/mob/living/M in target_list)
				if(M.devourable && M.can_be_drop_prey)
					vore_selected.nom_atom(M)
					to_chat(M,span_vwarning("In a bright flash of white light, you suddenly find yourself trapped in \the [src]'s [vore_selected.get_belly_name()]!"))
	species.update_lleill_hud(src)

/datum/power/lleill/contact
	name = "Energy Transfer"
	desc = "Take the energy of another creature by making physical contact with them, the other party must consent. This will make them feel drained."
	verbpath = /mob/living/carbon/human/proc/lleill_contact
	ability_icon_state = "lleill_contact"

/mob/living/carbon/human/proc/lleill_contact()
	set name = "Energy Transfer"
	set desc = "Take the energy of another creature by making physical contact with them, the other party must consent. This will make them feel drained."
	set category = VERB_CAT_ABILITIES_LLEILL
	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.

	var/list/contact_options = list(
		"Kiss (lips)",
		"Kiss (neck)",
		"Bite (neck)",
		"Bite (wrist)",
		"Hold Hand",
		"Embrace",
		"Boop (nose)",
		"Stroke (hair)",
		"Custom"
		)

	if(stat)
		to_chat(src, span_warning("You can't go do that when weakened like this."))
		return

	var/list/targets = list()
	for(var/mob/living/carbon/human/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(M.z != src.z || get_dist(src,M) > 1)
			continue
		if(src == M)
			continue
		targets |= M

	if(!targets.len)
		to_chat(src, span_warning("There is nobody next to you."))
		return
	var/datum/lleill_contact_review/contact = new
	rel_set(contact, nameof(contact.actor), src)
	contact.targets = targets
	contact.contact_options = contact_options
	contact.start()

/// Pick who, pick how (and describe it, for Custom), then they consent. The actor stays
/// conscious throughout.
/datum/lleill_contact_review
	parent_type = /datum/prompt_workflow
	var/mob/living/carbon/human/actor
	var/list/targets
	var/list/contact_options
	var/mob/living/carbon/human/chosen_target
	var/contact_type
	var/custom_text

CAPABILITIES(/datum/lleill_contact_review)
	ref_one(nameof(actor), /mob/living/carbon/human)
	ref_one(nameof(chosen_target), /mob/living/carbon/human)

/datum/prompt/choice/lleill_contact
	timeout = 0

/datum/prompt/choice/lleill_contact/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/datum/lleill_contact_review/contact = owner
	return contact.why_not()

/datum/prompt/text/lleill_contact
	timeout = 0

/datum/prompt/text/lleill_contact/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/lleill_contact_review/contact = owner
	return contact.why_not()

/datum/prompt/yes_no/lleill_contact
	timeout = 0

/datum/prompt/yes_no/lleill_contact/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/lleill_contact_review/contact = owner
	if(QDELETED(contact.actor) || QDELETED(contact.chosen_target))
		return "gone"
	// Refusing the invitation used to stop the flow before its consciousness check.
	return value == FALSE ? null : contact.why_not()

/datum/lleill_contact_review/proc/why_not()
	return QDELETED(actor) ? "gone" : actor.stat != CONSCIOUS ? "not conscious" : null

/datum/lleill_contact_review/proc/start()
	// flow_begin checked the actor before starting; it did not call ended on failure.
	if(why_not())
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(start_step))
	if(!result.ok)
		failed_step("start", result.error)

/datum/lleill_contact_review/proc/start_step()
	open_request(src, /datum/prompt/choice/lleill_contact, PROC_REF(target_chosen), answerer = actor, asker = actor, title = "Make contact", question = "Who do you wish to take energy from?", choices = targets)

/datum/lleill_contact_review/proc/stopped(declined = FALSE)
	if(declined && !QDELETED(actor) && !QDELETED(chosen_target))
		to_chat(actor, span_warning("\The [chosen_target] refuses the contact."))
	retire()

/datum/lleill_contact_review/proc/failed_step(step, error)
	stack_trace("lleill contact step [step]: [error]")
	retire()

/datum/lleill_contact_review/proc/target_chosen(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(target_chosen_step), A)
	if(!result.ok)
		failed_step("target", result.error)

/datum/lleill_contact_review/proc/target_chosen_step(datum/act/request/A)
	if(!A.answer)
		stopped()
		return
	rel_set(src, nameof(chosen_target), A.request.value)
	if(QDELETED(chosen_target))
		stopped()
		return
	open_request(src, /datum/prompt/choice/lleill_contact, PROC_REF(type_chosen), answerer = actor, asker = actor, title = "Contact type", question = "How do you wish to make contact with \the [chosen_target]?", choices = contact_options)

/datum/lleill_contact_review/proc/type_chosen(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(type_chosen_step), A)
	if(!result.ok)
		failed_step("type", result.error)

/datum/lleill_contact_review/proc/type_chosen_step(datum/act/request/A)
	if(QDELETED(chosen_target) || !A.answer)
		stopped(isnull(A.request.value))
		return
	contact_type = A.request.value
	if(contact_type == "Custom")
		open_request(src, /datum/prompt/text/lleill_contact, PROC_REF(custom_entered), answerer = actor, asker = actor, title = "Custom contact", question = "Write a description of how you make contact with \the [chosen_target], from a third person perspective.")
		return
	ask_consent()

/datum/lleill_contact_review/proc/custom_entered(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(custom_entered_step), A)
	if(!result.ok)
		failed_step("custom", result.error)

/datum/lleill_contact_review/proc/custom_entered_step(datum/act/request/A)
	// Closing the old custom prompt supplied an empty answer, then resumed the flow.
	if(QDELETED(chosen_target) || why_not())
		stopped()
		return
	if(!A.answer && !isnull(A.request.value))
		stopped()
		return
	custom_text = A.answer ? A.request.value : ""
	ask_consent()

/datum/lleill_contact_review/proc/ask_consent()
	open_request(src, /datum/prompt/yes_no/lleill_contact, PROC_REF(consented), answerer = chosen_target, asker = actor, title = "Actions", question = "Do you accept the [contact_type] physical contact from \the [actor]?")

/datum/lleill_contact_review/proc/consented(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(consented_step), A)
	if(!result.ok)
		failed_step("consent", result.error)

/datum/lleill_contact_review/proc/consented_step(datum/act/request/A)
	if(QDELETED(actor) || QDELETED(chosen_target))
		stopped()
		return
	if(!A.answer || A.request.value != TRUE)
		stopped(isnull(A.request.value) || A.answer)
		return
	actor.lleill_contact_answered(chosen_target, contact_type, custom_text)
	retire()

/mob/living/carbon/human/proc/lleill_contact_answered(mob/living/carbon/human/chosen_target, contact_type, custom_text)
	if(get_dist(src,chosen_target) > 1)
		to_chat(src, span_warning("You need to be standing next to [chosen_target]."))
		return
	if(contact_type == "Kiss (lips)")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " presses their lips up against %T%'s own."))
	if(contact_type == "Kiss (neck)")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " presses their lips up against %T%'s neck."))
	if(contact_type == "Bite (neck)")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " bites down on %T%'s neck."))
	if(contact_type == "Bite (wrist)")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " bites down on %T%'s wrist."))
	if(contact_type == "Hold Hand")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " takes %T%'s hand into their own."))
	if(contact_type == "Embrace")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " embraces %T%."))
	if(contact_type == "Stroke (hair)")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " runs their hand through %T%'s hair."))
	if(contact_type == "Boop (nose)")
		act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " boops %T% on the nose."))
	if(contact_type == "Custom")
		src.visible_message(span_infoplain("[custom_text]"))
	task_timed(src, 10 SECONDS, target = chosen_target, receiver = src, on_done = PROC_REF(lleill_contact_done), done_args = list(chosen_target), on_fail = PROC_REF(lleill_contact_broken), fail_args = list(chosen_target))
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_contact_broken(mob/living/carbon/human/chosen_target)
	act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " and %T% break contact before energy has been transferred."))

/mob/living/carbon/human/proc/lleill_contact_done(mob/living/carbon/human/chosen_target)
	act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " and %T% complete their contact."))
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy = species.lleill_energy_max
	adjust_nutrition((chosen_target.nutrition / 2))
	to_chat(src, span_warning("You feel revitalised."))
	chosen_target.set_tiredness(chosen_target.tiredness + 70)
	chosen_target.set_nutrition(max((chosen_target.nutrition / 2),75))
	chosen_target.remove_blood(40) //removes enough blood to make them feel a bit woozy, mostly just for flavour
	chosen_target.status_adjust(STAT_BLURRY, 20)
	to_chat(chosen_target, span_warning("You feel considerably weakened for the moment."))
	species.update_lleill_hud(src)

/datum/power/lleill/alchemy
	name = "Alchemy (25)"
	desc = "Convert a potion material into a potion without the use of a base or alembic."
	verbpath = /mob/living/carbon/human/proc/lleill_alchemy
	ability_icon_state = "lleill_alchemy"

/mob/living/carbon/human/proc/lleill_alchemy()
	set name = "Alchemy (25)"
	set desc = "Convert a potion material into a potion without the use of a base or alembic."
	set category = VERB_CAT_ABILITIES_LLEILL

	var/energy_cost = 25


	if(species.lleill_energy < energy_cost)
		to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return

	if(stat)
		to_chat(src, span_warning("You can't go do that when weakened like this."))
		return

	var/obj/item/potion_material/I = get_active_hand()
	if(!I)
		to_chat(src, span_warning("You have no item in your active hand."))
		return

	if(!istype(I))
		to_chat(src, span_warning("\The [I] is not a potion material."))
		return
	var/obj/item/reagent_containers/glass/bottle/potion/transmute_product = I.product_potion

	if(!get_active_hand(I))
		to_chat(src, span_warning("The item is no longer in your hands."))
		return
	else
		act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to change the form of %I%."), item = I)
		task_start(/datum/task/timed/human_lleill_alchemy, src, I, transmute_product = transmute_product, energy_cost = energy_cost)
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_alchemy_stopped(datum/task/timed/human_lleill_alchemy/task)
	var/obj/item/potion_material/I = task.target
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " leaves %I% in its original form."), item = I)

/datum/task/timed/human_lleill_alchemy
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/lleill_alchemy_done
	cancel_proc = /mob/living/carbon/human/proc/lleill_alchemy_stopped
	var/transmute_product
	var/energy_cost

/mob/living/carbon/human/proc/lleill_alchemy_done(datum/task/timed/human_lleill_alchemy/task)
	var/obj/item/potion_material/I = task.target
	var/transmute_product = task.transmute_product
	var/energy_cost = task.energy_cost
	var/obj/item/reagent_containers/glass/bottle/potion/product = transmute_product
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " transmutes %I% into \the [initial(product.name)]."), item = I)
	consume(I, src)
	var/spawnloc = get_turf(src)
	var/obj/item/N = new transmute_product(spawnloc)
	put_in_active_hand(N)
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy -= energy_cost
	species.update_lleill_hud(src)

/datum/power/lleill/beastform
	name = "Beast Form (100)"
	desc = "Take the form of a non-humanoid creature."
	verbpath = /mob/living/carbon/human/proc/lleill_beast_form
	ability_icon_state = "lleill_beast"

/mob/living/carbon/human/proc/lleill_beast_form()
	set name = "Beast Form (100)"
	set desc = "Take the form of a non-humanoid creature."
	set category = VERB_CAT_ABILITIES_LLEILL
	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.

	var/energy_cost = 100

	if(species.lleill_energy < energy_cost)
		to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return

	var/static/list/beast_options = list("Armadillo" = /mob/living/simple_mob/animal/passive/armadillo,
									"Azure Tit" = /mob/living/simple_mob/animal/passive/bird/azure_tit/beastmode,
									"Bear" = /mob/living/simple_mob/animal/space/bear/brown/beastmode,
									"Cat" = /mob/living/simple_mob/animal/passive/cat/black/beastmode,
									"Chicken" = /mob/living/simple_mob/animal/passive/chicken,
									"Cow" = /mob/living/simple_mob/animal/passive/cow,
									"Dire Wolf" = /mob/living/simple_mob/vore/wolf/direwolf,
									"Dog (Bull Terrier)" = /mob/living/simple_mob/animal/passive/dog/bullterrier,
									"Dog (Corgi)" = /mob/living/simple_mob/animal/passive/dog/corgi,
									"Dog (Tamaskan)" = /mob/living/simple_mob/animal/passive/dog/tamaskan,
									"Duck" = /mob/living/simple_mob/animal/sif/duck,
									"Fox" = /mob/living/simple_mob/animal/passive/fox/beastmode,
									"Fox (Fennec)" = /mob/living/simple_mob/vore/fennec,
									"Giant Bat" = /mob/living/simple_mob/vore/bat,
									"Giant Frog" = /mob/living/simple_mob/vore/aggressive/frog,
									"Giant Rat" = /mob/living/simple_mob/vore/aggressive/rat,
									"Giant Snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
									"Goat" = /mob/living/simple_mob/animal/goat,
									"Goose" = /mob/living/simple_mob/animal/space/goose,
									"Horse" = /mob/living/simple_mob/vore/horse,
									"Horse (Big)" = /mob/living/simple_mob/vore/horse/big,
									"Hyena" = /mob/living/simple_mob/animal/hyena,
									"Kelpie" = /mob/living/simple_mob/vore/horse/kelpie,
									"Lion" = /mob/living/simple_mob/vore/retaliate/lion,
									"Lizard" = /mob/living/simple_mob/animal/passive/lizard,
									"Mouse" = /mob/living/simple_mob/animal/passive/mouse/beastmode,
									"Otie" = /mob/living/simple_mob/vore/otie,
									"Panther" = /mob/living/simple_mob/vore/aggressive/panther,
									"Penguin" = /mob/living/simple_mob/animal/passive/penguin,
									"Possum" = /mob/living/simple_mob/animal/passive/opossum/beastmode,
									"Rabbit" = /mob/living/simple_mob/vore/rabbit,
									"Raccoon" = /mob/living/simple_mob/animal/passive/raccoon,
									"Raptor" = /mob/living/simple_mob/vore/raptor,
									"Red Panda" = /mob/living/simple_mob/vore/redpanda,
									"Reindeer" = /mob/living/simple_mob/vore/reindeer,
									"Robin" = /mob/living/simple_mob/animal/passive/bird/european_robin/beastmode,
									"Seagull" = /mob/living/simple_mob/vore/seagull,
									"Sheep" = /mob/living/simple_mob/vore/sheep,
									"Slug" = /mob/living/simple_mob/vore/slug,
									"Squirrel" = /mob/living/simple_mob/vore/squirrel,
									"Wolf" = /mob/living/simple_mob/vore/wolf,
									"Unicorn" = /mob/living/simple_mob/vore/horse/unicorn/beastmode
									)

	open_request(src, /datum/prompt/choice/lleill_beast, PROC_REF(lleill_beast_chosen), answerer = src, choices = beast_options, energy_cost = energy_cost)

/mob/living/carbon/human/proc/lleill_beast_chosen(datum/act/request/A)
	var/datum/prompt/choice/lleill_beast/ask = A.request
	if(!A.answer)
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.value) && ask.last_error == "no energy")
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/list/beast_options = ask.choices
	var/energy_cost = ask.energy_cost
	var/chosen_beast = ask.value

	var/mob/living/M = src
	if(!istype(M))
		return

	if(M.stat)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
		to_chat(src, span_warning("You can't do that in your condition."))
		return

	if(M.vitality() <= 0.1)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
		to_chat(src, span_warning("You are too injured to transform into a beast."))
		return

	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins significantly shifting their form."))
	task_start(/datum/task/timed/human_lleill_beast_form_human, src, src, energy_cost = energy_cost, beast_options = beast_options, chosen_beast = chosen_beast)
	return TRUE

/datum/task/timed/human_lleill_beast_form_human
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/lleill_beast_form_human_done
	cancel_proc = /mob/living/carbon/human/proc/lleill_beast_form_human_failed
	var/energy_cost
	var/list/beast_options
	var/chosen_beast

/mob/living/carbon/human/proc/lleill_beast_form_human_done(datum/task/timed/human_lleill_beast_form_human/task)
	var/energy_cost = task.energy_cost
	var/list/beast_options = task.beast_options
	var/chosen_beast = task.chosen_beast

	var/image/coolanimation = image('icons/obj/glamour.dmi', null, "animation")
	coolanimation.plane = PLANE_LIGHTING_ABOVE
	src.overlays += coolanimation
	after(src, 1 SECOND, PROC_REF(finish_beast_shift), with = list(coolanimation, chosen_beast, beast_options[chosen_beast], energy_cost))
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_beast_form_human_failed(datum/task/timed/human_lleill_beast_form_human/task)
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " ceases shifting their form."))
	return 0

/mob/living/carbon/human/proc/spawn_beast_mob(chosen_beast)
	var/tf_type = chosen_beast
	if(!ispath(tf_type))
		return
	var/new_mob = new tf_type(src.loc)
	return new_mob

/mob/living/proc/revert_beast_form()
	set name = "Revert Beast Form"
	set desc = "Return to your humanoid form."
	set category = VERB_CAT_ABILITIES_LLEILL

	if(stat)
		to_chat(src, span_warning("You can't do that in your condition."))
		return

	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins significantly shifting their form."))
	perform_op(src, src, "revert_beast_form", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)
	return TRUE

/mob/living/proc/revert_beast_form_living_done(datum/act/op/A)
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " has reverted to their original form."))
	revert_beast_tf()

/mob/living/proc/revert_beast_form_living_failed(datum/act/op/A)
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " ceases shifting their form."))
	return 0

/mob/living/proc/revert_beast_tf()
	if(!tf_mob_holder)
		return
	var/mob/living/ourmob = tf_mob_holder
	//legacy ai_holder.set_stance(STANCE_SLEEP) removed; brain auto-sleeps on
	// stat change via its /datum/om/event/mob_statchange handler.
	return_player_to_tf_holder("reverted beast form")
	set_tf_mob_holder(null)
	var/turf/beast_loc = src.loc
	ourmob.forceMove(beast_loc)
	ourmob.forceMove(beast_loc)
	rel_set(ourmob, nameof(ourmob.vore_selected), vore_selected) // a pointer at one of the bellies (vore_organs), never owned
	rel_clear(src, nameof(vore_selected))
	ourmob.mob_belly_transfer(src)

	seq_run_frame_now(ourmob, /datum/sequence/life)

	if(ishuman(src))
		for(var/obj/item/W in contents_of(src))
			if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))
				continue
			src.drop_from_inventory(W)

	replaced_by(src)

//Hanner variant

/datum/power/lleill/beastform_hanner
	name = "Beast Form (100)"
	desc = "Take the form of a non-humanoid creature."
	verbpath = /mob/living/carbon/human/proc/hanner_beast_form
	ability_icon_state = "lleill_beast"

/mob/living/carbon/human/proc/hanner_beast_form()
	set name = "Beast Form (100)"
	set desc = "Take the form of a non-humanoid creature."
	set category = VERB_CAT_ABILITIES_LLEILL
	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.

	var/energy_cost = 100

	if(species.lleill_energy < energy_cost)
		to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return

	var/static/list/beast_options = list("Armadillo" = /mob/living/simple_mob/animal/passive/armadillo,
									"Azure Tit" = /mob/living/simple_mob/animal/passive/bird/azure_tit/beastmode,
									"Bear" = /mob/living/simple_mob/animal/space/bear/brown/beastmode,
									"Cat" = /mob/living/simple_mob/animal/passive/cat/black/beastmode,
									"Chicken" = /mob/living/simple_mob/animal/passive/chicken,
									"Cow" = /mob/living/simple_mob/animal/passive/cow,
									"Dire Wolf" = /mob/living/simple_mob/vore/wolf/direwolf,
									"Dog (Corgi)" = /mob/living/simple_mob/animal/passive/dog/corgi,
									"Dog (Bull Terrier)" = /mob/living/simple_mob/animal/passive/dog/bullterrier,
									"Dog (Tamaskan)" = /mob/living/simple_mob/animal/passive/dog/tamaskan,
									"Duck" = /mob/living/simple_mob/animal/sif/duck,
									"Fox" = /mob/living/simple_mob/animal/passive/fox/beastmode,
									"Fox (Fennec)" = /mob/living/simple_mob/vore/fennec,
									"Giant Bat" = /mob/living/simple_mob/vore/bat,
									"Giant Frog" = /mob/living/simple_mob/vore/aggressive/frog,
									"Giant Rat" = /mob/living/simple_mob/vore/aggressive/rat,
									"Giant Snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
									"Goat" = /mob/living/simple_mob/animal/goat,
									"Goose" = /mob/living/simple_mob/animal/space/goose,
									"Horse" = /mob/living/simple_mob/vore/horse,
									"Horse (Big)" = /mob/living/simple_mob/vore/horse/big,
									"Hyena" = /mob/living/simple_mob/animal/hyena,
									"Kelpie" = /mob/living/simple_mob/vore/horse/kelpie,
									"Lion" = /mob/living/simple_mob/vore/retaliate/lion,
									"Lizard" = /mob/living/simple_mob/animal/passive/lizard,
									"Mouse" = /mob/living/simple_mob/animal/passive/mouse/beastmode,
									"Otie" = /mob/living/simple_mob/vore/otie,
									"Panther" = /mob/living/simple_mob/vore/aggressive/panther,
									"Penguin" = /mob/living/simple_mob/animal/passive/penguin,
									"Possum" = /mob/living/simple_mob/animal/passive/opossum/beastmode,
									"Rabbit" = /mob/living/simple_mob/vore/rabbit,
									"Raccoon" = /mob/living/simple_mob/animal/passive/raccoon,
									"Raptor" = /mob/living/simple_mob/vore/raptor,
									"Red Panda" = /mob/living/simple_mob/vore/redpanda,
									"Reindeer" = /mob/living/simple_mob/vore/reindeer,
									"Robin" = /mob/living/simple_mob/animal/passive/bird/european_robin/beastmode,
									"Seagull" = /mob/living/simple_mob/vore/seagull,
									"Sheep" = /mob/living/simple_mob/vore/sheep,
									"Slug" = /mob/living/simple_mob/vore/slug,
									"Squirrel" = /mob/living/simple_mob/vore/squirrel,
									"Wolf" = /mob/living/simple_mob/vore/wolf,
									"Unicorn" = /mob/living/simple_mob/vore/horse/unicorn/beastmode
									)

	open_request(src, /datum/prompt/choice/lleill_beast, PROC_REF(hanner_beast_chosen), answerer = src, choices = beast_options, energy_cost = energy_cost)

/mob/living/carbon/human/proc/hanner_beast_chosen(datum/act/request/A)
	var/datum/prompt/choice/lleill_beast/ask = A.request
	if(!A.answer)
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.value) && ask.last_error == "no energy")
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/list/beast_options = ask.choices
	var/energy_cost = ask.energy_cost
	var/chosen_beast = ask.value

	var/mob/living/M = src
	if(!istype(M))
		return

	if(M.stat)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
		to_chat(src, span_warning("You can't do that in your condition."))
		return

	if(M.vitality() <= 0.1)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
		to_chat(src, span_warning("You are too injured to transform into a beast."))
		return

	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins significantly shifting their form."))
	task_start(/datum/task/timed/human_hanner_beast_form_human, src, src, energy_cost = energy_cost, beast_options = beast_options, chosen_beast = chosen_beast)
	return TRUE

/datum/task/timed/human_hanner_beast_form_human
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/hanner_beast_form_human_done
	cancel_proc = /mob/living/carbon/human/proc/hanner_beast_form_human_failed
	var/energy_cost
	var/list/beast_options
	var/chosen_beast

/mob/living/carbon/human/proc/hanner_beast_form_human_done(datum/task/timed/human_hanner_beast_form_human/task)
	var/energy_cost = task.energy_cost
	var/list/beast_options = task.beast_options
	var/chosen_beast = task.chosen_beast

	var/image/coolanimation = image('icons/obj/glamour.dmi', null, "animation")
	coolanimation.plane = PLANE_LIGHTING_ABOVE
	src.overlays += coolanimation
	after(src, 1 SECOND, PROC_REF(finish_beast_shift), with = list(coolanimation, chosen_beast, beast_options[chosen_beast], energy_cost))

/// The end of a beast shift, a second after the animation starts.
/mob/living/carbon/human/proc/finish_beast_shift(image/coolanimation, chosen_beast, beast_type, energy_cost)
	overlays -= coolanimation
	var/mob/living/new_mob = spawn_beast_mob(beast_type)
	if(new_mob && isliving(new_mob))
		new_mob.faction = faction
		rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
		species.lleill_energy -= energy_cost
		grant(new_mob, granted_verb(/mob/living/proc/revert_beast_form), new_mob)
		grant(new_mob, granted_verb(/mob/living/proc/set_size), new_mob)
		grant(new_mob, granted_verb(/mob/living/simple_mob/proc/ColorMate), new_mob)
		transfer_mob_identity(new_mob)
		new_mob.visible_message(span_infoplain(span_bold("\The [src]") + " has transformed into \the [chosen_beast]!"))

/mob/living/carbon/human/proc/hanner_beast_form_human_failed(datum/task/timed/human_hanner_beast_form_human/task)
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " ceases shifting their form."))
	return 0
