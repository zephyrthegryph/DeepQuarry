// Protean host powers: folding into the control cluster, latching onto a host
// and assimilating them. The character mob itself sits inside the cluster,
// with a real loc, and keeps living.

/datum/protean_power/hardsuit
	name = "Hardsuit Transform"
	desc = "Coalesce your nanite swarm into their control module, allowing others to wear you."
	icon_state = "rig"
	usable_in_rig = TRUE
	verb_path = /mob/living/carbon/human/proc/nano_rig_transform

/datum/protean_power/hardsuit/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	if(F.in_rig())
		F.leave_rig()
		return
	if(H.resting)
		to_chat(H, span_warning("You can only do this while standing."))
		return
	to_chat(H, span_notice("You rapidly condense into your module."))
	if(!do_after(H, 2 SECONDS, target = H))
		to_chat(H, span_warning("You must remain still to condense!"))
		return
	if(can_use(H, F) && F.form_control_check())
		F.enter_rig()

/mob/living/carbon/human/proc/nano_rig_transform()
	set name = "Modify Form - Hardsuit"
	set desc = "Allows a protean to retract its mass into its hardsuit module at will."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/hardsuit)

/datum/protean_power/latch_host
	name = "Latch Host"
	desc = "Forcibly latch or unlatch your RIG from a host mob."
	icon_state = "latch"
	usable_in_rig = TRUE
	verb_path = /mob/living/carbon/human/proc/nano_latch

/datum/protean_power/latch_host/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	if(F.in_rig())
		var/mob/living/wearer = F.rig.wearer
		if(!wearer)
			to_chat(H, span_warning("You aren't being worn, dummy."))
			return
		wearer.drop_from_inventory(F.rig)
		to_chat(H, span_notice("You detach from your host."))
		return
	var/obj/item/grab/G = H.get_active_hand()
	if(!istype(G))
		to_chat(H, span_warning("You need to be grabbing a humanoid mob aggressively to latch onto them."))
		return
	var/mob/living/carbon/human/target = GRAB_TARGET(G)
	if(!istype(target))
		to_chat(H, span_warning("You can only latch onto humanoid mobs!"))
		return
	if(target.GetComponent(/datum/component/forms/protean))
		to_chat(H, span_danger("You can't latch onto a fellow Protean!"))
		return
	if(G.state < GRAB_AGGRESSIVE)
		to_chat(H, span_warning("You need a more aggressive grab to do this!"))
		return
	H.visible_message(span_warning("[H] is attempting to latch onto [target]!"), span_danger("You attempt to latch onto [target]!"))
	if(!do_after(H, 5 SECONDS, target))
		return
	if(QDELETED(G) || G.loc != H || G.state < GRAB_AGGRESSIVE || !can_use(H, F))
		return
	if(target.get_equipped_item(SLOT_ID_BACK))
		target.drop_from_inventory(target.get_equipped_item(SLOT_ID_BACK))
	H.visible_message(span_danger("[H] latched onto [target]!"), span_danger("You latch yourself onto [target]!"))
	target.status_at_least(EFFECT_WEAKENED, 3)
	if(!F.enter_rig())
		return
	target.equip_to_slot(F.rig, slot_back)
	log_game("PROTEAN: [key_name(H)] latched onto [key_name(target)] at [AREACOORD(target)]")

/mob/living/carbon/human/proc/nano_latch()
	set name = "Latch/Unlatch host"
	set desc = "Allows a protean to forcibly latch or unlatch from a host."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/latch_host)

/datum/protean_power/assimilate_host
	name = "Assimilate Host"
	desc = "Allows a protean to assimilate a latched host, allowing them to devour them right away."
	icon_state = "assimilate"
	usable_in_rig = TRUE
	rig_only = TRUE
	verb_path = /mob/living/carbon/human/proc/nano_assimilate

/datum/protean_power/assimilate_host/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	if(!F.rig.wearer)
		to_chat(H, span_vwarning("You need a host to assimilate."))
		return
	log_game("PROTEAN: [key_name(H)] assimilated their host [key_name(F.rig.wearer)]")
	F.leave_rig(devour = TRUE)

/mob/living/carbon/human/proc/nano_assimilate()
	set name = "Assimilate Host"
	set desc = "Allows a protean to assimilate a latched host, allowing them to devour them right away."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/assimilate_host)

/datum/protean_power/rig_interface
	name = "Utilize Hardsuit Interface"
	desc = "Open your control cluster's hardsuit interface."
	usable_in_rig = TRUE
	rig_only = TRUE
	in_stat_panel = FALSE
	verb_path = /mob/living/carbon/human/proc/usehardsuit

/datum/protean_power/rig_interface/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	to_chat(H, "You attempt to interface with the [F.rig].")
	F.rig.tgui_interact(H)

/mob/living/carbon/human/proc/usehardsuit()
	set name = "Utilize Hardsuit Interface"
	set desc = "Allows a protean to open its hardsuit interface."
	set category = "Abilities.Protean"
	activate_protean_power(/datum/protean_power/rig_interface)
