// modified bluespace collar where the size is controlled by the signaller.

/obj/item/clothing/accessory/collar/shock/bluespace/modified
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped. It has a little reciever attached."
	icon_state = "collar_size_mod"
	item_state = "collar_size"
	overlay_state = "collar_size"
	target_size = 1
	on = 1

CAPABILITIES(/obj/item/clothing/accessory/collar/shock/bluespace/modified)
	op("modified_collar_signaler", item(/obj/item/assembly/signaler), priority(OP_PRIORITY_DEFAULT - 1), label("Wire signaler"), then(PROC_REF(modified_collar_signaler)))

/// Old attackby: already has a signaler.
/obj/item/clothing/accessory/collar/shock/bluespace/modified/proc/modified_collar_signaler(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("There is already a signaler wired to the [src]."))
	return OP_PASS

/obj/item/clothing/accessory/collar/shock/bluespace/modified/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/collar_name = "[src]"
	var/turf/product_turf = get_turf(src)
	if(!consume(src, user))
		return OP_OK
	to_chat(user, span_notice("You crack the bluespace crystal [collar_name], the attached signaler disconnects."))
	new /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning(product_turf)
	return OP_OK

/obj/item/clothing/accessory/collar/shock/bluespace/modified/ui_data(datum/act/eval/A)
	var/list/data = ..()
	var/list/merged_1 = ui_data_obj_item_clothing_accessory_collar_shock_bluespace_modified(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/clothing/accessory/collar/shock/bluespace/modified's window data.
/obj/item/clothing/accessory/collar/shock/bluespace/modified/proc/ui_data_obj_item_clothing_accessory_collar_shock_bluespace_modified(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["target_size"] = "code"
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/modified/ui_act_size(datum/act/op/A, size)
	return // no modifying size

/obj/item/clothing/accessory/collar/shock/bluespace/modified/receive_signal(datum/signal/signal)
	if(!signal)
		return
	set_target_size((signal.encryption * 2)/100)
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
		if (target_size < 0.26)
			act_message(H, null, MSG_SELF(span_notice("Your collar flickers, but is not powerful enough to shrink you that small.")), \
				MSG_OTHERS(span_warning("The collar on %U% flickers, but fizzles out.")))
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
