// quickdraw(starts) (doc/rewrite/final_api.html, section 11 "Containers and slots"): a storage worn for a quick hand to its contents.
//
//   CAPABILITIES(/obj/item/storage/quickdraw, quickdraw(starts = nameof(/obj/item/storage/quickdraw::quickmode)))
//
// State key QUICKDRAW_DRAWS. While it is on, an empty hand on a case the person carries hands over its first item instead of opening it; off, the case
// is an ordinary storage. A case in a pocket opens on a touch whatever the mode (a pocketed storage otherwise comes to the hand). Alt-clicking a
// carried case opens or closes it and switches the mode, and the menu entry "Switch Quickdraw Mode" switches it alone. `starts` is TRUE, or the name
// of a holder var that says whether the case starts in quickdraw mode.
//
// Ops (all keyed "quickdraw.<name>"): draw, switch_alt, switch.

MSG_DEF_SELF(quickdraw/draws, "%T% now draws the first object inside.")
MSG_DEF_SELF(quickdraw/opens, "%T% now opens as a container.")
MSG_DEF_SELF(quickdraw/is_off, "It opens as a container.")

CAPABILITY_TYPE(quickdraw, CAP_QUICKDRAW, /datum/capability/lib/quickdraw, key = NONE, starts = null)
cap_keys(CAP_QUICKDRAW, DRAWS = MSG(quickdraw/is_off))

/datum/capability/lib/quickdraw
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/quickdraw/entries()
	return list(
		op("draw", hand(), priority(above("storage.open")), when(CAP_PROC(draws_by_hand)), label("Draw"), then(CAP_PROC(draw_or_open))),
		op("switch_alt", hand(), answers(INTENT_TOGGLE), priority(above("storage.toggle_open")), when(CAP_PROC(carried_by_actor)), label("Switch quickdraw mode"), then(CAP_PROC(alt_switch))),
		op("switch", menu(), label("Switch Quickdraw Mode"), needs(carried()), toggles(QUICKDRAW_DRAWS), says(CAP_PROC(switched_message))))

/// A case that starts in quickdraw mode is in it from the moment its holder initializes.
/datum/capability/lib/quickdraw/on_holder_init(datum/act/eval/A)
	var/wanted = starts
	if(istext(wanted))
		wanted = A.holder.vars[wanted]
	if(wanted)
		cap_key_set(A.holder, QUICKDRAW_DRAWS, TRUE, null)

/// What the mode switch just did.
/datum/capability/lib/quickdraw/proc/switched_message(datum/act/A)
	return quickdraw_draws(A.holder) ? /datum/msg/quickdraw/draws : /datum/msg/quickdraw/opens

/// A human's empty hand on a case they carry that draws, or that sits in a pocket.
/datum/capability/lib/quickdraw/proc/draws_by_hand(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	var/obj/item/storage/S = A.holder
	if(!istype(H) || S.loc != H || !isnull(A.held) || H.get_active_hand())
		return FALSE
	if(quickdraw_draws(S) && (length(S.slot_contents(CONTAINER_SLOT_STORAGE)) || S.has_latent()))
		return TRUE
	return H.get_equipped_item(SLOT_ID_POCKET_L) == S || H.get_equipped_item(SLOT_ID_POCKET_R) == S

/datum/capability/lib/quickdraw/proc/draw_or_open(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	var/obj/item/storage/S = A.holder
	S.make_contents_real()
	if(quickdraw_draws(S) && length(S.slot_contents(CONTAINER_SLOT_STORAGE)))
		var/first_item = S.slot_contents(CONTAINER_SLOT_STORAGE)[1]
		if(first_item)
			H.put_in_hands(first_item)
			return OP_OK
	S.open(H)
	return OP_OK

/datum/capability/lib/quickdraw/proc/carried_by_actor(datum/act/op/A)
	var/atom/holder = A.holder
	return holder.loc == A.actor

/// The alt-click opens or closes a carried case, and switches its mode.
/datum/capability/lib/quickdraw/proc/alt_switch(datum/act/op/A)
	var/obj/item/storage/S = A.holder
	S.toggle_window(A.actor)
	cap_key_set(S, QUICKDRAW_DRAWS, !quickdraw_draws(S), null)
	to_chat(A.actor, quickdraw_draws(S) ? "[S] now draws the first object inside." : "[S] now opens as a container.")
	return OP_OK
