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

	matter = list(MAT_STEEL = 10000,MAT_GLASS = 2500)

	var/code = 2
	electric_pack = TRUE

/obj/item/radio/electropack/attack_hand(mob/living/user as mob)
	if(src == user.back)
		to_chat(user, span_notice("You need help taking this off!"))
		return
	..()

/obj/item/radio/electropack/attackby(obj/item/W as obj, mob/user as mob)
	..()
	if(istype(W, /obj/item/clothing/head/helmet))
		if(!b_stat)
			to_chat(user, span_notice("[src] is not ready to be attached!"))
			return
		var/obj/item/assembly/shock_kit/A = new /obj/item/assembly/shock_kit( user )
		A.icon = 'icons/obj/assemblies.dmi'

		user.drop_from_inventory(W)
		W.loc = A
		W.master = A
		A.part1 = W

		user.drop_from_inventory(src)
		loc = A
		master = A
		A.part2 = src

		user.put_in_hands(A)
		A.add_fingerprint(user)

// DQEdit Start — TGUI migration. The electropack's panel had three
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
// DQEdit End

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
				addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(dq_set_moved_recently), M, FALSE), 5 SECONDS, TIMER_DELETE_ME)
		to_chat(M, span_danger("You feel a sharp shock!"))
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(3, 1, M)
		s.start()

		M.Weaken(10)

	if(master && wires & 1)
		master.receive_signal()
	return

// DQEdit Start — TGUI Electropack window; no more browse() panel.
/obj/item/radio/electropack/attack_self(mob/user, flag1)
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
// DQEdit End
