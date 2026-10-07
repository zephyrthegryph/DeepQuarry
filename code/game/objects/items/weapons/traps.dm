
/*
 * Beartraps.
 * Buckles crossing individuals, doing moderate brute damage.
 */

/obj/item/beartrap
	name = "mechanical trap"
	throw_speed = 2
	throw_range = 1
	gender = PLURAL
	icon = 'icons/obj/items.dmi'
	icon_state = "beartrap0"
	desc = "A mechanically activated leg trap. Low-tech, but reliable. Looks like it could really hurt if you set it off."
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	throwforce = 0
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_STEEL, 18750)
	var/deployed = 0
	var/camo_net = FALSE
	var/stun_length = 0.25 SECONDS

/obj/item/beartrap/start_active
	deployed = TRUE

/obj/item/beartrap/proc/can_use(mob/user)
	return (user.IsAdvancedToolUser() && !issilicon(user) && !user.stat && !user.restrained())

MSG_DEF(beartrap/deploying, "You begin deploying %T%!", "%U% starts to deploy %T%.")
MSG_DEF(beartrap/deployed, "You have deployed %T%!", "%U% has deployed %T%.")
MSG_DEF(beartrap/freeing, "You carefully begin to free the one caught in %T%.", "%U% begins freeing the one caught in %T%.")
MSG_DEF(beartrap/freed, "You free the one caught in %T%.", "%U% frees the one caught in %T%.")
MSG_DEF(beartrap/disarming, "You begin disarming %T%!", "%U% starts to disarm %T%.")
MSG_DEF(beartrap/disarmed, "You have disarmed %T%!", "%U% has disarmed %T%.")

CAPABILITIES(/obj/item/beartrap)
	op("deploy", in_hand(), label("Deploy trap"), needs(req(PROC_REF(can_deploy), silent = TRUE)),
		begins(MSG(beartrap/deploying), blind = "You hear the slow creaking of a spring."), wait(6 SECONDS),
		then(PROC_REF(deploy_trap)), says(MSG(beartrap/deployed), blind = "You hear a latch click loudly."))
	op("free", hand(), label("Free the victim"), when(PROC_REF(can_free)), priority(OP_PRIORITY_TAKE_OUT), begins(MSG(beartrap/freeing)), wait(6 SECONDS),
		then(PROC_REF(free_victim)), says(MSG(beartrap/freed)))
	op("disarm", hand(), label("Disarm"), when(PROC_REF(can_disarm)),
		begins(MSG(beartrap/disarming), blind = "You hear a latch click followed by the slow creaking of a spring."), plays(SFX_MACHINES_CLICK), wait(6 SECONDS),
		then(PROC_REF(disarm_trap)), says(MSG(beartrap/disarmed)))

/obj/item/beartrap/proc/can_deploy(datum/act/op/A)
	return !deployed && can_use(A.actor)

/obj/item/beartrap/proc/can_free(datum/act/op/A)
	return has_buckled_mobs() && can_use(A.actor)

/obj/item/beartrap/proc/can_disarm(datum/act/op/A)
	return !has_buckled_mobs() && deployed && can_use(A.actor)

/obj/item/beartrap/proc/deploy_trap(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(src, SFX_MACHINES_CLICK, 1.4)

	deployed = 1
	user.drop_from_inventory(src)
	changed(src)
	set_anchored(TRUE)
	log_and_message_admins("has set up a [name] at \the [get_area(loc)]", user)

/obj/item/beartrap/proc/free_victim(datum/act/op/A)
	for(var/mob/victim in src?.buckled_mob_list())
		unbuckle_mob(victim)
	set_anchored(FALSE)

/obj/item/beartrap/proc/disarm_trap(datum/act/op/A)
	deployed = 0
	set_anchored(FALSE)
	changed(src)

/obj/item/beartrap/proc/attack_mob(mob/living/L)

	var/target_zone
	if(L.lying)
		target_zone = ran_zone()
	else
		target_zone = pick(BP_L_FOOT, BP_R_FOOT, BP_L_LEG, BP_R_LEG)

	//armour
	var/blocked = L.armor_against(INJURY_PIERCE, target_zone)

	if(blocked >= 100)
		return

	if(!L.injure(INJURY_PIERCE, 30, target_zone, src, flags = INJURE_ARMORED))
		return 0

	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		var/obj/item/organ/external/affected = H.get_organ(check_zone(target_zone))
		if(!affected) // took it clean off!
			to_chat(H, span_danger("The steel jaws of \the [src] take your limb clean off!"))
			L.status_at_least(STAT_STUNNED, stun_length*2)
			deployed = 0
			set_anchored(FALSE)
			return

	//trap the victim in place
	set_dir(L.dir)
	set_can_buckle(TRUE)
	buckle_mob(L)
	L.status_at_least(STAT_STUNNED, stun_length)
	to_chat(L, span_danger("The steel jaws of \the [src] bite into you, trapping you in place!"))
	deployed = 0
	set_anchored(FALSE)
	set_can_buckle(initial(can_buckle))

/obj/item/beartrap/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(deployed && isliving(AM))
		var/mob/living/L = AM
		if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step on %T%!")), \
				MSG_OTHERS(span_danger("%U% steps on %T%.")), \
				MSG_BLIND(span_infoplain(span_bold("You hear a loud metallic snap!"))))
			SSmotiontracker.ping(src,100) // Clunk!
			attack_mob(L)
			if(!has_buckled_mobs())
				set_anchored(FALSE)
			deployed = 0
			changed(src)
			log_and_message_admins("has sprung a [name] at \the [get_area(loc)], last touched by [forensic_data?.get_lastprint()]", L)
	..()

/obj/item/beartrap/draw(datum/look/look)
	..()

	if(!deployed)
		if(camo_net)
			look.set_alpha(255)

		look.state("beartrap0")
	else
		if(camo_net)
			look.set_alpha(50)

		look.state("beartrap1")

/obj/item/beartrap/hunting
	name = "hunting trap"
	desc = "A mechanically activated leg trap. High-tech and reliable. Looks like it could really hurt if you set it off."
	stun_length = 1 SECOND
	camo_net = TRUE
	color = "#C9DCE1"

/*
 * Barbed-Wire.
 * Slows individuals crossing it. Barefoot individuals will be cut. Can be electrified by placing over a cable node.
 */

/obj/item/material/barbedwire
	name = "barbed wire"
	desc = "A coil of wire."
	icon = 'icons/obj/trap.dmi'
	icon_state = "barbedwire"
	anchored = FALSE
	layer = TABLE_LAYER
	w_class = ITEMSIZE_LARGE
	explosion_resistance = 1
	can_dull = TRUE
	fragile = TRUE
	force_divisor = 0.20
	thrown_force_divisor = 0.25

	sharp = TRUE
	injury_kind = INJURY_PIERCE

/obj/item/material/barbedwire/set_material(new_material)
	..()

	if(!QDELETED(src))
		max_integrity = max(1, round(material.integrity / 3)) * MATERIAL_WEAR_UNIT
		update_integrity(max_integrity)
		name = (material.edge_damage() * force_divisor > 15) ?  "[material.display_name] razor wire" : "[material.display_name] [initial(name)]"

/obj/item/material/barbedwire/proc/can_use(mob/user)
	return (user.IsAdvancedToolUser() && !issilicon(user) && !user.stat && !user.restrained())

CAPABILITIES(/obj/item/material/barbedwire)
	op("deploy", in_hand(), label("Deploy trap"), then(PROC_REF(deploy_trap_input)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("collect", hand(), then(PROC_REF(interaction_hand)))
	// a hit wears the coil, then the material's own repair still has its turn
	op("barbedwire_hit", item(/obj/item), priority(OP_PRIORITY_PART + 1), then(PROC_REF(barbedwire_interaction_item)))

/obj/item/material/barbedwire/proc/deploy_trap_input(datum/act/op/A)
	interaction_self(A.actor, A.held, null)
	return OP_OK

/// Old attack_hand: collect a deployed coil (anything else is the pick up).
/obj/item/material/barbedwire/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(anchored && can_use(user))
		act_message(user, src, MSG_SELF(span_notice("You begin collecting %T%!")), \
			MSG_OTHERS(span_danger("%U% starts to collect %T%.")), \
			MSG_BLIND("You hear the sound of rustling [material.name]."))
		play_sfx(src, SFX_MACHINES_CLICK)

		task_timed(user, get_integrity() / MATERIAL_WEAR_UNIT, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done3), done_args = list(user))
	else
		return OP_DECLINE
	return OP_OK

/obj/item/material/barbedwire/proc/attack_hand_timed_done3(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You have collected %T%!")), \
		MSG_OTHERS(span_danger("%U% has collected %T%.")))
	set_anchored(FALSE)

/// Old attack_self.
/obj/item/material/barbedwire/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!anchored && can_use(user))
		act_message(user, src, MSG_SELF(span_danger("You begin deploying %T%!")), \
			MSG_OTHERS(span_danger("%U% starts to deploy %T%.")), \
			MSG_BLIND("You hear the rustling of [material.name]."))

		task_timed(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done2), done_args = list(user))
	return TRUE

/obj/item/material/barbedwire/proc/attack_self_timed_done2(mob/user)
	act_message(user, src, MSG_SELF(span_danger("You have deployed %T%!")), \
		MSG_OTHERS(span_danger("%U% has deployed %T%.")), \
		MSG_BLIND("You hear the rustling of [material.name]."))
	play_sfx(src, SFX_ITEMS_WIRECUTTER, 0.7)
	after(src, 0.2 SECONDS, TYPE_PROC_REF(/atom, om_playsound), with = list('sound/items/Wirecutter.ogg', 40, 1))
	user.drop_from_inventory(src)
	forceMove(get_turf(src))
	set_anchored(TRUE)

/// Old attackby: wear from being hit, then falls through as its ..() did.
/obj/item/material/barbedwire/proc/barbedwire_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W))
		return OP_PASS

	if((W.flags & NOCONDUCT) || !shock(user, 70, pick(BP_L_HAND, BP_R_HAND)))
		user.setClickCooldown(user.get_attack_speed(W))
		user.do_attack_animation(src)
		play_sfx(src, SFX_EFFECTS_GRILLEHIT, 0.8)

		var/inc_damage = W.force

		if(W.obj_damage_type() != BRUTE)
			inc_damage *= 0.3

		material_wear(inc_damage * MATERIAL_WEAR_UNIT)

	return OP_DECLINE

/obj/item/material/barbedwire/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!istype(tool))
		return OP_OK

	if((tool.flags & NOCONDUCT) || !shock(user, 70, pick(BP_L_HAND, BP_R_HAND)))
		user.setClickCooldown(user.get_attack_speed(tool))
		user.do_attack_animation(src)
		play_sfx(src, SFX_EFFECTS_GRILLEHIT, 0.8)

		var/inc_damage = tool.force

		if(!shock(user, 100, pick(BP_L_HAND, BP_R_HAND)))
			playsound(src, tool.usesound, 100, 1)
			inc_damage *= 3

		if(tool.obj_damage_type() != BRUTE)
			inc_damage *= 0.3

		material_wear(inc_damage * MATERIAL_WEAR_UNIT)

	return OP_OK

/// The look (the draw sweep: from its template).
/obj/item/material/barbedwire/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][anchored ? "-out" : ""]")

/obj/item/material/barbedwire/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(anchored && isliving(AM))
		var/mob/living/L = AM
		if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step in %T%!")), \
				MSG_OTHERS(span_danger("%U% steps in %T%.")), \
				MSG_BLIND(span_infoplain(span_bold("You hear a sharp rustling!"))))
			attack_mob(L)
	..()

/obj/item/material/barbedwire/proc/shock(mob/user as mob, prb, target_zone = BP_TORSO)
	if(!anchored || get_integrity() <= 0)		// anchored/destroyed grilles are never connected
		return 0
	if(material.conductivity <= 0)
		return 0
	if(!prob(prb))
		return 0
	if(!in_range(src, user))//To prevent TK and mech users from getting shocked
		return 0
	var/turf/T = get_turf(src)
	var/obj/structure/cable/C = T.get_cable_node()
	if(C)
		var/PN = C.get_power_region()
		if(PN)

			if(PN)
				power_warn(PN)

				var/PN_damage = power_electrocute_damage(PN) * (material.conductivity / 50)

				var/drained_energy = PN_damage * 10 / CELLRATE

				power_draw(PN, drained_energy)

				if(ishuman(user))
					var/mob/living/carbon/human/H = user

					var/obj/item/organ/external/affected = H.get_organ(check_zone(target_zone))

					H.electrocute_act(PN_damage, src, H.get_siemens_coefficient_organ(affected))

				else
					if(isliving(user))
						var/mob/living/L = user
						L.electrocute_act(PN_damage, src, 0.8)

			fx_sparks(src, 3)
			if(user.has_status(STAT_STUNNED))
				return 1
		else
			return 0
	return 0

/obj/item/material/barbedwire/proc/attack_mob(mob/living/L)
	var/target_zone
	if(L.lying)
		target_zone = ran_zone()
	else
		target_zone = pick(BP_L_FOOT, BP_R_FOOT, BP_L_LEG, BP_R_LEG)

	//armour
	var/blocked = L.armor_against(injury_kind, target_zone)

	if(blocked >= 100)
		return

	if(L?.buckled_to()) //wheelchairs, office chairs, rollerbeds
		return

	shock(L, 100, target_zone)

	L.apply_body_effect(/datum/body_effect/entangled, 3 SECONDS)

	if(!L.injure(injury_kind, force * (issilicon(L) ? 0.25 : 1), target_zone, src, flags = INJURE_ARMORED))
		return

	play_sfx(src, SFX_EFFECTS_GLASS_STEP) // not sure how to handle metal shards with sounds
	if(ishuman(L))
		var/mob/living/carbon/human/H = L

		if(H.species.siemens_coefficient<0.5) //Thick skin.
			return

		if( H.get_equipped_item(SLOT_ID_SHOES) || ( H.get_equipped_item(SLOT_ID_SUIT) && (H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & FEET) ) )
			return

		if(H.species.flags & NO_MINOR_CUT)
			return

		to_chat(H, span_danger("You step directly on \the [src]!"))

		var/list/check = list(BP_L_FOOT, BP_R_FOOT)
		while(check.len)
			var/picked = pick(check)
			var/obj/item/organ/external/affecting = H.get_organ(picked)
			if(affecting)
				if(affecting.is_robotic())
					return
				H.injure(INJURY_BLUNT, force, affecting, src)
				if(affecting.organ_can_feel_pain())
					H.status_at_least(STAT_WEAKENED, 3)
				return
			check -= picked

	if(material.is_brittle() && prob(material.hardness))
		material_wear(get_integrity())
	else if(!prob(material.hardness))
		material_wear(MATERIAL_WEAR_UNIT)

	return

/obj/item/material/barbedwire/plastic
	name = "snare wire"
	default_material = MAT_PLASTIC


// === merged from traps_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/beartrap
	slot_flags = SLOT_MASK
	item_icons = list(
		slot_wear_mask_str = 'icons/inventory/face/mob.dmi'
		)

/obj/item/beartrap/equipped()
	if(ishuman(src.loc))
		var/mob/living/carbon/human/H = src.loc
		if(H.get_equipped_item(SLOT_ID_MASK) == src)
			grant(H, granted_verb(/mob/living/proc/shred_limb_temp), src)
		else
			revoke(H, granted_verb(/mob/living/proc/shred_limb_temp), src)
	..()

/obj/item/beartrap/dropped(mob/user, equipping, slot)
	if(user)
		revoke(user, granted_verb(/mob/living/proc/shred_limb_temp), src)
	..()
