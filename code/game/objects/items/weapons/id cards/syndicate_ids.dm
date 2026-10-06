/obj/item/card/id/syndicate
	name = "agent card"
	icon_state = "generic-s"
	assignment = "Agent"
	var/electronic_warfare = 1
	var/mob/registered_user

	var/tmp/datum/tgui_module/agentcard/agentcard_module

// agentcard_module is rebuilt fresh by Initialize() every time (like reset_icon());
// registered_user is a mob ref (and a live observer registration) (C5).
/obj/item/card/id/syndicate/state_exclude()
	return ..() + list("agentcard_module", "registered_user")

/obj/item/card/id/syndicate/Initialize(mapload)
	. = ..()
	access = GLOB.syndicate_access.Copy()

/obj/item/card/id/syndicate/station_access/Initialize(mapload)
	. = ..() // Same as the normal Syndicate id, only already has all station access
	access |= SSaccess.get_all_station_access()

CAPABILITIES(/obj/item/card/id/syndicate)
	owns_one(nameof(agentcard_module), /datum/tgui_module/agentcard, starts = /datum/tgui_module/agentcard)
	without("show") // its own self-use edits or shows the card
	op("agent_card", in_hand(), label("Edit or show"), then(PROC_REF(interaction_agent_card)))

// the card's registered user is unset.
/obj/item/card/id/syndicate/on_destroy(force)
	unset_registered_user(registered_user())
	..()

/obj/item/card/id/syndicate/prevent_tracking()
	return electronic_warfare

/obj/item/card/id/syndicate/afterattack(obj/item/O as obj, mob/user as mob, proximity)
	if(!proximity) return
	if(istype(O, /obj/item/card/id))
		var/obj/item/card/id/I = O
		src.access |= I.GetAccess()
		if(SSantag.player_is_antag(user.mind) || registered_user() == user)
			to_chat(user, span_notice("The microscanner activates as you pass it over the ID, copying its access."))

/// Edit or show an agent ID. Re-checked on the answer: still carried by its registered owner.
/datum/prompt/choice/agent_id_mode
	title = "Show or Edit?"
	question = "Would you like to edit the ID, or show it?"
	timeout = 0
	recheck_on_open = TRUE
	choices = list("Edit", "Show")
	buttons = TRUE
	ask_flags = ASK_CARRIED | ASK_CAPABLE

/datum/prompt/choice/agent_id_mode/recheck_extra()
	var/obj/item/card/id/syndicate/card = owner
	return card.registered_user() == answerer ? null : "not the owner"

/obj/item/card/id/syndicate/proc/edit_or_show_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/mob/user = context.request.answerer
	switch(context.answer.value)
		if("Edit")
			agentcard_module.tgui_interact(user)
		if("Show")
			show_id_card(user)

/// Old attack_self: the card registers its first user, who can then edit or show it.
/obj/item/card/id/syndicate/proc/interaction_agent_card(datum/act/op/A)
	var/mob/user = A.actor
	// We use the fact that registered_name is not unset should the owner be vaporized, to ensure the id doesn't magically become unlocked.
	if(!registered_user() && register_user(user))
		to_chat(user, span_notice("The microscanner marks you as its owner, preventing others from accessing its internals."))
	if(registered_user() == user)
		open_request(src, /datum/prompt/choice/agent_id_mode, PROC_REF(edit_or_show_chosen), answerer = user)
		return

/obj/item/card/id/syndicate/proc/register_user(mob/user)
	if(!istype(user) || user == registered_user())
		return FALSE
	unset_registered_user()
	rel_set(src, nameof(registered_user), user)
	user.set_id_info(src)
	user.register(OBSERVER_EVENT_DESTROY, src, /obj/item/card/id/syndicate/proc/unset_registered_user)
	return TRUE

/obj/item/card/id/syndicate/proc/unset_registered_user(mob/user)
	if(!registered_user() || (user && user != registered_user()))
		return
	registered_user().unregister(OBSERVER_EVENT_DESTROY, src)
	rel_clear(src, nameof(registered_user))

/proc/id_card_states()
	if(!GLOB.id_card_states)
		GLOB.id_card_states = list()
		for(var/path in typesof(/obj/item/card/id))
			var/obj/item/card/id/ID = new path()
			var/datum/card_state/CS = new()
			CS.icon_state = initial(ID.icon_state)
			CS.item_state = initial(ID.item_state)
			CS.sprite_stack = ID.initial_sprite_stack
			CS.name = initial(ID.name)
			GLOB.id_card_states += CS
		GLOB.id_card_states = dd_sortedObjectList(GLOB.id_card_states)

	return GLOB.id_card_states

/datum/card_state
	var/name
	var/icon_state
	var/item_state
	var/sprite_stack

/datum/card_state/dd_SortValue()
	return name

/obj/item/card/id/syndicate_command
	name = "operative ID card"
	desc = "An ID straight from a mercenary organisation."
	registered_name = "Operative"
	assignment = "Operative Commander"
	icon_state = "syndicate-id"
	access = list(ACCESS_SYNDICATE, ACCESS_EXTERNAL_AIRLOCKS)

/// Relation view: registered user (reads null once it is gone).
/obj/item/card/id/syndicate/proc/registered_user() as /mob
	return registered_user
