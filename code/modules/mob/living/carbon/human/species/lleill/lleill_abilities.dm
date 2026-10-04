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
		proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
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

	COOLDOWN_START(src, last_special, 50)

	om_ask(src, /datum/om/prompt/choice/shapeshifter_form, PROC_REF(lleill_shape_chosen), choices = species.get_valid_shapeshifter_forms(src))

/mob/living/carbon/human/proc/lleill_shape_chosen(datum/om/prompt/choice/shapeshifter_form/ask)
	lleill_change_shape(ask.choice)

/mob/living/carbon/human/proc/lleill_change_shape(new_species = null)
	if(!new_species)
		return

	GLOB.wrapped_species_by_ref["\ref[src]"] = new_species
	dna.base_species = new_species
	proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.base_species = new_species
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " shifts and contorts, taking the form of \a [new_species]!"))
	regenerate_icons()

/mob/living/carbon/human/proc/lleill_select_colour()

	set name = "Select Body Colour"
	set category = VERB_CAT_ABILITIES_LLEILL

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	open_request(src, /datum/prompt/color, PROC_REF(lleill_colour_chosen), answerer = src, title = "Shapeshifter Colour", question = "Please select a new body color.", default = rgb(r_skin, g_skin, b_skin), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/lleill_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	lleill_set_colour(A.answer.answer_value)

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

	om_ask(src, /datum/om/prompt/choice/lleill_energy/lleill_transmute, PROC_REF(lleill_transmute_chosen), choices = transmute_list, energy_cost = energy_cost, item = I)

/// A Lleill power's pick that costs energy. Re-checked on the answer: conscious, and still
/// enough energy.
/datum/om/prompt/choice/lleill_energy
	ask_flags = ASK_CONSCIOUS
	var/energy_cost

/datum/om/prompt/choice/lleill_energy/valid()
	var/mob/living/carbon/human/H = answerer
	if(H.species.lleill_energy < energy_cost)
		to_chat(H, span_warning("You do not have enough energy to do that! You currently have [H.species.lleill_energy] energy."))
		return "no energy"
	return null

/// Also re-checked: the item is still in the active hand.
/datum/om/prompt/choice/lleill_energy/lleill_transmute
	title = "Transmutation"
	message = "Choose a glamour to transmute the item into:"
	var/obj/item/item

/datum/om/prompt/choice/lleill_energy/lleill_transmute/valid()
	var/mob/living/carbon/human/H = answerer
	if(H.get_active_hand() != item)
		to_chat(H, span_warning("The item is no longer in your hands."))
		return "not in hand"
	return ..()

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

/mob/living/carbon/human/proc/lleill_transmute_chosen(datum/om/prompt/choice/lleill_energy/lleill_transmute/ask)
	var/obj/item/I = ask.item
	var/energy_cost = ask.energy_cost
	var/obj/item/transmute_product = ask.choices[ask.choice]
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to change the form of %I%."), item = I)
	om_task_start(/datum/om/task/timed/human_lleill_transmute_human, src, I, energy_cost = energy_cost, transmute_product = transmute_product)

/datum/om/task/timed/human_lleill_transmute_human
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/lleill_transmute_human_done
	cancel_proc = /mob/living/carbon/human/proc/lleill_transmute_human_failed
	var/energy_cost
	var/obj/item/transmute_product

/mob/living/carbon/human/proc/lleill_transmute_human_done(datum/om/task/timed/human_lleill_transmute_human/task)
	var/energy_cost = task.energy_cost
	var/obj/item/I = task.target
	var/obj/item/transmute_product = task.transmute_product
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " transmutes %I% into \the [transmute_product.name]."), item = I)
	consume(I, src)
	var/spawnloc = get_turf(src)
	var/obj/item/N = new transmute_product(spawnloc)
	put_in_active_hand(N)
	proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy -= energy_cost
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_transmute_human_failed(datum/om/task/timed/human_lleill_transmute_human/task)
	var/obj/item/I = task.target
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " leaves %I% in its original form."), item = I)
	return 0

/datum/power/lleill/rings
	name = "Glamour Rings"
	desc = "Place or teleport to a glamour ring."
	verbpath = /mob/living/carbon/human/proc/lleill_rings
	ability_icon_state = "lleill_ring"

/mob/living/carbon/human/proc/lleill_ring_interrupted()
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to form white rings on the ground."))

/mob/living/carbon/human/proc/lleill_ring_placed(energy_cost_spawn)
	if(species.lleill_energy < energy_cost_spawn)
		return
	to_chat(src, span_warning("You place a new glamour ring at your feet."))
	var/spawnloc = get_turf(src)
	var/obj/structure/glamour_ring/R = new(spawnloc)
	R.connected_mob = src
	rel_add(src, nameof(teleporters), R)
	proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
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
	if(!isnull(answer_value))
		var/obj/structure/glamour_ring/R = answer_value
		if(!istype(R) || QDELETED(R))
			return "gone"
		if(!(answer_value in H.teleporters))
			return "ring gone"
	return H.species.lleill_energy < energy_cost ? "no energy" : null

/mob/living/carbon/human/proc/lleill_ring_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/lleill_ring_action/ask = A.request
	var/r_action = ask.answer_value
	var/energy_cost_spawn = ask.energy_cost_spawn
	var/energy_cost_tele = ask.energy_cost_tele
	if(r_action == "Cancel")
		return
	if(findtext(r_action,"Spawn New Ring"))
		if(species.lleill_energy < energy_cost_spawn)
			to_chat(src, span_warning("You do not have enough energy to do that!"))
			return
		om_task_timed(src, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(lleill_ring_placed), done_args = list(energy_cost_spawn), on_fail = PROC_REF(lleill_ring_interrupted))
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
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.answer_value) && ask.last_error == "no energy")
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/obj/structure/glamour_ring/R = ask.answer_value
	var/energy_cost_tele = ask.energy_cost
	var/T = get_turf(src)
	play_sfx(T, SFX_SPARKS)
	anim(T,src,'icons/mob/mob.dmi',,"phaseout",,src.dir)

	var/S = get_turf(R)
	src.forceMove(S)
	proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
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
	om_flow_start(/datum/om/flow/lleill_contact, src, null, targets = targets, contact_options = contact_options)

/// Pick who, pick how (and describe it, for Custom), then they consent. The actor stays
/// conscious throughout.
/datum/om/flow/lleill_contact
	requires = PROMPT_CONSCIOUS
	var/list/targets
	var/list/contact_options
	var/mob/living/carbon/human/chosen_target
	var/contact_type
	var/custom_text

/datum/om/flow/lleill_contact/ended(reason)
	if(actor && chosen_target && (reason == "declined" || reason == "cancelled"))
		to_chat(actor, span_warning("\The [chosen_target] refuses the contact."))

/datum/om/flow/lleill_contact/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(target_chosen), message = "Who do you wish to take energy from?", title = "Make contact", choices = targets)

/datum/om/flow/lleill_contact/proc/target_chosen(datum/om/prompt/choice/ask)
	rel_set(src, nameof(chosen_target), ask.choice)
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(type_chosen), message = "How do you wish to make contact with \the [chosen_target]?", title = "Contact type", choices = contact_options)

/datum/om/flow/lleill_contact/proc/type_chosen(datum/om/prompt/choice/ask)
	contact_type = ask.choice
	if(contact_type == "Custom")
		om_ask(actor, /datum/om/prompt/text, PROC_REF(custom_entered), message = "Write a description of how you make contact with \the [chosen_target], from a third person perspective.", title = "Custom contact", cancel_answer = "")
		return
	ask_consent()

/datum/om/flow/lleill_contact/proc/custom_entered(datum/om/prompt/text/ask)
	custom_text = ask.text
	ask_consent()

/datum/om/flow/lleill_contact/proc/ask_consent()
	om_ask(chosen_target, /datum/om/prompt/confirm, PROC_REF(consented), message = "Do you accept the [contact_type] physical contact from \the [actor]?", title = "Actions")

/datum/om/flow/lleill_contact/proc/consented(datum/om/prompt/confirm/ask)
	var/mob/living/carbon/human/H = actor
	H.lleill_contact_answered(chosen_target, contact_type, custom_text)

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
	om_task_timed(src, 10 SECONDS, target = chosen_target, receiver = src, on_done = PROC_REF(lleill_contact_done), done_args = list(chosen_target), on_fail = PROC_REF(lleill_contact_broken), fail_args = list(chosen_target))
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_contact_broken(mob/living/carbon/human/chosen_target)
	act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " and %T% break contact before energy has been transferred."))

/mob/living/carbon/human/proc/lleill_contact_done(mob/living/carbon/human/chosen_target)
	act_message(src, chosen_target, others = span_infoplain(span_bold("%U%") + " and %T% complete their contact."))
	proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.lleill_energy = species.lleill_energy_max
	adjust_nutrition((chosen_target.nutrition / 2))
	to_chat(src, span_warning("You feel revitalised."))
	chosen_target.set_tiredness(chosen_target.tiredness + 70)
	chosen_target.set_nutrition(max((chosen_target.nutrition / 2),75))
	chosen_target.remove_blood(40) //removes enough blood to make them feel a bit woozy, mostly just for flavour
	chosen_target.status_adjust(EFFECT_BLURRY, 20)
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
		om_task_start(/datum/om/task/timed/human_lleill_alchemy, src, I, transmute_product = transmute_product, energy_cost = energy_cost)
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_alchemy_stopped(datum/om/task/timed/human_lleill_alchemy/task)
	var/obj/item/potion_material/I = task.target
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " leaves %I% in its original form."), item = I)

/datum/om/task/timed/human_lleill_alchemy
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/lleill_alchemy_done
	cancel_proc = /mob/living/carbon/human/proc/lleill_alchemy_stopped
	var/transmute_product
	var/energy_cost

/mob/living/carbon/human/proc/lleill_alchemy_done(datum/om/task/timed/human_lleill_alchemy/task)
	var/obj/item/potion_material/I = task.target
	var/transmute_product = task.transmute_product
	var/energy_cost = task.energy_cost
	var/obj/item/reagent_containers/glass/bottle/potion/product = transmute_product
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " transmutes %I% into \the [initial(product.name)]."), item = I)
	consume(I, src)
	var/spawnloc = get_turf(src)
	var/obj/item/N = new transmute_product(spawnloc)
	put_in_active_hand(N)
	proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
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
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.answer_value) && ask.last_error == "no energy")
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/list/beast_options = ask.choices
	var/energy_cost = ask.energy_cost
	var/chosen_beast = ask.answer_value

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
	om_task_start(/datum/om/task/timed/human_lleill_beast_form_human, src, src, energy_cost = energy_cost, beast_options = beast_options, chosen_beast = chosen_beast)
	return TRUE

/datum/om/task/timed/human_lleill_beast_form_human
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/lleill_beast_form_human_done
	cancel_proc = /mob/living/carbon/human/proc/lleill_beast_form_human_failed
	var/energy_cost
	var/list/beast_options
	var/chosen_beast

/mob/living/carbon/human/proc/lleill_beast_form_human_done(datum/om/task/timed/human_lleill_beast_form_human/task)
	var/energy_cost = task.energy_cost
	var/list/beast_options = task.beast_options
	var/chosen_beast = task.chosen_beast

	var/image/coolanimation = image('icons/obj/glamour.dmi', null, "animation")
	coolanimation.plane = PLANE_LIGHTING_ABOVE
	src.overlays += coolanimation
	after(src, 1 SECOND, PROC_REF(finish_beast_shift), with = list(coolanimation, chosen_beast, beast_options[chosen_beast], energy_cost))
	species.update_lleill_hud(src)

/mob/living/carbon/human/proc/lleill_beast_form_human_failed(datum/om/task/timed/human_lleill_beast_form_human/task)
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
	om_task_timed(src, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(revert_beast_form_living_done), done_args = list(), on_fail = PROC_REF(revert_beast_form_living_failed), fail_args = list())
	return TRUE

/mob/living/proc/revert_beast_form_living_done()
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " has reverted to their original form."))
	revert_beast_tf()

/mob/living/proc/revert_beast_form_living_failed()
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

	om_run_frame_now(ourmob, /datum/om/pipeline/life)

	if(ishuman(src))
		for(var/obj/item/W in contents_of(src))
			if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))
				continue
			src.drop_from_inventory(W)

	qdel(src)

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
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.answer_value) && ask.last_error == "no energy")
			to_chat(src, span_warning("You do not have enough energy to do that! You currently have [species.lleill_energy] energy."))
		return
	var/list/beast_options = ask.choices
	var/energy_cost = ask.energy_cost
	var/chosen_beast = ask.answer_value

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
	om_task_start(/datum/om/task/timed/human_hanner_beast_form_human, src, src, energy_cost = energy_cost, beast_options = beast_options, chosen_beast = chosen_beast)
	return TRUE

/datum/om/task/timed/human_hanner_beast_form_human
	duration = 10 SECONDS
	complete_proc = /mob/living/carbon/human/proc/hanner_beast_form_human_done
	cancel_proc = /mob/living/carbon/human/proc/hanner_beast_form_human_failed
	var/energy_cost
	var/list/beast_options
	var/chosen_beast

/mob/living/carbon/human/proc/hanner_beast_form_human_done(datum/om/task/timed/human_hanner_beast_form_human/task)
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
		proto_private(src, nameof(species)) // per-mob change: never mutate the shared species
		species.lleill_energy -= energy_cost
		grant(new_mob, granted_verb(/mob/living/proc/revert_beast_form), new_mob)
		grant(new_mob, granted_verb(/mob/living/proc/set_size), new_mob)
		grant(new_mob, granted_verb(/mob/living/simple_mob/proc/ColorMate), new_mob)
		transfer_mob_identity(new_mob)
		new_mob.visible_message(span_infoplain(span_bold("\The [src]") + " has transformed into \the [chosen_beast]!"))

/mob/living/carbon/human/proc/hanner_beast_form_human_failed(datum/om/task/timed/human_hanner_beast_form_human/task)
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " ceases shifting their form."))
	return 0
