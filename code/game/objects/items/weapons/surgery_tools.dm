/* Surgery Tools
 * Contains:
 *		Bio-Regenerator
 *		Retractor
 *		Hemostat
 *		Cautery
 *		Surgical Drill
 *		Scalpel
 *		Researchable Scalpels
 *		Circular Saws
 *		Misc Tools
 *		Cyborg Tools
 *		Alien Tools
 */

/obj/item/surgical
	name = "Surgical tool"
	desc = "This shouldn't be here, ahelp it."
	icon = 'icons/obj/surgery.dmi'
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/surgical)
	configure(item_sounds(drop = SFX_ITEMS_DROP_WELDINGTOOL, pickup = SFX_ITEMS_PICKUP_WELDINGTOOL))

/obj/item/surgical/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HELP)	//A tad messy, but this should stop people from smacking their patients in surgery
		return NONE
	..()

/*
 * Bio-Regenerator
 */
/obj/item/surgical/bioregen
	name="bioregenerator"
	desc="A special tool used in surgeries which can pull toxins from and restore oxygen to organic tissue as well as recreate missing biological structures to allow otherwise irreperable flesh to be mended."
	icon_state="bioregen"

CAPABILITIES(/obj/item/surgical/bioregen)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SCRAP))

/*
 * Retractor
 */

/obj/item/surgical/retractor
	name = "retractor"
	desc = "Retracts stuff."
	icon_state = "retractor"
	material_total = 10000 + 5000

CAPABILITIES(/obj/item/surgical/retractor)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SCRAP))

/*
 * Hemostat
 */
/obj/item/surgical/hemostat
	name = "hemostat"
	desc = "You think you have seen this before."
	icon_state = "hemostat"
	material_total = 5000 + 2500

CAPABILITIES(/obj/item/surgical/hemostat)
	configure(item_combat(attack_verbs = list("attacked", "pinched")))
	configure(item_sounds(hit = SFX_ITEMS_WIRECUTTER, drop = SFX_ITEMS_DROP_SCRAP))

/*
 * Cautery
 */
/obj/item/surgical/cautery
	name = "cautery"
	desc = "This stops bleeding."
	icon_state = "cautery"
	material_total = 5000 + 2500

CAPABILITIES(/obj/item/surgical/cautery)
	configure(item_combat(attack_verbs = list("burnt")))
	configure(item_sounds(drop = SFX_ITEMS_DROP_SCRAP))

/*
 * Surgical Drill
 */
/obj/item/surgical/surgicaldrill
	name = "surgical drill"
	desc = "You can drill using this item. You dig?"
	icon_state = "drill"
	material_total = 15000 + 10000
	w_class = ITEMSIZE_NORMAL

CAPABILITIES(/obj/item/surgical/surgicaldrill)
	configure(item_combat(force = 15.0, attack_verbs = list("drilled")))
	configure(item_sounds(hit = SFX_WEAPONS_CIRCSAWHIT, drop = SFX_ITEMS_DROP_ACCESSORY))

/*
 * Scalpel
 */
/obj/item/surgical/scalpel
	name = "scalpel"
	desc = "Cut, cut, and once more cut."
	icon_state = "scalpel"
	injury_kind = INJURY_CUT
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	throwforce = 5.0
	throw_speed = 3
	throw_range = 5
	material_total = 10000 + 5000
	var/clamp_chance = 0 // chance that the scalpel will perform cautery on its own

CAPABILITIES(/obj/item/surgical/scalpel)
	configure(item_combat(force = 10.0, sharp = TRUE, edge = TRUE, attack_verbs = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE, drop = SFX_ITEMS_DROP_KNIFE))

/*
 * Researchable Scalpels
 */
/obj/item/surgical/scalpel/laser1
	name = "laser scalpel"
	desc = "A scalpel augmented with a directed laser, for more precise cutting without blood entering the field.  This one looks basic and could be improved."
	icon_state = "scalpel_laser1"
	injury_kind = INJURY_BURN
	clamp_chance = 75

CAPABILITIES(/obj/item/surgical/scalpel/laser1)
	configure(item_sounds(hit = SFX_WEAPONS_BLADE1))

/obj/item/surgical/scalpel/laser2
	name = "laser scalpel"
	desc = "A scalpel augmented with a directed laser, for more precise cutting without blood entering the field.  This one looks somewhat advanced."
	icon_state = "scalpel_laser2"
	injury_kind = INJURY_BURN
	clamp_chance = 85

CAPABILITIES(/obj/item/surgical/scalpel/laser2)
	configure(item_combat(force = 12.0))
	configure(item_sounds(hit = SFX_WEAPONS_BLADE1))

/obj/item/surgical/scalpel/laser3
	name = "laser scalpel"
	desc = "A scalpel augmented with a directed laser, for more precise cutting without blood entering the field.  This one looks to be the pinnacle of precision energy cutlery!"
	icon_state = "scalpel_laser3"
	injury_kind = INJURY_BURN
	clamp_chance = 95

CAPABILITIES(/obj/item/surgical/scalpel/laser3)
	configure(item_combat(force = 15.0))
	configure(item_sounds(hit = SFX_WEAPONS_BLADE1))

/obj/item/surgical/scalpel/manager
	name = "incision management system"
	desc = "A true extension of the surgeon's body, this marvel instantly and completely prepares an incision allowing for the immediate commencement of therapeutic steps."
	icon_state = "scalpel_manager"
	clamp_chance = 100

CAPABILITIES(/obj/item/surgical/scalpel/manager)
	configure(item_combat(force = 7.5))

/obj/item/surgical/scalpel/ripper
	name = "jagged scalpel"
	desc = "A horrifying bladed tool with a large metal spike in its center. The tool is used for rapidly removing organs or medical malpractice."
	icon_state = "organ_ripper"
	item_state = "bone_setter"
	toolspeed = 0.75

CAPABILITIES(/obj/item/surgical/scalpel/ripper)
	configure(item_combat(force = 15.0))

/*
 * Circular Saws
 */
/obj/item/surgical/circular_saw
	name = "circular saw"
	desc = "For heavy duty cutting."
	icon_state = "saw"
	w_class = ITEMSIZE_NORMAL
	throwforce = 9.0
	throw_speed = 3
	throw_range = 5
	material_total = 20000 + 10000
	injury_kind = INJURY_CUT

CAPABILITIES(/obj/item/surgical/circular_saw)
	configure(item_combat(force = 15.0, attack_verbs = list("attacked", "slashed", "sawed", "cut"), sharp = TRUE, edge = TRUE))
	configure(item_sounds(hit = SFX_WEAPONS_CIRCSAWHIT, drop = SFX_ITEMS_DROP_ACCESSORY))

/obj/item/surgical/circular_saw/manager
	name = "energetic bone diverter"
	desc = "For heavy duty cutting (and sealing), with science!"
	icon_state = "adv_saw"
	item_state = "saw3"
	injury_kind = INJURY_CUT
	injury_kinds = alist(INJURY_BURN = 1/3, INJURY_CUT = 2/3)
	w_class = ITEMSIZE_NORMAL
	material_total = 25000 + 20000
	toolspeed = 0.75

CAPABILITIES(/obj/item/surgical/circular_saw/manager)
	configure(item_combat(attack_verbs = list("attacked", "slashed", "seared", "cut")))
	configure(item_sounds(hit = SFX_WEAPONS_EMITTER2))

/*
 * Misc Tools
 */
/obj/item/surgical/bonegel
	name = "bone gel"
	desc = "For fixing bones."
	icon_state = "bone-gel"
	throwforce = 1.0

CAPABILITIES(/obj/item/surgical/bonegel)
	configure(item_combat(force = 0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_BOTTLE))

/obj/item/surgical/FixOVein
	name = "FixOVein"
	desc = "Like bone gel. For veins."
	icon_state = "fixovein"
	throwforce = 1.0

CAPABILITIES(/obj/item/surgical/FixOVein)
	configure(item_combat(force = 0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_BOTTLE))

/obj/item/surgical/bonesetter
	name = "bone setter"
	desc = "Put them in their place."
	icon_state = "bone_setter"
	throwforce = 9.0
	throw_speed = 3
	throw_range = 5

CAPABILITIES(/obj/item/surgical/bonesetter)
	configure(item_combat(force = 8.0, attack_verbs = list("attacked", "hit", "bludgeoned")))
	configure(item_sounds(drop = SFX_ITEMS_DROP_SCRAP))

/obj/item/surgical/bone_clamp
	name = "bone clamp"
	desc = "The best way to get a bone fixed fast."
	icon_state = "bone_clamp"
	throwforce = 9
	throw_speed = 3
	throw_range = 5

CAPABILITIES(/obj/item/surgical/bone_clamp)
	configure(item_combat(force = 8, attack_verbs = list("attacked", "hit", "bludgeoned")))



/*
 * Alien Tools
 */
/obj/item/surgical/retractor/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/hemostat/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/cautery/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/surgicaldrill/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/scalpel/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/circular_saw/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/FixOVein/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.25

/obj/item/surgical/bone_clamp/alien
	icon = 'icons/obj/abductor.dmi'
	toolspeed = 0.75
