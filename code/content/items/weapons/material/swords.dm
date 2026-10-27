/obj/item/material/sword
	name = "claymore"
	desc = "What are you standing around staring at this for? Get to killing!"
	icon_state = "claymore"
	force_divisor = 0.7 // 42 when wielded with hardnes 60 (steel)
	thrown_force_divisor = 0.5 // 10 when thrown with weight 20 (steel)

CAPABILITIES(/obj/item/material/sword)
	configure(item_combat(injury_kind = INJURY_CUT))
	configure(item_worn(slots = SLOT_BELT))
	configure(item_combat(sharp = TRUE, edge = TRUE, attack_verbs = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE, drop = SFX_ITEMS_DROP_SWORD, pickup = SFX_ITEMS_PICKUP_SWORD))

/obj/item/material/sword/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(unique_parry_check(user, attacker, damage_source) && prob(50))
		act_message(user, src, others = span_danger("%U% parries [attack_text] with %T%!"))
		play_sfx(src, SFX_WEAPONS_PUNCHMISS, 2, extrarange = 0)
		return 1
	return 0

/obj/item/material/sword/katana
	name = "katana"
	desc = "Woefully underpowered in D20. This one looks pretty sharp."
	icon_state = "katana"

CAPABILITIES(/obj/item/material/sword/katana)
	configure(item_worn(slots = SLOT_BELT | SLOT_BACK))

/obj/item/material/sword/katana/caneblade
	name = "cane blade"
	desc = "Used for making people fall over instead of helping them stand up."
	icon_state = "caneblade"
	item_state = "caneblade"

/obj/item/material/sword/rapier
	name = "rapier"
	desc = "A slender, fancy and sharply pointed sword."
	icon_state = "rapier"
	item_state = "rapier"
	applies_material_colour = 0

CAPABILITIES(/obj/item/material/sword/rapier)
	configure(item_combat(injury_kind = INJURY_PIERCE))
	configure(item_worn(slots = SLOT_BELT))
	configure(item_combat(attack_verbs = list("attacked", "stabbed", "prodded", "poked", "lunged"), edge = 0))

/obj/item/material/sword/longsword
	name = "longsword"
	desc = "A double-edged large blade."
	icon_state = "longsword"
	item_state = "longsword"
	applies_material_colour = 0

CAPABILITIES(/obj/item/material/sword/longsword)
	configure(item_worn(slots = SLOT_BELT | SLOT_BACK))
	configure(item_combat(can_cleave = TRUE))

/obj/item/material/sword/sabre
	name = "sabre"
	desc = "A sharp curved sword, a favored weapon of pirates far in the past."
	icon_state = "sabre"
	item_state = "sabre"
	applies_material_colour = 0 //messes up the hilt color otherwise

CAPABILITIES(/obj/item/material/sword/sabre)
	configure(item_worn(slots = SLOT_BELT))

/obj/item/material/sword/battleaxe
	name = "battleaxe"
	desc = "A one handed battle axe, still a deadly weapon."
	icon_state = "axe"
	item_state = "axe"
	applies_material_colour = 0

CAPABILITIES(/obj/item/material/sword/battleaxe)
	configure(item_worn(slots = SLOT_BACK))
	configure(item_combat(attack_verbs = list("attacked", "chopped", "cleaved", "torn", "cut"), can_cleave = TRUE))
	configure(item_sounds(drop = SFX_ITEMS_DROP_AXE, pickup = SFX_ITEMS_PICKUP_AXE))

/obj/item/material/sword/battleaxe/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(unique_parry_check(user, attacker, damage_source) && prob(10))
		act_message(user, src, others = span_danger("%U% parries [attack_text] with %T%!"))
		play_sfx(src, SFX_WEAPONS_PUNCHMISS, 2, extrarange = 0)
		return 1
	return 0

/obj/item/material/sword/gladius
	name = "gladius"
	desc = "An ancient short sword, designed to stab and cut."
	icon_state = "gladius"
	item_state = "gladius"
	applies_material_colour = 0

CAPABILITIES(/obj/item/material/sword/gladius)
	configure(item_worn(slots = SLOT_BELT))
