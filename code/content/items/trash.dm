//Items labled as 'trash' for the trash bag.
//TODO: Make this an item var or something...

//Added by Jack Rost
/obj/item/trash
	icon = 'icons/obj/trash.dmi'
	w_class = ITEMSIZE_SMALL
	desc = "This is rubbish."
	MATERIAL_BULK(MAT_STEEL, 30)
	var/age = 0

CAPABILITIES(/obj/item/trash)
	variants(nameof(variant), PROC_REF(variant_table))
	configure(item_sounds(drop = SFX_ITEMS_DROP_WRAPPER, pickup = SFX_ITEMS_PICKUP_WRAPPER))
	param(nameof(age), pos = 1)
	after_init(0, then(PROC_REF(track_persistence)))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/trash/proc/variant_table()
	return GLOB.dq_variants_trash

/// Trash not loaded with the map is tracked for persistence.
/obj/item/trash/proc/track_persistence(datum/act/timer/A)
	if(!A.mapload || !CONFIG_GET(flag/persistence_ignore_mapload))
		SSpersistence.track_value(src, /datum/persistent/filth/trash)

// persistent trash forgets this item.
/obj/item/trash/lifecycle_dematerialize()
	SSpersistence.forget_value(src, /datum/persistent/filth/trash)
	..()

/obj/item/trash/candy
	name = "hard candy wrapper"
	icon_state = "candy"

/obj/item/trash/candy/gums
	name = "gummy candy bag"
	icon_state = "candy_gums"

/obj/item/trash/candy/proteinbar
	name = "protein bar wrapper"
	icon_state = "proteinbar"

/obj/item/trash/candy/fruitbar
	name = "fruit bar wrapper"
	icon_state = "fruitbar"

/obj/item/trash/chips
	name = "chips bag"
	icon_state = "chips"

/obj/item/trash/chips/bbq
	name = "bbq chips bag"
	icon_state = "chips_bbq"

/obj/item/trash/chips/snv
	name = "salt & vinegar chips bag"
	icon_state = "chips_snv"

/obj/item/trash/unajerky
	name = "Moghes Imported Sissalik Jerky tin"
	icon_state = "unathitinred"

CAPABILITIES(/obj/item/trash/unajerky)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/plate
	name = "plate"
	icon_state = "plate"

CAPABILITIES(/obj/item/trash/plate)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/asian_bowl
	name = "asian bowl"
	icon_state	= "asian_bowl"

CAPABILITIES(/obj/item/trash/asian_bowl)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/snack_bowl
	name = "snack bowl"
	icon_state	= "snack_bowl"

CAPABILITIES(/obj/item/trash/snack_bowl)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/small_bowl
	name = "small bowl"
	icon_state	= "small_bowl"

CAPABILITIES(/obj/item/trash/small_bowl)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/turkeybones
	name = "turkey bones"
	icon_state	= "turkeybones"

CAPABILITIES(/obj/item/trash/turkeybones)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/coffee
	name = "empty cup"
	icon_state = "coffee_vended"

CAPABILITIES(/obj/item/trash/coffee)
	configure(item_sounds(drop = SFX_ITEMS_DROP_PAPERCUP, pickup = SFX_ITEMS_PICKUP_PAPERCUP))

/obj/item/trash/ramen
	name = "cup ramen"
	icon_state = "ramen"

CAPABILITIES(/obj/item/trash/ramen)
	configure(item_sounds(drop = SFX_ITEMS_DROP_PAPERCUP, pickup = SFX_ITEMS_PICKUP_PAPERCUP))

/obj/item/trash/tray
	name = "tray"
	icon_state = "tray"

CAPABILITIES(/obj/item/trash/tray)
	configure(item_sounds(drop = SFX_ITEMS_TRAYHIT1))

/obj/item/trash/candle
	name = "candle"
	icon = 'icons/obj/candle.dmi'
	icon_state = "candle4"

CAPABILITIES(/obj/item/trash/candle)
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLOVES, pickup = SFX_ITEMS_PICKUP_GLOVES))

// Aurora Food Port
/obj/item/trash/brownies
	name = "brownie tray"
	icon_state = "brownies"

CAPABILITIES(/obj/item/trash/brownies)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/snacktray
	name = "snacktray"
	icon_state = "snacktray"

CAPABILITIES(/obj/item/trash/snacktray)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/dipbowl
	name = "dip bowl"
	icon_state = "dipbowl"

CAPABILITIES(/obj/item/trash/dipbowl)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/chipbasket
	name = "empty chip basket"
	icon_state = "chipbasket_empty"

CAPABILITIES(/obj/item/trash/chipbasket)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FOOD, pickup = SFX_ITEMS_PICKUP_FOOD))

/obj/item/trash/spitgum
	name = "old gum"
	desc = "A disgusting chewed up wad of gum."
	icon = 'icons/inventory/face/item.dmi'
	icon_state = "spit-gum"

CAPABILITIES(/obj/item/trash/spitgum)
	configure(item_sounds(drop = SFX_ITEMS_DROP_FLESH, pickup = SFX_ITEMS_PICKUP_FLESH))

/obj/item/trash/lollibutt
	name = "lollipop stick"
	desc = "A lollipop stick devoid of pop."
	icon = 'icons/inventory/face/item.dmi'
	icon_state = "pop-stick"

CAPABILITIES(/obj/item/trash/lollibutt)
	configure(item_sounds(drop = SFX_ITEMS_DROP_COMPONENT, pickup = SFX_ITEMS_PICKUP_COMPONENT))

/obj/item/trash/spitwad
	name = "spit wad"
	desc = "A disgusting spitwad."
	icon = 'icons/inventory/face/item.dmi'
	icon_state = "spit-chew"

CAPABILITIES(/obj/item/trash/spitwad)
	configure(item_worn(slots = SLOT_EARS | SLOT_MASK))
	configure(item_sounds(drop = SFX_ITEMS_DROP_FLESH, pickup = SFX_ITEMS_PICKUP_FLESH))

/obj/item/trash/beef
	name = "empty beef can"
	icon_state = "beef"

CAPABILITIES(/obj/item/trash/beef)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/beans
	name = "empty bean can"
	icon_state = "beans"

CAPABILITIES(/obj/item/trash/beans)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/tomato
	name = "empty tomato soup can"
	icon_state = "tomato"

CAPABILITIES(/obj/item/trash/tomato)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/spinach
	name = "empty spinach can"
	icon_state = "spinach"

CAPABILITIES(/obj/item/trash/spinach)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/fishegg
	name = "empty fisheggs can"
	icon_state = "fisheggs"

CAPABILITIES(/obj/item/trash/fishegg)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/carpegg
	name = "empty carpeggs can"
	icon_state = "carpeggs"

CAPABILITIES(/obj/item/trash/carpegg)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/ntbeans
	name = "empty baked bean can"
	icon_state = "ntbeans"

CAPABILITIES(/obj/item/trash/ntbeans)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/maps
	name = "empty MAPS can"
	icon_state = "maps"

CAPABILITIES(/obj/item/trash/maps)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/appleberry
	name = "appleberry can"
	icon_state = "appleberry"

CAPABILITIES(/obj/item/trash/appleberry)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/brainzsnax
	name = "\improper BrainzSnax can"
	icon_state = "brainzsnax"

CAPABILITIES(/obj/item/trash/brainzsnax)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

/obj/item/trash/brainzsnaxred
	name = "\improper BrainzSnax RED can"
	icon_state = "brainzsnaxred"

CAPABILITIES(/obj/item/trash/brainzsnaxred)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SODA, pickup = SFX_ITEMS_PICKUP_SODA))

//Candy Bars (1-10)
/obj/item/trash/candy/cb01
	name = "\improper Tau Ceti Bar wrapper"
	icon_state = "cb01"

/obj/item/trash/candy/cb02
	name = "\improper Hundred-Thousand Thaler Bar wrapper"
	icon_state = "cb02"

/obj/item/trash/candy/cb03
	name = "\improper Lars' Saltlakris wrapper"
	icon_state = "cb03"

/obj/item/trash/candy/cb04
	name = "\improper Aerostat Bar wrapper"
	icon_state = "cb04"

/obj/item/trash/candy/cb05
	name = "\improper Andromeda Bar wrapper"
	icon_state = "cb05"

/obj/item/trash/candy/cb06
	name = "\improper Mocha Crunch wrapper"
	icon_state = "cb06"

/obj/item/trash/candy/cb07
	name = "\improper TaroMilk Bar wrapper"
	icon_state = "cb07"

/obj/item/trash/candy/cb08
	name = "\improper Cronk Bar wrapper"
	icon_state = "cb08"

/obj/item/trash/candy/cb09
	name = "\improper Kaju Mamma! Bar wrapper"
	icon_state = "cb09"

/obj/item/trash/candy/cb10
	name = "\improper Shantak Bar wrapper"
	icon_state = "cb10"

// Custom garbage or whatever

/obj/item/trash/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.species.trashcan == 1)
			play_sfx(src, SFX_ITEMS_EATFOOD, volume = rand(10,50))
			user.drop_item()
			vore_selected_of(H).nom_atom(src)
			balloon_alert(H, "you can taste the flavor of garbage. Wait what?")
			return

	if(isrobot(M))
		var/mob/living/silicon/robot/R = M
		if(R.module?.eats_trash) // You can now feed the trash borg yay.
			play_sfx(src, SFX_ITEMS_EATFOOD, volume = rand(10,50))
			user.drop_item()
			vore_selected_of(R).nom_atom(src)
			R.balloon_alert_visible("[user] feeds [R] with [src]!", "you feed [R] \the [src]!")
			return
	// Trash can't be used as a weapon; deal no attack.
	return NONE

/obj/item/trash/ratpackramen
	name = "\improper Prepackaged Meal Tray"
	icon = 'icons/obj/trash_vr.dmi'
	icon_state = "altevian_pack_ramen_standard-trash"

/obj/item/trash/ratpackramen/standard
	icon_state = "altevian_pack_ramen_standard-trash"

/obj/item/trash/ratpackramen/lacquer1
	icon_state = "altevian_pack_ramen_lacquer1-trash"

/obj/item/trash/ratpackramen/lacquer2
	icon_state = "altevian_pack_ramen_lacquer2-trash"

/obj/item/trash/ratpackramen/lacquer3
	icon_state = "altevian_pack_ramen_lacquer3-trash"

/obj/item/trash/ratpackramen/fleet
	icon_state = "altevian_pack_ramen_fleet-trash"

/obj/item/trash/ratpackramen/trans
	icon_state = "altevian_pack_ramen_trans-trash"

/obj/item/trash/ratpackramen/ace
	icon_state = "altevian_pack_ramen_ace-trash"
