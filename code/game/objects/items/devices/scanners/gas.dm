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

DECLARE_INTERACTIONS(/obj/item/analyzer, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/analyzer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	if (user.stat)
		return
	if (!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return

	analyze_gases_by(src, src, user)
	return

/obj/item/analyzer/afterattack(obj/O, mob/user, proximity)
	if(proximity)
		analyze_gases_by(src, O, user)
	return
