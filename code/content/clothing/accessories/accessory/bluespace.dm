//Size collar remote

/obj/item/clothing/accessory/collar/shock/bluespace
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped."
	icon_state = "collar_size"
	item_state = "collar_size"
	overlay_state = "collar_size"
	/// Ratio (target_size / size_multiplier at activation) the collar itself applied.
	/// Stored as a ratio rather than an absolute snapshot so that restoring only
	/// undoes the collar's own contribution instead of clobbering whatever other
	/// size sources (potions, sizeguns, etc.) did to the wearer in the meantime.
	var/applied_ratio
	var/last_activated = 0
	var/target_size = 1
	on = 1

/obj/item/clothing/accessory/collar/shock/bluespace/tgui_static_data(mob/user)
	var/list/data = ..()
	data["target_size_min"] = RESIZE_MINIMUM_DORMS
	data["target_size_max"] = RESIZE_MAXIMUM_DORMS
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["target_size"] = target_size
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/proc/ui_act_size(datum/act/op/A, size)
	var/mob/user = A.actor
	set_target_size(clamp((size/100), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS))
	to_chat(user, span_notice("You set the size to [target_size * 100]%"))
	if(target_size < RESIZE_MINIMUM || target_size > RESIZE_MAXIMUM)
		to_chat(user, span_notice("Note: Resizing limited to 25-200% automatically while outside dormatory areas.")) //hint that we clamp it in resize
	. = TRUE

/obj/item/clothing/accessory/collar/shock/bluespace/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption != code)
		return

	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		var/mob/living/carbon/human/H = M
		if(!istype(H))
			return
		if(!H.vore_prefs.resizable)
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts but nothing happens to you.")), \
				MSG_OTHERS(span_warning("The space around %U% compresses for a moment but then nothing happens.")))
			return
		if(applied_ratio == null)
			if(!(ELAPSED(src, last_activated, CLOCK_WORLD) > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			STAMP(src, last_activated, CLOCK_WORLD)
			applied_ratio = H.size_multiplier ? (target_size / H.size_multiplier) : 1
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you change size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they change size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			fx_sparks(M, 3)
		else
			STAMP(src, last_activated, CLOCK_WORLD)
			H.resize(applied_ratio ? (H.size_multiplier / applied_ratio) : H.size_multiplier, ignore_prefs = FALSE, allow_stripping = TRUE)
			applied_ratio = null
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you return to your original size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they return to their original size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			fx_sparks(M, 3)
	return

/obj/item/clothing/accessory/collar/shock/bluespace/relaymove(mob/living/user,direction)
	return //For some reason equipping this item was triggering this proc, putting the wearer inside of the collars belly for some reason.

CAPABILITIES(/obj/item/clothing/accessory/collar/shock/bluespace)
	op("bluespace_collar_wire_signaler", item(/obj/item/assembly/signaler), label("Wire signaler"), then(PROC_REF(bluespace_collar_wire_signaler)))
	op("size", ui_act("size", arg("size", num())), then(PROC_REF(ui_act_size)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))

/// Old attackby: wire a signaler in, making a modified collar.
/obj/item/clothing/accessory/collar/shock/bluespace/proc/bluespace_collar_wire_signaler(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/component = A.held
	to_chat(user, span_notice("You wire the signaler into the [src]."))
	user.drop_item()
	consume(component, user)
	var/turf/T = get_turf(src)
	new /obj/item/clothing/accessory/collar/shock/bluespace/modified(T)
	consume(src, user)
	return OP_PASS

/obj/item/clothing/accessory/collar/shock/bluespace/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You crack the bluespace crystal [src]."))
	new /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning(get_turf(src))
	consume(src, user)
	return OP_OK
