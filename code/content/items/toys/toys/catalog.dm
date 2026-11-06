/* Toys!
 * Contains:
 *		Balloons
 *		Fake telebeacon
 *		Fake singularity
 *		Toy swords
 *		Toy bosun's whistle
 *		Snap pops
 *		Water flower
 *      Therapy dolls
 *      Toddler doll
 *      Inflatable duck
 *		Action figures
 *		Plushies
 *		Toy cult sword
 *		Bouquets
 *		Stick Horse
 */

/obj/item/toy

CAPABILITIES(/obj/item/toy)
	configure(movable_motion(throw_range = 20, throw_speed = 4))
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLOVES))

/obj/item/toy/syndicateballoon
	name = "criminal balloon"
	desc = "There is a tag on the back that reads \"FUK NT!11!\"."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "syndballoon"
	w_class = ITEMSIZE_LARGE

CAPABILITIES(/obj/item/toy/syndicateballoon)
	configure(movable_motion(throw_range = 20, throw_speed = 4))
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER))

/obj/item/toy/nanotrasenballoon
	name = "criminal balloon"
	desc = "Across the balloon the following is printed: \"Man, I love NanoTrasen soooo much. I use only NT products. You have NO idea.\""
	icon = 'icons/obj/weapons.dmi'
	icon_state = "ntballoon"
	w_class = ITEMSIZE_LARGE

CAPABILITIES(/obj/item/toy/nanotrasenballoon)
	configure(movable_motion(throw_range = 20, throw_speed = 4))
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER))

/obj/item/toy/colorballoon /// To color it, VV the 'color' var with a hex color code with the # included.
	name = "balloon"
	desc = "It's a plain little balloon. Comes in many colors!"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "colorballoon"
	w_class = ITEMSIZE_LARGE

CAPABILITIES(/obj/item/toy/colorballoon)
	configure(movable_motion(throw_range = 20, throw_speed = 4))
	configure(item_thrown(force = 0))
	configure(item_combat(force = 0))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER))

/*
 * Fake telebeacon
 */
/obj/item/toy/blink
	name = "electronic blink toy game"
	desc = "Blink.  Blink.  Blink. Ages 8 and up."
	icon = 'icons/obj/radio.dmi'
	icon_state = "beacon"
	item_state = "signaler"

/*
 * Fake singularity
 */
/obj/item/toy/spinningtoy
	name = "gravitational singularity"
	desc = "\"Singulo\" brand spinning toy."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "singularity_s1"

/obj/item/toy/katana
	name = "replica katana"
	desc = "Woefully underpowered in D20."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "katana"
	item_state = "katana"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
		)
	w_class = ITEMSIZE_NORMAL

CAPABILITIES(/obj/item/toy/katana)
	configure(item_worn(slots = SLOT_BELT | SLOT_BACK))
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5, attack_verbs = list("attacked", "slashed", "stabbed", "sliced")))

//Toy cult sword
/obj/item/toy/cultsword
	name = "foam sword"
	desc = "An arcane weapon (made of foam) wielded by the followers of the hit Saturday morning cartoon \"King Nursee and the Acolytes of Heroism\"."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "cultblade"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
		)
	w_class = ITEMSIZE_LARGE

CAPABILITIES(/obj/item/toy/cultsword)
	configure(item_combat(attack_verbs = list("attacked", "slashed", "stabbed", "poked")))

//Flowers fake & real

/obj/item/toy/bouquet
	name = "bouquet"
	desc = "A lovely bouquet of flowers. Smells nice!"
	icon = 'icons/obj/items.dmi'
	icon_state = "bouquet"
	w_class = ITEMSIZE_SMALL

/obj/item/toy/bouquet/fake
	name = "plastic bouquet"
	desc = "A cheap plastic bouquet of flowers. Smells like cheap, toxic plastic."

/obj/item/toy/stickhorse
	name = "stick horse"
	desc = "A pretend horse on a stick for any aspiring little cowboy to ride."
	icon = 'icons/obj/toy.dmi'
	icon_state = "stickhorse"
	w_class = ITEMSIZE_LARGE

/obj/item/toy/character
	icon = 'icons/obj/toy.dmi'
	w_class = ITEMSIZE_SMALL
	pixel_z = 5

/obj/item/toy/character/alien
	name = "xenomorph xiniature"
	desc = "A miniature xenomorph. Scary!"
	icon_state = "aliencharacter"

/obj/item/toy/character/cleric
	name = "cleric miniature"
	desc = "A wee little cleric, with his wee little staff."
	icon_state = "clericcharacter"

/obj/item/toy/character/warrior
	name = "warrior miniature"
	desc = "That sword would make a decent toothpick."
	icon_state = "warriorcharacter"

/obj/item/toy/character/thief
	name = "thief miniature"
	desc = "Hey, where did my wallet go!?"
	icon_state = "thiefcharacter"

/obj/item/toy/character/wizard
	name = "wizard miniature"
	desc = "MAGIC!"
	icon_state = "wizardcharacter"

/obj/item/toy/character/voidone
	name = "void one miniature"
	desc = "The dark lord has risen!"
	icon_state = "darkmastercharacter"

/obj/item/toy/character/lich
	name = "lich miniature"
	desc = "Murderboner extraordinaire."
	icon_state = "lichcharacter"

//This should really be somewhere else but I don't know where. w/e

/obj/item/inflatable_duck
	name = "inflatable duck"
	desc = "No bother to sink or swim when you can just float!"
	icon_state = "inflatable"
	icon = 'icons/inventory/belt/item.dmi'

CAPABILITIES(/obj/item/inflatable_duck)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER))

/obj/item/toy/xmastree
	name = "Miniature Christmas tree"
	desc = "Tiny cute Christmas tree."
	icon = 'icons/obj/toy.dmi'
	icon_state = "tinyxmastree"
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/toy/xmastree)
	configure(item_thrown(force = 1))
	configure(item_combat(force = 1))
	configure(item_sounds(drop = SFX_ITEMS_DROP_BOX))

//////////////////////////////////////////////////////
//					Chess Pieces					//
//////////////////////////////////////////////////////

/obj/item/toy/chess
	name = "chess piece"
	desc = "This should never display."
	icon = 'icons/obj/chess.dmi'
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/toy/chess)
	configure(item_thrown(force = 1))
	configure(item_combat(force = 1))
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLASS))

/obj/item/toy/chess/pawn_white
	name = "white pawn"
	desc = "A white pawn chess piece. Get accused of cheating when executing a sick En Passant."
	icon_state = "white_pawn"

/obj/item/toy/chess/pawn_black
	name = "black pawn"
	desc = "A black pawn chess piece. Get accused of cheating when executing a sick En Passant."
	icon_state = "black_pawn"

/obj/item/toy/chess/rook_white
	name = "white rook"
	desc = "A white rook chess piece. Also known as a castle."
	icon_state = "white_rook"

/obj/item/toy/chess/rook_black
	name = "black rook"
	desc = "A black rook chess piece. Also known as a castle."
	icon_state = "black_rook"

/obj/item/toy/chess/knight_white
	name = "white knight"
	desc = "A white knight chess piece. Sadly, you can't ride it."
	icon_state = "white_knight"

/obj/item/toy/chess/knight_black
	name = "black knight"
	desc = "A black knight chess piece. 'Just a flesh wound.'"
	icon_state = "black_knight"

/obj/item/toy/chess/bishop_white
	name = "white bishop"
	desc = "A white bishop chess piece."
	icon_state = "white_bishop"

/obj/item/toy/chess/bishop_black
	name = "black bishop"
	desc = "A black bishop chess piece."
	icon_state = "black_bishop"

/obj/item/toy/chess/queen_white
	name = "white queen"
	desc = "A white queen chess piece."
	icon_state = "white_queen"

/obj/item/toy/chess/queen_black
	name = "black queen"
	desc = "A black queen chess piece."
	icon_state = "black_queen"

/obj/item/toy/chess/king_white
	name = "white king"
	desc = "A white king chess piece."
	icon_state = "white_king"

/obj/item/toy/chess/king_black
	name = "black king"
	desc = "A black king chess piece."
	icon_state = "black_king"

/obj/item/toy/sif
	name = "Sif planet model"
	desc = "A \"Space Life\" brand planet model of Sif, it's oddly cold to the touch."
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "sif"

/* Virgo Toys!
 * Contains:
 *		Mistletoe
 *		Plushies
 *		Pet rocks
 *		Chew toys
 *		Cat toys
 *		Fake flash
 *		Big red button
 *		Garden gnome
 *		Toy AI
 *      Hand buzzer
 *      Toy cuffs
 *      Toy nuke
 *		Toy gibber
 *		Toy xeno
 *		Russian revolver
 *		Trick revolver
 *		Toy chainsaw
 *		Random miniature spawner
 *		Snake popper
 *		Professor Who universal ID
 *		Professor Who sonic driver
 *		Action figures
 *		Desk toys
 */

/*
 * Mistletoe
 */
/obj/item/toy/mistletoe
	name = "mistletoe"
	desc = "You are supposed to kiss someone under these"
	icon = 'icons/obj/toy.dmi'
	icon_state = "mistletoe"

/*
 * Cat toys
 */
/obj/item/toy/cat_toy
	name = "toy mouse"
	desc = "A colorful toy mouse!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "toy_mouse"
	w_class = ITEMSIZE_TINY

/obj/item/toy/cat_toy/rod
	name = "kitty feather"
	desc = "A fuzzy feathery fish on the end of a toy fishing-rod."
	icon = 'icons/obj/toy.dmi'
	icon_state = "cat_toy"
	w_class = ITEMSIZE_SMALL
	item_state = "fishing_rod"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
		)

/*
 * Garden gnome
 */
/obj/item/toy/gnome
	name = "garden gnome"
	desc = "It's a gnome, not a gnelf. Made of weak ceramic."
	icon = 'icons/obj/toy.dmi'
	icon_state = "gnome"

/*
 * Toy cuffs
 */
/obj/item/handcuffs/fake
	name = "plastic handcuffs"
	desc = "Use this to keep plastic prisoners in line."
	MATERIAL_BULK(MAT_PLASTIC, 500) // Was list(PLASTIC = 500): a "PLASTIC" key, no such material.
	breakouttime = 30
	use_time = 60
	sprite_sheets = list(SPECIES_TESHARI = 'icons/mob/species/teshari/handcuffs.dmi')

CAPABILITIES(/obj/item/handcuffs/fake)
	configure(item_sounds(drop = SFX_ITEMS_DROP_ACCESSORY, pickup = SFX_ITEMS_PICKUP_ACCESSORY))

/obj/item/handcuffs/legcuffs/fake
	name = "plastic legcuffs"
	desc = "Use this to keep plastic prisoners in line."
	breakouttime = 30	//Deciseconds = 30s = 0.5 minute
	use_time = 120

/obj/item/storage/box/handcuffs/fake
	name = "box of plastic handcuffs"
	desc = "A box full of plastic handcuffs."
	icon_state = "handcuff"
	starts_with = list(/obj/item/handcuffs/fake = 1, /obj/item/handcuffs/legcuffs/fake = 1)
	foldable = null

CAPABILITIES(/obj/item/storage/box/handcuffs/fake)
	configure(storage(accepts = list(/obj/item/handcuffs/fake, /obj/item/handcuffs/legcuffs/fake)))

/*
 * Professor Who universal ID
 */
/obj/item/clothing/under/universalid
	name = "identification card"
	desc = "A novelty identification card based on Professor Who's Universal ID."
	icon = 'icons/obj/toy.dmi'
	icon_state = "universal_id"
	w_class = ITEMSIZE_TINY

	sprite_sheets = null

	item_state = "golem"  //This is dumb and hacky but was here when I got here.
	worn_state = "golem"  //It's basically just a coincidentally black iconstate in the file.

CAPABILITIES(/obj/item/clothing/under/universalid)
	configure(item_worn(slots = SLOT_ID | SLOT_EARS, covers = 0))
	configure(item_sounds(equip = TRAIT_NONE))

/*
 * Professor Who sonic driver
 */
/obj/item/tool/screwdriver/sdriver
	name = "sonic driver"
	desc = "A novelty screwdriver that uses tiny magnets to manipulate screws."
	icon = 'icons/obj/toy.dmi'
	icon_state = "sonic_driver"
	item_state = "screwdriver_black"
	random_color = FALSE

CAPABILITIES(/obj/item/tool/screwdriver/sdriver)
	configure(item_tooling(speed = 1))
	configure(item_sounds(use = SFX_ITEMS_SONIC_DRIVER))

/*
 * Professor Who time capsule
 */
/obj/item/storage/box/timecap
	name = "action time capsule"
	desc = "A toy recreation of the Time Capsule from Professor Who. Can hold up to two action figures."
	icon = 'icons/obj/toy.dmi'
	icon_state = "time_cap"
	max_storage_space = ITEMSIZE_COST_TINY * 2
	use_sound = SFX_MACHINES_CLICK

CAPABILITIES(/obj/item/storage/box/timecap)
	configure(item_sounds(drop = SFX_ITEMS_DROP_ACCESSORY, pickup = SFX_ITEMS_PICKUP_ACCESSORY))
	configure(storage(accepts = list(/obj/item/toy/figure), max_size = ITEMSIZE_TINY))

/*
 * Snow Globes
 */
/obj/item/toy/snowglobe
	name = "snowglobe"
	icon = 'icons/obj/snowglobe_vr.dmi'

/obj/item/toy/snowglobe/snowvillage
	desc = "Depicts a small, quaint village buried in snow."
	icon_state = "smolsnowvillage"

/obj/item/toy/snowglobe/tether
	desc = "Depicts a massive space elevator reaching to the sky."
	icon_state = "smoltether"

/obj/item/toy/snowglobe/stellardelight
	desc = "Depicts an interstellar spacecraft."
	icon_state = "smolstellardelight"

/obj/item/toy/snowglobe/rascalspass
	desc = "Depicts a nanotrasen facility on a temperate world."
	icon_state = "smolrascalspass"
