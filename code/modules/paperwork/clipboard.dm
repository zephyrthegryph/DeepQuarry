/obj/item/clipboard
	name = "clipboard"
	desc = "Used to clip paper to, for an on-the-go writing board."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "clipboard"
	item_state = "clipboard"
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	throw_speed = 3
	throw_range = 10
	var/tmp/obj/item/pen/haspen	//The stored pen.
	var/tmp/obj/item/toppaper	//The topmost piece of paper.
	slot_flags = SLOT_BELT

/obj/item/clipboard/Initialize(mapload)
	. = ..()
	update_icon()

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/clipboard/proc/mousedrop_input(datum/act/input/A)
	if(!handle_hand_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/clipboard/proc/handle_hand_drop(mob/user, obj/over_object)
	if(ishuman(user))
		var/mob/M = user
		if(!(istype(over_object, /atom/movable/screen) ))
			return FALSE

		if(!M.restrained() && !M.stat)
			switch(over_object.name)
				if("r_hand")
					M.unEquip(src)
					M.put_in_r_hand(src)
				if("l_hand")
					M.unEquip(src)
					M.put_in_l_hand(src)

			add_fingerprint(user)
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/item/clipboard, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/clipboard/appearance_overlays()
	. = list()
	if(toppaper())
		. += toppaper().icon_state
		. += toppaper().overlays
	if(haspen())
		. += "clipboard_pen"
	. += "clipboard_over"
	return .

/// Old attackby.
/obj/item/clipboard/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)

	if(istype(W, /obj/item/paper) || istype(W, /obj/item/photo))
		if(!own_bring_in(src, nameof(contents), W, null, user, TRUE, null, FALSE))
			return INTERACTION_HANDLED_PASS
		if(istype(W, /obj/item/paper))
			rel_set(src, nameof(toppaper), W)
		to_chat(user, span_notice("You clip the [W] onto \the [src]."))
		update_icon()

	else if(istype(toppaper(), /obj/item) && istype(W, /obj/item/pen))
		toppaper().attackby(W, user)
		update_icon()

	return INTERACTION_HANDLED_PASS

/obj/item/clipboard/afterattack(turf/T as turf, mob/user)
	for(var/obj/item/paper/P in turf_contents_of_type(T, /obj/item/paper))
		P.forceMove(src)
		rel_set(src, nameof(toppaper), P)
		update_icon()
		to_chat(user, span_notice("You clip the [P] onto \the [src]."))

// TGUI migration. attack_self opens Clipboard.tsx; the
// Topic pen/write/remove/rename/read/look actions move to tgui_act.
// Reading a paper/photo chains to that item's TGUI viewer
// (Paper.tsx / Photo.tsx).
DECLARE_INTERACTIONS(/obj/item/clipboard, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/clipboard/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/item/clipboard)
	interface("Clipboard", title = "Clipboard")
	without("ui_open")
	op("remove_pen", ui_act("remove_pen"), then(PROC_REF(ui_act_remove_pen)))
	op("add_pen", ui_act("add_pen"), then(PROC_REF(ui_act_add_pen)))
	op("write", ui_act("write", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_write)))
	op("remove", ui_act("remove", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_remove)))
	op("rename", ui_act("rename", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_rename)))
	op("open", ui_act("open", arg("kind", schema_text(4096)), arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_open)))
	drag_onto(PROC_REF(mousedrop_input))

/// /obj/item/clipboard's window data.
/obj/item/clipboard/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["has_pen"] = !!haspen()
	var/list/items = list()
	// Top paper first so React can render it at the head of the list.
	if(toppaper())
		items += list(list(
			"ref" = "\ref[toppaper()]",
			"name" = toppaper().name,
			"kind" = "paper",
			"is_top" = TRUE,
		))
	FOR_REAL_CONTENTS(var/obj/item/paper/P, src)
		if(P == toppaper())
			continue
		items += list(list(
			"ref" = "\ref[P]",
			"name" = P.name,
			"kind" = "paper",
			"is_top" = FALSE,
		))
	FOR_REAL_CONTENTS(var/obj/item/photo/Ph, src)
		items += list(list(
			"ref" = "\ref[Ph]",
			"name" = Ph.name,
			"kind" = "photo",
			"is_top" = FALSE,
		))
	data["items"] = items
	return data

/obj/item/clipboard/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat || user.restrained() || loc != user)
		return FALSE
	return TRUE

/obj/item/clipboard/proc/ui_act_remove_pen(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(haspen() && haspen().loc == src)
		haspen().forceMove(user.loc)
		user.put_in_hands(haspen())
		rel_clear(src, nameof(/obj/item/clipboard::haspen))
		update_icon()
	return TRUE

/obj/item/clipboard/proc/ui_act_add_pen(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!haspen())
		var/obj/item/pen/W = user.get_active_hand()
		if(istype(W, /obj/item/pen))
			if(!own_bring_in(src, nameof(/obj/item/clipboard::haspen), W, null, user, TRUE, null, FALSE))
				return TRUE
			rel_set(src, nameof(/obj/item/clipboard::haspen), W)
			to_chat(user, span_notice("You slot the pen into \the [src]."))
			update_icon()
	return TRUE

/obj/item/clipboard/proc/ui_act_write(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return TRUE
	if(O == toppaper() && istype(O, /obj/item/paper))
		var/obj/item/I = user.get_active_hand()
		if(istype(I, /obj/item/pen))
			O.attackby(I, user)
	return TRUE

/obj/item/clipboard/proc/ui_act_remove(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return TRUE
	if(istype(O, /obj/item/paper) || istype(O, /obj/item/photo))
		O.forceMove(user.loc)
		user.put_in_hands(O)
		if(O == toppaper())
			rel_set(src, nameof(/obj/item/clipboard::toppaper), locate_within(src, /obj/item/paper))
		update_icon()
	return TRUE

/obj/item/clipboard/proc/ui_act_rename(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return TRUE
	if(istype(O, /obj/item/paper))
		var/obj/item/paper/p = O
		p.paper_verb_rename(user)
	else if(istype(O, /obj/item/photo))
		var/obj/item/photo/ph = O
		ph.photo_verb_rename(user)
	return TRUE

/obj/item/clipboard/proc/ui_act_open(datum/act/op/A, kind, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return TRUE
	switch(kind)
		if("paper")
			var/obj/item/paper/p = O
			p.show_content(user)
		if("photo")
			var/obj/item/photo/ph = O
			ph.show(user)
	return TRUE

/// The stored pen. (a relation view: null once that is deleted).
/obj/item/clipboard/proc/haspen() as /obj/item/pen
	return haspen

/// The topmost piece of paper. (a relation view: null once that is deleted).
/obj/item/clipboard/proc/toppaper() as /obj/item
	return toppaper
