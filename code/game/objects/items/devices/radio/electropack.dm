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

/// Is `thing` the item on `user`'s back?
/proc/worn_on_back_of(obj/item/thing, mob/user)
	READS_FROM() // what is worn where is asked when the hand reaches for it
	return thing == user.get_equipped_item(SLOT_ID_BACK)

/// The wearer can't take it off alone.
/obj/item/radio/electropack/proc/interaction_hand(datum/act/op/A)
	if(!worn_on_back_of(src, A.actor))
		return OP_DECLINE
	to_chat(A.actor, span_warning("You need help taking this off."))
	return OP_OK

/// Old attackby: a helmet and the pack make a shock kit (once its panel is open).
/obj/item/radio/electropack/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/clothing/head/helmet))
		if(!b_stat)
			to_chat(user, span_notice("[src] is not ready to be attached!"))
			return OP_OK
		var/obj/item/assembly/shock_kit/K = new /obj/item/assembly/shock_kit( user )
		K.icon = 'icons/obj/assemblies.dmi'

		rel_set(W, nameof(W.master), K)
		if(!move_into(K, nameof(K.part1), W, user))
			return OP_OK

		rel_set(src, nameof(src.master), K)
		if(!move_into(K, nameof(K.part2), src, user))
			return OP_OK

		user.put_in_hands(K)
		K.add_fingerprint(user)
		return OP_OK
	return OP_DECLINE

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
				after(M, 5 SECONDS, GLOBAL_PROC_REF(dq_set_moved_recently), with = list(M, FALSE))
		to_chat(M, span_danger("You feel a sharp shock!"))
		fx_sparks(M, 3)

		M.status_at_least(STAT_WEAKENED, 10)

	return

// TGUI Electropack window; no more browse() panel.
/obj/item/radio/electropack/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(!ishuman(user))
		return
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/item/radio/electropack)
	interface("Electropack")
	without("ui_open")
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("freq", ui_act("freq", arg("delta", num())), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("delta", num())), then(PROC_REF(ui_act_code)))
	// strapped to the actor's own back, it can't be taken off alone (otherwise the click declines to the ordinary hand)
	op("strapped", hand(), label("Take off"), then(PROC_REF(interaction_hand)))
	op("shock_kit", item(/obj/item/clothing/head/helmet), label("Make a shock kit"), then(PROC_REF(interaction_item)))

/// /obj/item/radio/electropack's window data.
/obj/item/radio/electropack/ui_data(datum/act/eval/A)
	return list(
		"on" = on,
		"frequency" = frequency,
		"freq_display" = format_frequency(frequency),
		"code" = code,
	)

/obj/item/radio/electropack/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!..())
		return FALSE
	if(!can_use(user))
		return FALSE
	user.set_machine(src)
	return TRUE

/obj/item/radio/electropack/proc/ui_act_power(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	on = !on
	icon_state = "electropack[on]"
	return TRUE

/obj/item/radio/electropack/proc/ui_act_freq(datum/act/op/A, delta_arg)
	if(!ui_gate(A))
		return FALSE
	var/delta = delta_arg
	if(isnum(delta))
		set_frequency(sanitize_frequency(frequency + delta))
	return TRUE

/obj/item/radio/electropack/proc/ui_act_code(datum/act/op/A, delta_arg)
	if(!ui_gate(A))
		return FALSE
	var/delta = delta_arg
	if(isnum(delta))
		code = clamp(round(code + delta), 1, 100)
	return TRUE
