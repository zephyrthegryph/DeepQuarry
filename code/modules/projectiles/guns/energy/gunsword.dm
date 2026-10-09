/obj/item/gun/energy/gun/fluff/gunsword
	name = "Sword Buster"
	desc = "The Sword Buster gun is custom built using the science behind a Golden Empire pistol. The cell can be removed in close range and used as energy shortsword."

	icon = 'icons/vore/custom_guns_vr.dmi'
	icon_state = "gbuster100"

	icon_override = 'icons/vore/custom_guns_vr.dmi'
	item_state = "gbuster"
	item_icons = list(slot_r_hand_str = 'icons/vore/custom_guns_vr.dmi', slot_l_hand_str = 'icons/vore/custom_guns_vr.dmi', "slot_belt" = 'icons/inventory/belt/mob.dmi')

	w_class = ITEMSIZE_NORMAL
	projectile_type = /obj/item/projectile/beam/stun
	fire_sound = SFX_WEAPONS_TASER
	charge_meter = 1

	cell_type = /obj/item/cell/device/weapon/gunsword

	modifystate = "gbuster"

	firemodes = list(
	list(mode_name="stun", charge_cost=240,projectile_type=/obj/item/projectile/beam/stun, modifystate="gbuster", fire_sound=SFX_WEAPONS_TASER),
	list(mode_name="lethal", charge_cost=480,projectile_type=/obj/item/projectile/beam/imperial, modifystate="gbuster", fire_sound=SFX_WEAPONS_MANDALORIAN),
	)

// -----------------gunsword battery--------------------------
/obj/item/cell/device/weapon/gunsword
	name = "Buster Cell"
	desc = "The Buster Cell. It doubles as a sword when activated outside the gun housing."
	icon = 'icons/vore/custom_guns_vr.dmi'
	icon_state = "gsaberoff"
	icon_override = 'icons/vore/custom_guns_vr.dmi'
	item_state = "gsaberoff"
	maxcharge = 2400
	charge_amount = 20
	standard_overlays = FALSE
	force = 3
	throwforce = 5
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL

	var/active = 0
	var/active_force = 30
	var/active_armourpen = 50
	var/active_throwforce = 20
	var/active_w_class = ITEMSIZE_LARGE
	var/active_embed_chance = 0		//In the off chance one of these is supposed to embed, you can just tweak this var
	sharp = FALSE
	edge = FALSE
	armor_penetration = 0
	flags = NOBLOODY
	var/lrange = 2
	var/lpower = 2
	var/lcolor = "#800080"


/obj/item/cell/device/weapon/gunsword/proc/activate(mob/living/user)
	if(active)
		return
	icon_state = "gsaber"
	item_state = "gsaber"
	active = 1
	embed_chance = active_embed_chance
	force = active_force
	armor_penetration = active_armourpen
	throwforce = active_throwforce
	sharp = TRUE
	edge = TRUE
	w_class = active_w_class
	play_sfx(src, SFX_WEAPONS_SABERON)
	set_light(lrange, lpower, lcolor)
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")



/obj/item/cell/device/weapon/gunsword/proc/deactivate(mob/living/user)
	if(!active)
		return
	play_sfx(src, SFX_WEAPONS_SABEROFF)
	icon_state = "gsaberoff"
	item_state = "gsaberoff"
	active = 0
	embed_chance = initial(embed_chance)
	force = initial(force)
	armor_penetration = initial(armor_penetration)
	throwforce = initial(throwforce)
	sharp = initial(sharp)
	edge = initial(edge)
	w_class = initial(w_class)
	set_light(0,0)
	attack_verb = null


CAPABILITIES(/obj/item/cell/device/weapon/gunsword)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/cell/device/weapon/gunsword/proc/interaction_self(datum/act/op/A)
	var/mob/living/user = A.actor
	if (active)
		if (CLUMSY_HARM_CHANCE(user))
			act_message(user, src, MSG_SELF(span_danger("You accidentally cut yourself with %T%.")), \
				MSG_OTHERS(span_danger("%U% accidentally cuts %THEMSELVES% with %T%.")))
			user.injure(INJURY_CUT, 5, source = src)
			user.injure(INJURY_BURN, 5, source = src)
		deactivate(user)
		update_held_icon()
	else
		activate(user)
		update_held_icon()

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	add_fingerprint(user)
	return TRUE

