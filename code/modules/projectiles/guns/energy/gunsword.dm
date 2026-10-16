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
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL

	var/active = 0
	var/active_force = 30
	var/active_armourpen = 50
	var/active_throwforce = 20
	var/active_w_class = ITEMSIZE_LARGE
	var/active_embed_chance = 0		//In the off chance one of these is supposed to embed, you can just tweak this var
	flags = NOBLOODY
	var/lrange = 2
	var/lpower = 2
	var/lcolor = "#800080"


/obj/item/cell/device/weapon/gunsword/proc/activate(mob/living/user)
	if(active)
		return
	set_icon_state("gsaber")
	set_item_state("gsaber")
	active = 1
	embed_chance = active_embed_chance
	set_force(active_force)
	set_armor_penetration(active_armourpen)
	set_throwforce(active_throwforce)
	set_sharp(TRUE)
	set_edge(TRUE)
	set_w_class(active_w_class)
	play_sfx(src, SFX_WEAPONS_SABERON)
	set_glow(src, GLOW(lrange, lpower, lcolor))
	set_attack_verb(list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut"))



/obj/item/cell/device/weapon/gunsword/proc/deactivate(mob/living/user)
	if(!active)
		return
	play_sfx(src, SFX_WEAPONS_SABEROFF)
	set_icon_state("gsaberoff")
	set_item_state("gsaberoff")
	active = 0
	embed_chance = initial(embed_chance)
	set_force(combat_of_type(type).force)
	set_armor_penetration(combat_of_type(type).armor_penetration)
	set_throwforce(thrown_of_type(type).force)
	set_sharp(combat_of_type(type).sharp)
	set_edge(combat_of_type(type).edge)
	set_w_class(initial(w_class))
	set_glow(src, GLOW(0, 0, null))
	set_attack_verb(null)


CAPABILITIES(/obj/item/cell/device/weapon/gunsword)
	configure(item_thrown(force = 5))
	configure(item_combat(force = 3, sharp = FALSE, edge = FALSE, armor_penetration = 0))
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


	add_fingerprint(user)
	return TRUE

