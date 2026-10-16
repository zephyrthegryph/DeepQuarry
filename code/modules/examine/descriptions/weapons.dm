/*
	Note: This file is meant for actual weapons (guns, swords, etc), and not the stupid 'every obj is a weapon, except when it's not' thing.
*/

//******
//*Guns*
//******

/obj/item/gun/energy/crossbow

CAPABILITIES(/obj/item/gun/energy/crossbow)
	configure(examine_text(antag = "This is a stealthy weapon which fires poisoned bolts at your target.  When it hits someone, they will suffer a stun effect, in \
	addition to toxins.  The energy crossbow recharges itself slowly, and can be concealed in your pocket or bag."))
	configure(item_worn(slots = SLOT_BELT | SLOT_HOLSTER))

/obj/item/gun/energy/chameleon

//*******
//*Melee*
//*******

/obj/item/melee/energy/sword

/obj/item/melee/cultblade
