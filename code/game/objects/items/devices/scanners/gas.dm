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
	op("analyze", in_hand(), when(cond_not(nameof(special_handling))), needs(req_conscious(), req(PROC_REF(can_analyze), because = MSG(analyzer/clumsy))), then(PROC_REF(interaction_self)))

/// Requirement: only a dexterous user can work the analyzer.
/obj/item/analyzer/proc/can_analyze(datum/act/op/A)
	return (advanced_tool_user(A.actor)) ? null : MSG(analyzer/clumsy)

/// Can `user` work a dexterous tool (hands, a species that can)?
/proc/advanced_tool_user(mob/user)
	READS_FROM() // a body's dexterity is asked when the tool is used
	return user.IsAdvancedToolUser()

MSG_DEF_SELF(analyzer/clumsy, "You don't have the dexterity to do this.")

/// Old attack_self: analyse the air around you.
/obj/item/analyzer/proc/interaction_self(datum/act/op/A)
	analyze_gases_by(src, src, A.actor)
	return OP_OK

/obj/item/analyzer/afterattack(obj/O, mob/user, proximity)
	if(proximity)
		analyze_gases_by(src, O, user)
	return
