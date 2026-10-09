/* Cards
 * Contains:
 *		DATA CARD
 *		ID CARD
 *		FINGERPRINT CARD HOLDER
 *		FINGERPRINT CARD
 */

/*
 * DATA CARDS - Used for the teleporter
 */
/obj/item/card
	name = "card"
	desc = "A tiny plaque of plastic. Does card things."
	icon = 'icons/obj/card_new.dmi'
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	var/associated_account_number = 0

	var/list/initial_sprite_stack = list("") // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)
	var/base_icon = 'icons/obj/card_new.dmi'
	var/list/sprite_stack

	var/list/files
	drop_sound = SFX_ITEMS_DROP_CARD
	pickup_sound = SFX_ITEMS_PICKUP_CARD

/obj/item/card/Initialize(mapload)
	. = ..()
	reset_icon()

/// The sprite stack is tracked: the card redraws when it is set (the setter compares the list, so a new list is a new look).
TRACKED(/obj/item/card, sprite_stack)

/obj/item/card/proc/reset_icon()
	set_sprite_stack(initial_sprite_stack)

/// The sprite stack as layers: the first state is the base, the rest overlays on it (was a
/// blended /icon per card; the layers draw the same without generating an icon).
/obj/item/card/draw(datum/look/look)
	..()
	look_parts(look)

/// What this chain's providers drew: each type's own part of the look, a subtype replacing or extending it (..()).
/obj/item/card/proc/look_parts(datum/look/look)
	var/drawn_state = look.state_so_far(src)
	look.set_icon(base_icon)
	if(!sprite_stack || !istype(sprite_stack) || sprite_stack == list(""))
		drawn_state = look.state(initial(icon_state))
		return
	var/first = TRUE
	for(var/iconstate in sprite_stack)
		if(!iconstate)
			iconstate = drawn_state
		if(first)
			drawn_state = look.state(iconstate)
			first = FALSE
		else
			look.overlay(image(base_icon, iconstate))

/obj/item/card/data
	name = "data card"
	desc = "A solid-state storage card, used to back up or transfer information. What knowledge could it contain?"
	icon_state = "data"
	var/function = "storage"
	var/data = "null"
	var/special = null
	item_state = "card-id"
	drop_sound = SFX_ITEMS_DROP_DISK
	pickup_sound = SFX_ITEMS_PICKUP_DISK

/obj/item/card/data/proc/data_label_effect(datum/act/op/A)
	var/mob/user = A.actor
	var/t = A.step_value("data_card_label")
	// The old verb took the text as its argument; ask for it instead.
	if(get(src, /mob) != user)
		return
	if (t)
		src.name = text("data card- '[]'", t)
	else
		src.name = "data card"
	src.add_fingerprint(user)

/obj/item/card/data/clown
	name = "\proper the coordinates to clown planet"
	icon_state = "rainbow"
	item_state = "card-id"
	level = 2
	desc = "This card contains coordinates to the fabled Clown Planet. Handle with care."
	function = "teleporter"
	data = "Clown Land"

/*
 * ID CARDS
 */

/obj/item/card/emag_broken
	desc = "It's a card with a magnetic strip attached to some circuitry. It looks too busted to be used for anything but salvage."
	name = "broken cryptographic sequencer"
	icon_state = "emag-spent"
	item_state = "card-id"

/obj/item/card/emag
	desc = "It's a card with a magnetic strip attached to some circuitry."
	name = "cryptographic sequencer"
	icon_state = "emag"
	item_state = "card-id"
	var/uses = 10

/// The card acts before the target's own attackby: the target's declared Emag interaction
/// (code/datums/sys/emag.dm) runs, or the card is an ordinary item when it declares none.
/obj/item/card/emag/resolve_attackby(atom/A, mob/user, attack_modifier, click_parameters)
	var/datum/interaction/emag = emag_interaction_for(A)
	if(!emag || isnull(emag.attempt(user, A, src)))
		return ..(A, user, click_parameters)
	return 1

/// Whether the card can still emag anything.
/obj/item/card/emag/proc/can_emag(mob/user)
	return uses > 0

/// Pays `used` uses for emagging A and logs it; a spent card breaks.
/obj/item/card/emag/proc/spend(mob/user, atom/A, used)
	uses -= used
	A.add_fingerprint(user)
	// Because some things (read lift doors) don't get emagged
	if(used)
		log_and_message_admins("emagged \an [A].")
	else
		log_and_message_admins("attempted to emag \an [A].")
	if(uses < 1)
		spent(user)

/// Out of uses.
/obj/item/card/emag/proc/spent(mob/user)
	user.visible_message(span_warning("\The [src] fizzles and sparks - it seems it's been used once too often, and is now spent."))
	user.drop_item()
	var/obj/item/card/emag_broken/junk = new(user.loc)
	junk.add_fingerprint(user)
	consume(src, user)

CAPABILITIES(/obj/item/card/emag)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/card/emag/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/stack/telecrystal))
		var/obj/item/stack/telecrystal/T = O
		if(T.get_amount() < 1)
			to_chat(user, span_notice("You are not adding enough telecrystals to fuel \the [src]."))
			return OP_PASS
		uses += T.get_amount()*0.5 //Gives 5 uses per 10 TC
		uses = CEILING(uses, 1) //Ensures no decimal uses nonsense, rounds up to be nice
		to_chat(user, span_notice("You add \the [O] to \the [src]. Increasing the uses of \the [src] to [uses]."))
		consume(O, user)
	return OP_PASS

/obj/item/card/emag/borg
	uses = 12
	var/burnt_out = FALSE

/obj/item/card/emag/borg/afterattack(atom/A, mob/user, proximity, click_parameters)
	if(!proximity || burnt_out) return
	var/datum/interaction/emag = emag_interaction_for(A)
	if(!emag || isnull(emag.attempt(user, A, src)))
		return ..(A, user, proximity, click_parameters)
	return 1

/obj/item/card/emag/borg/can_emag(mob/user)
	return !burnt_out && ..()

/obj/item/card/emag/borg/spent(mob/user)
	user.visible_message(span_warning("\The [src] fizzles and sparks - it seems it's been used once too often, and is now spent."))
	burnt_out = TRUE

/// FLUFF PERMIT

/obj/item/card_fluff
	name = "fluff card"
	desc = "A tiny plaque of plastic. Purely decorative?"
	description_fluff = "This permit was not issued by any branch of NanoTrasen, and as such it is not formally recognized at any NanoTrasen-operated installations. The bearer is not - under any circumstances - entitled to ownership of any items or allowed to perform any acts that would normally be restricted or illegal for their current position, regardless of what they or this permit may claim."
	icon = 'icons/obj/card_fluff.dmi'
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS

	var/list/initial_sprite_stack = list("") // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)
	var/base_icon = 'icons/obj/card_fluff.dmi'
	var/list/sprite_stack = list("") // ALLOW(instance_list): each decorative card starts with its own mutable appearance stack

	drop_sound = SFX_ITEMS_DROP_CARD
	pickup_sound = SFX_ITEMS_PICKUP_CARD

TRACKED(/obj/item/card_fluff, sprite_stack)

/obj/item/card_fluff/proc/reset_icon()
	set_sprite_stack(list(""))

/// The sprite stack as layers: the first state is the base, the rest overlays on it (was a
/// blended /icon per card; the layers draw the same without generating an icon).
/obj/item/card_fluff/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	look.set_icon(base_icon)
	if(!sprite_stack || !istype(sprite_stack) || sprite_stack == list(""))
		drawn_state = look.state(initial(icon_state))
		return
	var/first = TRUE
	for(var/iconstate in sprite_stack)
		if(!iconstate)
			iconstate = drawn_state
		if(first)
			drawn_state = look.state(iconstate)
			first = FALSE
		else
			look.overlay(image(base_icon, iconstate))

CAPABILITIES(/obj/item/card_fluff)
	op("customize", in_hand(), label("Customize card"), needs(carried(), req_capable()),
		asks(/datum/prompt/choice, keeps = 0, step = "element", fields = list("title" = "Customize Card", "question" = "What element would you like to customize?", "choices" = list("Band", "Stamp", "Reset"), "timeout" = 0)),
		asks(/datum/prompt/choice, keeps = 0, step = "band", when = PROC_REF(customizing_band), fields = list("title" = "Band colour", "question" = "Select colour", "choices" = list("red", "orange", "green", "dark green", "medical blue", "dark blue", "purple", "tan", "pink", "gold", "white", "black"), "timeout" = 0)),
		asks(/datum/prompt/choice, keeps = 0, step = "stamp", when = PROC_REF(customizing_stamp), fields = list("title" = "Stamp image", "question" = "Select image", "choices" = list("ship", "cross", "big ears", "shield", "circle-cross", "target", "smile", "frown", "peace", "exclamation"), "timeout" = 0)),
		then(PROC_REF(customize_chosen)))

/obj/item/card_fluff/proc/customizing_band(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("element")
	return R?.value == "Band"

/obj/item/card_fluff/proc/customizing_stamp(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("element")
	return R?.value == "Stamp"

/obj/item/card_fluff/proc/customize_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("element")
	switch(R.value)
		if("Band")
			band_chosen(A)
		if("Stamp")
			stamp_chosen(A)
		if("Reset")
			reset_icon()
	return OP_OK

/obj/item/card_fluff/proc/band_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("band")
	var/bandchoice = R.value
	var/list/changed_stack = sprite_stack.Copy()
	if(bandchoice == "red")
		changed_stack.Add("bar-red")
	else if(bandchoice == "orange")
		changed_stack.Add("bar-orange")
	else if(bandchoice == "green")
		changed_stack.Add("bar-green")
	else if(bandchoice == "dark green")
		changed_stack.Add("bar-darkgreen")
	else if(bandchoice == "medical blue")
		changed_stack.Add("bar-medblue")
	else if(bandchoice == "dark blue")
		changed_stack.Add("bar-blue")
	else if(bandchoice == "purple")
		changed_stack.Add("bar-purple")
	else if(bandchoice == "tan")
		changed_stack.Add("bar-tan")
	else if(bandchoice == "pink")
		changed_stack.Add("bar-pink")
	else if(bandchoice == "gold")
		changed_stack.Add("bar-gold")
	else if(bandchoice == "white")
		changed_stack.Add("bar-white")
	else if(bandchoice == "black")
		changed_stack.Add("bar-black")

	set_sprite_stack(changed_stack)

/obj/item/card_fluff/proc/stamp_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("stamp")
	var/stampchoice = R.value
	var/list/changed_stack = sprite_stack.Copy()
	if(stampchoice == "ship")
		changed_stack.Add("stamp-starship")
	else if(stampchoice == "cross")
		changed_stack.Add("stamp-cross")
	else if(stampchoice == "big ears")
		changed_stack.Add("stamp-bigears")	//get 'em outta the caption, wiseguy!!
	else if(stampchoice == "shield")
		changed_stack.Add("stamp-shield")
	else if(stampchoice == "circle-cross")
		changed_stack.Add("stamp-circlecross")
	else if(stampchoice == "target")
		changed_stack.Add("stamp-target")
	else if(stampchoice == "smile")
		changed_stack.Add("stamp-smile")
	else if(stampchoice == "frown")
		changed_stack.Add("stamp-frown")
	else if(stampchoice == "peace")
		changed_stack.Add("stamp-peace")
	else if(stampchoice == "exclamation")
		changed_stack.Add("stamp-exclaim")

	set_sprite_stack(changed_stack)

/obj/item/card/id/synthetic/borg
	var/mob/living/silicon/robot/robot_owner
	var/last_robot_loc

/obj/item/card/id/synthetic/borg/Initialize(mapload)
	. = ..()
	if(isrobot(loc))
		rel_set(src, nameof(robot_owner), loc)
		registered_name = robot_owner().braintype
		observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(check_loc)))

/obj/item/card/id/synthetic/borg/proc/check_loc(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/movable_attempted_move/event = A
	var/atom/old_loc = event.old_loc
	if(old_loc == robot_owner() || old_loc == robot_owner().module)
		last_robot_loc = old_loc
	if(!istype(loc, /obj/machinery) && loc != robot_owner() && loc != robot_owner().module)
		if(last_robot_loc)
			forceMove(last_robot_loc)
			last_robot_loc = null
		else
			forceMove(robot_owner())
		if(loc == robot_owner())
			hud_layerise()

/obj/item/card/emag/examine(mob/user)
	. = ..()
	. += "[uses] uses remaining."

/obj/item/card/emag/used
	uses = 1

CAPABILITIES(/obj/item/card/emag/used)
	rolls(nameof(uses), range_of(1, 5))

/// Relation view: robot owner (reads null once it is gone).
/obj/item/card/id/synthetic/borg/proc/robot_owner() as /mob/living/silicon/robot
	return robot_owner

/// Old object verbs.
CAPABILITIES(/obj/item/card/data)
	op("data_label_effect", menu(), label("Label Card"), needs(carried()), asks(/datum/prompt/text, fields = list("question" = "Enter a label for the card.", "title" = "Label Card", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "data_card_label"), then(PROC_REF(data_label_effect)))
