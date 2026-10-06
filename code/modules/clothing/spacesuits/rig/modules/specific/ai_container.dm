/obj/item/ai_verbs
	name = "AI verb holder"

/obj/item/ai_verbs/verb/hardsuit_interface()
	set category = VERB_CAT_HARDSUIT
	set name = "Open Hardsuit Interface"
	set src in usr

	if(!usr.loc || !usr.loc.loc || !istype(usr.loc.loc, /obj/item/rig_module))
		to_chat(usr, "You are not loaded into a hardsuit.")
		return

	var/obj/item/rig_module/module = usr.loc.loc
	if(!module.holder)
		to_chat(usr, "Your module is not installed in a hardsuit.")
		return

	module.holder.tgui_interact(usr, custom_state = GLOB.tgui_contained_state)

/obj/item/rig_module/ai_container

	name = "IIS module"
	desc = "An integrated intelligence system module suitable for most hardsuits."
	icon_state = "IIS"
	toggleable = 1
	usable = 1
	disruptive = 0
	activates_on_touch = 1

	engage_string = "Eject AI"
	activate_string = "Enable Core Transfer"
	deactivate_string = "Disable Core Transfer"

	interface_name = "integrated intelligence system"
	interface_desc = "A socket that supports a range of artificial intelligence systems."

	var/tmp/mob/integrated_ai	// Direct reference to the actual mob held in the suit.
	var/obj/item/aicard/ai_card  // Reference to the MMI, posibrain, intellicard or pAI card previously holding the AI.
	var/obj/item/ai_verbs/verb_holder

CAPABILITIES(/obj/item/rig_module/ai_container)
	owns_one(nameof(verb_holder), /obj/item/ai_verbs)

/obj/item/rig_module/ai_container/periodic_step()
	if(integrated_ai())
		var/obj/item/rig/rig = get_rig()
		if(rig && rig.ai_override_enabled)
			integrated_ai().get_rig_stats = 1
		else
			integrated_ai().get_rig_stats = 0

/obj/item/rig_module/ai_container/proc/update_verb_holder()
	if(!verb_holder)
		rel_set(src, nameof(verb_holder), new /obj/item/ai_verbs(src))
	if(integrated_ai())
		verb_holder.forceMove(integrated_ai())
	else
		verb_holder.forceMove(src)

/obj/item/rig_module/ai_container/accepts_item(obj/item/input_device, mob/living/user)

	// Check if there's actually an AI to deal with.
	var/mob/living/silicon/ai/target_ai
	if(isAI(input_device))
		target_ai = input_device
	else
		target_ai = locate_within(input_device, /mob/living/silicon/ai)

	var/obj/item/aicard/card = ai_card

	// Downloading from/loading to a terminal.
	if(istype(input_device,/obj/machinery/computer/aifixer) || istype(input_device,/mob/living/silicon/ai) || istype(input_device,/obj/structure/AIcore/deactivated))

		// If we're stealing an AI, make sure we have a card for it.
		if(!card)
			card = new /obj/item/aicard(src)

		// Terminal interaction only works with an intellicarded AI.
		if(!istype(card))
			return 0

		// Since we've explicitly checked for three types, this should be safe.
		input_device.attackby(card,user)

		// If the transfer failed we can delete the card.
		if(locate_in_list(card, /mob/living/silicon/ai))
			rel_set(src, nameof(ai_card), card)
			rel_set(src, nameof(integrated_ai), locate_in_list(card, /mob/living/silicon/ai))
		else
			eject_ai()
		update_verb_holder()
		return 1

	if(istype(input_device,/obj/item/aicard))
		// We are carding the AI in our suit.
		if(integrated_ai())
			integrated_ai().attackby(input_device,user)
			// If the transfer was successful, we can clear out our vars.
			if(integrated_ai().loc != src)
				rel_clear(src, nameof(integrated_ai))
				eject_ai()
		else
			// You're using an empty card on an empty suit, idiot.
			if(!target_ai)
				return 0
			integrate_ai(input_device,user)
		return 1

	// Okay, it wasn't a terminal being touched, check for all the simple insertions.
	if(istype(input_device, /obj/item/paicard) || istype(input_device, /obj/item/mmi))
		if(integrated_ai())
			integrated_ai().attackby(input_device,user)
			// If the transfer was successful, we can clear out our vars.
			if(integrated_ai().loc != src)
				rel_clear(src, nameof(integrated_ai))
				eject_ai()
		else
			integrate_ai(input_device,user)
		return 1

	return 0

/obj/item/rig_module/ai_container/engage(atom/target, notify_ai, mob/user)

	if(!..())
		return 0

	var/mob/living/carbon/human/H = holder.wearer()

	if(!target)
		if(ai_card)
			if(istype(ai_card,/obj/item/aicard))
				ai_card.tgui_interact(H, custom_state = GLOB.tgui_deep_inventory_state)
			else
				eject_ai(H)
		update_verb_holder()
		return 1

	if(accepts_item(target,H))
		return 1

	return 0

/obj/item/rig_module/ai_container/removed()
	eject_ai()
	..()

/obj/item/rig_module/ai_container/proc/eject_ai(mob/user)

	if(ai_card)
		if(istype(ai_card, /obj/item/aicard))
			if(integrated_ai() && !integrated_ai().stat)
				if(user)
					to_chat(user, span_danger("You cannot eject your currently stored AI. Purge it manually."))
				return 0
			to_chat(user, span_danger("You purge the previous AI from your Integrated Intelligence System, freeing it for use."))
			if(integrated_ai())
				integrated_ai().ghostize()
				spent(integrated_ai(), user)
				rel_clear(src, nameof(integrated_ai))
			if(ai_card)
				rel_clear(src, nameof(ai_card), OWN_DELETE)
		else if(user)
			user.put_in_hands(ai_card)
		else
			ai_card.forceMove(get_turf(src))
	rel_take(src, nameof(ai_card))
	rel_clear(src, nameof(integrated_ai))
	update_verb_holder()

/obj/item/rig_module/ai_container/proc/integrate_ai(obj/item/ai,mob/user)
	if(!ai) return

	// The ONLY THING all the different AI systems have in common is that they all store the mob inside an item.
	var/mob/living/ai_mob = locate_within(ai, /mob/living)
	if(ai_mob)

		if(ai_mob.key && ai_mob.client)

			if(istype(ai, /obj/item/aicard))

				if(!ai_card)
					rel_set(src, nameof(ai_card), new /obj/item/aicard(src))

				var/obj/item/aicard/source_card = ai
				var/obj/item/aicard/target_card = ai_card
				if(istype(source_card) && istype(target_card))
					if(target_card.grab_ai(ai_mob, user))
						source_card.clear()
					else
						return 0
				else
					return 0
			else
				if(!move_into(src, nameof(src.ai_card), ai, user))
					return 0
				to_chat(ai_mob, span_blue("You have been transferred to \the [holder]'s [src]."))
				to_chat(user, span_blue("You load [ai_mob] into \the [holder]'s [src]."))

			rel_set(src, nameof(integrated_ai), ai_mob)

			if(!(locate(integrated_ai()) in ai_card))
				rel_clear(src, nameof(integrated_ai))
				eject_ai()
		else
			to_chat(user, span_warning("There is no active AI within \the [ai]."))
	else
		to_chat(user, span_warning("There is no active AI within \the [ai]."))
	update_verb_holder()
	return


/obj/item/rig_module/ai_container/ownership()
	. = ..()
	. += owns(nameof(ai_card), policy = OWN_CONTAINED)

/// Direct reference to the actual mob held in the suit. (a relation view: null once it is deleted).
/obj/item/rig_module/ai_container/proc/integrated_ai() as /mob
	return integrated_ai
