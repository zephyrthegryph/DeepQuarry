/obj/item/rig_module/gauntlets

	name = "proto-kinetic gear unit"
	desc = "A set of paired proto-kinetic gauntlets and greaves. There's no way this is actually usable. Right?"
	icon_state = "module"

	interface_name = "proto-kinetic gear unit"
	interface_desc = "A set of paired proto-kinetic gauntlets and greaves. For disrupting rocks and creatures' innards."

	activate_string = "Deploy Gauntlets"
	deactivate_string = "Undeploy Gauntlets"

	usable = 0
	toggleable = 1
	use_power_cost = 0
	active_power_cost = 0
	passive_power_cost = 0
	var/obj/item/kinetic_crusher/machete/gauntlets/rig/stored_gauntlets

DECLARE_DEFAULT_CHILD(/obj/item/rig_module/gauntlets, "stored_gauntlets", /obj/item/kinetic_crusher/machete/gauntlets/rig)

/obj/item/rig_module/gauntlets/Initialize(mapload)
	. = ..()
	rel_set(stored_gauntlets, nameof(stored_gauntlets.storing_module), src)

/obj/item/rig_module/gauntlets/activate(skip_engage = 0, mob/user)
	if(!..())
		return
	var/mob/living/M = holder.wearer()
	if(!M)
		return

	if(M.get_equipped_item(SLOT_ID_HAND_L) && M.get_equipped_item(SLOT_ID_HAND_R))
		to_chat(M, span_danger("Your hands are full."))
		deactivate()
		return
	if(M.combat_mode)
		act_message(M, null, MSG_SELF(span_danger("You throw your arms out, extending [stored_gauntlets] from \the [holder] with a click!")), \
			MSG_OTHERS(span_danger("%U% throws %THEIR% arms out, extending [stored_gauntlets] from \the [holder] with a click!")), \
			MSG_BLIND(span_notice("You hear a threatening hiss and a click.")))
	else
		act_message(M, null, MSG_SELF(span_notice("You extend  [stored_gauntlets] from \the [holder] with a click!")), \
			MSG_OTHERS(span_notice("%U% extends [stored_gauntlets] from \the [holder] with a click!")), \
			MSG_BLIND(span_notice("You hear a hiss and a click.")))

	play_sfx(src, SFX_ITEMS_HELMETDEPLOY)
	M.put_in_hands(stored_gauntlets)

/obj/item/rig_module/gauntlets/deactivate()
	..()
	var/mob/living/M = holder.wearer()
	if(!M)
		return
	for(var/obj/item/kinetic_crusher/machete/gauntlets/gaming in contents_of(M))
		M.drop_from_inventory(gaming, src)

/obj/item/rig_module/gauntlets/ownership()
	. = ..()
	. += owns(nameof(stored_gauntlets), policy = OWN_CONTAINED)
