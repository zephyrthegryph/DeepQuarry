/*
// This is going to get so incredibly bloated.
// But this is where all of the "Loot" goes. Anything fun or useful that doesn't deserve its own file, pile in.
*/

/obj/random/tool
	name = "random tool"
	desc = "This is a random tool"
	icon_state = "tool"

CAPABILITIES(/obj/random/tool)
	loot(
		table = list(
			/obj/item/tool/screwdriver,
			/obj/item/tool/wirecutters,
			/obj/item/weldingtool,
			/obj/item/weldingtool/largetank,
			/obj/item/tool/crowbar,
			/obj/item/tool/wrench,
			/obj/item/flashlight,
			/obj/item/multitool))

/obj/random/tool/powermaint
	name = "random powertool"
	desc = "This is a random rare powertool for maintenance"
	icon_state = "tool_2"

CAPABILITIES(/obj/random/tool/powermaint)
	configure(loot(
		table = list(
			/obj/random/tool = 320,
			/obj/item/tool/transforming/powerdrill = 1,
			/obj/item/tool/transforming/jawsoflife = 1,
			/obj/item/weldingtool/electric = 15,
			/obj/item/weldingtool/experimental = 5)))

/obj/random/tool/power
	name = "random powertool"
	desc = "This is a random powertool"
	icon_state = "tool_2"

CAPABILITIES(/obj/random/tool/power)
	configure(loot(
		table = list(
			/obj/item/tool/transforming/powerdrill,
			/obj/item/tool/transforming/jawsoflife,
			/obj/item/weldingtool/electric,
			/obj/item/weldingtool/experimental)))

/obj/random/tool/alien
	name = "random alien tool"
	desc = "This is a random tool"
	icon_state = "tool_3"

CAPABILITIES(/obj/random/tool/alien)
	configure(loot(
		table = list(
			/obj/item/tool/screwdriver/alien,
			/obj/item/tool/wirecutters/alien,
			/obj/item/weldingtool/alien,
			/obj/item/tool/crowbar/alien,
			/obj/item/tool/wrench/alien,
			/obj/item/stack/cable_coil/alien,
			/obj/item/multitool/alien)))

/obj/random/technology_scanner
	name = "random scanner"
	desc = "This is a random technology scanner."
	icon_state = "tech"

CAPABILITIES(/obj/random/technology_scanner)
	loot(table = list(/obj/item/t_scanner = 5, /obj/item/radio = 2, /obj/item/analyzer = 5))

/obj/random/powercell
	name = "random powercell"
	desc = "This is a random powercell."
	icon = 'icons/obj/power_cells.dmi'
	icon_state = "random"

CAPABILITIES(/obj/random/powercell)
	loot(table = list(/obj/item/cell = 40, /obj/item/cell/device = 25, /obj/item/cell/high = 25, /obj/item/cell/super = 9, /obj/item/cell/hyper = 1))

/obj/random/powercell/device
	name = "random device powercell"
	desc = "This is a random device powercell."
	icon_state = "random_device"

CAPABILITIES(/obj/random/powercell/device)
	configure(loot(table = list(/obj/item/cell/device = 80, /obj/item/cell/device/hyper = 10, /obj/item/cell/device/empproof = 10)))

/obj/random/bomb_supply
	name = "bomb supply"
	desc = "This is a random bomb supply."
	icon_state = "tech"

CAPABILITIES(/obj/random/bomb_supply)
	loot(
		table = list(/obj/item/assembly/igniter, /obj/item/assembly/prox_sensor, /obj/item/assembly/signaler, /obj/item/assembly/timer, /obj/item/multitool))


/obj/random/toolbox
	name = "random toolbox"
	desc = "This is a random toolbox."
	icon_state = "toolbox"

CAPABILITIES(/obj/random/toolbox)
	loot(
		table = list(
			/obj/item/storage/toolbox/mechanical = 6,
			/obj/item/storage/toolbox/electrical = 6,
			/obj/item/storage/toolbox/emergency = 2,
			/obj/item/storage/toolbox/syndicate = 1))

/obj/random/smes_coil
	name = "random smes coil"
	desc = "This is a random smes coil."
	icon_state = "cell_2"

CAPABILITIES(/obj/random/smes_coil)
	loot(table = list(/obj/item/smes_coil = 4, /obj/item/smes_coil/super_capacity = 1, /obj/item/smes_coil/super_io = 1))

/obj/random/pacman
	name = "random portable generator"
	desc = "This is a random portable generator."
	icon_state = "cell_3"

CAPABILITIES(/obj/random/pacman)
	loot(
		table = list(/obj/machinery/power/port_gen/pacman = 6, /obj/machinery/power/port_gen/pacman/super = 3, /obj/machinery/power/port_gen/pacman/mrs = 1))

/obj/random/tech_supply
	name = "random tech supply"
	desc = "This is a random piece of technology supplies."
	icon = 'icons/obj/power_cells.dmi'
	icon_state = "random"

CAPABILITIES(/obj/random/tech_supply)
	loot(
		table = list(
			/obj/random/powercell = 3,
			/obj/random/technology_scanner = 2,
			/obj/item/packageWrap = 1,
			/obj/random/bomb_supply = 2,
			/obj/item/extinguisher = 1,
			/obj/item/clothing/gloves/fyellow = 1,
			/obj/item/stack/cable_coil/random = 3,
			/obj/random/toolbox = 2,
			/obj/item/storage/belt/utility = 2,
			/obj/item/storage/belt/utility/full = 1,
			/obj/random/tool = 5,
			/obj/item/tape_roll = 2,
			/obj/item/taperoll/engineering = 2,
			/obj/item/taperoll/atmos = 1,
			/obj/item/flashlight/maglight = 1),
		chance = 75)

/obj/random/tech_supply/nofail
	name = "guaranteed random tech supply"
CAPABILITIES(/obj/random/tech_supply/nofail)
	configure(loot(chance = 100))

/obj/random/tech_supply/component
	name = "random tech component"
	desc = "This is a random machine component."
	icon_state = "random_device"

CAPABILITIES(/obj/random/tech_supply/component)
	configure(loot(
		table = list(
			/obj/item/stock_parts/gear = 3,
			/obj/item/stock_parts/console_screen = 2,
			/obj/item/stock_parts/spring = 1,
			/obj/item/stock_parts/capacitor = 6,
			/obj/item/stock_parts/manipulator = 6,
			/obj/item/stock_parts/matter_bin = 6,
			/obj/item/stock_parts/scanning_module = 6)))

/obj/random/tech_supply/component/nofail
	name = "guaranteed random tech component"
CAPABILITIES(/obj/random/tech_supply/component/nofail)
	configure(loot(chance = 100))

/obj/random/medical
	name = "Random Medicine"
	desc = "This is a random medical item."
	icon_state = "medical"

CAPABILITIES(/obj/random/medical)
	loot(
		table = list(
			/obj/random/medical/lite = 21,
			/obj/random/medical/pillbottle = 5,
			/obj/item/storage/pill_bottle/tramadol = 1,
			/obj/item/storage/pill_bottle/antitox = 1,
			/obj/item/storage/pill_bottle/carbon = 1,
			/obj/item/bodybag/cryobag = 3,
			/obj/item/reagent_containers/syringe/antitoxin = 5,
			/obj/item/reagent_containers/syringe/antiviral = 3,
			/obj/item/reagent_containers/syringe/inaprovaline = 5,
			/obj/item/reagent_containers/hypospray = 1,
			/obj/item/storage/box/freezer = 1,
			/obj/item/stack/nanopaste = 2))

/obj/random/medical/pillbottle
	name = "Random Pill Bottle"
	desc = "This is a random pill bottle."
	icon_state = "pillbottle"

CAPABILITIES(/obj/random/medical/pillbottle)
	configure(loot(
		table = list(
			/obj/item/storage/pill_bottle/spaceacillin,
			/obj/item/storage/pill_bottle/dermaline,
			/obj/item/storage/pill_bottle/dexalin_plus,
			/obj/item/storage/pill_bottle/bicaridine,
			/obj/item/storage/pill_bottle/blood_regen)))

/obj/random/medical/lite
	name = "Random Medicine"
	desc = "This is a random simple medical item."
	icon_state = "medical"

CAPABILITIES(/obj/random/medical/lite)
	configure(loot(
		table = list(
			/obj/item/stack/medical/bruise_pack = 4,
			/obj/item/stack/medical/ointment = 4,
			/obj/item/stack/medical/advanced/bruise_pack = 2,
			/obj/item/stack/medical/advanced/ointment = 2,
			/obj/item/stack/medical/splint = 1,
			/obj/item/healthanalyzer = 4,
			/obj/item/bodybag = 1,
			/obj/item/reagent_containers/hypospray/autoinjector = 3,
			/obj/item/storage/pill_bottle/kelotane = 2,
			/obj/item/storage/pill_bottle/antitox = 2),
		chance = 75))

/obj/random/firstaid
	name = "Random First Aid Kit"
	desc = "This is a random first aid kit."
	icon_state = "medicalkit"

CAPABILITIES(/obj/random/firstaid)
	loot(
		table = list(
			/obj/item/storage/firstaid/regular = 10,
			/obj/item/storage/firstaid/toxin = 8,
			/obj/item/storage/firstaid/o2 = 8,
			/obj/item/storage/firstaid/adv = 4,
			/obj/item/storage/firstaid/fire = 8,
			/obj/item/denecrotizer/medical = 1,
			/obj/item/storage/firstaid/combat = 1,
			/obj/item/storage/firstaid/experimental = 2))

/obj/random/contraband
	name = "Random Illegal Item"
	desc = "Hot Stuff."
	icon_state = "sus"

CAPABILITIES(/obj/random/contraband)
	loot(
		table = list(
			/obj/item/storage/pill_bottle/paracetamol = 6,
			/obj/item/storage/pill_bottle/happy = 4,
			/obj/item/storage/pill_bottle/zoom = 4,
			/obj/item/material/butterfly = 4,
			/obj/item/material/butterflyblade = 6,
			/obj/item/material/butterflyhandle = 6,
			/obj/item/material/butterfly/switchblade = 2,
			/obj/item/clothing/accessory/knuckledusters = 2,
			/obj/item/material/knife/tacknife = 1,
			/obj/item/clothing/suit/storage/vest/heavy/merc = 1,
			/obj/item/beartrap = 1,
			/obj/item/handcuffs = 1,
			/obj/item/handcuffs/legcuffs = 1,
			/obj/item/lockpick = 1,
			/obj/item/reagent_containers/syringe/drugs = 2,
			/obj/item/reagent_containers/syringe/steroid = 1),
		chance = 50)

/obj/random/contraband/nofail
	name = "Guaranteed Random Illegal Item"
CAPABILITIES(/obj/random/contraband/nofail)
	configure(loot(chance = 100))

/obj/random/cash
	name = "random currency"
	desc = "LOADSAMONEY!"
	icon = 'icons/obj/items.dmi'
	icon_state = "spacecash1"

CAPABILITIES(/obj/random/cash)
	loot(
		table = list(
			/obj/random/maintenance/clean = 320,
			/obj/item/spacecash/c1 = 12,
			/obj/item/spacecash/c5 = 10,
			/obj/item/spacecash/c10 = 8,
			/obj/item/spacecash/c20 = 4,
			/obj/item/spacecash/c50 = 1,
			/obj/item/spacecash/c100 = 1))

/obj/random/cash/big
	name = "random currency pile"
	desc = "DOSH!"
	icon = 'icons/obj/items.dmi'
	icon_state = "spacecash100"

CAPABILITIES(/obj/random/cash/big)
	configure(loot(
		table = list(
			/obj/item/spacecash/c10 = 64,
			/obj/item/spacecash/c20 = 32,
			/obj/item/spacecash/c50 = 16,
			/obj/item/spacecash/c100 = 8,
			/obj/item/spacecash/c200 = 4,
			/obj/item/spacecash/c500 = 2,
			/obj/item/spacecash/c1000 = 1)))

/obj/random/cash/huge
	name = "random huge currency pile"
	desc = "LOOK AT MY WAD!"
	icon = 'icons/obj/items.dmi'
	icon_state = "spacecash1000"

CAPABILITIES(/obj/random/cash/huge)
	configure(loot(table = list(/obj/item/spacecash/c200 = 15, /obj/item/spacecash/c500 = 10, /obj/item/spacecash/c1000 = 5)))

/obj/random/soap
	name = "Random Soap (All)"
	desc = "This is a random bar of soap. Includes special types."
	icon = 'icons/obj/soap.dmi'
	icon_state = "rainbow_soap"

CAPABILITIES(/obj/random/soap)
	loot(
		table = list(
			/obj/item/soap = 1,
			/obj/item/soap/nanotrasen = 1,
			/obj/item/soap/deluxe = 1,
			/obj/item/soap/syndie = 1,
			/obj/item/soap/space_soap = 2,
			/obj/item/soap/water_soap = 1,
			/obj/item/soap/fire_soap = 1,
			/obj/item/soap/rainbow_soap = 1,
			/obj/item/soap/diamond_soap = 1,
			/obj/item/soap/uranium_soap = 1,
			/obj/item/soap/silver_soap = 1,
			/obj/item/soap/brown_soap = 1,
			/obj/item/soap/white_soap = 1,
			/obj/item/soap/grey_soap = 1,
			/obj/item/soap/pink_soap = 1,
			/obj/item/soap/purple_soap = 1,
			/obj/item/soap/blue_soap = 1,
			/obj/item/soap/cyan_soap = 1,
			/obj/item/soap/green_soap = 1,
			/obj/item/soap/yellow_soap = 1,
			/obj/item/soap/orange_soap = 1,
			/obj/item/soap/red_soap = 1,
			/obj/item/soap/golden_soap = 1))

/obj/random/soap_common
	name = "Random Soap (Common)"
	desc = "This is a random bar of soap. Only has the basic types; no NT, deluxe, or syndisoap."
	icon = 'icons/obj/soap.dmi'
	icon_state = "rainbow_soap"

CAPABILITIES(/obj/random/soap_common)
	loot(
		table = list(
			/obj/item/soap = 1,
			/obj/item/soap/space_soap = 2,
			/obj/item/soap/water_soap = 1,
			/obj/item/soap/fire_soap = 1,
			/obj/item/soap/rainbow_soap = 1,
			/obj/item/soap/diamond_soap = 1,
			/obj/item/soap/uranium_soap = 1,
			/obj/item/soap/silver_soap = 1,
			/obj/item/soap/brown_soap = 1,
			/obj/item/soap/white_soap = 1,
			/obj/item/soap/grey_soap = 1,
			/obj/item/soap/pink_soap = 1,
			/obj/item/soap/purple_soap = 1,
			/obj/item/soap/blue_soap = 1,
			/obj/item/soap/cyan_soap = 1,
			/obj/item/soap/green_soap = 1,
			/obj/item/soap/yellow_soap = 1,
			/obj/item/soap/orange_soap = 1,
			/obj/item/soap/red_soap = 1,
			/obj/item/soap/golden_soap = 1))

/obj/random/drinkbottle
	name = "random drink"
	desc = "This is a random drink."
	icon = 'icons/obj/drinks.dmi'
	icon_state = "whiskeybottle1"

CAPABILITIES(/obj/random/drinkbottle)
	loot(
		table = list(
			/obj/item/reagent_containers/food/drinks/bottle/whiskey,
			/obj/item/reagent_containers/food/drinks/bottle/gin,
			/obj/item/reagent_containers/food/drinks/bottle/specialwhiskey,
			/obj/item/reagent_containers/food/drinks/bottle/vodka,
			/obj/item/reagent_containers/food/drinks/bottle/tequila,
			/obj/item/reagent_containers/food/drinks/bottle/absinthe,
			/obj/item/reagent_containers/food/drinks/bottle/wine,
			/obj/item/reagent_containers/food/drinks/bottle/cognac,
			/obj/item/reagent_containers/food/drinks/bottle/rum,
			/obj/item/reagent_containers/food/drinks/bottle/patron,
			/obj/item/reagent_containers/food/drinks/bottle/vermouth,
			/obj/item/reagent_containers/food/drinks/bottle/goldschlager,
			/obj/item/reagent_containers/food/drinks/bottle/kahlua,
			/obj/item/reagent_containers/food/drinks/bottle/melonliquor,
			/obj/item/reagent_containers/food/drinks/bottle/bluecuracao,
			/obj/item/reagent_containers/food/drinks/bottle/grenadine,
			/obj/item/reagent_containers/food/drinks/bottle/sake,
			/obj/item/reagent_containers/food/drinks/bottle/champagne,
			/obj/item/reagent_containers/food/drinks/bottle/peppermintschnapps,
			/obj/item/reagent_containers/food/drinks/bottle/peachschnapps,
			/obj/item/reagent_containers/food/drinks/bottle/lemonadeschnapps,
			/obj/item/reagent_containers/food/drinks/bottle/jager,
			/obj/item/reagent_containers/food/drinks/bottle/small/cider,
			/obj/item/reagent_containers/food/drinks/bottle/small/litebeer,
			/obj/item/reagent_containers/food/drinks/bottle/small/beer,
			/obj/item/reagent_containers/food/drinks/bottle/small/beer/silverdragon,
			/obj/item/reagent_containers/food/drinks/bottle/small/beer/meteor))

/obj/random/drinksoft
	name = "random soft drink"
	desc = "This is a random (once) carbonated beverage drinks can."
	icon = 'icons/obj/drinks.dmi'
	icon_state = "cola"

CAPABILITIES(/obj/random/drinksoft)
	loot(
		table = list(
			/obj/item/reagent_containers/food/drinks/cans/cola,
			/obj/item/reagent_containers/food/drinks/cans/waterbottle,
			/obj/item/reagent_containers/food/drinks/cans/space_mountain_wind,
			/obj/item/reagent_containers/food/drinks/cans/thirteenloko,
			/obj/item/reagent_containers/food/drinks/cans/dr_gibb,
			/obj/item/reagent_containers/food/drinks/cans/dr_gibb_diet,
			/obj/item/reagent_containers/food/drinks/cans/starkist,
			/obj/item/reagent_containers/food/drinks/cans/space_up,
			/obj/item/reagent_containers/food/drinks/cans/lemon_lime,
			/obj/item/reagent_containers/food/drinks/cans/iced_tea,
			/obj/item/reagent_containers/food/drinks/cans/grape_juice,
			/obj/item/reagent_containers/food/drinks/cans/tonic,
			/obj/item/reagent_containers/food/drinks/cans/sodawater,
			/obj/item/reagent_containers/food/drinks/cans/gingerale,
			/obj/item/reagent_containers/food/drinks/cans/root_beer))


/obj/random/snack
	name = "random snack"
	desc = "This is a random snackfood. Probably still safe to eat?"
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "tastybread"

CAPABILITIES(/obj/random/snack)
	loot(
		table = list(
			/obj/item/reagent_containers/food/snacks/candy,
			/obj/item/reagent_containers/food/snacks/candy/proteinbar,
			/obj/item/reagent_containers/food/snacks/candy/gummy,
			/obj/item/reagent_containers/food/snacks/candy/donor,
			/obj/item/reagent_containers/food/snacks/candy_corn,
			/obj/item/reagent_containers/food/snacks/chips,
			/obj/item/reagent_containers/food/snacks/chips/bbq,
			/obj/item/reagent_containers/food/snacks/cookiesnack,
			/obj/item/reagent_containers/food/snacks/fruitbar,
			/obj/item/reagent_containers/food/snacks/chocolatebar,
			/obj/item/reagent_containers/food/snacks/chocolatepiece,
			/obj/item/reagent_containers/food/snacks/chocolatepiece/white,
			/obj/item/reagent_containers/food/snacks/chocolatepiece/truffle,
			/obj/item/reagent_containers/food/snacks/chocolateegg,
			/obj/item/reagent_containers/food/snacks/donut/plain,
			/obj/item/reagent_containers/food/snacks/donut/plain/jelly,
			/obj/item/reagent_containers/food/snacks/donut/pink,
			/obj/item/reagent_containers/food/snacks/donut/pink/jelly,
			/obj/item/reagent_containers/food/snacks/donut/purple,
			/obj/item/reagent_containers/food/snacks/donut/purple/jelly,
			/obj/item/reagent_containers/food/snacks/donut/green,
			/obj/item/reagent_containers/food/snacks/donut/green/jelly,
			/obj/item/reagent_containers/food/snacks/donut/beige,
			/obj/item/reagent_containers/food/snacks/donut/beige/jelly,
			/obj/item/reagent_containers/food/snacks/donut/choc,
			/obj/item/reagent_containers/food/snacks/donut/choc/jelly,
			/obj/item/reagent_containers/food/snacks/donut/blue,
			/obj/item/reagent_containers/food/snacks/donut/blue/jelly,
			/obj/item/reagent_containers/food/snacks/donut/yellow,
			/obj/item/reagent_containers/food/snacks/donut/yellow/jelly,
			/obj/item/reagent_containers/food/snacks/donut/olive,
			/obj/item/reagent_containers/food/snacks/donut/olive/jelly,
			/obj/item/reagent_containers/food/snacks/donut/homer,
			/obj/item/reagent_containers/food/snacks/donut/homer/jelly,
			/obj/item/reagent_containers/food/snacks/donut/choc_sprinkles,
			/obj/item/reagent_containers/food/snacks/donut/choc_sprinkles/jelly,
			/obj/item/reagent_containers/food/snacks/tuna,
			/obj/item/reagent_containers/food/snacks/pistachios,
			/obj/item/reagent_containers/food/snacks/semki,
			/obj/item/reagent_containers/food/snacks/cb01,
			/obj/item/reagent_containers/food/snacks/cb02,
			/obj/item/reagent_containers/food/snacks/cb03,
			/obj/item/reagent_containers/food/snacks/cb04,
			/obj/item/reagent_containers/food/snacks/cb05,
			/obj/item/reagent_containers/food/snacks/cb06,
			/obj/item/reagent_containers/food/snacks/cb07,
			/obj/item/reagent_containers/food/snacks/cb08,
			/obj/item/reagent_containers/food/snacks/cb09,
			/obj/item/reagent_containers/food/snacks/cb10,
			/obj/item/reagent_containers/food/snacks/tofu,
			/obj/item/reagent_containers/food/snacks/donkpocket,
			/obj/item/reagent_containers/food/snacks/muffin,
			/obj/item/reagent_containers/food/snacks/soylentgreen,
			/obj/item/reagent_containers/food/snacks/soylenviridians,
			/obj/item/reagent_containers/food/snacks/popcorn,
			/obj/item/reagent_containers/food/snacks/sosjerky,
			/obj/item/reagent_containers/food/snacks/no_raisin,
			/obj/item/reagent_containers/food/snacks/packaged/spacetwinkie,
			/obj/item/reagent_containers/food/snacks/cheesiehonkers,
			/obj/item/reagent_containers/food/snacks/poppypretzel,
			/obj/item/reagent_containers/food/snacks/baguette,
			/obj/item/reagent_containers/food/snacks/carrotfries,
			/obj/item/reagent_containers/food/snacks/candiedapple,
			/obj/item/storage/box/admints,
			/obj/item/reagent_containers/food/snacks/tastybread,
			/obj/item/reagent_containers/food/snacks/liquidfood,
			/obj/item/reagent_containers/food/snacks/liquidprotein,
			/obj/item/reagent_containers/food/snacks/liquidvitamin,
			/obj/item/reagent_containers/food/snacks/skrellsnacks,
			/obj/item/reagent_containers/food/snacks/unajerky,
			/obj/item/reagent_containers/food/snacks/croissant,
			/obj/item/reagent_containers/food/snacks/sugarcookie,
			/obj/item/reagent_containers/food/drinks/dry_ramen))

/obj/random/meat
	name = "random meat"
	desc = "This is a random slab of meat."
	icon = 'icons/obj/food.dmi'
	icon_state = "meat"

CAPABILITIES(/obj/random/meat)
	loot(
		table = list(
			/obj/item/reagent_containers/food/snacks/meat = 60,
			/obj/item/reagent_containers/food/snacks/xenomeat/spidermeat = 20,
			/obj/item/reagent_containers/food/snacks/carpmeat = 10,
			/obj/item/reagent_containers/food/snacks/bearmeat = 5,
			/obj/item/reagent_containers/food/snacks/meat/syntiflesh = 1,
			/obj/item/reagent_containers/food/snacks/meat/human = 1,
			/obj/item/reagent_containers/food/snacks/meat/monkey = 1,
			/obj/item/reagent_containers/food/snacks/meat/corgi = 1,
			/obj/item/reagent_containers/food/snacks/xenomeat = 1))

/obj/random/pizzabox
	name = "random pizza box"
	desc = "This is a random pizza box."
	icon = 'icons/obj/food.dmi'
	icon_state = "pizzabox1"

CAPABILITIES(/obj/random/pizzabox)
	loot(
		table = list(
			/obj/item/pizzabox/margherita,
			/obj/item/pizzabox/mushroom,
			/obj/item/pizzabox/meat,
			/obj/item/pizzabox/vegetable,
			/obj/item/pizzabox/pineapple))

/obj/random/pizzabox/supplypack
	drop_get_turf = FALSE

/obj/random/material //Random materials for building stuff
	name = "random material"
	desc = "This is a random material."
	icon_state = "material"

CAPABILITIES(/obj/random/material)
	loot(
		table = list(
			loot_stack(1, /obj/item/stack/material/steel, 10),
			loot_stack(1, /obj/item/stack/material/glass, 10),
			loot_stack(1, /obj/item/stack/material/glass/reinforced, 10),
			loot_stack(1, /obj/item/stack/material/plastic, 10),
			loot_stack(1, /obj/item/stack/material/wood, 10),
			loot_stack(1, /obj/item/stack/material/wood/sif, 10),
			loot_stack(1, /obj/item/stack/material/cardboard, 10),
			loot_stack(1, /obj/item/stack/rods, 10),
			loot_stack(1, /obj/item/stack/material/sandstone, 10),
			loot_stack(1, /obj/item/stack/material/marble, 10),
			loot_stack(1, /obj/item/stack/material/plasteel, 10)))

/obj/random/material/refined //Random materials for building stuff
	name = "random refined material"
	desc = "This is a random refined metal."
	icon_state = "material_2"

CAPABILITIES(/obj/random/material/refined)
	configure(loot(
		table = list(
			loot_stack(1, /obj/item/stack/material/steel, 10),
			loot_stack(1, /obj/item/stack/material/glass, 10),
			loot_stack(1, /obj/item/stack/material/glass/reinforced, 5),
			loot_stack(1, /obj/item/stack/material/glass/phoronglass, 5),
			loot_stack(1, /obj/item/stack/material/glass/phoronrglass, 5),
			loot_stack(1, /obj/item/stack/material/plasteel, 5),
			loot_stack(1, /obj/item/stack/material/durasteel, 5),
			loot_stack(1, /obj/item/stack/material/gold, 5),
			loot_stack(1, /obj/item/stack/material/iron, 10),
			loot_stack(1, /obj/item/stack/material/copper, 10),
			loot_stack(1, /obj/item/stack/material/aluminium, 10),
			loot_stack(1, /obj/item/stack/material/lead, 10),
			loot_stack(1, /obj/item/stack/material/diamond, 3),
			loot_stack(1, /obj/item/stack/material/deuterium, 5),
			loot_stack(1, /obj/item/stack/material/uranium, 5),
			loot_stack(1, /obj/item/stack/material/phoron, 5),
			loot_stack(1, /obj/item/stack/material/silver, 5),
			loot_stack(1, /obj/item/stack/material/platinum, 5),
			loot_stack(1, /obj/item/stack/material/mhydrogen, 3),
			loot_stack(1, /obj/item/stack/material/osmium, 3),
			loot_stack(1, /obj/item/stack/material/titanium, 5),
			loot_stack(1, /obj/item/stack/material/tritium, 3),
			loot_stack(1, /obj/item/stack/material/verdantium, 2))))

/obj/random/material/precious //Precious metals, go figure
	name = "random precious metal"
	desc = "This is a small stack of a random precious metal."
	icon_state = "material_3"

CAPABILITIES(/obj/random/material/precious)
	configure(loot(
		table = list(
			loot_stack(1, /obj/item/stack/material/gold, 5),
			loot_stack(1, /obj/item/stack/material/copper, 5),
			loot_stack(1, /obj/item/stack/material/silver, 5),
			loot_stack(1, /obj/item/stack/material/platinum, 5),
			loot_stack(1, /obj/item/stack/material/osmium, 5))))

/obj/random/tank
	name = "random tank"
	desc = "This is a tank."
	icon = 'icons/obj/tank.dmi'
	icon_state = "canister"

CAPABILITIES(/obj/random/tank)
	loot(
		table = list(
			/obj/item/tank/oxygen = 5,
			/obj/item/tank/oxygen/yellow = 4,
			/obj/item/tank/oxygen/red = 4,
			/obj/item/tank/air = 3,
			/obj/item/tank/emergency/oxygen = 4,
			/obj/item/tank/emergency/oxygen/engi = 3,
			/obj/item/tank/emergency/oxygen/double = 2,
			/obj/item/suit_cooling_unit = 1))

/obj/random/cigarettes
	name = "random cigarettes"
	desc = "This is a cigarette."
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "cigpacket"

CAPABILITIES(/obj/random/cigarettes)
	loot(
		table = list(
			/obj/item/storage/fancy/cigarettes = 5,
			/obj/item/storage/fancy/cigarettes/dromedaryco = 4,
			/obj/item/storage/fancy/cigarettes/killthroat = 3,
			/obj/item/storage/fancy/cigarettes/luckystars = 3,
			/obj/item/storage/fancy/cigarettes/jerichos = 3,
			/obj/item/storage/fancy/cigarettes/menthols = 3,
			/obj/item/storage/fancy/cigarettes/carcinomas = 3,
			/obj/item/storage/fancy/cigarettes/professionals = 3,
			/obj/item/storage/fancy/cigar = 1,
			/obj/item/clothing/mask/smokable/cigarette/cigar = 1,
			/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba = 1,
			/obj/item/clothing/mask/smokable/cigarette/cigar/havana = 1))

/obj/random/coin
	name = "random coin"
	desc = "This is a coin spawn."
	icon = 'icons/misc/mark.dmi'
	icon_state = "rup"

CAPABILITIES(/obj/random/coin)
	loot(
		table = list(
			/obj/item/coin/copper = 7,
			/obj/item/coin/silver = 5,
			/obj/item/coin/steel = 5,
			/obj/item/coin/iron = 3,
			/obj/item/coin/gold = 4,
			/obj/item/coin/titanium = 3,
			/obj/item/coin/phoron = 3,
			/obj/item/coin/uranium = 1,
			/obj/item/coin/platinum = 2,
			/obj/item/coin/lead = 2,
			/obj/item/coin/diamond = 1))

/obj/random/coin/sometimes
CAPABILITIES(/obj/random/coin/sometimes)
	configure(loot(chance = 34))


/obj/random/action_figure
	name = "random action figure"
	desc = "This is a random action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "assistant"

CAPABILITIES(/obj/random/action_figure)
	loot(
		table = list(
			/obj/item/toy/figure/cmo,
			/obj/item/toy/figure/assistant,
			/obj/item/toy/figure/atmos,
			/obj/item/toy/figure/bartender,
			/obj/item/toy/figure/borg,
			/obj/item/toy/figure/gardener,
			/obj/item/toy/figure/captain,
			/obj/item/toy/figure/cargotech,
			/obj/item/toy/figure/ce,
			/obj/item/toy/figure/chaplain,
			/obj/item/toy/figure/chef,
			/obj/item/toy/figure/chemist,
			/obj/item/toy/figure/clown,
			/obj/item/toy/figure/corgi,
			/obj/item/toy/figure/detective,
			/obj/item/toy/figure/dsquad,
			/obj/item/toy/figure/engineer,
			/obj/item/toy/figure/geneticist,
			/obj/item/toy/figure/hop,
			/obj/item/toy/figure/hos,
			/obj/item/toy/figure/qm,
			/obj/item/toy/figure/janitor,
			/obj/item/toy/figure/agent,
			/obj/item/toy/figure/librarian,
			/obj/item/toy/figure/md,
			/obj/item/toy/figure/mime,
			/obj/item/toy/figure/miner,
			/obj/item/toy/figure/ninja,
			/obj/item/toy/figure/wizard,
			/obj/item/toy/figure/rd,
			/obj/item/toy/figure/roboticist,
			/obj/item/toy/figure/scientist,
			/obj/item/toy/figure/syndie,
			/obj/item/toy/figure/secofficer,
			/obj/item/toy/figure/warden,
			/obj/item/toy/figure/psychologist,
			/obj/item/toy/figure/paramedic,
			/obj/item/toy/figure/ert,
			/obj/item/toy/figure/station,
			/obj/item/toy/sif))


/obj/random/plushie
	name = "random plushie"
	desc = "This is a random plushie."
	icon = 'icons/obj/toy.dmi'
	icon_state = "nymphplushie"

CAPABILITIES(/obj/random/plushie)
	loot(
		table = list(
			/obj/item/toy/plushie/nymph,
			/obj/item/toy/plushie/mouse,
			/obj/item/toy/plushie/kitten,
			/obj/item/toy/plushie/lizard,
			/obj/item/toy/plushie/black_cat,
			/obj/item/toy/plushie/black_fox,
			/obj/item/toy/plushie/blue_fox,
			/obj/random/carp_plushie,
			/obj/item/toy/plushie/coffee_fox,
			/obj/item/toy/plushie/corgi,
			/obj/item/toy/plushie/crimson_fox,
			/obj/item/toy/plushie/deer,
			/obj/item/toy/plushie/girly_corgi,
			/obj/item/toy/plushie/grey_cat,
			/obj/item/toy/plushie/marble_fox,
			/obj/item/toy/plushie/octopus,
			/obj/item/toy/plushie/orange_cat,
			/obj/item/toy/plushie/orange_fox,
			/obj/item/toy/plushie/pink_fox,
			/obj/item/toy/plushie/purple_fox,
			/obj/item/toy/plushie/red_fox,
			/obj/item/toy/plushie/robo_corgi,
			/obj/item/toy/plushie/siamese_cat,
			/obj/item/toy/plushie/spider,
			/obj/item/toy/plushie/tabby_cat,
			/obj/item/toy/plushie/tuxedo_cat,
			/obj/item/toy/plushie/white_cat,
			/obj/item/toy/plushie/lizardplushie,
			/obj/item/toy/plushie/lizardplushie/kobold,
			/obj/item/toy/plushie/slimeplushie,
			/obj/item/toy/plushie/box,
			/obj/item/toy/plushie/borgplushie,
			/obj/item/toy/plushie/borgplushie/medihound,
			/obj/item/toy/plushie/borgplushie/scrubpuppy,
			/obj/item/toy/plushie/foxbear,
			/obj/item/toy/plushie/nukeplushie,
			/obj/item/toy/plushie/otter,
			/obj/item/toy/plushie/vox,
			/obj/item/toy/plushie/shark,
			/obj/item/toy/plushie/tinytin,
			/obj/item/toy/plushie/tinytin_sec,
			loot_sub(1, list(/obj/item/toy/plushie/borgplushie/drake/sec, /obj/item/toy/plushie/borgplushie/drake/med, /obj/item/toy/plushie/borgplushie/drake/sci, /obj/item/toy/plushie/borgplushie/drake/jani, /obj/item/toy/plushie/borgplushie/drake/eng, /obj/item/toy/plushie/borgplushie/drake/mine, /obj/item/toy/plushie/borgplushie/drake/trauma)),
			/obj/item/toy/plushie/teshari/_yw,
			/obj/item/toy/plushie/teshari/w_yw,
			/obj/item/toy/plushie/teshari/b_yw,
			/obj/item/toy/plushie/teshari/y_yw,
			/obj/item/toy/plushie/teppi,
			/obj/item/toy/plushie/teppi/alt,
			loot_sub(1, list(/obj/item/toy/plushie/dragon, /obj/item/toy/plushie/dragon/green, /obj/item/toy/plushie/dragon/purple, /obj/item/toy/plushie/dragon/red_east, /obj/item/toy/plushie/dragon/green_east, /obj/item/toy/plushie/dragon/white_east, /obj/item/toy/plushie/dragon/gold_east))))

/obj/random/plushielarge
	name = "random large plushie"
	desc = "This is a randomn large plushie."
	icon = 'icons/obj/toy.dmi'
	icon_state = "droneplushie"

CAPABILITIES(/obj/random/plushielarge)
	loot(table = list(/obj/structure/plushie/ian, /obj/structure/plushie/drone, /obj/structure/plushie/carp, /obj/structure/plushie/beepsky))

/obj/random/toy
	name = "random toy"
	desc = "This is a random toy."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ship"

CAPABILITIES(/obj/random/toy)
	loot(
		table = list(
			/obj/item/toy/bosunwhistle,
			/obj/item/toy/plushie/therapy,
			/obj/item/toy/plushie/therapy/purple,
			/obj/item/toy/plushie/therapy/blue,
			/obj/item/toy/plushie/therapy/yellow,
			/obj/item/toy/plushie/therapy/orange,
			/obj/item/toy/plushie/therapy/green,
			/obj/item/toy/cultsword,
			/obj/item/toy/katana,
			/obj/item/toy/snappop,
			/obj/item/toy/sword,
			/obj/item/toy/balloon,
			/obj/item/gun/projectile/revolver/toy/crossbow,
			/obj/item/toy/blink,
			/obj/item/reagent_containers/spray/waterflower,
			/obj/item/toy/eight_ball,
			/obj/item/toy/eight_ball/conch,
			/obj/item/toy/mecha/ripley,
			/obj/item/toy/mecha/fireripley,
			/obj/item/toy/mecha/deathripley,
			/obj/item/toy/mecha/gygax,
			/obj/item/toy/mecha/durand,
			/obj/item/toy/mecha/honk,
			/obj/item/toy/mecha/marauder,
			/obj/item/toy/mecha/seraph,
			/obj/item/toy/mecha/mauler,
			/obj/item/toy/mecha/odysseus,
			/obj/item/toy/mecha/phazon,
			/obj/item/toy/monster_bait))

/obj/random/mouseremains
	name = "random mouseremains"
	desc = "For use with mouse spawners."
	icon = 'icons/obj/assemblies/new_assemblies.dmi'
	icon_state = "mousetrap"

CAPABILITIES(/obj/random/mouseremains)
	loot(
		table = list(
			/obj/item/assembly/mousetrap,
			/obj/item/assembly/mousetrap/armed,
			/obj/effect/decal/cleanable/bug_remains,
			/obj/effect/decal/cleanable/ash,
			/obj/item/trash/cigbutt,
			/obj/item/trash/cigbutt/cigarbutt,
			/obj/effect/decal/remains/mouse))

/obj/random/janusmodule
	name = "random janus circuit"
	desc = "A random (possibly broken) Janus module."
	icon_state = "tech_2"

CAPABILITIES(/obj/random/janusmodule)
	loot(table = list(loot_types(1, subtypesof(/obj/item/circuitboard/mecha/imperion))))

/obj/random/curseditem
	name = "random cursed item"
	desc = "For use in dungeons."
	icon = 'icons/obj/storage.dmi'
	icon_state = "red"

CAPABILITIES(/obj/random/curseditem)
	loot(table = list(/obj/item/paper/carbon/cursedform, loot_types(1, subtypesof(/obj/item/clothing/head/psy_crown))))

//Random MRE stuff

/obj/random/mre
	name = "random MRE"
	desc = "This is a random single MRE."
	icon = 'icons/obj/food.dmi'
	icon_state = "mre"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre)
	loot(
		table = list(
			/obj/item/storage/mre,
			/obj/item/storage/mre/menu2,
			/obj/item/storage/mre/menu3,
			/obj/item/storage/mre/menu4,
			/obj/item/storage/mre/menu5,
			/obj/item/storage/mre/menu6,
			/obj/item/storage/mre/menu7,
			/obj/item/storage/mre/menu8,
			/obj/item/storage/mre/menu9,
			/obj/item/storage/mre/menu10))


/obj/random/mre/main
	name = "random MRE main course"
	desc = "This is a random main course for MREs."
	icon_state = "pouch"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre/main)
	configure(loot(
		table = list(
			/obj/item/storage/mrebag,
			/obj/item/storage/mrebag/menu2,
			/obj/item/storage/mrebag/menu3,
			/obj/item/storage/mrebag/menu4,
			/obj/item/storage/mrebag/menu5,
			/obj/item/storage/mrebag/menu6,
			/obj/item/storage/mrebag/menu7,
			/obj/item/storage/mrebag/menu8)))

/obj/random/mre/side
	name = "random MRE side dish"
	desc = "This is a random side dish for MREs."
	icon_state = "pouch"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre/side)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/snacks/tossedsalad,
			/obj/item/reagent_containers/food/snacks/boiledrice,
			/obj/item/reagent_containers/food/snacks/poppypretzel,
			/obj/item/reagent_containers/food/snacks/twobread,
			/obj/item/reagent_containers/food/snacks/jelliedtoast)))

/obj/random/mre/dessert
	name = "random MRE dessert"
	desc = "This is a random dessert for MREs."
	icon_state = "pouch"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre/dessert)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/snacks/candy,
			/obj/item/reagent_containers/food/snacks/candy/proteinbar,
			/obj/item/reagent_containers/food/snacks/donut/plain,
			/obj/item/reagent_containers/food/snacks/donut/plain/jelly,
			/obj/item/reagent_containers/food/snacks/chocolatebar,
			/obj/item/reagent_containers/food/snacks/cookie)))

/obj/random/mre/dessert/vegan
	name = "random vegan MRE dessert"
	desc = "This is a random vegan dessert for MREs."

CAPABILITIES(/obj/random/mre/dessert/vegan)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/snacks/candy,
			/obj/item/reagent_containers/food/snacks/chocolatebar,
			/obj/item/reagent_containers/food/snacks/donut/plain/jelly,
			/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit)))

/obj/random/mre/drink
	name = "random MRE drink"
	desc = "This is a random drink for MREs."
	icon_state = "packet"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre/drink)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/condiment/small/packet/coffee,
			/obj/item/reagent_containers/food/condiment/small/packet/tea,
			/obj/item/reagent_containers/food/condiment/small/packet/cocoa,
			/obj/item/reagent_containers/food/condiment/small/packet/grape,
			/obj/item/reagent_containers/food/condiment/small/packet/orange,
			/obj/item/reagent_containers/food/condiment/small/packet/watermelon,
			/obj/item/reagent_containers/food/condiment/small/packet/apple)))

/obj/random/mre/spread
	name = "random MRE spread"
	desc = "This is a random spread packet for MREs."
	icon_state = "packet"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre/spread)
	configure(loot(
		table = list(/obj/item/reagent_containers/food/condiment/small/packet/jelly, /obj/item/reagent_containers/food/condiment/small/packet/honey)))

/obj/random/mre/spread/vegan
	name = "random vegan MRE spread"
	desc = "This is a random vegan spread packet for MREs"

CAPABILITIES(/obj/random/mre/spread/vegan)
	configure(loot(table = list(/obj/item/reagent_containers/food/condiment/small/packet/jelly)))

/obj/random/mre/sauce
	name = "random MRE sauce"
	desc = "This is a random sauce packet for MREs."
	icon_state = "packet"
	drop_get_turf = FALSE

CAPABILITIES(/obj/random/mre/sauce)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/condiment/small/packet/salt,
			/obj/item/reagent_containers/food/condiment/small/packet/pepper,
			/obj/item/reagent_containers/food/condiment/small/packet/sugar,
			/obj/item/reagent_containers/food/condiment/small/packet/capsaicin,
			/obj/item/reagent_containers/food/condiment/small/packet/ketchup,
			/obj/item/reagent_containers/food/condiment/small/packet/mayo,
			/obj/item/reagent_containers/food/condiment/small/packet/soy)))

/obj/random/mre/sauce/vegan
CAPABILITIES(/obj/random/mre/sauce/vegan)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/condiment/small/packet/salt,
			/obj/item/reagent_containers/food/condiment/small/packet/pepper,
			/obj/item/reagent_containers/food/condiment/small/packet/sugar,
			/obj/item/reagent_containers/food/condiment/small/packet/soy)))

/obj/random/mre/sauce/sugarfree
CAPABILITIES(/obj/random/mre/sauce/sugarfree)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/condiment/small/packet/salt,
			/obj/item/reagent_containers/food/condiment/small/packet/pepper,
			/obj/item/reagent_containers/food/condiment/small/packet/capsaicin,
			/obj/item/reagent_containers/food/condiment/small/packet/ketchup,
			/obj/item/reagent_containers/food/condiment/small/packet/mayo,
			/obj/item/reagent_containers/food/condiment/small/packet/soy)))

/obj/random/mre/sauce/crayon
CAPABILITIES(/obj/random/mre/sauce/crayon)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/generic,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/red,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/orange,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/yellow,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/green,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/blue,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/purple,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/grey,
			/obj/item/reagent_containers/food/condiment/small/packet/crayon/brown)))

/obj/random/thermalponcho
	name = "random thermal poncho"
	desc = "This is a thermal poncho spawn."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "classicponcho"

CAPABILITIES(/obj/random/thermalponcho)
	loot(
		table = list(
			/obj/item/clothing/accessory/poncho/thermal = 5,
			/obj/item/clothing/accessory/poncho/thermal/red = 3,
			/obj/item/clothing/accessory/poncho/thermal/green = 3,
			/obj/item/clothing/accessory/poncho/thermal/purple = 3,
			/obj/item/clothing/accessory/poncho/thermal/blue = 3))

/obj/random/pouch
	name = "Random Storage Pouch"
	desc = "This is a random storage pouch."
	icon = 'icons/inventory/pockets/item.dmi'
	icon_state = "random"

CAPABILITIES(/obj/random/pouch)
	loot(
		table = list(
			/obj/item/storage/pouch = 10,
			/obj/item/storage/pouch/large = 3,
			/obj/item/storage/pouch/small = 8,
			/obj/item/storage/pouch/ammo = 5,
			/obj/item/storage/pouch/eng_tool = 5,
			/obj/item/storage/pouch/eng_supply = 5,
			/obj/item/storage/pouch/eng_parts = 5,
			/obj/item/storage/pouch/medical = 5,
			/obj/item/storage/pouch/flares/full_flare = 5,
			/obj/item/storage/pouch/flares/full_glow = 5,
			/obj/item/storage/pouch/holster = 5,
			/obj/item/storage/pouch/baton/full = 5,
			/obj/item/storage/pouch/holding = 1))

/obj/random/flashlight
	name = "Random Flashlight"
	desc = "This is a random storage pouch."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "random_flashlight"

CAPABILITIES(/obj/random/flashlight)
	loot(
		table = list(
			/obj/item/flashlight = 8,
			/obj/item/flashlight/color = 6,
			/obj/item/flashlight/color/green = 6,
			/obj/item/flashlight/color/purple = 6,
			/obj/item/flashlight/color/red = 6,
			/obj/item/flashlight/color/orange = 6,
			/obj/item/flashlight/color/yellow = 6,
			/obj/item/flashlight/maglight = 2))

/obj/random/mug
	name = "Random Mug"
	desc = "This is a random coffee mug."
	icon = 'icons/obj/drinks_mugs.dmi'
	icon_state = "coffeecup_spawner"

CAPABILITIES(/obj/random/mug)
	loot(
		table = list(
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/sol,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/fleet,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/fivearrows,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/psc,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/alma,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/almp,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/nt,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/metal/wulf,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/gilthari,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/zeng,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/wt,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/aether,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/bishop,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/oculum,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/one,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/puni,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/heart,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/pawn,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/diona,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/britcup,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/flame,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/blue,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/black,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/green,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/green/dark,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/rainbow,
			/obj/item/reagent_containers/food/drinks/glass2/coffeemug/metal))

/obj/random/donkpocketbox
	name = "Random Donk-pocket Box"
	desc = "This is a random Donk-pocket Box."
	icon = 'icons/obj/boxes.dmi'
	icon_state = "donkpocket_spawner"

CAPABILITIES(/obj/random/donkpocketbox)
	loot(
		table = list(
			/obj/item/storage/box/donkpockets,
			/obj/item/storage/box/donkpockets/spicy,
			/obj/item/storage/box/donkpockets/teriyaki,
			/obj/item/storage/box/donkpockets/pizza,
			/obj/item/storage/box/donkpockets/honk,
			/obj/item/storage/box/donkpockets/gondola,
			/obj/item/storage/box/donkpockets/berry))

/obj/random/bluespace
	name = "Random Bluespace Item"
	desc = "This is a random Bluespace item."
	icon_state = "bluespace"

CAPABILITIES(/obj/random/bluespace)
	loot(
		table = list(
			/obj/item/gun/energy/sizegun = 20,
			/obj/item/slow_sizegun = 20,
			/obj/item/clothing/accessory/collar/shock/bluespace = 20,
			/obj/item/reagent_containers/glass/beaker/bluespace = 4,
			/obj/item/bodysnatcher = 4,
			/obj/item/clothing/under/hyperfiber = 10,
			/obj/item/clothing/under/hyperfiber/bluespace = 10,
			/obj/item/implant/sizecontrol = 20,
			/obj/item/ore_bag/holding = 2,
			/obj/item/storage/bag/sheetsnatcher/holding = 2,
			/obj/item/storage/backpack/holding = 2,
			/obj/item/storage/backpack/holding/duffle = 2,
			/obj/item/storage/bag/trash/holding = 2,
			/obj/item/storage/pouch/holding = 2,
			/obj/item/storage/belt/medical/holding = 2,
			/obj/item/storage/belt/utility/holding = 2,
			/obj/item/perfect_tele = 2,
			/obj/item/capture_crystal/random = 8,
			/obj/item/bluespace_harpoon = 10,
			/obj/item/bluespace_crystal = 10,
			/obj/item/clothing/glasses/graviton = 1,
			/obj/item/cracker = 10,
			/obj/item/cracker/shrinking = 1,
			/obj/item/cracker/growing = 1,
			/obj/item/cracker/invisibility = 1,
			/obj/item/cracker/drugged = 1,
			/obj/item/cracker/knockover = 1,
			/obj/item/cracker/vore = 1,
			/obj/item/cracker/money = 1))

/obj/random/translator
	name = "Random language translator"
	desc = "This is a random single language translator."
	icon = 'icons/obj/device.dmi'
	icon_state = "translator_small"

CAPABILITIES(/obj/random/translator)
	loot(
		table = list(
			/obj/item/universal_translator/limited,
			/obj/item/universal_translator/limited/sol,
			/obj/item/universal_translator/limited/terminus,
			/obj/item/universal_translator/limited/tradeband,
			/obj/item/universal_translator/limited/gutterband,
			/obj/item/universal_translator/limited/skrellian,
			/obj/item/universal_translator/limited/unathi,
			/obj/item/universal_translator/limited/siik,
			/obj/item/universal_translator/limited/schechi,
			/obj/item/universal_translator/limited/vedaqh,
			/obj/item/universal_translator/limited/birdsong,
			/obj/item/universal_translator/limited/sagaru,
			/obj/item/universal_translator/limited/canilunzt,
			/obj/item/universal_translator/limited/ecureuilian,
			/obj/item/universal_translator/limited/daemon,
			/obj/item/universal_translator/limited/enochian,
			/obj/item/universal_translator/limited/vespinae,
			/obj/item/universal_translator/limited/dragon,
			/obj/item/universal_translator/limited/spacer,
			/obj/item/universal_translator/limited/tavan,
			/obj/item/universal_translator/limited/echosong,
			/obj/item/universal_translator/limited/akhani,
			/obj/item/universal_translator/limited/alai))

/obj/random/anomaly_core
	name = "Random anomaly core"
	desc = "This is a random single anomaly core."
	icon = 'icons/obj/devices/tool.dmi'
	icon_state = "neutralyzer"

CAPABILITIES(/obj/random/anomaly_core)
	loot(table = list(loot_types(1, subtypesof(/obj/item/assembly/signaler/anomaly))))


//This file is for VR only

/obj/random/explorer_shield
	name = "random explorer shield"
	desc = "This is a random shield for the explorer lockers."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "explorer_shield"

CAPABILITIES(/obj/random/explorer_shield)
	loot(table = list(/obj/item/shield/riot/explorer, /obj/item/shield/riot/explorer/purple))

/obj/random/awayloot
	name = "random away mission loot"
	desc = "A list of things that people can find in away missions."
	icon = 'icons/mob/randomlandmarks.dmi'
	icon_state = "awayloot"

CAPABILITIES(/obj/random/awayloot)
	loot(
		table = list(
			/obj/item/aliencoin/basic = 50,
			/obj/item/aliencoin/silver = 40,
			/obj/item/aliencoin/gold = 30,
			/obj/item/aliencoin/phoron = 20,
			/obj/item/denecrotizer = 10,
			/obj/item/capture_crystal = 5,
			/obj/item/perfect_tele = 5,
			/obj/item/bluespace_harpoon = 5,
			/obj/item/cell/infinite = 1,
			/obj/item/cell/void = 1,
			/obj/item/cell/device/weapon/recharge/alien = 1,
			/obj/item/clothing/shoes/boots/speed = 1,
			/obj/item/nif = 1,
			/obj/item/paicard = 1,
			/obj/item/storage/backpack/dufflebag/syndie = 2,
			/obj/item/storage/backpack/dufflebag/syndie/ammo = 2,
			/obj/item/storage/backpack/dufflebag/syndie/med = 2,
			/obj/item/clothing/mask/gas/voice = 2,
			/obj/item/radio_jammer = 2,
			/obj/item/toy/bosunwhistle = 1,
			/obj/item/bananapeel = 1,
			/obj/fiftyspawner/platinum = 5,
			/obj/fiftyspawner/gold = 3,
			/obj/fiftyspawner/silver = 3,
			/obj/fiftyspawner/diamond = 1,
			/obj/fiftyspawner/phoron = 5,
			/obj/item/telecube/randomized = 1,
			/obj/item/capture_crystal/random = 1),
		chance = 50)

/obj/random/awayloot/nofail
	name = "garunteed random away mission loot"
CAPABILITIES(/obj/random/awayloot/nofail)
	configure(loot(chance = 100))

/obj/random/awayloot/looseloot
CAPABILITIES(/obj/random/awayloot/looseloot)
	configure(loot(
		table = list(
			/obj/item/aliencoin = 50,
			/obj/item/aliencoin/silver = 40,
			/obj/item/aliencoin/gold = 30,
			/obj/item/aliencoin/phoron = 20,
			/obj/item/denecrotizer = 10,
			/obj/item/capture_crystal = 5,
			/obj/item/capture_crystal/great = 3,
			/obj/item/capture_crystal/ultra = 1,
			/obj/item/capture_crystal/random = 4,
			/obj/item/perfect_tele = 5,
			/obj/item/bluespace_harpoon = 5,
			/obj/item/cell/infinite = 1,
			/obj/item/cell/void = 1,
			/obj/item/cell/device/weapon/recharge/alien = 1,
			/obj/item/clothing/shoes/boots/speed = 1,
			/obj/item/nif = 1,
			/obj/item/paicard = 1,
			/obj/item/storage/backpack/dufflebag/syndie = 2,
			/obj/item/storage/backpack/dufflebag/syndie/ammo = 2,
			/obj/item/storage/backpack/dufflebag/syndie/med = 2,
			/obj/item/clothing/mask/gas/voice = 2,
			/obj/item/radio_jammer = 2,
			/obj/item/toy/bosunwhistle = 1,
			/obj/item/bananapeel = 1,
			/obj/fiftyspawner/platinum = 5,
			/obj/fiftyspawner/gold = 3,
			/obj/fiftyspawner/silver = 3,
			/obj/fiftyspawner/diamond = 1,
			/obj/fiftyspawner/phoron = 5,
			/obj/item/telecube/randomized = 1,
			/obj/random/empty_or_lootable_crate = 10,
			/obj/random/medical = 10,
			/obj/random/firstaid = 5,
			/obj/random/maintenance = 30,
			/obj/random/mre = 10,
			/obj/random/snack = 15,
			/obj/random/tech_supply = 10,
			/obj/random/tech_supply/component = 15,
			/obj/random/tool = 10,
			/obj/random/tool/power = 5,
			/obj/random/tool/alien = 1,
			/obj/random/weapon = 5,
			/obj/random/ammo_all = 5,
			/obj/random/projectile/random = 3,
			/obj/random/multiple/voidsuit = 5)))

/obj/random/mainttoyloot
	name = "random loot from maint"
	desc = "A list of things that people can find in away missions."
	icon = 'icons/mob/randomlandmarks.dmi'
	icon_state = "fanc_trejur"

CAPABILITIES(/obj/random/mainttoyloot)
	loot(
		table = list(
			/obj/item/aliencoin/basic = 50,
			/obj/item/aliencoin/silver = 40,
			/obj/item/aliencoin/gold = 30,
			/obj/item/aliencoin/phoron = 20,
			/obj/item/capture_crystal = 5,
			/obj/random/mouseray = 5,
			/obj/item/perfect_tele = 5,
			/obj/item/bluespace_harpoon = 5,
			/obj/item/paicard = 1,
			/obj/item/storage/backpack/dufflebag/syndie = 2,
			/obj/item/storage/backpack/dufflebag/syndie/ammo = 2,
			/obj/item/storage/backpack/dufflebag/syndie/med = 2,
			/obj/item/clothing/mask/gas/voice = 2,
			/obj/item/radio_jammer = 2,
			/obj/item/toy/bosunwhistle = 1,
			/obj/item/bananapeel = 1,
			/obj/fiftyspawner/platinum = 5,
			/obj/fiftyspawner/gold = 3,
			/obj/fiftyspawner/silver = 3,
			/obj/fiftyspawner/diamond = 1,
			/obj/fiftyspawner/phoron = 5,
			/obj/item/capture_crystal/random = 1,
			/obj/random/unidentified_medicine = 1),
		chance = 50)
/obj/random/mainttoyloot/nofail
CAPABILITIES(/obj/random/mainttoyloot/nofail)
	configure(loot(chance = 100))


/obj/random/maintenance/misc //Clutter and loot for maintenance and away missions
	name = "random maintenance item"
	desc = "This is a random maintenance item."
	icon = 'icons/mob/randomlandmarks.dmi'
	icon_state = "trejur"


CAPABILITIES(/obj/random/maintenance/misc)
	configure(loot(
		table = list(
			/obj/random/maintenance = 500,
			/obj/random/maintenance/cargo = 300,
			/obj/random/maintenance/engineering = 300,
			/obj/random/maintenance/medical = 300,
			/obj/random/maintenance/research = 300,
			/obj/random/maintenance/security = 600,
			/obj/random/maintenance/morestuff = 50,
			/obj/random/mainttoyloot/nofail = 25,
			/obj/random/maintenance/foodstuff = 10),
		chance = 75))

/obj/random/maintenance/foodstuff
	name = "random food or drink item"
	desc = "This is a random maintenance item."
	icon = 'icons/mob/randomlandmarks.dmi'
	icon_state = "foodstuffs"


CAPABILITIES(/obj/random/maintenance/foodstuff)
	configure(loot(
		table = list(/obj/random/snack = 100, /obj/random/drinksoft = 100, /obj/random/mre = 50, /obj/random/donkpocketbox = 10, /obj/random/meat = 1),
		chance = 100))

/obj/random/maintenance/morestuff
	name = "random potentially useful things"
	desc = "This is a random maintenance item."
	icon = 'icons/mob/randomlandmarks.dmi'
	icon_state = "trejur"


CAPABILITIES(/obj/random/maintenance/morestuff)
	configure(loot(
		table = list(
			/obj/random/tool = 10,
			/obj/random/toolbox = 1,
			/obj/random/powercell = 2,
			/obj/random/flashlight = 2,
			/obj/random/pouch = 1,
			/obj/random/thermalponcho = 1,
			/obj/random/contraband = 5,
			/obj/random/cargopod = 5,
			/obj/item/flame/lighter = 1,
			/obj/item/storage/wallet/random = 1,
			/obj/random/cutout = 1),
		chance = 100))

/obj/random/instrument
	name = "random instrument"
	desc = "This is a random instrument."
	icon = 'icons/obj/musician.dmi'
	icon_state = "violin"

CAPABILITIES(/obj/random/instrument)
	loot(
		table = list(
			/obj/item/instrument/violin = 5,
			/obj/item/instrument/banjo = 5,
			/obj/item/instrument/guitar = 5,
			/obj/item/instrument/eguitar = 5,
			/obj/item/instrument/accordion = 5,
			/obj/item/instrument/trumpet = 5,
			/obj/item/instrument/saxophone = 5,
			/obj/item/instrument/trombone = 5,
			/obj/item/instrument/recorder = 5,
			/obj/item/instrument/harmonica = 5,
			/obj/item/instrument/bikehorn = 1,
			/obj/item/instrument/piano_synth = 5,
			/obj/item/instrument/glockenspiel = 5,
			/obj/item/instrument/musicalmoth = 1),
		chance = 100)

/obj/random/internal_organ
	name = "random organ"
	desc = "A random internal organ. Juicy fresh! Or... maybe not."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "heart"

CAPABILITIES(/obj/random/internal_organ)
	loot(
		table = list(
			/obj/item/organ/internal/appendix,
			/obj/item/organ/internal/eyes,
			/obj/item/organ/internal/heart,
			/obj/item/organ/internal/kidneys,
			/obj/item/organ/internal/liver,
			/obj/item/organ/internal/spleen,
			/obj/item/organ/internal/lungs,
			/obj/item/organ/internal/stomach,
			/obj/item/organ/internal/voicebox),
		chance = 90)

/obj/random/potion
	name = "random potion"
	desc = "A random potion."
	icon_state = "potion"

CAPABILITIES(/obj/random/potion)
	loot(
		table = list(
			/obj/item/reagent_containers/glass/bottle/potion/healing = 20,
			/obj/item/reagent_containers/glass/bottle/potion/greater_healing = 4,
			/obj/item/reagent_containers/glass/bottle/potion/fire_resist = 20,
			/obj/item/reagent_containers/glass/bottle/potion/antidote = 20,
			/obj/item/reagent_containers/glass/bottle/potion/water = 20,
			/obj/item/reagent_containers/glass/bottle/potion/regeneration = 8,
			/obj/item/reagent_containers/glass/bottle/potion/panacea = 10,
			/obj/item/reagent_containers/glass/bottle/potion/magic = 10,
			/obj/item/reagent_containers/glass/bottle/potion/lightness = 10,
			/obj/item/reagent_containers/glass/bottle/potion/SOP = 4,
			/obj/item/reagent_containers/glass/bottle/potion/shrink = 4,
			/obj/item/reagent_containers/glass/bottle/potion/growth = 4,
			/obj/item/reagent_containers/glass/bottle/potion/pain = 20,
			/obj/item/reagent_containers/glass/bottle/potion/faerie = 10,
			/obj/item/reagent_containers/glass/bottle/potion/relaxation = 10,
			/obj/item/reagent_containers/glass/bottle/potion/speed = 10,
			/obj/item/reagent_containers/glass/bottle/potion/attractiveness = 10,
			/obj/item/reagent_containers/glass/bottle/potion/girljuice = 4,
			/obj/item/reagent_containers/glass/bottle/potion/boyjuice = 4,
			/obj/item/reagent_containers/glass/bottle/potion/badpolymorph = 4,
			/obj/item/reagent_containers/glass/bottle/potion/bonerepair = 2,
			/obj/item/reagent_containers/glass/bottle/potion/truepolymorph = 1),
		chance = 100)

/obj/random/potion_ingredient
	name = "random potion ingredient"
	desc = "A random potion."
	icon_state = "ingredient"

CAPABILITIES(/obj/random/potion_ingredient)
	loot(
		table = list(
			/obj/item/potion_material/blood_ruby = 10,
			/obj/item/potion_material/ruby_eye = 2,
			/obj/item/potion_material/golden_scale = 10,
			/obj/item/potion_material/frozen_dew = 10,
			/obj/item/potion_material/living_coral = 10,
			/obj/item/potion_material/rare_horn = 4,
			/obj/item/potion_material/moldy_bread = 5,
			/obj/item/potion_material/glowing_gem = 5,
			/obj/item/potion_material/giant_toe = 5,
			/obj/item/potion_material/flesh_of_the_stars = 2,
			/obj/item/potion_material/spinning_poppy = 2,
			/obj/item/potion_material/salt_mage = 2,
			/obj/item/potion_material/golden_grapes = 10,
			/obj/item/potion_material/fairy_house = 5,
			/obj/item/potion_material/thorny_bulb = 5,
			/obj/item/potion_material/ancient_egg = 5,
			/obj/item/potion_material/crown_stem = 5,
			/obj/item/potion_material/red_ingot = 2,
			/obj/item/potion_material/soft_diamond = 2,
			/obj/item/potion_material/solid_mist = 2,
			/obj/item/potion_material/spider_leg = 1,
			/obj/item/potion_material/folded_dark = 1),
		chance = 100)

/obj/random/potion_ingredient/plus
	name = "random better potion ingredient"
	desc = "A random potion."
	icon_state = "ingredient_plus"

CAPABILITIES(/obj/random/potion_ingredient/plus)
	configure(loot(
		table = list(
			/obj/item/potion_material/blood_ruby = 20,
			/obj/item/potion_material/ruby_eye = 4,
			/obj/item/potion_material/golden_scale = 20,
			/obj/item/potion_material/frozen_dew = 20,
			/obj/item/potion_material/living_coral = 20,
			/obj/item/potion_material/rare_horn = 8,
			/obj/item/potion_material/moldy_bread = 10,
			/obj/item/potion_material/glowing_gem = 10,
			/obj/item/potion_material/giant_toe = 10,
			/obj/item/potion_material/flesh_of_the_stars = 4,
			/obj/item/potion_material/spinning_poppy = 4,
			/obj/item/potion_material/salt_mage = 4,
			/obj/item/potion_material/golden_grapes = 20,
			/obj/item/potion_material/fairy_house = 10,
			/obj/item/potion_material/thorny_bulb = 10,
			/obj/item/potion_material/ancient_egg = 10,
			/obj/item/potion_material/crown_stem = 10,
			/obj/item/potion_material/red_ingot = 4,
			/obj/item/potion_material/soft_diamond = 4,
			/obj/item/potion_material/solid_mist = 4,
			/obj/item/potion_material/spider_leg = 2,
			/obj/item/potion_material/folded_dark = 2,
			/obj/item/potion_material/glamour_transparent = 1,
			/obj/item/potion_material/glamour_shrinking = 1,
			/obj/item/potion_material/glamour_twinkling = 1,
			/obj/item/potion_material/glamour_shard = 1),
		chance = 100))

/obj/random/potion_base
	name = "random potion base"
	desc = "A random potion base."
	icon_state = "base"

CAPABILITIES(/obj/random/potion_base)
	loot(table = list(/obj/item/potion_base/aqua_regia, /obj/item/potion_base/ichor, /obj/item/potion_base/alkahest), chance = 100)

/obj/random/fantasy_item
	name = "random fantasy item"
	desc = "A random fantasy item."
	icon_state = "fantasy"

CAPABILITIES(/obj/random/fantasy_item)
	loot(
		table = list(
			/obj/item/healthanalyzer/scroll = 3,
			/obj/item/gun/energy/taser/magic = 10,
			/obj/item/bluespace_harpoon/wand = 5,
			/obj/item/slow_sizegun/magic = 10,
			/obj/item/clothing/gloves/bluespace/magic = 10,
			/obj/item/coin/gold = 30,
			/obj/item/coin/silver = 30,
			/obj/item/coin/platinum = 30,
			/obj/item/material/sword/rapier = 20,
			/obj/item/material/sword/longsword = 20,
			/obj/item/clothing/head/helmet/bucket/wood = 20,
			/obj/item/tool/wirecutters/alien/magic = 3,
			/obj/item/tool/crowbar/alien/magic = 3,
			/obj/item/tool/screwdriver/alien/magic = 3,
			/obj/item/weldingtool/alien/magic = 3,
			/obj/item/tool/wrench/alien/magic = 3,
			/obj/item/surgical/bone_clamp/alien/magic = 3,
			/obj/item/stack/material/gold = 10,
			/obj/item/stack/material/silver = 10,
			/obj/item/bone/skull = 3,
			/obj/item/material/twohanded/staff = 20,
			/obj/item/gun/energy/hooklauncher/ring = 3,
			/obj/item/toy/eight_ball = 3,
			/obj/item/perfect_tele/magic = 3),
		chance = 100)

/obj/random/fantasy_item/better
	name = "better random fantasy item"
	desc = "A random fantasy item."
	icon_state = "fantasy2"

CAPABILITIES(/obj/random/fantasy_item/better)
	configure(loot(
		table = list(
			/obj/item/healthanalyzer/scroll,
			/obj/item/gun/energy/taser/magic,
			/obj/item/bluespace_harpoon/wand,
			/obj/item/slow_sizegun/magic,
			/obj/item/clothing/gloves/bluespace/magic,
			/obj/item/tool/wirecutters/alien/magic,
			/obj/item/tool/crowbar/alien/magic,
			/obj/item/tool/screwdriver/alien/magic,
			/obj/item/weldingtool/alien/magic,
			/obj/item/tool/wrench/alien/magic,
			/obj/item/surgical/bone_clamp/alien/magic,
			/obj/item/material/twohanded/staff,
			/obj/item/gun/energy/hooklauncher/ring,
			/obj/item/perfect_tele/magic,
			/obj/item/reagent_containers/glass/bottle/potion/truepolymorph),
		chance = 100))

/obj/random/mega_nukies
	name = "random mega nukie"
	desc = "A random mega nukie."
	icon = 'icons/obj/drinks.dmi'
	icon_state = "nukie_mega_high"

CAPABILITIES(/obj/random/mega_nukies)
	loot(
		table = list(
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_sight = 5,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_heart = 2,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_sleep = 5,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_shock = 5,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_fast = 5,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_high = 5,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_shrink = 10,
			/obj/item/reagent_containers/food/drinks/cans/nukie_mega_grow = 10),
		chance = 100)

/obj/random/shibari
	name = "random shibari"
	desc = "A random shibari."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "shibari_None"

CAPABILITIES(/obj/random/shibari)
	loot(
		table = list(
			/obj/item/clothing/suit/shibari,
			/obj/item/clothing/suit/shibari/red,
			/obj/item/clothing/suit/shibari/blue,
			/obj/item/clothing/suit/shibari/green,
			/obj/item/clothing/suit/shibari/yellow,
			/obj/item/clothing/suit/shibari/black,
			/obj/item/clothing/suit/shibari/pink),
		chance = 100)

/obj/random/chips
	name = "random chips"
	icon_state = "chips"

CAPABILITIES(/obj/random/chips)
	loot(table = list(/obj/item/spacecasinocash/c1 = 35, /obj/item/spacecasinocash/c10 = 10, /obj/item/spacecasinocash/c100 = 5), chance = 90)

/obj/random/chips/better
	name = "better random chips"
	icon_state = "chips_1"

CAPABILITIES(/obj/random/chips/better)
	configure(loot(
		table = list(
			/obj/item/spacecasinocash/c10 = 35,
			/obj/item/spacecasinocash/c100 = 15,
			/obj/item/spacecasinocash/c200 = 5,
			/obj/item/spacecasinocash/c500 = 1),
		chance = 100))

/obj/random/chips/good
	name = "good random chips"
	icon_state = "chips_2"

CAPABILITIES(/obj/random/chips/good)
	configure(loot(
		table = list(
			/obj/item/spacecasinocash/c100 = 45,
			/obj/item/spacecasinocash/c200 = 15,
			/obj/item/spacecasinocash/c500 = 5,
			/obj/item/spacecasinocash/c1000 = 1)))


/obj/random/organ
	name = "Random Organ"
	desc = "An amalgamate of meaty things"
	icon_state = "brain"

CAPABILITIES(/obj/random/organ)
	loot(
		table = list(
			/obj/random/meat = 1500,
			/obj/item/organ/internal/brain = 20,
			/obj/item/organ/internal/brain/unathi = 20,
			/obj/item/organ/internal/brain/xeno = 20,
			/obj/item/organ/internal/eyes = 20,
			/obj/item/organ/internal/appendix = 20,
			/obj/item/organ/internal/heart = 20,
			/obj/item/organ/internal/intestine = 20,
			/obj/item/organ/internal/intestine/xeno = 20,
			/obj/item/organ/internal/kidneys = 20,
			/obj/item/organ/internal/kidneys/vox = 20,
			/obj/item/organ/internal/liver = 20,
			/obj/item/organ/internal/liver/unathi = 20,
			/obj/item/organ/internal/liver/vox = 20,
			/obj/item/organ/internal/lungs = 20,
			/obj/item/organ/internal/lungs/unathi = 20,
			/obj/item/organ/internal/lungs/vox = 20,
			/obj/item/organ/internal/spleen = 20,
			/obj/item/organ/internal/spleen/skrell = 20,
			/obj/item/organ/internal/stomach = 20,
			/obj/item/organ/internal/stomach/unathi = 20,
			/obj/item/organ/internal/stomach/xeno = 20,
			/obj/item/organ/internal/voicebox = 20,
			/obj/item/organ/internal/voicebox/skrell = 20,
			/obj/item/organ/internal/brain/replicant = 10,
			/obj/item/organ/internal/eyes/replicant = 10,
			/obj/item/organ/internal/heart/replicant = 10,
			/obj/item/organ/internal/kidneys/replicant = 10,
			/obj/item/organ/internal/liver/replicant = 10,
			/obj/item/organ/internal/lungs/replicant = 10,
			/obj/item/organ/internal/voicebox/replicant = 10,
			/obj/item/organ/internal/xenos/plasmavessel/replicant = 10,
			/obj/item/organ/internal/xenos/acidgland/replicant = 5,
			/obj/item/organ/internal/xenos/resinspinner/replicant = 5,
			/obj/item/organ/internal/immunehub/replicant = 5,
			/obj/item/organ/internal/metamorphgland/replicant = 5,
			/obj/item/organ/internal/heart/replicant/rage = 5,
			/obj/item/organ/internal/lungs/replicant/mending = 5))

/obj/random/vendorsnack
	name = "random snack vending machine"
	desc = "This is a random snack vending machine"
	icon = 'icons/obj/vending.dmi'
	icon_state = "generic"

CAPABILITIES(/obj/random/vendorsnack)
	loot(
		table = list(
			/obj/random/vendordrink,
			/obj/random/vendorfood,
			/obj/machinery/vending/hotfood,
			/obj/machinery/vending/sovietvend,
			/obj/machinery/vending/fooddessert,
			/obj/machinery/vending/radren))
