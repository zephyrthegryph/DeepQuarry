/*
//	Least descriptive filename?
//	This is where all of the things that aren't really loot should go.
//	Barricades, mines, etc.
*/

/obj/random/junk //Broken items, or stuff that could be picked up
	name = "random junk"
	desc = "This is some random junk."
	icon = 'icons/obj/trash.dmi'
	icon_state = "trashbag3"

CAPABILITIES(/obj/random/junk)
	loot(table = list(/obj/effect/decal/cleanable/generic = 20, /loot/junk/trash = 56, /loot/junk/useful = 24))

/obj/random/trash //Mostly remains and cleanable decals. Stuff a janitor could clean up
	name = "random trash"
	desc = "This is some random trash."
	icon = 'icons/effects/effects.dmi'
	icon_state = "greenglow"

CAPABILITIES(/obj/random/trash)
	loot(
		table = list(
			/obj/effect/decal/remains/lizard,
			/obj/effect/decal/cleanable/blood/gibs/robot,
			/obj/effect/decal/cleanable/blood/oil,
			/obj/effect/decal/cleanable/blood/oil/streak,
			/obj/effect/decal/cleanable/bug_remains,
			/obj/effect/decal/remains/mouse,
			/obj/effect/decal/cleanable/vomit/old,
			/obj/effect/decal/cleanable/blood/old,
			/obj/effect/decal/cleanable/ash,
			/obj/effect/decal/cleanable/generic,
			/obj/effect/decal/cleanable/flour,
			/obj/effect/decal/cleanable/dirt,
			/obj/effect/decal/remains/robot))

/obj/random/crate //Random 'standard' crates for variety in maintenance spawns.
	name = "random crate"
	desc = "This is a random crate"
	icon = 'icons/obj/closets/bases/crate.dmi'
	icon_state = "base"

CAPABILITIES(/obj/random/crate)
	loot(
		table = list(
			/obj/structure/closet/crate/plastic,
			/obj/structure/closet/crate/aether,
			/obj/structure/closet/crate/centauri,
			/obj/structure/closet/crate/einstein,
			/obj/structure/closet/crate/focalpoint,
			/obj/structure/closet/crate/gilthari,
			/obj/structure/closet/crate/grayson,
			/obj/structure/closet/crate/nanotrasen,
			/obj/structure/closet/crate/nanothreads,
			/obj/structure/closet/crate/oculum,
			/obj/structure/closet/crate/ward,
			/obj/structure/closet/crate/xion,
			/obj/structure/closet/crate/zenghu,
			/obj/structure/closet/crate/allico,
			/obj/structure/closet/crate/carp,
			/obj/structure/closet/crate/galaksi,
			/obj/structure/closet/crate/thinktronic,
			/obj/structure/closet/crate/ummarcar,
			/obj/structure/closet/crate/unathi,
			/obj/structure/closet/crate/hydroponics,
			/obj/structure/closet/crate/engineering,
			/obj/structure/closet/crate))

/obj/random/vendorall //Fully random selection of consumer vendors
	name = "random vending machine"
	desc = "This is a random vending machine"
	icon = 'icons/obj/vending.dmi'
	icon_state = "radren-off"

CAPABILITIES(/obj/random/vendorall)
	loot(
		table = list(
			/obj/machinery/vending/coffee = 5,
			/obj/machinery/vending/snack = 5,
			/obj/machinery/vending/cola = 5,
			/obj/machinery/vending/fitness = 3,
			/obj/machinery/vending/cigarette = 4,
			/obj/machinery/vending/giftvendor = 3,
			/obj/machinery/vending/weeb = 5,
			/obj/machinery/vending/sol = 5,
			/obj/machinery/vending/snix = 5,
			/obj/machinery/vending/snlvend = 5,
			/obj/machinery/vending/sovietsoda = 5,
			/obj/machinery/vending/sovietvend = 5,
			/obj/machinery/vending/radren = 5,
			/obj/machinery/vending/altevian = 3,
			/obj/machinery/vending/desatti = 5,
			/obj/machinery/vending/nukie = 5))

/obj/random/vendorfood //Random food vendors for station use
	name = "random snack vending machine"
	desc = "This is a random food vending machine"
	icon = 'icons/obj/vending.dmi'
	icon_state = "snack"

CAPABILITIES(/obj/random/vendorfood)
	loot(
		table = list(
			/obj/machinery/vending/snack,
			/obj/machinery/vending/weeb,
			/obj/machinery/vending/sol,
			/obj/machinery/vending/snix,
			/obj/machinery/vending/snlvend,
			/obj/machinery/vending/altevian,
			/obj/machinery/vending/desatti))

/obj/random/vendordrink //Random drink vendors for station use
	name = "random drink vending machine"
	desc = "This is a random drink vending machine"
	icon = 'icons/obj/vending.dmi'
	icon_state = "Cola_Machine"

CAPABILITIES(/obj/random/vendordrink)
	loot(
		table = list(
			/obj/machinery/vending/cola,
			/obj/machinery/vending/cola/soft,
			/obj/machinery/vending/bepis,
			/obj/machinery/vending/sovietsoda,
			/obj/machinery/vending/radren,
			/obj/machinery/vending/nukie))

/obj/random/obstruction //Large objects to block things off in maintenance
	name = "random obstruction"
	desc = "This is a random obstruction."
	icon = 'icons/obj/cult.dmi'
	icon_state = "cultgirder"

CAPABILITIES(/obj/random/obstruction)
	loot(
		table = list(
			/obj/structure/barricade,
			/obj/structure/girder,
			/obj/structure/girder/displaced,
			/obj/structure/girder/reinforced,
			/obj/structure/grille,
			/obj/structure/grille/broken,
			/obj/structure/foamedmetal,
			/obj/structure/inflatable,
			/obj/structure/inflatable/door))

/obj/random/landmine
	name = "Random Land Mine"
	desc = "This is a random land mine."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "landmine"

CAPABILITIES(/obj/random/landmine)
	loot(
		table = list(
			/obj/effect/mine = 30,
			/obj/effect/mine/frag = 25,
			/obj/effect/mine/emp = 25,
			/obj/effect/mine/camo = 15,
			/obj/effect/mine/emp/camo = 15,
			/obj/effect/mine/stun = 10,
			/obj/effect/mine/incendiary = 10),
		chance = 75)

/obj/random/humanoidremains
	name = "Random Humanoid Remains"
	desc = "This is a random pile of remains."
	icon = 'icons/effects/blood.dmi'
	icon_state = "remains"

CAPABILITIES(/obj/random/humanoidremains)
	loot(
		table = list(
			/obj/effect/decal/remains/human = 30,
			/obj/effect/decal/remains/ribcage = 25,
			/obj/effect/decal/remains/tajaran = 25,
			/obj/effect/decal/remains/unathi = 10,
			/obj/effect/decal/remains/posi = 10),
		chance = 85)

/obj/random/nukies_can_legal
	name = "Random Legal Nukies Can"
	desc = "This is a random can of (legal) Nukies Energy Drink."

CAPABILITIES(/obj/random/nukies_can_legal)
	loot(
		table = list(
			/obj/item/reagent_containers/food/drinks/cans/nukie_peach,
			/obj/item/reagent_containers/food/drinks/cans/nukie_pear,
			/obj/item/reagent_containers/food/drinks/cans/nukie_cherry,
			/obj/item/reagent_containers/food/drinks/cans/nukie_melon,
			/obj/item/reagent_containers/food/drinks/cans/nukie_banana,
			/obj/item/reagent_containers/food/drinks/cans/nukie_rose,
			/obj/item/reagent_containers/food/drinks/cans/nukie_lemon,
			/obj/item/reagent_containers/food/drinks/cans/nukie_fruit,
			/obj/item/reagent_containers/food/drinks/cans/nukie_special))

/obj/random/desatti_snacks
	name = "Random Desatti Snacks"
	desc = "This is a random Desatti Catering snack."

CAPABILITIES(/obj/random/desatti_snacks)
	loot(
		table = list(
			/obj/item/storage/box/jaffacake,
			/obj/item/storage/box/winegum,
			/obj/item/storage/box/saucer,
			/obj/item/storage/box/shrimpsandbananas,
			/obj/item/storage/box/rhubarbcustard,
			/obj/item/storage/box/custardcream,
			/obj/item/storage/box/bourbon,
			/obj/item/reagent_containers/food/snacks/packaged/sausageroll,
			/obj/item/reagent_containers/food/snacks/packaged/pasty,
			/obj/item/reagent_containers/food/snacks/packaged/scotchegg,
			/obj/item/reagent_containers/food/snacks/packaged/porkpie))

/obj/random_multi/single_item/captains_spare_id
	name = "Multi Point - Captain's Spare"
	id = "Captain's spare id"
	item_path = /obj/item/card/id/gold/captain/spare

/obj/random_multi/single_item/hand_tele
	name = "Multi Point - Hand Teleporter"
	id = "hand tele"
	item_path = /obj/item/hand_tele

/obj/random_multi/single_item/sfr_headset
	name = "Multi Point - headset"
	id = "SFR headset"
	item_path = /obj/random/sfr

// This is in here because it's spawned by the SFR Headset randomizer
/obj/random/sfr
	name = "random SFR headset"
	desc = "This is a headset spawn."
	icon = 'icons/misc/mark.dmi'
	icon_state = "rup"

CAPABILITIES(/obj/random/sfr)
	loot(
		table = list(
			/obj/item/radio/headset/heads/captain/sfr,
			/obj/item/radio/headset/alt/cargo,
			/obj/item/radio/headset/alt/headset_com,
			/obj/item/radio/headset))

// Mining Goodies
/obj/random/multiple/minevault
	name = "random vault loot"
	desc = "Loot for mine vaults."
	icon = 'icons/obj/storage.dmi'
	icon_state = "crate"

CAPABILITIES(/obj/random/multiple/minevault)
	loot(
		table = list(
			loot_set(5, list(/obj/item/clothing/mask/smokable/pipe, /obj/item/reagent_containers/food/drinks/bottle/rum, /obj/item/reagent_containers/food/drinks/bottle/whiskey, /obj/item/reagent_containers/food/snacks/grown/ambrosiadeus, /obj/item/flame/lighter/zippo, /obj/structure/closet/crate/hydroponics)),
			loot_set(5, list(/obj/item/pickaxe, /obj/item/clothing/under/rank/miner, /obj/item/clothing/head/hardhat, /obj/structure/closet/crate/engineering)),
			loot_set(5, list(/obj/item/pickaxe/drill, /obj/item/clothing/suit/space/void/mining, /obj/item/clothing/head/helmet/space/void/mining, /obj/structure/closet/crate/engineering)),
			loot_set(5, list(/obj/item/pickaxe/advdrill, /obj/item/clothing/suit/space/void/mining/alt, /obj/item/clothing/head/helmet/space/void/mining/alt, /obj/structure/closet/crate/engineering)),
			loot_set(5, list(/obj/item/reagent_containers/glass/beaker/bluespace, /obj/item/reagent_containers/glass/beaker/bluespace, /obj/item/reagent_containers/glass/beaker/bluespace, /obj/structure/closet/crate/science)),
			loot_set(5, list(/obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/structure/closet/crate/engineering)),
			loot_set(5, list(/obj/item/pickaxe, /obj/item/clothing/glasses/material, /obj/structure/ore_box, /obj/structure/closet/crate)),
			loot_set(5, list(/obj/item/reagent_containers/glass/beaker/noreact, /obj/item/reagent_containers/glass/beaker/noreact, /obj/item/reagent_containers/glass/beaker/noreact, /obj/structure/closet/crate/science)),
			loot_set(5, list(/obj/item/storage/secure/briefcase/money, /obj/structure/closet/crate/freezer/rations)),
			loot_set(5, list(/obj/item/clothing/accessory/tie/horrible, /obj/item/clothing/accessory/tie/horrible, /obj/item/clothing/accessory/tie/horrible, /obj/item/clothing/accessory/tie/horrible, /obj/item/clothing/accessory/tie/horrible, /obj/item/clothing/accessory/tie/horrible, /obj/structure/closet/crate)),
			loot_set(5, list(/obj/item/melee/baton, /obj/item/melee/baton, /obj/item/melee/baton, /obj/item/melee/baton, /obj/structure/closet/crate)),
			loot_set(5, list(/obj/item/clothing/under/shorts/red, /obj/item/clothing/under/shorts/blue, /obj/structure/closet/crate)),
			loot_set(2, list(/obj/item/melee/baton/cattleprod, /obj/item/melee/baton/cattleprod, /obj/item/cell/high, /obj/item/cell/high, /obj/structure/closet/crate)),
			loot_set(2, list(/obj/item/latexballon, /obj/item/latexballon, /obj/structure/closet/crate)),
			loot_set(2, list(/obj/item/toy/syndicateballoon, /obj/item/toy/syndicateballoon, /obj/structure/closet/crate)),
			loot_set(2, list(/obj/item/rig/industrial/equipped, /obj/item/ore_bag, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/clothing/head/kitty, /obj/item/clothing/head/kitty, /obj/item/clothing/head/kitty, /obj/item/clothing/head/kitty, /obj/structure/closet/crate)),
			loot_set(2, list(/obj/random/coin, /obj/random/coin, /obj/random/coin, /obj/random/coin, /obj/random/coin, /obj/structure/closet/crate/plastic)),
			loot_set(2, list(/obj/random/multiple/voidsuit, /obj/random/multiple/voidsuit, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/clothing/suit/space/syndicate/black/red, /obj/item/clothing/head/helmet/space/syndicate/black/red, /obj/item/clothing/suit/space/syndicate/black/red, /obj/item/clothing/head/helmet/space/syndicate/black/red, /obj/item/gun/projectile/automatic/mini_uzi, /obj/item/gun/projectile/automatic/mini_uzi, /obj/item/ammo_magazine/m45uzi, /obj/item/ammo_magazine/m45uzi, /obj/item/ammo_magazine/m45uzi/empty, /obj/item/ammo_magazine/m45uzi/empty, /obj/structure/closet/crate/plastic)),
			loot_set(2, list(/obj/item/clothing/suit/ianshirt, /obj/item/clothing/suit/ianshirt, /obj/item/bedsheet/ian, /obj/structure/closet/crate/plastic)),
			loot_set(2, list(/obj/item/clothing/suit/armor/vest, /obj/item/clothing/suit/armor/vest, /obj/item/gun/projectile/garand, /obj/item/gun/projectile/garand, /obj/item/ammo_magazine/m762enbloc, /obj/item/ammo_magazine/m762enbloc, /obj/structure/closet/crate/plastic)),
			loot_set(2, list(/obj/mecha/working/ripley/mining)),
			loot_set(2, list(/obj/mecha/working/hoverpod/combatpod)),
			loot_set(2, list(/obj/item/pickaxe/silver, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/pickaxe/advdrill, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/pickaxe/jackhammer, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/pickaxe/diamond, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/pickaxe/diamonddrill, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/pickaxe/gold, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/pickaxe/plasmacutter, /obj/item/ore_bag, /obj/item/clothing/glasses/material, /obj/structure/closet/crate/engineering)),
			loot_set(2, list(/obj/item/material/sword/katana, /obj/item/material/sword/katana, /obj/structure/closet/crate)),
			loot_set(2, list(/obj/item/material/sword, /obj/item/material/sword, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/clothing/mask/balaclava, /obj/item/material/star, /obj/item/material/star, /obj/item/material/star, /obj/item/material/star, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/weed_extract, /obj/item/xenos_claw, /obj/structure/closet/crate/science)),
			loot_set(1, list(/obj/item/clothing/head/bearpelt, /obj/item/clothing/under/soviet, /obj/item/clothing/under/soviet, /obj/item/gun/projectile/shotgun/pump/rifle/ceremonial, /obj/item/gun/projectile/shotgun/pump/rifle/ceremonial, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/gun/projectile/revolver/detective, /obj/item/gun/projectile/contender, /obj/item/gun/projectile/p92x, /obj/item/gun/projectile/derringer, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/melee/cultblade, /obj/item/clothing/suit/cultrobes, /obj/item/clothing/head/culthood, /obj/item/soulstone, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/vampiric, /obj/item/vampiric, /obj/structure/closet/crate/science)),
			loot_set(1, list(/obj/item/archaeological_find)),
			loot_set(1, list(/obj/item/melee/energy/sword, /obj/item/melee/energy/sword, /obj/item/melee/energy/sword, /obj/item/shield/energy, /obj/item/shield/energy, /obj/structure/closet/crate/science)),
			loot_set(1, list(/obj/item/storage/backpack/clown, /obj/item/clothing/under/rank/clown, /obj/item/clothing/shoes/clown_shoes, /obj/item/pda/clown, /obj/item/clothing/mask/gas/clown_hat, /obj/item/bikehorn, /obj/item/reagent_containers/spray/waterflower, /obj/item/pen/crayon/rainbow, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/clothing/under/mime, /obj/item/clothing/shoes/black, /obj/item/pda/mime, /obj/item/clothing/gloves/white, /obj/item/clothing/mask/gas/mime, /obj/item/clothing/head/beret, /obj/item/clothing/suit/suspenders, /obj/item/pen/crayon/mime, /obj/item/reagent_containers/food/drinks/bottle/bottleofnothing, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/item/storage/belt/champion, /obj/item/clothing/mask/luchador, /obj/item/clothing/mask/luchador/rudos, /obj/item/clothing/mask/luchador/tecnicos, /obj/structure/closet/crate)),
			loot_set(1, list(/obj/machinery/artifact, /obj/structure/anomaly_container)),
			loot_set(1, list(/obj/random/curseditem, /obj/random/humanoidremains, /obj/structure/closet/crate))))

/obj/random/multiple/ore_pile
	name = "random ore pile"
	desc = "A pile of random ores. High chance of a larger pile of common ores, lower chances of small piles of rarer ores."
	icon = 'icons/obj/mining.dmi'
	icon_state = "ore_clown"


CAPABILITIES(/obj/random/multiple/ore_pile)
	loot(
		table = list(
			loot_set(10, list(/obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal, /obj/item/ore/coal)),
			loot_set(3, list(/obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond)),
			loot_set(15, list(/obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass)),
			loot_set(5, list(/obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold, /obj/item/ore/gold)),
			loot_set(2, list(/obj/item/ore/hydrogen, /obj/item/ore/hydrogen)),
			loot_set(10, list(/obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron, /obj/item/ore/iron)),
			loot_set(10, list(/obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead, /obj/item/ore/lead)),
			loot_set(5, list(/obj/item/ore/marble, /obj/item/ore/marble, /obj/item/ore/marble, /obj/item/ore/marble, /obj/item/ore/marble)),
			loot_set(3, list(/obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium)),
			loot_set(5, list(/obj/item/ore/phoron, /obj/item/ore/phoron, /obj/item/ore/phoron, /obj/item/ore/phoron, /obj/item/ore/phoron)),
			loot_set(5, list(/obj/item/ore/rutile, /obj/item/ore/rutile, /obj/item/ore/rutile, /obj/item/ore/rutile, /obj/item/ore/rutile)),
			loot_set(5, list(/obj/item/ore/silver, /obj/item/ore/silver, /obj/item/ore/silver, /obj/item/ore/silver, /obj/item/ore/silver)),
			loot_set(3, list(/obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium)),
			loot_set(2, list(/obj/item/ore/verdantium, /obj/item/ore/verdantium))))

/obj/random/multiple/corp_crate
	name = "random corporate crate"
	desc = "A random corporate crate with thematic contents."
	icon = 'icons/obj/storage.dmi'
	icon_state = "crate"

CAPABILITIES(/obj/random/multiple/corp_crate)
	loot(
		table = list(
			loot_set(10, list(/obj/random/tank, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/aether)),
			loot_set(5, list(/obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/aether)),
			loot_set(10, list(/obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/structure/closet/crate/centauri)),
			loot_set(10, list(/obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/item/storage/box/donkpockets, /obj/item/storage/box/donkpockets, /obj/item/storage/box/donkpockets, /obj/item/storage/box/donkpockets, /obj/item/storage/box/donkpockets, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/structure/closet/crate/einstein)),
			loot_set(5, list(/obj/item/circuitboard/smes, /obj/random/smes_coil, /obj/random/smes_coil, /obj/structure/closet/crate/focalpoint)),
			loot_set(10, list(/obj/item/module/power_control, /obj/item/stack/cable_coil, /obj/item/frame/apc, /obj/item/cell/apc, /obj/structure/closet/crate/focalpoint)),
			loot_set(5, list(/obj/random/drinkbottle, /obj/random/drinkbottle, /obj/random/drinkbottle, /obj/random/cigarettes, /obj/random/cigarettes, /obj/random/cigarettes, /obj/structure/closet/crate/gilthari)),
			loot_set(10, list(/obj/random/tech_supply/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/structure/closet/crate/grayson)),
			loot_set(15, list(/obj/random/multiple/ore_pile, /obj/random/multiple/ore_pile, /obj/random/multiple/ore_pile, /obj/random/multiple/ore_pile, /obj/structure/closet/crate/grayson)),
			loot_set(10, list(/obj/random/material/refined, /obj/random/material/refined, /obj/random/material/refined, /obj/random/material/refined, /obj/structure/closet/crate/grayson)),
			loot_set(2, list(/obj/random/energy, /obj/random/energy, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/structure/closet/crate/secure/heph)),
			loot_set(1, list(/obj/random/grenade/box, /obj/random/grenade/box, /obj/structure/closet/crate/secure/heph)),
			loot_set(2, list(/obj/random/projectile/random, /obj/random/projectile/random, /obj/structure/closet/crate/secure/lawson)),
			loot_set(3, list(/obj/random/grenade/less_lethal, /obj/random/grenade/less_lethal, /obj/random/grenade/less_lethal, /obj/random/grenade/less_lethal, /obj/structure/closet/crate/secure/nanotrasen)),
			loot_set(5, list(/obj/random/multiple/voidsuit/security, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/secure/nanotrasen)),
			loot_set(5, list(/obj/random/multiple/voidsuit/medical, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/secure/veymed)),
			loot_set(5, list(/obj/random/multiple/voidsuit/mining, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/grayson)),
			loot_set(5, list(/obj/random/multiple/voidsuit/engineering, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/xion)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/salvagecorp_shipbreaker, /obj/item/clothing/head/helmet/space/void/salvagecorp_shipbreaker, /obj/item/tank/jetpack/breaker, /obj/structure/closet/crate/coyote_salvage)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/medical, /obj/random/medical, /obj/random/medical, /obj/random/medical/lite, /obj/random/medical/lite, /obj/structure/closet/crate/veymed)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/firstaid, /obj/random/firstaid, /obj/random/firstaid, /obj/random/unidentified_medicine/fresh_medicine, /obj/random/unidentified_medicine/fresh_medicine, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(5, list(/obj/random/internal_organ, /obj/random/internal_organ, /obj/random/internal_organ, /obj/random/internal_organ, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(10, list(/obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/structure/closet/crate/xion)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/medical, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/lite, /obj/random/medical/lite, /obj/structure/closet/crate/freezer/zenghu)),
			loot_set(10, list(/obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/unidentified_medicine/fresh_medicine, /obj/random/unidentified_medicine/fresh_medicine, /obj/structure/closet/crate/freezer/zenghu)),
			loot_set(10, list(/obj/item/toner, /obj/item/toner, /obj/item/toner, /obj/item/clipboard, /obj/item/clipboard, /obj/item/pen/red, /obj/item/pen/blue, /obj/item/pen/blue, /obj/item/camera_film, /obj/item/folder/blue, /obj/item/folder/red, /obj/item/folder/yellow, /obj/item/hand_labeler, /obj/item/tape_roll, /obj/item/paper_bin, /obj/item/sticky_pad/random, /obj/structure/closet/crate/ummarcar)),
			loot_set(5, list(/obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/structure/closet/crate/unathi)),
			loot_set(10, list(/obj/item/reagent_containers/glass/bucket, /obj/item/mop, /obj/item/clothing/under/rank/janitor, /obj/item/cartridge/janitor, /obj/item/clothing/gloves/black, /obj/item/clothing/head/soft/purple, /obj/item/storage/belt/janitor, /obj/item/clothing/shoes/galoshes, /obj/item/clothing/glasses/hud/janitor, /obj/item/storage/bag/trash, /obj/item/lightreplacer, /obj/item/reagent_containers/spray/cleaner, /obj/item/reagent_containers/glass/rag, /obj/item/grenade/chem_grenade/cleaner, /obj/item/grenade/chem_grenade/cleaner, /obj/item/grenade/chem_grenade/cleaner, /obj/structure/closet/crate/galaksi)),
			loot_set(5, list(/obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/structure/closet/crate/allico)),
			loot_set(5, list(/obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/structure/closet/crate/nukies)),
			loot_set(5, list(/obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/structure/closet/crate/desatti)),
			loot_set(2, list(/obj/item/tank/phoron/pressurized, /obj/item/tank/phoron/pressurized, /obj/structure/closet/crate/secure/phoron)),
			loot_set(1, list(/obj/random/contraband/nofail, /obj/random/contraband/nofail, /obj/random/unidentified_medicine/combat_medicine, /obj/random/unidentified_medicine/combat_medicine, /obj/random/projectile/random, /obj/random/projectile/random, /obj/random/mre, /obj/random/mre, /obj/structure/closet/crate/secure/saare)),
			loot_set(2, list(/obj/random/grenade, /obj/random/grenade, /obj/random/grenade, /obj/random/grenade, /obj/random/grenade, /obj/random/grenade, /obj/structure/closet/crate/secure/saare)),
			loot_set(1, list(/obj/random/material/precious, /obj/random/material/precious, /obj/random/material/precious, /obj/random/material/precious, /obj/structure/closet/crate/secure/saare)),
			loot_set(1, list(/obj/random/cash/big, /obj/random/cash/big, /obj/random/cash/big, /obj/random/cash/huge, /obj/random/cash/huge, /obj/random/cash/huge, /obj/structure/closet/crate/secure/saare))))

/obj/random/multiple/corp_crate/no_weapons
	name = "random corporate crate (no weapons)"
	desc = "A random corporate crate with thematic contents. No weapons."
	icon = 'icons/obj/storage.dmi'
	icon_state = "crate"

CAPABILITIES(/obj/random/multiple/corp_crate/no_weapons)
	configure(loot(
		table = list(
			loot_set(10, list(/obj/random/tank, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/aether)),
			loot_set(5, list(/obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/aether)),
			loot_set(10, list(/obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/structure/closet/crate/centauri)),
			loot_set(10, list(/obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/structure/closet/crate/einstein)),
			loot_set(5, list(/obj/item/circuitboard/smes, /obj/random/smes_coil, /obj/random/smes_coil, /obj/structure/closet/crate/focalpoint)),
			loot_set(10, list(/obj/item/module/power_control, /obj/item/stack/cable_coil, /obj/item/frame/apc, /obj/item/cell/apc, /obj/structure/closet/crate/focalpoint)),
			loot_set(5, list(/obj/random/drinkbottle, /obj/random/drinkbottle, /obj/random/drinkbottle, /obj/random/cigarettes, /obj/random/cigarettes, /obj/random/cigarettes, /obj/structure/closet/crate/gilthari)),
			loot_set(10, list(/obj/random/tech_supply/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/structure/closet/crate/grayson)),
			loot_set(15, list(/obj/random/multiple/ore_pile, /obj/random/multiple/ore_pile, /obj/random/multiple/ore_pile, /obj/random/multiple/ore_pile, /obj/structure/closet/crate/grayson)),
			loot_set(10, list(/obj/random/material/refined, /obj/random/material/refined, /obj/random/material/refined, /obj/random/material/refined, /obj/structure/closet/crate/grayson)),
			loot_set(5, list(/obj/random/multiple/voidsuit/security, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/secure/nanotrasen)),
			loot_set(5, list(/obj/random/multiple/voidsuit/medical, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/secure/veymed)),
			loot_set(5, list(/obj/random/multiple/voidsuit/mining, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/grayson)),
			loot_set(5, list(/obj/random/multiple/voidsuit/engineering, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/xion)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/salvagecorp_shipbreaker, /obj/item/clothing/head/helmet/space/void/salvagecorp_shipbreaker, /obj/item/tank/jetpack/breaker, /obj/structure/closet/crate/coyote_salvage)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/medical, /obj/random/medical, /obj/random/medical, /obj/random/medical/lite, /obj/random/medical/lite, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/firstaid, /obj/random/firstaid, /obj/random/firstaid, /obj/random/unidentified_medicine/fresh_medicine, /obj/random/unidentified_medicine/fresh_medicine, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(5, list(/obj/random/internal_organ, /obj/random/internal_organ, /obj/random/internal_organ, /obj/random/internal_organ, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(10, list(/obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/structure/closet/crate/xion)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/medical, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/lite, /obj/random/medical/lite, /obj/structure/closet/crate/freezer/zenghu)),
			loot_set(10, list(/obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/unidentified_medicine/fresh_medicine, /obj/random/unidentified_medicine/fresh_medicine, /obj/structure/closet/crate/freezer/zenghu)),
			loot_set(10, list(/obj/item/toner, /obj/item/toner, /obj/item/toner, /obj/item/clipboard, /obj/item/clipboard, /obj/item/pen/red, /obj/item/pen/blue, /obj/item/pen/blue, /obj/item/camera_film, /obj/item/folder/blue, /obj/item/folder/red, /obj/item/folder/yellow, /obj/item/hand_labeler, /obj/item/tape_roll, /obj/item/paper_bin, /obj/item/sticky_pad/random, /obj/structure/closet/crate/ummarcar)),
			loot_set(5, list(/obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/structure/closet/crate/unathi)),
			loot_set(10, list(/obj/item/reagent_containers/glass/bucket, /obj/item/mop, /obj/item/clothing/under/rank/janitor, /obj/item/cartridge/janitor, /obj/item/clothing/gloves/black, /obj/item/clothing/head/soft/purple, /obj/item/storage/belt/janitor, /obj/item/clothing/shoes/galoshes, /obj/item/clothing/glasses/hud/janitor, /obj/item/storage/bag/trash, /obj/item/lightreplacer, /obj/item/reagent_containers/spray/cleaner, /obj/item/reagent_containers/glass/rag, /obj/item/grenade/chem_grenade/cleaner, /obj/item/grenade/chem_grenade/cleaner, /obj/item/grenade/chem_grenade/cleaner, /obj/structure/closet/crate/galaksi)),
			loot_set(5, list(/obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/structure/closet/crate/allico)),
			loot_set(5, list(/obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/structure/closet/crate/nukies)),
			loot_set(5, list(/obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/structure/closet/crate/desatti)),
			loot_set(2, list(/obj/item/tank/phoron/pressurized, /obj/item/tank/phoron/pressurized, /obj/structure/closet/crate/secure/phoron)),
			loot_set(1, list(/obj/random/material/precious, /obj/random/material/precious, /obj/random/material/precious, /obj/random/material/precious, /obj/structure/closet/crate/secure/saare)),
			loot_set(1, list(/obj/random/cash/big, /obj/random/cash/big, /obj/random/cash/big, /obj/random/cash/huge, /obj/random/cash/huge, /obj/random/cash/huge, /obj/structure/closet/crate/secure/saare)))))

/obj/random/multiple/large_corp_crate
	name = "random large corporate crate"
	desc = "A random large corporate crate with thematic contents."
	icon = 'icons/obj/storage.dmi'
	icon_state = "largermetal"

CAPABILITIES(/obj/random/multiple/large_corp_crate)
	loot(
		table = list(
			loot_set(30, list(/obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/large/aether)),
			loot_set(30, list(/obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/structure/closet/crate/large/einstein)),
			loot_set(20, list(/obj/item/circuitboard/smes, /obj/item/circuitboard/smes, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/structure/closet/crate/large/einstein)),
			loot_set(2, list(/obj/random/energy, /obj/random/energy, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/random/energy, /obj/random/energy, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon, /obj/structure/closet/crate/large/secure/heph)),
			loot_set(2, list(/obj/random/projectile/random, /obj/random/projectile/random, /obj/random/projectile/random, /obj/random/projectile/random, /obj/structure/closet/crate/large/secure/heph)),
			loot_set(20, list(/obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/structure/closet/crate/large/xion)),
			loot_set(20, list(/obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/structure/closet/crate/large/secure/xion))))

/obj/random/multiple/large_corp_crate/no_weapons
	name = "random large corporate crate (no weapons)"
	desc = "A random large corporate crate with thematic contents. No weapons."
	icon = 'icons/obj/storage.dmi'
	icon_state = "largermetal"

CAPABILITIES(/obj/random/multiple/large_corp_crate/no_weapons)
	configure(loot(
		table = list(
			loot_set(30, list(/obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/large/aether)),
			loot_set(30, list(/obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/structure/closet/crate/large/einstein)),
			loot_set(20, list(/obj/item/circuitboard/smes, /obj/item/circuitboard/smes, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/random/smes_coil, /obj/structure/closet/crate/large/einstein)),
			loot_set(20, list(/obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/random/tech_supply/nofail, /obj/structure/closet/crate/large/xion)),
			loot_set(20, list(/obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/random/tech_supply/component/nofail, /obj/structure/closet/crate/large/secure/xion)))))

//recursion crate!
/obj/random/multiple/random_size_crate
	name = "random size corporate crate"
	desc = "A random size corporate crate with thematic contents: prefers small crates."
	icon = 'icons/obj/storage.dmi'
	icon_state = "largermetal"

CAPABILITIES(/obj/random/multiple/random_size_crate)
	loot(table = list(loot_set(85, list(/obj/random/multiple/corp_crate)), loot_set(15, list(/obj/random/multiple/large_corp_crate))))
// Random good, no guns gooder
/obj/random/multiple/random_size_crate/no_weapons
	name = "random size corporate crate (no weapons)"
	desc = "A random size corporate crate with thematic contents: prefers small crates."
	icon = 'icons/obj/storage.dmi'
	icon_state = "largermetal"

CAPABILITIES(/obj/random/multiple/random_size_crate/no_weapons)
	configure(loot(
		table = list(loot_set(85, list(/obj/random/multiple/corp_crate/no_weapons)), loot_set(15, list(/obj/random/multiple/large_corp_crate/no_weapons))),
		chance = 50))

/obj/random/multiple/random_size_crate/no_weapons/nofail
CAPABILITIES(/obj/random/multiple/random_size_crate/no_weapons/nofail)
	configure(loot(chance = 100))

/*
 * Turf swappers.
 */

/obj/random/turf
	name = "random Sif turf"
	desc = "This is a random Sif turf."


	var/override_outdoors = FALSE	// Do we override our chosen turf's outdoors?
	var/turf_outdoors = OUTDOORS_AREA	// Will our turf be outdoors?

CAPABILITIES(/obj/random/turf)
	configure(map_resolver(vars = list("drop_get_turf", "override_outdoors", "turf_outdoors")))
	loot(
		hook = GLOBAL_PROC_REF(loot_hook_random_turf),
		table = list(
			/turf/simulated/floor/outdoors/grass/sif,
			/turf/simulated/floor/outdoors/dirt,
			/turf/simulated/floor/outdoors/grass/sif/forest,
			/turf/simulated/floor/outdoors/rocks),
		chance = 80)


/// LOOT_HOOK for turf swappers: the rolled turf takes the spawner's outdoors override.
/proc/loot_hook_random_turf(atom/spawned, path, list/varedits, datum/loot_rng/rng)
	var/turf/T = spawned
	var/obj/random/turf/P = path
	if(isturf(T) && MAP_VAR(P, varedits, override_outdoors))
		T.outdoors = MAP_VAR(P, varedits, turf_outdoors)

/obj/random/turf/lava
	name = "random Lava spawn"
	desc = "This is a random lava spawn."

	override_outdoors = TRUE
	turf_outdoors = OUTDOORS_NO

CAPABILITIES(/obj/random/turf/lava)
	configure(loot(
		table = list(/turf/simulated/floor/lava = 5, /turf/simulated/floor/outdoors/rocks/caves = 3, /turf/simulated/mineral/ignore_mapgen/cave = 1)))

// Underdark stuff that would be cool if existed if the underdark doesn't.

/obj/random/underdark
	name = "random underdark loot"
	desc = "Random loot for Underdark."
	icon = 'icons/obj/items.dmi'
	icon_state = "spickaxe"

CAPABILITIES(/obj/random/underdark)
	loot(
		table = list(
			/obj/random/multiple/underdark/miningdrills = 3,
			/obj/random/multiple/underdark/ores = 3,
			/obj/random/multiple/underdark/treasure = 2,
			/obj/random/multiple/underdark/mechtool = 1))

/obj/random/underdark/uncertain
	icon_state = "upickaxe"
CAPABILITIES(/obj/random/underdark/uncertain)
	configure(loot(chance = 35))

/obj/random/multiple/underdark/miningdrills
	name = "random underdark mining tool loot"
	desc = "Random mining tool loot for Underdark."
	icon = 'icons/obj/items.dmi'
	icon_state = "spickaxe"

CAPABILITIES(/obj/random/multiple/underdark/miningdrills)
	loot(
		table = list(
			loot_set(10, list(/obj/item/pickaxe/silver)),
			loot_set(8, list(/obj/item/pickaxe/drill)),
			loot_set(6, list(/obj/item/pickaxe/advdrill)),
			loot_set(6, list(/obj/item/pickaxe/jackhammer)),
			loot_set(5, list(/obj/item/pickaxe/gold)),
			loot_set(4, list(/obj/item/pickaxe/plasmacutter)),
			loot_set(2, list(/obj/item/pickaxe/diamond)),
			loot_set(1, list(/obj/item/pickaxe/diamonddrill))))

/obj/random/multiple/underdark/ores
	name = "random underdark mining ore loot"
	desc = "Random mining utility loot for Underdark."
	icon = 'icons/obj/mining.dmi'
	icon_state = "satchel"

CAPABILITIES(/obj/random/multiple/underdark/ores)
	loot(
		table = list(
			loot_set(9, list(/obj/item/ore_bag, /obj/item/shovel, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/glass, /obj/item/ore/hydrogen, /obj/item/ore/hydrogen, /obj/item/ore/hydrogen, /obj/item/ore/hydrogen, /obj/item/ore/hydrogen, /obj/item/ore/hydrogen)),
			loot_set(7, list(/obj/item/ore_bag, /obj/item/pickaxe, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium, /obj/item/ore/osmium)),
			loot_set(4, list(/obj/item/clothing/suit/radiation, /obj/item/clothing/head/radiation, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium, /obj/item/ore/uranium)),
			loot_set(2, list(/obj/item/flashlight/lantern, /obj/item/clothing/glasses/material, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond, /obj/item/ore/diamond)),
			loot_set(1, list(/obj/item/mining_scanner, /obj/item/shovel/spade, /obj/item/ore/verdantium, /obj/item/ore/verdantium, /obj/item/ore/verdantium, /obj/item/ore/verdantium, /obj/item/ore/verdantium))))

/obj/random/multiple/underdark/treasure
	name = "random underdark treasure"
	desc = "Random treasure loot for Underdark."
	icon = 'icons/obj/storage.dmi'
	icon_state = "cashbag"

CAPABILITIES(/obj/random/multiple/underdark/treasure)
	loot(
		table = list(
			loot_set(5, list(/obj/random/coin, /obj/random/coin, /obj/random/coin, /obj/random/coin, /obj/random/coin, /obj/item/clothing/head/pirate)),
			loot_set(4, list(/obj/item/storage/bag/cash, /obj/item/spacecash/c500, /obj/item/spacecash/c100, /obj/item/spacecash/c50)),
			loot_set(3, list(/obj/item/clothing/head/hardhat/orange, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold, /obj/item/stack/material/gold)),
			loot_set(1, list(/obj/item/stack/material/phoron, /obj/item/stack/material/phoron, /obj/item/stack/material/phoron, /obj/item/stack/material/phoron, /obj/item/stack/material/diamond, /obj/item/stack/material/diamond, /obj/item/stack/material/diamond))))

/obj/random/multiple/underdark/mechtool
	name = "random underdark mech equipment"
	desc = "Random mech equipment loot for Underdark."
	icon = 'icons/mecha/mecha_equipment.dmi'
	icon_state = "mecha_clamp"

CAPABILITIES(/obj/random/multiple/underdark/mechtool)
	loot(
		table = list(
			loot_set(12, list(/obj/item/mecha_parts/mecha_equipment/tool/drill)),
			loot_set(10, list(/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp)),
			loot_set(8, list(/obj/item/mecha_parts/mecha_equipment/generator)),
			loot_set(7, list(/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/scattershot/rigged)),
			loot_set(6, list(/obj/item/mecha_parts/mecha_equipment/repair_droid)),
			loot_set(3, list(/obj/item/mecha_parts/mecha_equipment/gravcatapult)),
			loot_set(2, list(/obj/item/mecha_parts/mecha_equipment/weapon/energy/riggedlaser)),
			loot_set(2, list(/obj/item/mecha_parts/mecha_equipment/weapon/energy/flamer/rigged)),
			loot_set(1, list(/obj/item/mecha_parts/mecha_equipment/tool/drill/diamonddrill))))

/obj/random/multiple/corp_crate_supply
	name = "random corporate supply crate"
	desc = "A random corporate crate with thematic contents. No weapons."
	icon = 'icons/obj/storage.dmi'
	icon_state = "crate"

CAPABILITIES(/obj/random/multiple/corp_crate_supply)
	loot(
		table = list(
			loot_set(10, list(/obj/random/tank, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/aether)),
			loot_set(5, list(/obj/random/multiple/voidsuit/vintage, /obj/random/multiple/voidsuit/vintage, /obj/random/tank, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/aether)),
			loot_set(10, list(/obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/random/mre, /obj/structure/closet/crate/centauri)),
			loot_set(10, list(/obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/random/drinksoft, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/random/snack, /obj/structure/closet/crate/freezer/centauri)),
			loot_set(10, list(/obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/random/powercell, /obj/structure/closet/crate/einstein)),
			loot_set(5, list(/obj/item/circuitboard/smes, /obj/random/smes_coil, /obj/random/smes_coil, /obj/structure/closet/crate/focalpoint)),
			loot_set(10, list(/obj/item/module/power_control, /obj/item/stack/cable_coil, /obj/item/frame/apc, /obj/item/cell/apc, /obj/structure/closet/crate/focalpoint)),
			loot_set(5, list(/obj/random/drinkbottle, /obj/random/drinkbottle, /obj/random/drinkbottle, /obj/random/cigarettes, /obj/random/cigarettes, /obj/random/cigarettes, /obj/structure/closet/crate/gilthari)),
			loot_set(5, list(/obj/random/multiple/voidsuit/security, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/secure/nanotrasen)),
			loot_set(5, list(/obj/random/multiple/voidsuit/medical, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/secure/veymed)),
			loot_set(5, list(/obj/random/multiple/voidsuit/mining, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/grayson)),
			loot_set(5, list(/obj/random/multiple/voidsuit/engineering, /obj/random/tank, /obj/item/clothing/mask/breath, /obj/structure/closet/crate/xion)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/salvagecorp_shipbreaker, /obj/item/clothing/head/helmet/space/void/salvagecorp_shipbreaker, /obj/item/tank/jetpack/breaker, /obj/structure/closet/crate/coyote_salvage)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/medical, /obj/random/medical, /obj/random/medical, /obj/random/medical/lite, /obj/random/medical/lite, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/firstaid, /obj/random/firstaid, /obj/random/firstaid, /obj/random/unidentified_medicine/fresh_medicine, /obj/random/unidentified_medicine/fresh_medicine, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(5, list(/obj/random/internal_organ, /obj/random/internal_organ, /obj/random/internal_organ, /obj/random/internal_organ, /obj/structure/closet/crate/freezer/veymed)),
			loot_set(10, list(/obj/random/firstaid, /obj/random/medical, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/lite, /obj/random/medical/lite, /obj/structure/closet/crate/freezer/zenghu)),
			loot_set(10, list(/obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/medical/pillbottle, /obj/random/unidentified_medicine/fresh_medicine, /obj/random/unidentified_medicine/fresh_medicine, /obj/structure/closet/crate/freezer/zenghu)),
			loot_set(10, list(/obj/item/toner, /obj/item/toner, /obj/item/toner, /obj/item/clipboard, /obj/item/clipboard, /obj/item/pen/red, /obj/item/pen/blue, /obj/item/pen/blue, /obj/item/camera_film, /obj/item/folder/blue, /obj/item/folder/red, /obj/item/folder/yellow, /obj/item/hand_labeler, /obj/item/tape_roll, /obj/item/paper_bin, /obj/item/sticky_pad/random, /obj/structure/closet/crate/ummarcar)),
			loot_set(5, list(/obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/item/reagent_containers/food/snacks/unajerky, /obj/structure/closet/crate/unathi)),
			loot_set(10, list(/obj/item/reagent_containers/glass/bucket, /obj/item/mop, /obj/item/clothing/under/rank/janitor, /obj/item/cartridge/janitor, /obj/item/clothing/gloves/black, /obj/item/clothing/head/soft/purple, /obj/item/storage/belt/janitor, /obj/item/clothing/shoes/galoshes, /obj/item/clothing/glasses/hud/janitor, /obj/item/storage/bag/trash, /obj/item/lightreplacer, /obj/item/reagent_containers/spray/cleaner, /obj/item/reagent_containers/glass/rag, /obj/item/grenade/chem_grenade/cleaner, /obj/item/grenade/chem_grenade/cleaner, /obj/item/grenade/chem_grenade/cleaner, /obj/structure/closet/crate/galaksi)),
			loot_set(5, list(/obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/item/reagent_containers/food/snacks/candy/gummy, /obj/structure/closet/crate/allico)),
			loot_set(5, list(/obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/random/nukies_can_legal, /obj/structure/closet/crate/nukies)),
			loot_set(5, list(/obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/random/desatti_snacks, /obj/structure/closet/crate/desatti)),
			loot_set(2, list(/obj/item/tank/phoron/pressurized, /obj/item/tank/phoron/pressurized, /obj/structure/closet/crate/secure/phoron))))

/obj/random/multiple/legtrap
	name = "random legtraps"
	desc = "Random legtraps (beartraps and mousetraps)."
	icon = 'icons/misc/mark.dmi'
	icon_state = "x3"

CAPABILITIES(/obj/random/multiple/legtrap)
	loot(table = list(loot_set(67, list(/obj/item/assembly/mousetrap/armed)), loot_set(33, list(/obj/item/beartrap/start_active))))


/obj/random/empty_or_lootable_crate
	name = "random crate"
	desc = "Spawns a random crate which may or may not have contents. Sometimes spawns nothing."
	icon = 'icons/obj/storage.dmi'
	icon_state = "moneybag"

CAPABILITIES(/obj/random/empty_or_lootable_crate)
	loot(table = list(/obj/random/crate, /obj/random/multiple/corp_crate), chance = 80)

/obj/random/forgotten_tram
	name = "random forgotten tram item"
	desc = "Spawns a random item that someone might accidentally leave on a tram. Sometimes spawns nothing."

CAPABILITIES(/obj/random/forgotten_tram)
	loot(
		table = list(
			/obj/item/flashlight = 2,
			/obj/item/flashlight/color = 2,
			/obj/item/flashlight/color/green = 2,
			/obj/item/flashlight/color/purple = 2,
			/obj/item/flashlight/color/red = 2,
			/obj/item/flashlight/color/orange = 2,
			/obj/item/flashlight/color/yellow = 2,
			/obj/item/flashlight/glowstick = 2,
			/obj/item/flashlight/glowstick/blue = 2,
			/obj/item/flashlight/glowstick/orange = 1,
			/obj/item/flashlight/glowstick/red = 1,
			/obj/item/flashlight/glowstick/yellow = 1,
			/obj/item/flashlight/pen = 1,
			/obj/item/flashlight/maglight = 2,
			/obj/random/cigarettes = 5,
			/obj/random/soap = 5,
			/obj/random/drinksoft = 5,
			/obj/random/snack = 5,
			/obj/random/plushie = 5,
			/obj/item/storage/secure/briefcase = 2,
			/obj/item/storage/briefcase = 4,
			/obj/item/storage/backpack = 5,
			/obj/item/storage/backpack/medic = 5,
			/obj/item/storage/backpack/industrial = 5,
			/obj/item/storage/backpack/toxins = 5,
			/obj/item/storage/backpack/dufflebag = 3,
			/obj/item/storage/backpack/dufflebag/med = 3,
			/obj/item/storage/backpack/dufflebag/eng = 3,
			/obj/item/storage/backpack/dufflebag/syndie = 1,
			/obj/item/storage/backpack/dufflebag/syndie/med = 1,
			/obj/item/storage/backpack/dufflebag/syndie/ammo = 1,
			/obj/item/storage/backpack/satchel = 4,
			/obj/item/storage/backpack/satchel/norm = 5,
			/obj/item/storage/backpack/satchel/med = 5,
			/obj/item/storage/backpack/satchel/eng = 5,
			/obj/item/storage/backpack/satchel/tox = 5,
			/obj/item/storage/backpack/messenger/med = 5,
			/obj/item/storage/backpack/messenger/engi = 5,
			/obj/item/storage/backpack/messenger/tox = 5,
			/obj/item/storage/wallet = 3,
			/obj/item/clothing/gloves/black = 1,
			/obj/item/clothing/gloves/blue = 1,
			/obj/item/clothing/gloves/brown = 1,
			/obj/item/clothing/gloves/duty = 1,
			/obj/item/clothing/gloves/fingerless = 1,
			/obj/item/clothing/gloves/green = 1,
			/obj/item/clothing/gloves/grey = 1,
			/obj/item/clothing/gloves/orange = 1,
			/obj/item/clothing/gloves/yellow = 1,
			/obj/item/clothing/gloves/botanic_leather = 3,
			/obj/item/clothing/gloves/sterile/latex = 2,
			/obj/item/clothing/gloves/white = 5,
			/obj/item/clothing/gloves/rainbow = 5,
			/obj/item/clothing/gloves/fyellow = 2,
			/obj/item/clothing/glasses/rimless = 1,
			/obj/item/clothing/glasses/thin = 1,
			/obj/item/clothing/glasses/regular = 1,
			/obj/item/clothing/glasses/regular/rimless = 1,
			/obj/item/clothing/glasses/regular/thin = 1,
			/obj/item/clothing/glasses/fakesunglasses = 1,
			/obj/item/clothing/glasses/fakesunglasses/aviator = 1,
			/obj/item/clothing/glasses/omnihud = 1,
			/obj/item/clothing/head/hardhat = 4,
			/obj/item/clothing/head/hardhat/red = 3,
			/obj/item/clothing/head/hardhat/dblue = 2,
			/obj/item/clothing/head/hardhat/orange = 2,
			/obj/item/clothing/head/soft/ = 4,
			/obj/item/clothing/head/soft/black = 4,
			/obj/item/clothing/head/soft/blue = 4,
			/obj/item/clothing/head/soft/green = 4,
			/obj/item/clothing/head/soft/grey = 4,
			/obj/item/clothing/head/soft/med = 4,
			/obj/item/clothing/head/soft/nanotrasen = 4,
			/obj/item/clothing/head/soft/red = 4,
			/obj/item/clothing/head/soft/orange = 4,
			/obj/item/clothing/head/soft/sec = 4,
			/obj/item/clothing/head/soft/sec/corp = 4,
			/obj/item/clothing/head/soft/yellow = 6,
			/obj/item/clothing/head/ushanka = 1,
			/obj/item/clothing/head/beret = 3,
			/obj/item/clothing/head/beret/engineering = 3,
			/obj/item/clothing/head/beret/purple = 1,
			/obj/item/clothing/head/beret/sec = 3,
			/obj/item/clothing/head/beret/sec/corporate/officer = 3,
			/obj/item/clothing/head/beret/sec/navy/officer = 3,
			/obj/item/clothing/head/orangebandana = 2,
			/obj/item/clothing/suit/storage/toggle/bomber = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/black = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/blue = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/red = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/yellow = 3,
			/obj/item/clothing/suit/storage/toggle/brown_jacket = 3,
			/obj/item/clothing/suit/storage/toggle/leather_jacket = 3,
			/obj/item/clothing/suit/storage/toggle/labcoat = 4,
			/obj/item/clothing/suit/storage/toggle/labcoat/science = 4,
			/obj/item/clothing/suit/storage/miljacket = 4,
			/obj/item/clothing/suit/storage/miljacket/alt = 4,
			/obj/item/clothing/suit/storage/miljacket/black = 4,
			/obj/item/clothing/suit/storage/miljacket/green = 4,
			/obj/item/clothing/suit/storage/miljacket/grey = 4,
			/obj/item/clothing/suit/storage/miljacket/navy = 4,
			/obj/item/clothing/suit/storage/miljacket/tan = 4,
			/obj/item/clothing/suit/storage/miljacket/white = 4,
			/obj/item/clothing/suit/storage/trench = 4,
			/obj/item/clothing/suit/varsity = 3,
			/obj/item/clothing/suit/varsity/blue = 3,
			/obj/item/clothing/suit/varsity/brown = 3,
			/obj/item/clothing/suit/varsity/green = 3,
			/obj/item/clothing/suit/varsity/purple = 3,
			/obj/item/clothing/suit/varsity/red = 3,
			/obj/item/clothing/accessory/poncho = 3,
			/obj/item/clothing/accessory/poncho/blue = 3,
			/obj/item/clothing/accessory/poncho/green = 3,
			/obj/item/clothing/accessory/poncho/purple = 3,
			/obj/item/clothing/accessory/poncho/red = 3,
			/obj/item/clothing/accessory/poncho/roles/cargo = 3,
			/obj/item/clothing/accessory/poncho/roles/engineering = 3,
			/obj/item/clothing/accessory/poncho/roles/medical = 3,
			/obj/item/clothing/accessory/poncho/roles/science = 3,
			/obj/item/clothing/accessory/poncho/roles/security = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/atmos = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/cargo = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/engineer = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/medical = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/mining = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/research = 3,
			/obj/item/clothing/accessory/poncho/roles/cloak/security = 3,
			/obj/item/clothing/accessory/stethoscope = 2,
			/obj/item/camera = 2,
			/obj/item/pda = 3,
			/obj/item/radio/headset = 3,
			/obj/item/toy/tennis = 2,
			/obj/item/toy/tennis/red = 2,
			/obj/item/toy/tennis/yellow = 2,
			/obj/item/toy/tennis/green = 2,
			/obj/item/toy/tennis/cyan = 2,
			/obj/item/toy/tennis/blue = 2,
			/obj/item/toy/tennis/purple = 2,
			/obj/item/clothing/ears/earmuffs = 2,
			/obj/item/clothing/ears/earmuffs/headphones = 2,
			/obj/item/toy/baseball = 2),
		chance = 70)


//Buncha mapping helpers to make some map work easier

/obj/effect/map_helper
	icon = 'icons/misc/map_helpers.dmi'

// Mapping helpers apply to their level or area once the load is in place (map_resolve_later()).
CAPABILITIES(/obj/effect/map_helper)
	map_resolver(GLOBAL_PROC_REF(resolve_map_helper), vars = list("baseturf"))

/proc/resolve_map_helper(atom/loc, path, list/varedits)
	map_resolve_later(GLOBAL_PROC_REF(map_helper_apply), get_turf(loc), path, varedits)
	return TRUE

/// Applies mapping helper `path` placed on `T`.
/proc/map_helper_apply(turf/T, path, list/varedits)
	if(!T)
		return
	var/area/A = get_area(T)
	if(ispath(path, /obj/effect/map_helper/base_turf))
		var/obj/effect/map_helper/base_turf/P = path
		var/baseturf = MAP_VAR(P, varedits, baseturf)
		if(ispath(path, /obj/effect/map_helper/base_turf/area))
			if(A)
				A.base_turf = baseturf
		else if(baseturf)
			using_map.base_turf_by_z["[T.z]"] = baseturf
	else if(ispath(path, /obj/effect/map_helper/no_tele/area))
		if(A)
			A.flags |= BLUE_SHIELDED
			for(var/turf/AT in contents_of(A))
				AT.block_tele = 1
	else if(ispath(path, /obj/effect/map_helper/no_tele))
		for(var/turf/ZT in Z_TURFS(T.z))
			ZT.block_tele = 1
	else if(ispath(path, /obj/effect/map_helper/make_indoors/area))
		if(A)
			for(var/turf/simulated/AT in contents_of(A))
				AT.make_indoors()
	else if(ispath(path, /obj/effect/map_helper/make_indoors))
		for(var/turf/simulated/ZT in Z_TURFS(T.z))
			ZT.make_indoors()
	else if(ispath(path, /obj/effect/map_helper/make_outdoors/area))
		if(A)
			for(var/turf/simulated/AT in contents_of(A))
				AT.make_outdoors()
	else if(ispath(path, /obj/effect/map_helper/make_outdoors))
		for(var/turf/simulated/ZT in Z_TURFS(T.z))
			ZT.make_outdoors()
	else if(ispath(path, /obj/effect/map_helper/no_phaseshift/area))
		if(A)
			A.flags |= PHASE_SHIELDED

/obj/effect/map_helper/base_turf
	name = "z-wide baseturf editor"
	desc = "I set the provided 'baseturf' to the whole z-level I'm in!"
	var/baseturf

/obj/effect/map_helper/base_turf/area
	name = "area-wide baseturf editor"
	desc = "I set the provided 'baseturf' var to the whole /area I'm in!"

/obj/effect/map_helper/no_tele
	name = "z-wide teleport block"
	desc = "I disable the use of all hand tele's/translocators/bluespace harpoons/telescience in my z-level!"

/obj/effect/map_helper/no_tele/area
	name = "area-wide teleport block"
	desc = "I disable the use of all hand tele's/translocators/bluespace harpoons/telescience in my area!"

/obj/effect/map_helper/make_indoors
	name = "z-wide indoors maker"
	desc = "I forcibly call make_indoors on every turf on this z-level. Useful for admin late loading maps to fix lighting!"

/obj/effect/map_helper/make_indoors/area
	name = "Area indoors maker"
	desc = "I forcibly call make_indoors on every turf in this area."

/obj/effect/map_helper/make_outdoors
	name = "z-wide outdoors maker"
	desc = "I forcibly call make_outdoors on every turf on this z-level."

/obj/effect/map_helper/make_outdoors/area
	name = "Area outdoors maker"
	desc = "I forcibly call make_outdoors on every turf in this area."

/obj/effect/map_helper/no_phaseshift/area
	name = "area-wide phaseshift blocker"
	desc = "I disable the use of both shadekin and redspace phasing!"

//For active edges in Sif POIs
/obj/random/turf/lava/sif
	name = "random Lava spawn sif"
	desc = "This is a random lava spawn. Programmed to spawn lava with sif temps"

	override_outdoors = TRUE
	turf_outdoors = OUTDOORS_NO

CAPABILITIES(/obj/random/turf/lava/sif)
	configure(loot(
		table = list(
			/turf/simulated/floor/lava/external = 5,
			/turf/simulated/floor/outdoors/rocks/caves = 3,
			/turf/simulated/mineral/ignore_mapgen/cave = 1)))
