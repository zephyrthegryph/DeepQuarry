/*
A collection of Protean rigsuit modules, intended to encourage Symbiotic relations with a host.
All of these should require someone else to be wearing the Protean to function.
These should come standard with the Protean rigsuit, unless you want them to work for some upgrades.
*/


//This rig module feeds nutrition directly from the wearer to the Protean, to help them stay charged while worn.
/obj/item/rig_module/protean
	permanent = 1

/// The protean character the host cluster belongs to.
/obj/item/rig_module/protean/proc/get_protean()
	var/obj/item/rig/protean/prig = holder
	return istype(prig) ? prig.myprotean : null

/// Protean modules only work on someone else.
/obj/item/rig_module/protean/proc/wearer_is_protean(mob/living/carbon/human/H)
	return !!H?.get_protean_forms()

/obj/item/rig_module/protean/syphon
	name = "Protean Metabolic Syphon"
	desc = "This should never be outside of a RIG."
	icon_state = "flash"
	interface_name = "Protean Metabolic Syphon"
	interface_desc = "Toggle to drain nutrition/power from the user directly into the Protean's own energy stores."
	toggleable = 1
	activate_string = "Enable Syphon"
	deactivate_string = "Disable Syphon"

/obj/item/rig_module/protean/syphon/activate(skip_engage = 0, mob/user)
	if(!..())
		return 0

	var/mob/living/carbon/human/H = holder.wearer()
	if(H)
		to_chat(user, span_boldnotice("You activate the suit's energy syphon."))
		to_chat(H, span_warning("Your suit begins to sap at your own energy stores."))
		active = 1
	else
		return 0

/obj/item/rig_module/protean/syphon/deactivate(forced = FALSE, mob/user)
	if(!..())
		return 0
	if(forced)
		active = 0
		return
	var/mob/living/carbon/human/H = holder.wearer()
	if(H)
		to_chat(user, span_boldnotice("You deactivate the suit's energy syphon."))
		to_chat(H, span_warning("Your suit ceases from sapping your own energy."))
		active = 0
	else
		return 0

/obj/item/rig_module/protean/syphon/periodic_step()
	if(active)
		var/mob/living/carbon/human/H = holder.wearer()
		if(!H)
			return
		var/mob/living/P = get_protean()
		if(wearer_is_protean(H))
			to_chat(H, span_warning("Your Protean modules do not function on yourself."))
			deactivate(1)
		else if(P && (H.nutrition >= 100) && (P.nutrition <= 5000))
			H.adjust_nutrition(-10)
			P.adjust_nutrition(10)

//This rig module allows a worn Protean to toggle and configure its armor settings.
/obj/item/rig_module/protean/armor
	name = "Protean Adaptive Armor"
	desc = "This should never be outside of a RIG."
	interface_name = "Protean Adaptive Armor"
	interface_desc = "Adjusts the proteans deployed armor values to fit the needs of the wearer."
	usable = 1
	toggleable = 1
	activate_string = "Enable Armor"
	deactivate_string = "Disable Armor"
	engage_string = "Configure Armor"
	/// Armor type -> configured value. Lazy: an unset type is 0.
	var/list/armor_settings
	var/armor_weight_ratio = 0.01	//This amount of slowdown per 1% of armour. 3 slowdown at the max armour.

/// The armor types the wearer can configure.
TYPE_TABLE_DECLARE(/obj/item/rig_module/protean/armor, armor_types, list("melee", "bullet", "laser", "energy", "bomb"))

/obj/item/rig_module/protean/armor/engage(atom/target, notify_ai, mob/user)
	return armor_configuration_stage(target, notify_ai, user)

/obj/item/rig_module/protean/armor/proc/armor_configuration_stage(atom/target, notify_ai, mob/user, armor_chosen = null, armorvalue = null)
	if(isnull(armor_chosen))
		open_request(src, /datum/prompt/choice/protean_armor_configuration, PROC_REF(armor_type_answered), answerer = user, subject = target, target_expected = !isnull(target), notify_ai = notify_ai, choices = TYPE_TABLE_GET(src, armor_types))
		return
	if(armor_chosen)
		if(isnull(armorvalue))
			open_request(src, /datum/prompt/number/protean_armor_configuration, PROC_REF(armor_value_answered), answerer = user, subject = target, target_expected = !isnull(target), notify_ai = notify_ai, armor_chosen = armor_chosen)
			return
		if(isnum(armorvalue))
			LAZYSET(armor_settings, armor_chosen, armorvalue)
			interface_desc = initial(interface_desc)
			slowdown = 0
			for(var/entry in TYPE_TABLE_GET(src, armor_types))	//This is dumb and ugly but I dont feel like rewriting rig TGUI just to make this a pretty list
				var/value = LAZYACCESS(armor_settings, entry) || 0
				interface_desc += " [entry]: [value]"
				slowdown += value*armor_weight_ratio
			interface_desc += " Slowdown: [slowdown]"

/obj/item/rig_module/protean/armor/proc/armor_type_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/protean_armor_configuration/ask = context.answer
	armor_configuration_stage(ask.target_expected ? ask.subject : null, ask.notify_ai, ask.answerer, ask.answer_value)
	SStgui.update_uis(src)

/obj/item/rig_module/protean/armor/proc/armor_value_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/protean_armor_configuration/ask = context.answer
	armor_configuration_stage(ask.target_expected ? ask.subject : null, ask.notify_ai, ask.answerer, ask.armor_chosen, ask.answer_value)
	SStgui.update_uis(src)

/obj/item/rig_module/protean/armor/activate(skip_engage = 0, mob/user)
	var/obj/item/rig/protean/prig = holder
	if(istype(prig) && prig.assimilated_rig)
		to_chat(user, span_bolddanger("Armor module non-functional while a RIG is assimilated."))
		return
	if(!..(1, user))
		return 0

	var/mob/living/carbon/human/H = holder.wearer()
	if(H)
		var/list/temparmor = list()
		for(var/entry in TYPE_TABLE_GET(src, armor_types))
			temparmor[entry] = LAZYACCESS(armor_settings, entry) || 0
		temparmor["bio"] = 100
		temparmor["rad"] = 100
		to_chat(user, span_boldnotice("You signal the suit to harden."))
		to_chat(H, span_notice("Your suit hardens in response to physical trauma."))
		holder.set_armor(dq_armor(temparmor))
		for(var/obj/item/piece in list(holder.gloves,holder.helmet,holder.boots,holder.chest))
			piece.set_armor(dq_armor(temparmor))
		holder.slowdown = slowdown
		active = 1
		H.worn_protection_changed()
	else
		return 0

/obj/item/rig_module/protean/armor/deactivate(forced = FALSE, mob/user)
	if(!..(1, user))
		return 0
	if(forced)
		holder.set_armor(dq_armor(list("melee" = 0, "bullet" = 0, "laser" = 0,"energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 100)))
		for(var/obj/item/piece in list(holder.gloves,holder.helmet,holder.boots,holder.chest))
			piece.set_armor(dq_armor(list("melee" = 0, "bullet" = 0, "laser" = 0,"energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 100)))
		holder.slowdown = initial(slowdown)
		active = 0
		holder.wearer()?.worn_protection_changed()
		return
	var/mob/living/carbon/human/H = holder.wearer()
	if(H)
		to_chat(user, span_boldnotice("You signal the suit to relax."))
		to_chat(H, span_warning("Your suit softens."))
		holder.set_armor(dq_armor(list("melee" = 0, "bullet" = 0, "laser" = 0,"energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 100)))
		for(var/obj/item/piece in list(holder.gloves,holder.helmet,holder.boots,holder.chest))
			piece.set_armor(dq_armor(list("melee" = 0, "bullet" = 0, "laser" = 0,"energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 100)))
		holder.slowdown = initial(slowdown)
		active = 0
		H.worn_protection_changed()
	else
		return 0

/obj/item/rig_module/protean/armor/periodic_step()
	if(active)
		var/mob/living/carbon/human/H = holder.wearer()
		if(!H)
			deactivate(1)
			return
		if(wearer_is_protean(H))
			to_chat(H, span_warning("Your Protean modules do not function on yourself."))
			deactivate(1)


//This rig module lets a Protean expend its metal stores to heal its host
#define PROTEAN_HOST_REPAIR_PER_TICK 4

/obj/item/rig_module/protean/healing
	name = "Protean Restorative Nanites"
	desc = "This should never be outside of a RIG."
	interface_name = "Protean Restorative Nanites"
	interface_desc = "Utilises stored steel from the Protean to slowly heal and repair the wearer."
	toggleable = 1
	activate_string = "Enable Healing"
	deactivate_string = "Disable Healing"

/obj/item/rig_module/protean/healing/activate(skip_engage = 0, mob/user)
	if(!..(1, user))
		return 0
	var/mob/living/carbon/human/H = holder.wearer()
	var/mob/living/P = get_protean()
	if(!H || !P)
		return 0
	if(wearer_is_protean(H))
		to_chat(H, span_warning("Your Protean modules do not function on yourself."))
		return 0
	var/obj/item/organ/internal/nano/refactory/R = P.nano_get_refactory()
	if(!R || R.get_stored_material(MAT_STEEL) < 100)
		return 0
	to_chat(user, span_boldnotice("You activate the suit's restorative nanites."))
	to_chat(H, span_warning("Your suit begins mending your injuries."))
	active = 1
	return 1

/obj/item/rig_module/protean/healing/deactivate(forced = FALSE, mob/user)
	if(!..(1, user))
		return 0
	var/mob/living/carbon/human/H = holder.wearer()
	if(!H)
		return 0
	to_chat(user, span_boldnotice("You deactivate the suit's restorative nanites."))
	to_chat(H, span_warning("Your suit is no longer mending your injuries."))
	active = 0
	return 1

/// Wound repair on the host, whatever it is made of, paid for in steel by what
/// mend() actually repaired. Never touches lesions or dead organs (bug 11).
/obj/item/rig_module/protean/healing/periodic_step()
	if(!active)
		return
	var/mob/living/carbon/human/H = holder.wearer()
	var/mob/living/P = get_protean()
	if(!H || !P)
		deactivate()
		return
	if(wearer_is_protean(H))
		to_chat(H, span_warning("Your Protean modules do not function on yourself."))
		deactivate()
		return
	var/obj/item/organ/internal/nano/refactory/R = P.nano_get_refactory()
	if(!R || !R.get_stored_material(MAT_STEEL))
		to_chat(H, span_warning("Your [holder] is out of steel."))
		deactivate()
		return
	var/static/list/repair_tags = list(TREAT_TISSUE_REPAIR, TREAT_BURN_CARE, TREAT_PLATING_REPAIR, TREAT_WIRING_REPAIR)
	R.fund_repair(H, repair_tags, PROTEAN_HOST_REPAIR_PER_TICK)

/obj/item/rig_module/protean/healing/accepts_item(obj/item/stack/material/steel/S, mob/living/user)
	if(!istype(S) || !istype(user))
		return 0
	var/mob/living/P = get_protean()
	var/obj/item/organ/internal/nano/refactory/R = P?.nano_get_refactory()
	if(R?.add_stored_material(S.material.name, 1 * S.perunit) && S.use(1))
		to_chat(user, span_boldnotice("You directly feed some steel to the [holder]."))
		return 1
	return 0

#undef PROTEAN_HOST_REPAIR_PER_TICK

/datum/prompt/choice/protean_armor_configuration
	title = "Protean Armor"
	question = "Which armor to adjust?"
	timeout = 0
	recheck_on_open = TRUE
	var/target_expected = FALSE
	var/notify_ai

/datum/prompt/choice/protean_armor_configuration/recheck_extra()
	var/obj/item/rig_module/protean/armor/module = owner
	var/mob/user = answerer
	var/atom/target = subject
	if(!istype(module) || QDELETED(module) || !istype(user) || QDELETED(user))
		return "gone"
	if(target_expected && (!istype(target) || QDELETED(target)))
		return "gone"
	return null

/datum/prompt/number/protean_armor_configuration
	title = "Protean Armor"
	question = "Set armour reduction value (Max of 60%)"
	default = 0
	timeout = 0
	recheck_on_open = TRUE
	var/target_expected = FALSE
	var/notify_ai
	var/armor_chosen

/datum/prompt/number/protean_armor_configuration/recheck_extra()
	var/obj/item/rig_module/protean/armor/module = owner
	var/mob/user = answerer
	var/atom/target = subject
	if(!istype(module) || QDELETED(module) || !istype(user) || QDELETED(user))
		return "gone"
	if(target_expected && (!istype(target) || QDELETED(target)))
		return "gone"
	return null

/datum/prompt/number/protean_armor_configuration/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default, 60, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
