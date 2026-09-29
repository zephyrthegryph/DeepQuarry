MATERIAL_MIX(/obj/item/radio/electropack, list(MAT_STEEL = 10000,MAT_GLASS = 2500))
/obj/item/radio/electropack
	name = "electropack"
	desc = "Dance my monkeys! DANCE!!!"
	icon_state = "electropack0"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
			)
	item_state = "electropack"
	frequency = AMAG_ELE_FREQ
	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_HUGE


	var/code = 2
	electric_pack = TRUE

// Extends the radio's own Use (the radio UI; interaction_self declines for packs/beacons).
EXTEND_INTERACTIONS(/obj/item/radio/electropack, \
	INTERACT_HAND(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/item/radio/electropack/proc/can_take_off)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Requirement: the wearer can't take it off their own back.
/obj/item/radio/electropack/proc/can_take_off(mob/living/user, atom/target, obj/item/held)
	if(src == user.get_equipped_item(SLOT_ID_BACK))
		return "you need help taking this off"
	return TRUE

/// Blocks self-removal through can_take_off(); otherwise falls through to the ordinary hand.
/obj/item/radio/electropack/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	return FALSE

/obj/item/radio/electropack/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/clothing/head/helmet))
		if(!b_stat)
			to_chat(user, span_notice("[src] is not ready to be attached!"))
			return TRUE
		var/obj/item/assembly/shock_kit/A = new /obj/item/assembly/shock_kit( user )
		A.icon = 'icons/obj/assemblies.dmi'

		user.drop_from_inventory(W)
		W.forceMove(A)
		rel_set(W, "master", A)
		own_set(A, "part1", W)

		user.drop_from_inventory(src)
		forceMove(A)
		rel_set(src, "master", A)
		own_set(A, "part2", src)

		user.put_in_hands(A)
		A.add_fingerprint(user)
		return TRUE
	return FALSE

// TGUI migration. The electropack's panel had three
// controls (power, frequency, code); they all flow through tgui_act now.
/obj/item/radio/electropack/proc/can_use(mob/user)
	if(!user || user.stat || user.restrained())
		return FALSE
	if(ishuman(user) && (!SSticker || SSticker.mode != "monkey") && user.contents.Find(src))
		return TRUE
	if(user.contents.Find(master))
		return TRUE
	if(in_range(src, user) && isturf(loc))
		return TRUE
	return FALSE

/obj/item/radio/electropack/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption != code)
		return

	if(ismob(loc) && on)
		var/mob/M = loc
		var/turf/T = M.loc
		if(istype(T, /turf))
			if(!dq_get_moved_recently(M) && M.last_move)
				dq_set_moved_recently(M, TRUE)
				step(M, M.last_move)
				om_after(M, 5 SECONDS, GLOBAL_PROC_REF(dq_set_moved_recently), M, FALSE)
		to_chat(M, span_danger("You feel a sharp shock!"))
		fx_sparks(M, 3)

		M.status_at_least(EFFECT_WEAKENED, 10)

	if(master && wires & 1)
		master.receive_signal()
	return

// TGUI Electropack window; no more browse() panel.
/obj/item/radio/electropack/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(!ishuman(user))
		return
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/obj/item/radio/electropack/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Electropack", name, parent_ui)
		ui.open()

/obj/item/radio/electropack/tgui_data(mob/user)
	return list(
		"on" = on,
		"frequency" = frequency,
		"freq_display" = format_frequency(frequency),
		"code" = code,
	)

/obj/item/radio/electropack/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!can_use(usr))
		return
	usr.set_machine(src)
	switch(action)
		if("power")
			on = !on
			icon_state = "electropack[on]"
			return TRUE
		if("freq")
			var/delta = text2num("[params["delta"]]")
			if(isnum(delta))
				set_frequency(sanitize_frequency(frequency + delta))
			return TRUE
		if("code")
			var/delta = text2num("[params["delta"]]")
			if(isnum(delta))
				code = clamp(round(code + delta), 1, 100)
			return TRUE
