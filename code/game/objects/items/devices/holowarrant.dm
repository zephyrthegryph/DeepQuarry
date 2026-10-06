/obj/item/holowarrant
	name = "warrant projector"
	desc = "The practical paperwork replacement for the officer on the go."
	icon = 'icons/obj/device.dmi'
	icon_state = "holowarrant"
	item_state = "flashtool"
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 4
	throw_range = 10
	var/datum/data/record/warrant/active
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

//look at it
/obj/item/holowarrant/examine(mob/user)
	. = ..()
	if(active())
		. += "It's a holographic warrant for '[active().fields["namewarrant"]]'."
	if(in_range(user, src) || isobserver(user))
		show_content(user) //Opens a browse window, not chatbox related
	else
		. += span_notice("You have to go closer if you want to read it.")

//hit yourself with it
DECLARE_INTERACTIONS(/obj/item/holowarrant, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/obj/item/holowarrant/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	rel_clear(src, nameof(active))
	var/list/warrants = list()
	if(!isnull(GLOB.data_core.general))
		for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
			warrants += W.fields["namewarrant"]
	if(warrants.len == 0)
		to_chat(user,span_notice("There are no warrants available"))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(warrant_chosen), answerer = user, title = "Warrant Selection", question = "Which warrant would you like to load?", choices = warrants, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)

/// Swiping an ID (the subject, still in hand) to authorize the loaded warrant.
/datum/prompt/yes_no/holowarrant_authorize
	title = "Warrant authorization"
	question = "Would you like to authorize this warrant?"
	timeout = 0
	ask_flags = ASK_HELD | ASK_CAPABLE
	var/obj/item/card/id/card
	var/datum/data/record/warrant/warrant

CAPABILITIES(/datum/prompt/yes_no/holowarrant_authorize)
	ref_one(nameof(card), /obj/item/card/id)
	ref_one(nameof(warrant), /datum/data/record/warrant)

/datum/prompt/yes_no/holowarrant_authorize/prepare(datum/act/A)
	..()
	var/obj/item/card/id/captured_card = card
	var/datum/data/record/warrant/captured_warrant = warrant
	rel_clear(src, nameof(card))
	rel_set(src, nameof(card), captured_card)
	rel_clear(src, nameof(warrant))
	rel_set(src, nameof(warrant), captured_warrant)

/datum/prompt/yes_no/holowarrant_authorize/recheck_extra()
	return QDELETED(card) || QDELETED(warrant) ? "gone" : null

/obj/item/holowarrant/proc/warrant_chosen(datum/act/request/A)
	if(!A.answer)
		return
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		if(W.fields["namewarrant"] == A.answer.value)
			rel_set(src, nameof(active), W)

/obj/item/holowarrant/proc/authorize_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/yes_no/holowarrant_authorize/ask = A.answer
	var/mob/user = ask.answerer
	var/obj/item/card/id/I = ask.card
	if(ask.value && active() == ask.warrant)
		active().fields["auth"] = "[I.registered_name] - [I.assignment ? I.assignment : "(Unknown)"]"
	act_message(user, src, MSG_SELF(span_notice("You swipe \the [I] through %T%.")), \
		MSG_OTHERS(span_notice("%U% swipes \the [I] through %T%.")))

/obj/item/holowarrant/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(active())
		var/obj/item/card/id/I = W.GetIdCard()
		if(I && (ACCESS_HOS in I.GetAccess()))
			open_request(src, /datum/prompt/yes_no/holowarrant_authorize, PROC_REF(authorize_answered), answerer = user, subject = W, card = I, warrant = active())
			return TRUE
		to_chat(user, span_warning("You don't have the access to do this!"))
		return TRUE
	return FALSE

//hit other people with it
/obj/item/holowarrant/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	act_message(user, M, MSG_SELF(span_notice("You show the warrant to %T%.")), \
		MSG_OTHERS(span_notice("%U% holds up a warrant projector and shows the contents to %T%.")))
	M.examinate(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/holowarrant/proc/appearance_active()
	return active() ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/holowarrant/draw(datum/look/look)
	..()
	look.state("[appearance_active() ? "holowarrant_filled" : "holowarrant"]")

// show_content moved to code/modules/holowarrant_panel.dm (structured TGUI).

/obj/item/storage/box/holowarrants // addition starts
	name = "holowarrant devices"
	desc = "A box of holowarrant displays for security use."

/obj/item/storage/box/holowarrants/Initialize(mapload)
	. = ..()
	for(var/i = 0 to 3)
		new /obj/item/holowarrant(src) // addition ends

/// Relation view: active (reads null once it is gone).
/obj/item/holowarrant/proc/active() as /datum/data/record/warrant
	return active
