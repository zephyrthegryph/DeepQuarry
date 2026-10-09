/obj/structure/outcrop
	name = "outcrop"
	desc = "A boring rocky outcrop."
	icon = 'icons/obj/outcrop.dmi'
	density = TRUE
	throwpass = 1
	anchored = TRUE
	icon_state = "outcrop"
	var/mindrop = 5
	var/upperdrop = 10
	var/outcropdrop = /obj/item/ore/glass

CAPABILITIES(/obj/structure/outcrop)
	climb()
	op("pickaxe", item(/obj/item/pickaxe), label("Dig"), priority(OP_PRIORITY_PART), begins(MSG(outcrop/hacking)), wait(4 SECONDS), then(PROC_REF(dig_done)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

MSG_DEF(outcrop/hacking, span_notice("%U% begins to hack away at %T%."), span_notice("%U% begins to hack away at %T%."))

// ALLOW(init/INSTANCE_STATE): rolls whether this outcrop shows an egg
/obj/structure/outcrop/Initialize(mapload)
	. = ..()
	if(prob(1))
		add_overlay("[initial(icon_state)]-egg")

/obj/structure/outcrop/diamond
	name = "shiny outcrop"
	desc = "A shiny rocky outcrop."
	icon_state = "outcrop-diamond"
	mindrop = 2
	upperdrop = 4
	outcropdrop = /obj/item/ore/diamond

/obj/structure/outcrop/phoron
	name = "shiny outcrop"
	desc = "A shiny rocky outcrop."
	icon_state = "outcrop-phoron"
	mindrop = 4
	upperdrop = 8
	outcropdrop = /obj/item/ore/phoron

/obj/structure/outcrop/iron
	name = "rugged outcrop"
	desc = "A rugged rocky outcrop."
	icon_state = "outcrop-iron"
	mindrop = 10
	upperdrop = 20
	outcropdrop = /obj/item/ore/iron

/obj/structure/outcrop/coal
	name = "rugged outcrop"
	desc = "A rugged rocky outcrop."
	icon_state = "outcrop-coal"
	mindrop = 10
	upperdrop = 20
	outcropdrop = /obj/item/ore/coal

/obj/structure/outcrop/lead
	name = "rugged outcrop"
	desc = "A rugged rocky outcrop."
	icon_state = "outcrop-lead"
	mindrop = 2
	upperdrop = 5
	outcropdrop = /obj/item/ore/lead

/obj/structure/outcrop/gold
	name = "hollow outcrop"
	desc = "A hollow rocky outcrop."
	icon_state = "outcrop-gold"
	mindrop = 4
	upperdrop = 6
	outcropdrop = /obj/item/ore/gold

/obj/structure/outcrop/silver
	name = "hollow outcrop"
	desc = "A hollow rocky outcrop."
	icon_state = "outcrop-silver"
	mindrop = 6
	upperdrop = 8
	outcropdrop = /obj/item/ore/silver

/obj/structure/outcrop/platinum
	name = "hollow outcrop"
	desc = "A hollow rocky outcrop."
	icon_state = "outcrop-platinum"
	mindrop = 2
	upperdrop = 5
	outcropdrop = /obj/item/ore/osmium

/obj/structure/outcrop/uranium
	name = "spiky outcrop"
	desc = "A spiky rocky outcrop, it glows faintly."
	icon_state = "outcrop-uranium"
	mindrop = 4
	upperdrop = 8
	outcropdrop = /obj/item/ore/uranium

/obj/structure/outcrop/proc/dig_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You have finished digging!"))
	for(var/i=0;i<(rand(mindrop,upperdrop));i++)
		new outcropdrop(get_turf(src))
	consume(src, user)

/// Old attackby.
/obj/structure/outcrop/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (istype(W, /obj/item/melee/shock_maul))
		var/obj/item/melee/shock_maul/S = W
		if(!S.wielded || !S.status)
			to_chat(user, span_warning("\The [S] must be wielded in two hands and powered on to be used to mine this!"))
			return OP_PASS
		to_chat(user, span_notice("You pulverize \the [src]!"))
		for(var/i=0;i<(rand(mindrop,upperdrop));i++)
			new outcropdrop(get_turf(src))
		play_sfx(src, SFX_WEAPONS_RESONATOR_BLAST)
		user.visible_message(span_warning("\The [S] discharges with a thunderous, hair-raising crackle!"))
		S.deductcharge()
		S.set_status(0)
		S.update_held_icon()
		consume(src, user)
		return OP_PASS
	return OP_PASS

/obj/random/outcrop //In case you want an outcrop without pre-determining the type of ore.
	name = "random rock outcrop"
	desc = "This is a random rock outcrop."
	icon = 'icons/obj/outcrop.dmi'
	icon_state = "outcrop-random"

DECLARE_LOOT(/obj/random/outcrop, LOOT_TABLE(\
	/obj/structure/outcrop = 100, \
	/obj/structure/outcrop/iron = 100, \
	/obj/structure/outcrop/coal = 100, \
	/obj/structure/outcrop/silver = 65, \
	/obj/structure/outcrop/gold = 50, \
	/obj/structure/outcrop/uranium = 30, \
	/obj/structure/outcrop/phoron = 30, \
	/obj/structure/outcrop/diamond = 7, \
	/obj/structure/outcrop/platinum = 15, \
	/obj/structure/outcrop/lead = 15))
