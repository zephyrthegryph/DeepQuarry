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

CAPABILITIES(/obj/item/radio/electropack)
	without("ui_open")
	interface("Electropack", input = in_hand())
	extend("ui_open", when(req(PROC_REF(user_is_human))))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("freq", ui_act("freq", arg("delta", num())), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("delta", num())), then(PROC_REF(ui_act_code)))
	extend(TAG_UI, needs(req(PROC_REF(ui_usable), silent = TRUE)))
	op("keep_on", hand(), then(PROC_REF(hand_goes_on)))
	op("attach_helmet", item(/obj/item/clothing/head/helmet), label("Attach"), then(PROC_REF(helmet_attached)))

/// The pack's window opens for a person's hand.
/obj/item/radio/electropack/proc/user_is_human(datum/act/op/A)
	return ishuman(A.actor)

/// The wearer can't take it off their own back.
/obj/item/radio/electropack/proc/hand_goes_on(datum/act/op/A)
	var/mob/living/user = A.actor
	if(src == user.get_equipped_item(SLOT_ID_BACK))
		to_chat(user, span_warning("You need help taking this off."))
		return OP_REFUSED
	return OP_DECLINE // an empty hand that was not refused goes on to the ordinary hand

/obj/item/radio/electropack/proc/helmet_attached(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!b_stat)
		to_chat(user, span_notice("[src] is not ready to be attached!"))
		return OP_OK
	var/obj/item/assembly/shock_kit/kit = new /obj/item/assembly/shock_kit( user )
	kit.icon = 'icons/obj/assemblies.dmi'

	rel_set(W, nameof(W.master), kit)
	if(!move_into(kit, nameof(kit.part1), W, user))
		return OP_OK

	rel_set(src, nameof(src.master), kit)
	if(!move_into(kit, nameof(kit.part2), src, user))
		return OP_OK

	user.put_in_hands(kit)
	kit.add_fingerprint(user)
	return OP_OK

// TGUI migration. The electropack's panel had three
// controls (power, frequency, code); they all flow through tgui_act now.
/obj/item/radio/electropack/proc/can_use(mob/user)
	if(!user || user.stat || user.restrained())
		return FALSE
	if(ishuman(user) && (!SSticker || SSticker.mode != "monkey") && user.contents.Find(src)) // ALLOW(reads): who holds the pack is read when a button is pressed, never from a cached menu
		return TRUE
	if(user.contents.Find(master)) // ALLOW(reads): the pack's master is read when a button is pressed, never from a cached menu
		return TRUE
	if(in_range(src, user) && isturf(loc)) // ALLOW(reads): where the pack lies is read when a button is pressed, never from a cached menu
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
				after(M, 5 SECONDS, GLOBAL_PROC_REF(dq_set_moved_recently), with = list(M, FALSE))
		to_chat(M, span_danger("You feel a sharp shock!"))
		fx_sparks(M, 3)

		M.status_at_least(EFFECT_WEAKENED, 10)

	if(master && wires & 1)
		master.receive_signal()
	return

// TGUI Electropack window; no more browse() panel.
/obj/item/radio/electropack/ui_data(datum/act/eval/A)
	return list(
		"on" = on,
		"frequency" = frequency,
		"freq_display" = format_frequency(frequency),
		"code" = code,
	)

/// The window answers a viewer who can use the pack (the old can_use() guard, silent).
/obj/item/radio/electropack/proc/ui_usable(datum/act/op/A)
	return can_use(A.actor)

/obj/item/radio/electropack/proc/ui_act_power(datum/act/op/A)
	A.actor.set_machine(src)
	on = !on
	icon_state = "electropack[on]"
	return TRUE

/obj/item/radio/electropack/proc/ui_act_freq(datum/act/op/A, delta)
	A.actor.set_machine(src)
	set_frequency(sanitize_frequency(frequency + delta))
	return TRUE

/obj/item/radio/electropack/proc/ui_act_code(datum/act/op/A, delta)
	A.actor.set_machine(src)
	code = clamp(round(code + delta), 1, 100)
	return TRUE
