MATERIAL_MIX(/obj/item/analyzer, list(MAT_STEEL = 30,MAT_GLASS = 20))
/obj/item/analyzer
	name = "gas analyzer"
	desc = "A hand-held environmental scanner which reports current gas levels."
	icon = 'icons/obj/device.dmi'
	icon_state = "atmos"
	item_state = "analyzer"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	throwforce = 5
	throw_speed = 4
	throw_range = 20



	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	///Var for attack_self chain
	var/special_handling = FALSE

/obj/item/analyzer/atmosanalyze(mob/user)
	var/air = user.return_air()
	if (!air)
		return

	return atmosanalyzer_scan(src, air, user)

CAPABILITIES(/obj/item/analyzer)
	op("analyze", in_hand(), needs(req(PROC_REF(can_analyze), because = MSG(analyzer/clumsy))), then(PROC_REF(analyzed)))

MSG_DEF_SELF(analyzer/clumsy, "you don't have the dexterity to do this")

/// Requirement: only a dexterous user can work the analyzer (one who is out cold, or an analyzer that is handled elsewhere, is let through: the effect declines silently).
/obj/item/analyzer/proc/can_analyze(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling || user.stat) // ALLOW(reads): whether the analyzer is handled elsewhere is read when it is used, never from a cached menu
		return TRUE
	return user.IsAdvancedToolUser()

/obj/item/analyzer/proc/analyzed(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling)
		return OP_DECLINE
	if (user.stat)
		return OP_OK

	analyze_gases_by(src, src, user)
	return OP_OK

/obj/item/analyzer/afterattack(obj/O, mob/user, proximity)
	if(proximity)
		analyze_gases_by(src, O, user)
	return
