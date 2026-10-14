/obj/random/maintenance //Clutter and loot for maintenance and away missions
	name = "random maintenance item"
	desc = "This is a random maintenance item."


/obj/random/maintenance/clean
/*Maintenance loot lists without the trash, for use inside things.
Individual items to add to the maintenance list should go here, if you add
something, make sure it's not in one of the other lists.*/
	name = "random clean maintenance item"
	desc = "This is a random clean maintenance item."

CAPABILITIES(/obj/random/maintenance/clean)
	configure(loot(
		table = list(
			/obj/random/contraband = 10,
			/obj/item/flashlight/flare = 2,
			/obj/item/flashlight/glowstick = 2,
			/obj/item/flashlight/glowstick/blue = 2,
			/obj/item/flashlight/glowstick/orange = 1,
			/obj/item/flashlight/glowstick/red = 1,
			/obj/item/flashlight/glowstick/yellow = 1,
			/obj/item/flashlight/pen = 1,
			/obj/item/cell = 4,
			/obj/item/cell/device = 4,
			/obj/item/cell/high = 3,
			/obj/item/cell/super = 2,
			/obj/random/cigarettes = 5,
			/obj/item/clothing/mask/gas/clear = 3,
			/obj/item/clothing/mask/gas/half = 2,
			/obj/item/clothing/mask/breath = 4,
			/obj/item/reagent_containers/glass/rag = 2,
			/obj/item/reagent_containers/food/snacks/liquidfood = 4,
			/obj/item/storage/secure/briefcase = 2,
			/obj/item/storage/briefcase = 4,
			/obj/item/storage/backpack = 5,
			/obj/item/storage/backpack/satchel/norm = 5,
			/obj/item/storage/backpack/satchel = 4,
			/obj/item/storage/backpack/dufflebag = 3,
			/obj/item/storage/backpack/dufflebag/syndie = 1,
			/obj/item/storage/box = 5,
			/obj/item/storage/box/donkpockets = 3,
			/obj/item/storage/box/sinpockets = 2,
			/obj/item/storage/box/cups = 1,
			/obj/item/storage/box/mousetraps = 3,
			/obj/item/storage/wallet = 3,
			/obj/item/paicard = 1,
			/obj/item/clothing/shoes/galoshes = 2,
			/obj/item/clothing/shoes/syndigaloshes = 1,
			/obj/item/clothing/shoes/black = 4,
			/obj/item/clothing/shoes/laceup = 4,
			/obj/item/clothing/shoes/laceup/grey = 4,
			/obj/item/clothing/shoes/laceup/brown = 4,
			/obj/item/clothing/gloves/yellow = 1,
			/obj/item/clothing/gloves/botanic_leather = 3,
			/obj/item/clothing/gloves/sterile/latex = 2,
			/obj/item/clothing/gloves/white = 5,
			/obj/item/clothing/gloves/rainbow = 5,
			/obj/item/clothing/gloves/fyellow = 2,
			/obj/item/clothing/glasses/sunglasses = 1,
			/obj/item/clothing/glasses/meson = 3,
			/obj/item/clothing/glasses/meson/prescription = 2,
			/obj/item/clothing/glasses/welding = 1,
			/obj/item/clothing/head/bio_hood/general = 1,
			/obj/item/clothing/head/hardhat = 4,
			/obj/item/clothing/head/hardhat/red = 3,
			/obj/item/clothing/head/ushanka = 1,
			/obj/item/clothing/head/welding = 2,
			/obj/item/clothing/suit/storage/hazardvest = 4,
			/obj/item/clothing/suit/space/emergency = 1,
			/obj/item/clothing/suit/storage/toggle/bomber = 3,
			/obj/item/clothing/suit/bio_suit/general = 1,
			/obj/item/clothing/suit/storage/toggle/hoodie/black = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/blue = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/red = 3,
			/obj/item/clothing/suit/storage/toggle/hoodie/yellow = 3,
			/obj/item/clothing/suit/storage/toggle/brown_jacket = 3,
			/obj/item/clothing/suit/storage/toggle/leather_jacket = 3,
			/obj/item/clothing/suit/storage/vest/press = 1,
			/obj/item/clothing/suit/storage/apron = 3,
			/obj/item/clothing/under/color/grey = 4,
			/obj/item/clothing/under/syndicate/tacticool = 2,
			/obj/item/clothing/under/pants/camo = 2,
			/obj/item/clothing/under/harness = 1,
			/obj/item/clothing/under/tactical = 1,
			/obj/item/clothing/accessory/storage/webbing = 3,
			/obj/item/camera_assembly = 3,
			/obj/item/clothing/suit/caution = 4,
			/obj/item/clothing/head/cone = 3,
			/obj/item/card/emag_broken = 1,
			/obj/item/camera = 2,
			/obj/item/pda = 3,
			/obj/item/radio/headset = 3,
			/obj/item/toy/monster_bait = 3,
			/obj/item/toy/tennis = 2,
			/obj/item/toy/tennis/red = 2,
			/obj/item/toy/tennis/yellow = 2,
			/obj/item/toy/tennis/green = 2,
			/obj/item/toy/tennis/cyan = 2,
			/obj/item/toy/tennis/blue = 2,
			/obj/item/toy/tennis/purple = 2,
			/obj/item/toy/baseball = 1,
			/obj/item/pizzavoucher = 1,
			/obj/item/material/fishing_net/butterfly_net = 5,
			/obj/item/cracker = 2,
			/obj/random/mega_nukies = 5,
			/obj/random/potion_ingredient/plus = 1,
			/obj/random/translator = 2,
			/obj/random/shibari = 1)))

/obj/random/maintenance/security
/*Maintenance loot list. This one is for around security areas*/
	name = "random security maintenance item"
	desc = "This is a random security maintenance item."
	icon_state = "security"

CAPABILITIES(/obj/random/maintenance/security)
	configure(loot(
		table = list(
			/obj/random/maintenance/clean = 320,
			/obj/item/flashlight/maglight = 2,
			/obj/item/flash = 2,
			/obj/item/cell/device/weapon = 1,
			/obj/item/clothing/mask/gas/swat = 1,
			/obj/item/clothing/mask/gas/syndicate = 1,
			/obj/item/clothing/mask/balaclava = 2,
			/obj/item/clothing/mask/balaclava/tactical = 1,
			/obj/item/storage/backpack/security = 3,
			/obj/item/storage/backpack/satchel/sec = 3,
			/obj/item/storage/backpack/messenger/sec = 2,
			/obj/item/storage/backpack/dufflebag/sec = 2,
			/obj/item/storage/backpack/dufflebag/syndie/ammo = 1,
			/obj/item/storage/backpack/dufflebag/syndie/med = 1,
			/obj/item/storage/box/swabs = 2,
			/obj/item/storage/belt/security = 2,
			/obj/item/grenade/flashbang = 1,
			/obj/item/melee/baton = 1,
			/obj/item/reagent_containers/spray/pepper = 1,
			/obj/item/clothing/shoes/boots/jackboots = 3,
			/obj/item/clothing/shoes/boots/swat = 1,
			/obj/item/clothing/shoes/boots/combat = 1,
			/obj/item/clothing/gloves/swat = 1,
			/obj/item/clothing/gloves/combat = 1,
			/obj/item/clothing/glasses/sunglasses/big = 1,
			/obj/item/clothing/glasses/hud/security = 2,
			/obj/item/clothing/glasses/sunglasses/sechud = 1,
			/obj/item/clothing/glasses/sunglasses/sechud/aviator = 1,
			/obj/item/clothing/glasses/sunglasses/sechud/tactical = 1,
			/obj/item/clothing/head/beret/sec = 3,
			/obj/item/clothing/head/beret/sec/corporate/officer = 3,
			/obj/item/clothing/head/beret/sec/navy/officer = 3,
			/obj/item/clothing/head/helmet = 2,
			/obj/item/clothing/head/soft/sec = 4,
			/obj/item/clothing/head/soft/sec/corp = 4,
			/obj/item/clothing/suit/armor/vest = 3,
			/obj/item/clothing/suit/armor/vest/security = 2,
			/obj/item/clothing/suit/storage/vest/officer = 2,
			/obj/item/clothing/suit/storage/vest/detective = 1,
			/obj/item/clothing/suit/storage/vest/press = 1,
			/obj/item/clothing/accessory/storage/black_vest = 2,
			/obj/item/clothing/accessory/storage/black_drop_pouches = 2,
			/obj/item/clothing/accessory/holster/leg = 1,
			/obj/item/clothing/accessory/holster/hip = 1,
			/obj/item/clothing/accessory/holster/waist = 1,
			/obj/item/clothing/accessory/holster/armpit = 1,
			/obj/item/clothing/ears/earmuffs = 2,
			/obj/item/handcuffs = 2)))

/obj/random/maintenance/medical
/*Maintenance loot list. This one is for around medical areas*/
	name = "random medical maintenance item"
	desc = "This is a random medical maintenance item."
	icon_state = "medical"

CAPABILITIES(/obj/random/maintenance/medical)
	configure(loot(
		table = list(
			/obj/random/maintenance/clean = 320,
			/obj/random/medical/lite = 25,
			/obj/item/clothing/mask/breath/medical = 2,
			/obj/item/clothing/mask/surgical = 2,
			/obj/item/storage/backpack/medic = 5,
			/obj/item/storage/backpack/satchel/med = 5,
			/obj/item/storage/backpack/messenger/med = 5,
			/obj/item/storage/backpack/dufflebag/med = 3,
			/obj/item/storage/backpack/dufflebag/syndie/med = 1,
			/obj/item/storage/box/autoinjectors = 2,
			/obj/item/storage/box/beakers = 3,
			/obj/item/storage/box/bodybags = 2,
			/obj/item/storage/box/syringes = 3,
			/obj/item/storage/box/old_syringes = 3,
			/obj/item/storage/box/gloves = 3,
			/obj/item/storage/belt/medical/emt = 2,
			/obj/item/storage/belt/medical = 2,
			/obj/item/clothing/shoes/boots/combat = 1,
			/obj/item/clothing/shoes/white = 3,
			/obj/item/clothing/gloves/sterile/nitrile = 2,
			/obj/item/clothing/gloves/white = 5,
			/obj/item/clothing/glasses/hud/health = 2,
			/obj/item/clothing/glasses/hud/health/prescription = 1,
			/obj/item/clothing/head/bio_hood/virology = 1,
			/obj/item/clothing/suit/storage/toggle/labcoat = 4,
			/obj/item/clothing/suit/bio_suit/general = 1,
			/obj/item/clothing/under/rank/medical/paramedic = 2,
			/obj/item/clothing/accessory/storage/black_vest = 2,
			/obj/item/clothing/accessory/storage/white_vest = 2,
			/obj/item/clothing/accessory/storage/white_drop_pouches = 1,
			/obj/item/clothing/accessory/storage/black_drop_pouches = 1,
			/obj/item/clothing/accessory/stethoscope = 2)))

/obj/random/maintenance/engineering
/*Maintenance loot list. This one is for around medical areas*/
	name = "random engineering maintenance item"
	desc = "This is a random engineering maintenance item."
	icon_state = "tool"

CAPABILITIES(/obj/random/maintenance/engineering)
	configure(loot(
		table = list(
			/obj/random/maintenance/clean = 320,
			/obj/item/flashlight/maglight = 2,
			/obj/item/clothing/mask/gas/half = 3,
			/obj/item/clothing/mask/balaclava = 2,
			/obj/item/storage/briefcase/inflatable = 2,
			/obj/item/storage/backpack/industrial = 5,
			/obj/item/storage/backpack/satchel/eng = 5,
			/obj/item/storage/backpack/messenger/engi = 5,
			/obj/item/storage/backpack/dufflebag/eng = 3,
			/obj/item/storage/box = 5,
			/obj/item/storage/belt/utility/full = 2,
			/obj/item/storage/belt/utility = 3,
			/obj/item/clothing/head/beret/engineering = 3,
			/obj/item/clothing/head/soft/yellow = 3,
			/obj/item/clothing/head/orangebandana = 2,
			/obj/item/clothing/head/hardhat/dblue = 2,
			/obj/item/clothing/head/hardhat/orange = 2,
			/obj/item/clothing/glasses/welding = 1,
			/obj/item/clothing/head/welding = 2,
			/obj/item/clothing/suit/storage/hazardvest = 4,
			/obj/item/clothing/under/overalls = 2,
			/obj/item/clothing/shoes/boots/workboots = 3,
			/obj/item/clothing/shoes/magboots = 1,
			/obj/item/clothing/accessory/storage/black_vest = 2,
			/obj/item/clothing/accessory/storage/brown_vest = 2,
			/obj/item/clothing/accessory/storage/brown_drop_pouches = 1,
			/obj/item/clothing/ears/earmuffs = 3,
			/obj/item/beartrap = 1,
			/obj/item/handcuffs = 2)))

/obj/random/maintenance/research
/*Maintenance loot list. This one is for around medical areas*/
	name = "random research maintenance item"
	desc = "This is a random research maintenance item."
	icon_state = "science"

CAPABILITIES(/obj/random/maintenance/research)
	configure(loot(
		table = list(
			/obj/random/maintenance/clean = 320,
			/obj/item/analyzer/plant_analyzer = 3,
			/obj/item/flash/synthetic = 1,
			/obj/item/bucket_sensor = 2,
			/obj/item/cell/device/weapon = 1,
			/obj/item/storage/backpack/toxins = 5,
			/obj/item/storage/backpack/satchel/tox = 5,
			/obj/item/storage/backpack/messenger/tox = 5,
			/obj/item/pickaxe/excavationdrill = 2,
			/obj/item/storage/backpack/holding = 1,
			/obj/item/storage/box/beakers = 3,
			/obj/item/storage/box/syringes = 3,
			/obj/item/storage/box/gloves = 3,
			/obj/item/clothing/gloves/sterile/latex = 2,
			/obj/item/clothing/glasses/science = 4,
			/obj/item/clothing/glasses/material = 3,
			/obj/item/clothing/head/beret/purple = 1,
			/obj/item/clothing/head/bio_hood/scientist = 1,
			/obj/item/clothing/suit/storage/toggle/labcoat = 4,
			/obj/item/clothing/suit/storage/toggle/labcoat/science = 4,
			/obj/item/clothing/suit/bio_suit/scientist = 1,
			/obj/item/clothing/under/rank/scientist = 4,
			/obj/item/clothing/under/rank/scientist_new = 2)))

/obj/random/maintenance/cargo
/*Maintenance loot list. This one is for around cargo areas*/
	name = "random cargo maintenance item"
	desc = "This is a random cargo maintenance item."

CAPABILITIES(/obj/random/maintenance/cargo)
	configure(loot(
		table = list(
			/obj/random/maintenance/clean = 320,
			/obj/item/flashlight/lantern = 3,
			/obj/item/pickaxe = 4,
			/obj/item/pickaxe/drill = 3,
			/obj/item/storage/backpack/industrial = 5,
			/obj/item/storage/backpack/satchel/norm = 5,
			/obj/item/storage/backpack/dufflebag = 3,
			/obj/item/storage/backpack/dufflebag/syndie/ammo = 1,
			/obj/item/storage/toolbox/syndicate = 1,
			/obj/item/storage/belt/utility/full = 1,
			/obj/item/storage/belt/utility = 2,
			/obj/item/toner = 4,
			/obj/item/destTagger = 1,
			/obj/item/clothing/glasses/material = 3,
			/obj/item/clothing/head/soft/yellow = 3,
			/obj/item/clothing/suit/storage/hazardvest = 4,
			/obj/item/clothing/suit/storage/apron/overalls = 3,
			/obj/item/clothing/suit/storage/apron = 4,
			/obj/item/clothing/under/syndicate/tacticool = 2,
			/obj/item/clothing/under/syndicate/combat = 1,
			/obj/item/clothing/accessory/storage/black_vest = 2,
			/obj/item/clothing/accessory/storage/brown_vest = 2,
			/obj/item/clothing/ears/earmuffs = 3,
			/obj/item/beartrap = 1,
			/obj/item/handcuffs = 2)))
