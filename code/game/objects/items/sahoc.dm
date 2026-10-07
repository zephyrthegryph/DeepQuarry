/obj/item/buttonofnormal
	name = "Chaos button"
	desc = "It radiates an aura of chaotic size energy."
	icon = 'icons/obj/mobcap.dmi'
	icon_state = "mobcap0"
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 1000)
	throwforce = 00
	throw_speed = 4
	throw_range = 20
	force = 0
	var/colorindex = 0
	var/mob/living/capsuleowner //taken from Capsule Code
	var/sizetouse = 0.25

/obj/item/buttonofnormal/pickup(mob/user)
	if(!capsuleowner())
		rel_set(src, nameof(capsuleowner), user)

CAPABILITIES(/obj/item/buttonofnormal)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/buttonofnormal/proc/interaction_self(datum/act/op/A)
	if(colorindex)
		nonrandom()
	after(src, 1 SECONDS, PROC_REF(do_size_effect), with = list(capsuleowner()))
	return TRUE

/obj/item/buttonofnormal/throw_impact(atom/A, speed, mob/user)
	..()
	if(isliving(A))
		if(colorindex)
			nonrandom()
		after(src, 0.5 SECONDS, PROC_REF(do_size_effect), with = list(A))

/obj/item/buttonofnormal/proc/do_size_effect(atom/A)
	var/mob/living/capsulehit = A
	if(!istype(capsulehit))
		return
	capsulehit.resize(sizetouse)
	sizetouse = rand(25,200)/100 //randmization occurs after press

/// Old attackby.
/obj/item/buttonofnormal/proc/interaction_item(datum/act/op/A)
	var/obj/item/W = A.held
	if(istype(W, /obj/item/pen))
		colorindex = (colorindex + 1) % 6
		icon_state = "mobcap[colorindex]"
	if(istype(W, /obj/item/card/id))
		rel_clear(src, nameof(capsuleowner))
	return OP_DECLINE

/obj/item/buttonofnormal/proc/nonrandom() //Secret ball randmoizer rig code
	switch(colorindex)
		if(1)	sizetouse = RESIZE_HUGE
		if(2)	sizetouse = RESIZE_BIG
		if(3)	sizetouse = RESIZE_NORMAL
		if(4)	sizetouse = RESIZE_SMALL
		if(5)	sizetouse = RESIZE_TINY

/obj/item/daredevice
	name = "Dare button"
	desc = "A strange button, the only distinguishing feature being an engraved text reading 'Suffer to Gain.'."
	icon = 'icons/obj/mobcap.dmi'
	icon_state = "mobcap1"
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 5000)
	throwforce = 00
	throw_speed = 2
	throw_range = 20
	force = 0
	var/luckynumber7 = 0
	var/colorindex = 1

	var/static/list/winitems = list(
				/obj/item/reagent_containers/food/snacks/sugarcookie,
				/obj/item/spacecasinocash,
				/obj/item/reagent_containers/syringe/drugs,
	)

/// Old attackby.
/obj/item/daredevice/proc/interaction_item(datum/act/op/A)
	var/obj/item/W = A.held
	if(istype(W, /obj/item/pen))
		colorindex += 1
		if(colorindex >= 6)
			colorindex = 0
		icon_state = "mobcap[colorindex]"
	return OP_DECLINE

CAPABILITIES(/obj/item/daredevice)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/daredevice/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/capsuleowner = user
	play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
	var/item = pick(winitems)
	after(src, 10 SECONDS, PROC_REF(capsule_result), with = list(capsuleowner, item), keeps_dead = TRUE)
	return TRUE

/obj/item/daredevice/proc/capsule_result(mob/living/capsuleowner, item)
	if(capsuleowner)
		switch(luckynumber7)
			if(1)	capsuleowner.resize(RESIZE_TINY) //Loss Shrinking!
			if(2)	capsuleowner.injure(INJURY_BLUNT, 5, source = src) //Loss Damaging!
			if(3)	capsuleowner.status_at_least(STAT_WEAKENED, 5) //Loss Knee spaghetti!
			if(4)	capsuleowner.status_adjust(STAT_HALLUCINATING, 66) //loss woah, dude.
			if(5)	new	item(capsuleowner.loc) //Win!
			if(7)
				new	/obj/item/material/butterfly/switchblade(capsuleowner.loc)
				capsuleowner.injure(INJURY_CUT, 10, source = src) //Loss Damaging! WIN KNIVE!
			if(9)
				var/atom/product_location = capsuleowner.loc
				if(consume(src, capsuleowner))
					new /obj/item/gun/energy/sizegun/not_advanced(product_location)
				return
			if(777)	new	/obj/item/spacecash/c1000(capsuleowner.loc) //for rigging
			else luckynumber7 = (rand(0,10))
	luckynumber7 = rand(0,10)
	after(src, 10 SECONDS, PROC_REF(capsule_reset))

/obj/item/daredevice/proc/capsule_reset()
	play_sfx(src.loc, SFX_MACHINES_SLOTMACHINE)

//items literally just made for the above item spawner

//
//BADvanced size gun
//
/obj/item/gun/energy/sizegun/not_advanced
	name = "\improper corrupted size gun" // Adds \improper
	desc = "A highly advanced ray gun with a knob on the side to adjust the size you desire. Or at least that's what it used to be."
	projectile_type = /obj/item/projectile/beam/sizelaser/chaos
	charge_cost = 60 //1/3 of the base price for a normal one.
//
//CHAOS laser
//
/obj/item/projectile/beam/sizelaser/chaos //The Defintiely not advanced sizeguns laser.
	name = "chaos size beam"
	light_color = "#FF0000"
	light_range = 3
	light_power = 9 //should be plenty visible.
	var/static/list/chaos_colors = list(
					"#FF0000",
					"#00FF00",
					"#0000FF",
					"#FFFF00",
					"#00FFFF",
					"#FF00FF",
					"#000000",
					"#FFFFFF",
					"#F0F0F0",
					"#0F0F0F",
					)

/obj/item/projectile/beam/sizelaser/chaos/on_hit(atom/target)
	light_color = pick(chaos_colors)
	var/chaos = rand(25,200)
	var/mob/living/M = target
	if(ishuman(target))
		var/mob/living/carbon/human/H = M
		H.resize(chaos/100)
		H.show_message(span_purple("The beam fires into your body, changing your size!"))
		H.update_icon()
	else if (istype(target, /mob/living/))
		var/mob/living/H = M
		H.resize(chaos/100)
		H.update_icon()
	else
		return 1

/// Relation view: capsuleowner (reads null once it is gone).
/obj/item/buttonofnormal/proc/capsuleowner() as /mob/living
	return capsuleowner
