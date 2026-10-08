/datum/technomancer/equipment/tesla_armor
	name = "Tesla Armor"
	desc = "This piece of armor offers a retaliation-based defense.  When the armor is 'ready', it will completely protect you from \
	the next attack you suffer, and strike the attacker with a strong bolt of lightning, provided they are close enough.  This effect requires \
	fifteen seconds to recharge.  If you are attacked while this is recharging, a weaker lightning bolt is sent out, however you won't be protected from \
	the person beating you."
	cost = 150
	obj_path = /obj/item/clothing/suit/armor/tesla

/obj/item/clothing/suit/armor/tesla
	name = "tesla armor"
	desc = "This rather dangerous looking armor will hopefully shock your enemies, and not you in the process."
	icon_state = "tesla_armor_1" //wip
	blood_overlay_type = "armor"
	slowdown = 0.5
	armor_spec = ""
	actions_types = list(/datum/action/item_action/toggle_tesla_armor)
	var/active = 1	//Determines if the armor will zap or block
	var/ready = 1 //Determines if the next attack will be blocked, as well if a strong lightning bolt is sent out at the attacker.
	var/ready_icon_state = "tesla_armor_1" //also wip
	var/normal_icon_state = "tesla_armor_0"
	var/cooldown_to_charge = 15 SECONDS

/obj/item/clothing/suit/armor/tesla/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	//First, some retaliation.
	if(active)
		if(istype(damage_source, /obj/item/projectile))
			var/obj/item/projectile/P = damage_source
			if(P.firer && get_dist(user, P.firer) <= 3)
				if(ready)
					shoot_lightning(P.firer, 40)
				else
					shoot_lightning(P.firer, 15)

		else
			if(attacker && attacker != user)
				if(get_dist(user, attacker) <= 3) //Anyone farther away than three tiles is too far to shoot lightning at.
					if(ready)
						shoot_lightning(attacker, 40)
					else
						shoot_lightning(attacker, 15)

		//Deal with protecting our wearer now.
		if(ready)
			set_ready(FALSE)
			after(src, cooldown_to_charge, PROC_REF(recharge_ready), key = "recharge_timer", with = list(user))
			act_message(user, null, others = span_danger("%U%'s [src.name] blocks [attack_text]!"))
			return 1
	return 0

CAPABILITIES(/obj/item/clothing/suit/armor/tesla)
	op("tesla_armor_toggle_self", in_hand(), label("Toggle"), then(PROC_REF(tesla_armor_toggle_self)))

/// Old attack_self.
/obj/item/clothing/suit/armor/tesla/proc/tesla_armor_toggle_self(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	to_chat(user, span_notice("You [active ? "" : "de"]activate \the [src]."))
	user.update_inv_wear_suit()
	user.update_mob_action_buttons()

TRACKED(/obj/item/clothing/suit/armor/tesla, active)
TRACKED(/obj/item/clothing/suit/armor/tesla, ready)

/// Lit while it is active and ready to block; the worn suit and the wearer's action buttons follow (effects of the look).
/obj/item/clothing/suit/armor/tesla/draw(datum/look/look)
	..()
	var/lit = active && ready
	look.state(lit ? ready_icon_state : normal_icon_state)
	look.held_state(lit ? ready_icon_state : normal_icon_state)
	if(lit)
		look.light(2, 1, "#006AFF")
	else
		look.light_off()
	look.effect(PROC_REF(look_effect_wearer_buttons))

/obj/item/clothing/suit/armor/tesla/proc/look_effect_wearer_buttons()
	var/mob/living/carbon/human/H = loc
	if(istype(H))
		H.update_inv_wear_suit(0)
		H.update_mob_action_buttons()

/obj/item/clothing/suit/armor/tesla/proc/recharge_ready(mob/user)
	set_ready(TRUE)
	to_chat(user, span_notice("\The [src] is ready to protect you once more."))

/obj/item/clothing/suit/armor/tesla/proc/shoot_lightning(mob/target, power)
	var/obj/item/projectile/beam/lightning/lightning = new(get_turf(src))
	lightning.power = power
	lightning.old_style_target(target)
	lightning.fire()
	visible_message(span_danger("\The [src] strikes \the [target] with lightning!"))
	play_sfx(src, SFX_WEAPONS_GAUSS_SHOOT, 1.5)
