//
//The code for machines are in vending.dm
//Only put machines here. A machine's stock (products, contraband, premium, prices) is in strings/vending/catalog.json, keyed by its type.
//
//


/*
 * Vending machine types
 */

/*

/obj/machinery/vending/[vendors name here]   // --vending machine template   :)
	name = ""
	desc = ""
	icon = ''
	icon_state = ""
	vend_delay = 15
	products = list()
	contraband = list()
	premium = list()

*/

/*
/obj/machinery/vending/atmospherics //Commenting this out until someone ponies up some actual working, broken, and unpowered sprites - Quarxink
	name = "Tank Vendor"
	desc = "A vendor with a wide variety of masks and gas tanks."
	icon = 'icons/obj/objects.dmi'
	icon_state = "dispenser"
	product_paths = "/obj/item/tank/oxygen;/obj/item/tank/phoron;/obj/item/tank/emergency_oxygen;/obj/item/tank/emergency_oxygen/engi;/obj/item/clothing/mask/breath"
	productamounts = "10;10;10;5;25"
	vend_delay = 0
*/



/obj/machinery/vending/boozeomat
	name = "Booze-O-Mat"
	desc = "A technological marvel, the ads would have you believe this is able to mix just the mixture you'd like to drink the moment you ask for one."
	icon_state = "boozeomat"
	vend_delay = 15
	product_slogans = "I hope nobody asks me for a bloody cup o' tea...;Alcohol is humanity's friend. Would you abandon a friend?;Quite delighted to serve you!;Is nobody thirsty on this station?"
	product_ads = "Drink up!;Booze is good for you!;Alcohol is humanity's best friend.;Quite delighted to serve you!;Care for a nice, cold beer?;Nothing cures you like booze!;Have a sip!;Have a drink!;Have a beer!;Beer is good for you!;Only the finest alcohol!;Best quality booze since 2053!;Award-winning wine!;Maximum alcohol!;Man loves beer.;A toast for progress!"
	req_access = list(ACCESS_BAR)
	req_log_access = ACCESS_BAR
	has_logs = 1
	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/boozeomat)
	configure(uses_power(idle = 211))

/obj/machinery/vending/boozeomat/virgin
	name = "Virgin-O-Mat"

	product_slogans = "I hope hope someone asks me for a cup o' tea...;Alcohol is humanity's enemy. Would you join a foe?;Quite delighted to serve you!;Is nobody thirsty on this station?"
	product_ads = "Drink up responsibly!;Booze is bad for you!;Alcohol is humanity's worst enemy.;Quite delighted to serve you!;Care for a nice, cold ginger ale?;Nothing cures you like tea!;Have a sip!;Have a drink!;Have a water!;Beer is not good for you!;Only the finest non-alcoholic beverages!;Best quality soft drinks since 2053!;Award-winning lemonade!;Minimum alcohol!;Man loathes beer.;A toast for sobriety!"

/obj/machinery/vending/assist
	product_ads = "Only the finest!;Have some tools.;The most robust equipment.;The finest gear in space!"

/obj/machinery/vending/coffee
	name = "Hot Drinks machine"
	desc = "A Galaksi brand vending machine which dispenses hot drinks."
	product_ads = "Have a drink!;Drink up!;It's good for you!;Would you like a hot joe?;I'd kill for some coffee!;The best beans in the galaxy.;Only the finest brew for you.;Mmmm. Nothing like a coffee.;I like coffee, don't you?;Coffee helps you work!;Try some tea.;We hope you like the best!;Try our new chocolate!;Admin conspiracies"
	icon_state = "coffee"
	vend_delay = 34
	vend_power_usage = 85000 //85 kJ to heat a 250 mL cup of coffee
	vending_sound = "machines/vending/vending_coffee.ogg"

CAPABILITIES(/obj/machinery/vending/coffee)
	configure(atom_rules(description_fluff = "The Ward-Takahashi Galaksi Samovar 55 has been reconstituting hot drinks from their powdered forms since... Well, 2555, but the design has hardly changed in a century or so."))
	configure(uses_power(idle = 211))

/obj/machinery/vending/snack
	name = "Getmore Chocolate Corp"
	desc = "A snack machine courtesy of the Getmore Chocolate Corporation, a Centauri Provisions brand."
	product_slogans = "Try our new nougat bar!;Twice the calories for half the price!"
	product_ads = "The healthiest!;Award-winning chocolate bars!;Mmm! So good!;Oh my god it's so juicy!;Have a snack.;Snacks are good for you!;Get More with Getmore!;Best quality snacks from Centauri Provisions.;We love chocolate!;Try our new jerky!"
	icon_state = "snack"

CAPABILITIES(/obj/machinery/vending/snack)
	configure(atom_rules(description_fluff = "Despite its name, the Getmore Chocolate Corporation does not produce chocolate - or any foods at all. The company exists soley to refit Ward-Takahashi's Galaksi brand vending products to accept Centauri Provisions' massive range of snackfoods, and sell them at a significant markup. Generic vendors are not authorized to vend Centauri products, and their popularity forces the market to Getmore or Get Lost."))

/obj/machinery/vending/cola
	name = "Robust Softdrinks"
	desc = "A softdrink vendor graciously provided by NanoTrasen's own vending division."
	icon_state = "Cola_Machine"
	product_slogans = "Robust Softdrinks: More robust than a toolbox to the head!"
	product_ads = "Refreshing!;Hope you're thirsty!;Over 1 million drinks sold!;Thirsty? Why not cola?;Please, have a drink!;Drink up!;The best drinks in the galaxy."

	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/cola)
	configure(atom_rules(description_fluff = "In a genius sales move, the only vendor authorized to dispense 'outside' beverages (at temperatures lower than 30 degrees celcius) aboard NanoTrasen stations... Is NanoTrasen themselves."))
	configure(uses_power(idle = 211))

/obj/machinery/vending/fitness
	name = "SweatMAX"
	desc = "Fueled by your inner inadequacy!"
	icon_state = "fitness"



CAPABILITIES(/obj/machinery/vending/fitness)
	configure(atom_rules(description_fluff = "Provided by NanoMed, SweatMAX promises solutions to all of your problems. Premium gains at premium prices. Resale of SweatMAX products is a violation of NanoTrasen guidelines."))

/obj/machinery/vending/cart
	name = "PTech"
	desc = "Cartridges for PDAs."
	product_slogans = "Carts to go!"
	icon_state = "cart"
	req_access = list(ACCESS_HOP)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/cigarette
	name = "cigarette machine"
	desc = "If you want to get cancer, might as well do it in style!"
	product_slogans = "Space cigs taste good like a cigarette should.;I'd rather toolbox than switch.;Smoke!;Don't believe the reports - smoke today!"
	product_ads = "Probably not bad for you!;Don't believe the scientists!;It's good for you!;Don't quit, buy more!;Smoke!;Nicotine heaven.;Best cigarettes since 2150.;Award-winning cigs.;Feeling temperamental? Try a Temperamento!;Carcinoma Angels - go fuck yerself!;Don't be so hard on yourself, kid. Smoke a Lucky Star!"
	vend_delay = 34
	icon_state = "cigs"

CAPABILITIES(/obj/machinery/vending/cigarette)
	configure(atom_rules(description_fluff = "As the ease of cancer treatment progressed to the almost routine (if costly) in the 22nd century, the tobacco industry was quick to make sure smoking went back into style. Take your pick, you've got health insurance don't ya, kid?"))


/obj/machinery/vending/medical
	name = "NanoMed Plus"
	desc = "Medical drug dispenser."
	icon_state = "med"
	product_ads = "Go save some lives!;The best stuff for your medbay.;Only the finest tools.;Natural chemicals!;This stuff saves lives.;Don't you want some?;Ping!"
	req_access = list(ACCESS_MEDICAL)
	req_log_access = ACCESS_CMO
	has_logs = 1

CAPABILITIES(/obj/machinery/vending/medical)
	configure(atom_rules(description_fluff = "NanoMed is NanoTrasen's medical science division, and provides almost all of the modern medbay essentials in-house at no extra charge. By using this vending machine, employees accept liability for products that may or may not be temporarily replaced by placebos or experimental treatments."))
	configure(uses_power(idle = 211))

/obj/machinery/vending/phoronresearch
	name = "Toximate 3000"
	desc = "All the fine parts you need in one vending machine!"
	req_log_access = ACCESS_RD
	has_logs = 1

/obj/machinery/vending/wallmed1
	name = "NanoMed"
	desc = "A wall-mounted version of the NanoMed."
	product_ads = "Go save some lives!;The best stuff for your medbay.;Only the finest tools.;Natural chemicals!;This stuff saves lives.;Don't you want some?"
	icon_state = "wallmed"
	layer = ABOVE_WINDOW_LAYER
	density = FALSE //It is wall-mounted, and thus, not dense. --Superxpdude
	req_log_access = ACCESS_CMO
	has_logs = 1
	can_rotate = 0

CAPABILITIES(/obj/machinery/vending/wallmed1)
	configure(atom_rules(description_fluff = "NanoMed is NanoTrasen's medical science division, and provides almost all of the modern medbay essentials in-house at no extra charge. By using this vending machine, employees accept liability for products that may or may not be temporarily replaced by placebos or experimental treatments."))

/obj/machinery/vending/wallmed2
	name = "NanoMed"
	desc = "A wall-mounted version of the NanoMed, containing only vital first aid equipment."
	icon_state = "wallmed"
	layer = ABOVE_WINDOW_LAYER
	density = FALSE //It is wall-mounted, and thus, not dense. --Superxpdude
	req_log_access = ACCESS_CMO
	has_logs = 1
	can_rotate = 0

CAPABILITIES(/obj/machinery/vending/wallmed2)
	configure(atom_rules(description_fluff = "NanoMed is NanoTrasen's medical science division, and provides almost all of the modern medbay essentials in-house at no extra charge. By using this vending machine, employees accept liability for products that may or may not be temporarily replaced by placebos or experimental treatments."))

/obj/machinery/vending/wallmed1/public

/obj/machinery/vending/security
	name = "SecTech"
	desc = "A security equipment vendor."
	product_ads = "Crack capitalist skulls!;Beat some heads in!;Don't forget - harm is good!;Your weapons are right here.;Handcuffs!;Freeze, scumbag!;Don't tase me bro!;Tase them, bro.;Why not have a donut?"
	icon_state = "sec"
	req_access = list(ACCESS_SECURITY)
	req_log_access = ACCESS_ARMORY
	has_logs = 1

CAPABILITIES(/obj/machinery/vending/security)
	configure(atom_rules(description_fluff = "Security vending is kindly provided by the Lawson Arms company, Hephaestus Industries' law enforcement division."))

/obj/machinery/vending/hydronutrients
	name = "NutriMax"
	desc = "A plant nutrients vendor by the NanoPastures company."
	product_slogans = "Aren't you glad you don't have to fertilize the natural way?;Now with 50% less stink!;Plants are people too!"
	product_ads = "We like plants!;Don't you want some?;The greenest thumbs ever.;We like big plants.;Soft soil..."
	icon_state = "nutri_generic"

CAPABILITIES(/obj/machinery/vending/hydronutrients)
	configure(uses_power(idle = 211))


/obj/machinery/vending/hydroseeds
	name = "MegaSeed Servitor"
	desc = "When you need seeds fast!"
	product_slogans = "THIS'S WHERE TH' SEEDS LIVE! GIT YOU SOME!;Hands down the best seed selection on the station!;Also certain mushroom varieties available, more for experts! Get certified today!"
	product_ads = "We like plants!;Grow some crops!;Grow, baby, growww!;Aw h'yeah son!"
	icon_state = "seeds_generic"


/**
 *  Populate hydroseeds product_records
 *
 *  This needs to be customized to fetch the actual names of the seeds, otherwise
 *  the machine would simply list "packet of seeds" times 20
 */
/obj/machinery/vending/hydroseeds/build_inventory()
	load_catalog_stock()
	var/list/all_products = list(
		list(products, CAT_NORMAL),
		list(contraband, CAT_HIDDEN),
		list(premium, CAT_COIN))

	for(var/current_list in all_products)
		var/category = current_list[2]

		for(var/entry in current_list[1])
			var/obj/item/seeds/S = variant_new(entry, null)
			var/name = S.name
			spent(S)
			var/datum/stored_item/vending_product/product = new/datum/stored_item/vending_product(src, entry, name)

			product.set_price((entry in prices) ? prices[entry] : 0)
			product.set_amount((current_list[1][entry]) ? current_list[1][entry] : 1)
			product.set_category(category)

			rel_add(src, nameof(product_records), product)

	// Consumed, as in the base proc.
	products = null
	contraband = null
	premium = null
	prices = null

/obj/machinery/vending/magivend
	name = "MagiVend"
	desc = "A magic vending machine."
	icon_state = "MagiVend"
	product_slogans = "Sling spells the proper way with MagiVend!;Be your own Houdini! Use MagiVend!"
	vend_delay = 15
	vend_reply = "Have an enchanted evening!"
	product_ads = "FJKLFJSD;AJKFLBJAKL;1234 LOONIES LOL!;>MFW;Kill them fuckers!;GET DAT FUKKEN DISK;HONK!;EI NATH;Destroy the station!;Admin conspiracies since forever!;Space-time bending hardware!"

/obj/machinery/vending/dinnerware
	name = "Dinnerware"
	desc = "A WT Galaksi brand kitchen and restaurant equipment vendor."
	product_ads = "Mm, food stuffs!;Food and food accessories.;Get your plates!;You like forks?;I like forks.;Woo, utensils.;You don't really need these..."
	icon_state = "dinnerware"

/obj/machinery/vending/tool
	name = "YouTool"
	desc = "Tools for tools."
	icon_state = "tool"
	//req_access = list(ACCESS_MAINT_TUNNELS) //Maintenance access
	req_log_access = ACCESS_CE
	has_logs = 1

/obj/machinery/vending/engivend
	name = "Engi-Vend"
	desc = "Spare tool vending. What? Did you expect some witty description?"
	icon_state = "engivend"
	req_access = list(ACCESS_ENGINE_EQUIP)
	product_records = list()
	req_log_access = ACCESS_CE
	has_logs = 1

/obj/machinery/vending/engineering
	name = "Robco Tool Maker"
	desc = "Everything you need for do-it-yourself station repair."
	icon_state = "engi"
	req_access = list(ACCESS_ENGINE_EQUIP)
	req_log_access = ACCESS_CE
	has_logs = 1

/obj/machinery/vending/robotics
	name = "Robotech Deluxe"
	desc = "All the tools you need to create your own robot army."
	icon_state = "robotics"
	req_access = list(ACCESS_ROBOTICS)
	req_log_access = ACCESS_RD
	has_logs = 1

/obj/machinery/vending/giftvendor
	name = "AlliCo Baubles and Confectionaries"
	desc = "For that special someone!"
	icon_state = "giftvendor"
	vend_delay = 15

CAPABILITIES(/obj/machinery/vending/giftvendor)
	configure(atom_rules(description_fluff = "AlliCo Ltd. is a NanoTrasen subsidiary focused on the design and licensing of 'cute' products including toys, gifts, stationary and accessories. Their range of original characters feature in all aspects of popular culture, from snacks to animated series."))


/obj/machinery/vending/fishing
	name = "Loot Trawler"
	desc = "A special vendor for fishing equipment."
	product_ads = "Tired of trawling across the ocean floor? Get our loot!;Chum and rods.;Don't get baited into fishing without us!;Baby is your star-sign pisces? We'd make a perfect match.;Do not fear, plenty to catch around here.;Don't get reeled in helplessly, get your own rod today!"
	icon_state = "fishvendor"


/obj/machinery/vending/virtual_autodrobe
	name = "Virtual AutoDrobe"
	desc = "A virtual vending machine for virtual avatar customization."
	icon_state = "Theater"
	product_slogans = "Dress for success!;Suited and booted!;It's show time!;Why leave style up to fate? Use AutoDrobe!"


/obj/machinery/vending/deathmatch
	name = "Annihilation Shop (Green)"
	desc = "A virtual vending machine for virtual murder equipment. This one's for green team."


/obj/machinery/vending/deathmatch/red
	name = "Annihilation Shop (Red)"
	desc = "A virtual vending machine for virtual murder equipment. This one's for red team."

/obj/machinery/vending/hotfood
	name = "\improper Hot Foods!"
	desc = "An old vending machine promising 'hot foods'. You doubt any of its contents are still edible."
	vend_delay = 40
	icon_state = "hotfood"

/obj/machinery/vending/weeb
	name = "\improper Nippon-tan!"
	desc = "A distressingly ethnic vending machine loaded with high sucrose low calorie for lack of better words snacks."
	vend_delay = 30
	vend_reply = "Dōmo arigatō!"
	product_slogans = "Tanoshī! ;Itadakimasu!"
	icon_state = "weeb"


/obj/machinery/vending/sol
	name = "\improper Sol-Snacks"
	desc = "A SolCentric vending machine dispensing a number of Sol-themed snacks, along with other foods."
	vend_delay = 30
	product_slogans = "A taste of Sol!"
	icon_state = "solsnack"


/obj/machinery/vending/snix
	name = "\improper Snix"
	desc = "A snack vending machine, offering a selection of slavic beer snacks."
	vend_delay = 30
	product_slogans = "Snix!"
	icon_state = "snix"



/obj/machinery/vending/snlvend
	name = "\improper Shop-n-Large Snacks!"
	desc = "A Shop-n-Large brand vending machine! Enjoy all your favorites!"
	vend_delay = 30
	product_slogans = "Shop Shop-n-Large!, Buy! Buy! Buy!, Try our new Bread Tube! Now with 10% less sawdust!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "snlvendor"



/obj/machinery/vending/sovietsoda
	name = "BODA"
	desc = "An old sweet water vending machine, how did this end up here?"
	icon_state = "sovietsoda"
	product_ads = "For Tsar and Country.;Have you fulfilled your nutrition quota today?;Very nice!;We are simple people, for this is all we eat.;If there is a person, there is a problem. If there is no person, then there is no problem."
	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/sovietsoda)
	configure(uses_power(idle = 211))

/obj/machinery/vending/sovietvend
	name = "Ration Station"
	desc = "An old ration vendor unit. How it even still functional?"
	icon = 'icons/obj/vending.dmi'
	icon_state = "sovietvend"
	product_ads = "For Tsar and Country.;Have you fulfilled your nutrition quota today?;Very nice!;We are simple people, for this is all we eat.;If there is a person, there is a problem. If there is no person, then there is no problem."

/obj/machinery/vending/radren
	name = "Radical Renard Sodas"
	desc = "A softdrink vendor owned by a frontier based soda company that's been contracted by NanoTrasen"
	icon_state = "radren"
	product_slogans = "Enjoy the rad refreshing taste of Radical Renard brand soda!"
	product_ads = "Radically Refreshing!;Get Cool!;Have you tried our new Andromeda Apple?;Enjoy a cold one with Renard!"
	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/radren)
	configure(uses_power(idle = 211))
/obj/machinery/vending/donksoft
	name = "Donk-Soft!"
	desc = "A toy vendor owned by Donk-Soft, a NanoTrasen sub-company."
	icon_state = "donksoft"
	product_slogans = "Get your cool toys today!;Quality toy weapons for cheap prices!"
	product_ads = "Express your inner child today!;Who needs responsibilities when you have toy weapons?;Make your next murder FUN!"
	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/donksoft)
	configure(atom_rules(description_fluff = "Donk-Soft is a sub-company owned by NanoTrasen that distribute replica weapons that shoot squishy foam darts. \
	They've been a staple of personal entertainment for decades but their buisness has only just moved to the fringes of the galaxy."))

/*
 * Department/job vendors to sit in place of lockers taking up space
 */

/obj/machinery/vending/wardrobe
	icon = 'icons/obj/vending_job.dmi'


/obj/machinery/vending/wardrobe/bardrobe
	name = "bartender wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "bardrobe"
	req_access = list(ACCESS_BAR)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/secdrobe
	name = "security wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "secdrobe"
	req_access = list(ACCESS_BRIG)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/chefdrobe
	name = "chef wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "chefdrobe"
	req_access = list(ACCESS_KITCHEN)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/medidrobe
	name = "medical wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "medidrobe"
	req_access = list(ACCESS_MEDICAL_EQUIP)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/chemdrobe
	name = "chemistry wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "chemdrobe"
	req_access = list(ACCESS_CHEMISTRY)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/genedrobe
	name = "genetics wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "genedrobe"
	req_access = list(ACCESS_GENETICS)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/virodrobe
	name = "virology wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "virodrobe"
	req_access = list(ACCESS_VIROLOGY)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/scidrobe
	name = "science wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "scidrobe"
	req_access = list(ACCESS_RESEARCH)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/robodrobe
	name = "robotics wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "robodrobe"
	req_access = list(ACCESS_ROBOTICS)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/chapdrobe
	name = "chaplain wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "chapdrobe"
	req_access = list(ACCESS_CHAPEL_OFFICE)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/engidrobe
	name = "engineer wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "engidrobe"
	req_access = list(ACCESS_ENGINE_EQUIP)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/atmosdrobe
	name = "atmos tech wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "atmosdrobe"
	req_access = list(ACCESS_ATMOSPHERICS)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/hydrobe
	name = "hydroponics wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "hydrobe"
	req_access = list(ACCESS_HYDROPONICS)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/cargodrobe
	name = "cargo wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "cargodrobe"
	req_access = list(ACCESS_CARGO)
	req_log_access = ACCESS_HOP
	has_logs = 1
/*

/obj/machinery/vending/wardrobe/curadrobe
	name = "cura?? wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "curadrobe"
	req_access = list()
	products = list()
	req_log_access = ACCESS_HOP
	has_logs = 1

*/

/obj/machinery/vending/wardrobe/janidrobe
	name = "janitor wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "janidrobe"
	req_access = list(ACCESS_JANITOR)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/lawdrobe
	name = "IAA wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "lawdrobe"
	req_access = list(ACCESS_LAWYER)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/detdrobe
	name = "detective wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Want to do your job? Sure you do!"
	icon_state = "detdrobe"
	req_access = list(ACCESS_FORENSICS_LOCKERS)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/mimedrobe
	name = "mime wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "..."
	icon_state = "mimedrobe"
	req_access = list(ACCESS_MIME)
	req_log_access = ACCESS_HOP
	has_logs = 1

/obj/machinery/vending/wardrobe/clowndrobe
	name = "clown wardrobe vendor"
	desc = "All the things you need to perform your job! Why didn't you already have them?"
	product_slogans = "Honk!"
	icon_state = "clowndrobe"
	req_access = list(ACCESS_CLOWN)
	req_log_access = ACCESS_HOP
	has_logs = 1


// Food Machines (for event/away maps)

//I want this not just as part of the zoo. ;v
/obj/machinery/vending/food
	name = "Food-O-Mat"
	desc = "A technological marvel, supposedly able to cook or mix a large variety of food or drink."
	icon_state = "hotfood"
	vend_delay = 15

/obj/machinery/vending/food/arojoan //Fluff vendor for the lewd houseboat.
	name = "Custom Food-O-Mat"
	desc = "Do you think Joan cooks? Of course not. Lazy squirrel!"
	vend_delay = 15

//Specific food vending machines for events that want them!

/obj/machinery/vending/fooditalian
	name = "Italian Imports"
	desc = "You wanted some Italian food? Well here's some imported from the local pizza place!"
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/foodfast
	name = "United Grills"
	desc = "Not sure how they're united but man is this grilled food delicious! Though it seems to just be a lot of fast food..."
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/foodmeat
	name = "Meaty Marvels"
	desc = "What's a marvel is how you're not ordering from this machine yet!"
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/foodasian
	name = "Authenticate Asian"
	desc = "Some good ol' Sol food!"
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/foodfish
	name = "Fishy Food"
	desc = "Don't mind the name, this is 100% fish!"
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/foodveggie
	name = "Veggie Varieties"
	desc = "Even vegitarians have their own vending machines! How thoughtful."
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/fooddessert
	name = "Delightful Desserts"
	desc = "Even if you've stuffed your face with a pizza or two, you ALWAYS have room for dessert!"
	icon_state = "hotfood"
	vend_delay = 10

/obj/machinery/vending/foodstuffing
	name = "Stuffing Site"
	desc = "Is... is it just full of stuffing? No wait, there's turkey in there too."
	icon_state = "hotfood"
	vend_delay = 10

// Food Machines (for event/away maps)

/obj/machinery/vending/blood
	name = "Blood-Onator"
	desc = "Freezer-vendor for storage and quick dispensing of blood packs"
	product_ads = "The true life juice!;Vampire's choice!;Home-grown blood only!;Donate today, be saved tomorrow!;Approved by Zeng-Hu Pharmaceuticals Incorporated!; Curse you, Vey-Med artificial blood!"
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "blood"
	vend_delay = 7
	req_access = list(ACCESS_MEDICAL)
	req_log_access = ACCESS_CMO
	has_logs = 1

CAPABILITIES(/obj/machinery/vending/blood)
	configure(uses_power(idle = 211))

//Airlock antitox vendor
/obj/machinery/vending/wallmed_airlock
	name = "Airlock NanoMed"
	desc = "Wall-mounted Medical Equipment dispenser. This limited-use version dispenses antitoxins with mild painkillers for surface EVAs."
	icon_state = "wallmed"
	density = 0 //It is wall-mounted, and thus, not dense. --Superxpdude
	req_log_access = ACCESS_CMO
	has_logs = 1

/obj/machinery/seed_storage/brig
	name = "Prisoners' food seed storage"
	starting_seeds = list(
		VARIANT(/obj/item/seeds/appleseed) = 3,
		VARIANT(/obj/item/seeds/bananaseed) = 3,
		VARIANT(/obj/item/seeds/berryseed) = 3,
		VARIANT(/obj/item/seeds/cabbageseed) = 3,
		VARIANT(/obj/item/seeds/carrotseed) = 3,
		VARIANT(/obj/item/seeds/celery) = 3,
		VARIANT(/obj/item/seeds/chantermycelium) = 3,
		VARIANT(/obj/item/seeds/cherryseed) = 3,
		VARIANT(/obj/item/seeds/chiliseed) = 3,
		VARIANT(/obj/item/seeds/cocoapodseed) = 3,
		VARIANT(/obj/item/seeds/cornseed) = 3,
		VARIANT(/obj/item/seeds/durian) = 3,
		VARIANT(/obj/item/seeds/eggplantseed) = 3,
		VARIANT(/obj/item/seeds/grapeseed) = 3,
		VARIANT(/obj/item/seeds/grassseed) = 3,
		VARIANT(/obj/item/seeds/replicapod) = 3,
		VARIANT(/obj/item/seeds/lavenderseed) = 3,
		VARIANT(/obj/item/seeds/lemonseed) = 3,
		VARIANT(/obj/item/seeds/lettuce) = 3,
		VARIANT(/obj/item/seeds/limeseed) = 3,
		VARIANT(/obj/item/seeds/mtearseed) = 2,
		VARIANT(/obj/item/seeds/orangeseed) = 3,
		VARIANT(/obj/item/seeds/onionseed) = 3,
		VARIANT(/obj/item/seeds/peanutseed) = 3,
		VARIANT(/obj/item/seeds/plumpmycelium) = 3,
		VARIANT(/obj/item/seeds/poppyseed) = 3,
		VARIANT(/obj/item/seeds/potatoseed) = 3,
		VARIANT(/obj/item/seeds/pumpkinseed) = 3,
		VARIANT(/obj/item/seeds/rhubarb) = 3,
		VARIANT(/obj/item/seeds/riceseed) = 3,
		/obj/item/seeds/rose = 3,
		VARIANT(/obj/item/seeds/soyaseed) = 3,
		VARIANT(/obj/item/seeds/pineapple) = 3,
		VARIANT(/obj/item/seeds/sugarcaneseed) = 3,
		VARIANT(/obj/item/seeds/sunflowerseed) = 3,
		VARIANT(/obj/item/seeds/shandseed) = 2,
		VARIANT(/obj/item/seeds/tobaccoseed) = 3,
		VARIANT(/obj/item/seeds/tomatoseed) = 3,
		VARIANT(/obj/item/seeds/towermycelium) = 3,
		VARIANT(/obj/item/seeds/vanilla) = 3,
		VARIANT(/obj/item/seeds/watermelonseed) = 3,
		VARIANT(/obj/item/seeds/wheatseed) = 3,
		VARIANT(/obj/item/seeds/whitebeetseed) = 3,
		VARIANT(/obj/item/seeds/wabback) = 2)

/obj/machinery/vending/hydronutrients/brig
	name = "Brig NutriMax"
	desc = "A plant nutrients vendor. Seems some items aren't included."

/obj/machinery/vending/abductor
	name = "Abduct-U"
	desc = "A mysterious machine which can fabricate many tools for acquiring test subjects."
	icon_state = "dispenser_2way"
	vend_delay = 15

// Loadout Vending Machines Start

/obj/machinery/vending/loadout
	name = "Fingers and Toes"
	desc = "A special vendor for gloves and shoes!"
	product_ads = "Do you have fingers and toes? COVER THEM UP!;Show me your toes! Wait. NO DON'T! BUY NEW SHOES!;Don't leave prints, BUY SOME GLOVES!;Remember to check your shoes for micros! You don't have to let them out, but just check for them!;Fingers and Toes is not liable for micro entrapment or abuse under the feet of our patrons.!;This little piggy went WE WE WE all the way down to FINGERS AND TOES to pick up some sweet new gloves and shoes."
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "glovesnshoes"

/obj/machinery/vending/loadout/uniform
	name = "The Basics"
	desc = "A vendor using compressed matter cartridges to store large amounts of basic station uniforms."
	product_ads = "Don't get caught naked!;Pick up your uniform!;Using compressed matter cartridges and VERY ETHICAL labor practices, we bring you the uniforms you need!;No uniform? No problem!;We've got your covered!;The Basics is not responsible for being crushed under the amount of things inside our machines. DO NOT VEND IN EXCESS!!"
	icon_state = "loadout"
	vend_delay = 16

/obj/machinery/vending/loadout/accessory
	name = "Looty Inc."
	desc = "A special vendor for accessories."
	product_ads = "Want shinies? We have the shinies.;Need that special something to complete your outfit? We have what you need!;Ditch that old dull dangly something you've got and pick up one of our shinies!;Bracelets, collars, scarfs rings and more! We have the fancy things you need!;Does your pet need a collar? We don't judge! Keep them in line with one of one of ours!;Top of the line materials! 'Hand crafted' goods!"
	icon_state = "accessory"
	vend_delay = 6

/obj/machinery/vending/loadout/clothing
	name = "General Jump"
	desc = "A special vendor using compressed matter cartridges to store large amounts of clothing."
	product_ads = "Tired of your grey jumpsuit? Spruce yourself up!;We have the outfit for you!;Don't let that grey jumpsuit get you down, get a ROBUST outfit right now!;Using compressed matter catridges and VERY ETHICAL labor practices to bring YOU the clothing you crave!;Are you sure you want to go to work in THAT?;All of our wares have a whole TWO pockets!"
	icon_state = "clothing"
	vend_delay = 16

//////////////////START OF CHIPS CO. VENDORS//////////////////

/obj/machinery/vending/loadout/gadget
	name = "Chips Co."
	desc = "A special vendor for devices and gadgets."
	product_ads = "You can't RESIST our great deals!;Feeling disconnected? We have a gadget for you!;You know you have the capacity to buy our capacitors!;FILL THAT HOLE IN YOUR HEART WITH OUR PLASTIC DISTRACTIONS!!!;Devices for everyone! Chips Co.!;ROBUST INVENTORY, GREAT PRICES! ;DON'T FORGET THE oyPAD 13s PRO! ON SALE NOW, ONLY ONE THOUSAND THALERS!"
	icon_state = "gadgets"
	vend_delay = 11

/obj/machinery/vending/event/gadget //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Chips Co."
	desc = "A special vendor for devices and gadgets."
	product_ads = "You can't RESIST our great deals!;Feeling disconnected? We have a gadget for you!;You know you have the capacity to buy our capacitors!;FILL THAT HOLE IN YOUR HEART WITH OUR PLASTIC DISTRACTIONS!!!;Devices for everyone! Chips Co.!;ROBUST INVENTORY, GREAT PRICES! ;DON'T FORGET THE oyPAD 13s PRO! ON SALE NOW, ONLY ONE THOUSAND THALERS!"
	icon_state = "gadgets"
	vend_delay = 11

//////////////////END OF CHIPS CO. VENDORS//////////////////

/obj/machinery/vending/loadout/loadout_misc
	name = "Bits and Bobs"
	desc = "A special vendor for things and also stuff!"
	product_ads = "You never know when you might need an umbrella.;Hey kid... want some cardemon cards?;Miscellaneous for your miscellaneous heart.;Who's bob? Wouldn't you like to know.;I'm sorry there's no grappling hooks in our umbrellas.;We sell things AND stuff."
	icon_state = "loadout_misc"

/obj/machinery/vending/loadout/overwear
	name = "Big D's Best"
	desc = "A special vendor using compressed matter cartridges to store large amounts of overwear!"
	product_ads = "Dress your best! It's what Big D would want.;Overwear for all occasions!;Big D has what you need if what you need is some form of jacket!;Need a new hoodie? Big D has you covered.;Big D says you need a new suit!;Big D smiles when he sees you in one of his coats!"
	icon_state = "suit"
	vend_delay = 16

/obj/machinery/vending/loadout/costume
	name = "Thespian's Delight"
	desc = "Sometimes nerds need costumes!"
	product_ads = "Don't let your art be stifled!;Remember, practice makes perfect!;Break a leg!;Don't make me get the cane!;Thespian's Delight entering stage right!;Costumes for your acting needs!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "theater"

/obj/machinery/vending/loadout/gadget
	name = "Chips Co."
	desc = "A special vendor for devices and gadgets."
	product_ads = "You can't RESIST our great deals!;Feeling disconnected? We have a gadget for you!;You know you have the capacity to buy our capacitors!;FILL THAT HOLE IN YOUR HEART WITH OUR PLASTIC DISTRACTIONS!!!;Devices for everyone! Chips Co.!;ROBUST INVENTORY, GREAT PRICES! ;DON'T FORGET THE oyPAD 13s PRO! ON SALE NOW, ONLY ONE THOUSAND THALERS!"
	icon_state = "gadgets"
	vend_delay = 11

// Loadout Vending Machines End

/obj/machinery/vending/entertainer
	name = "Thespian's Delight"
	desc = "Sometimes nerds need costumes!"
	product_ads = "Don't let your art be stifled!;Remember, practice makes perfect!;Break a leg!;Don't make me get the cane!;Thespian's Delight entering stage right!;Costumes for your acting needs!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "theater"

// Event Loadout Vending Machines Start

/obj/machinery/vending/event //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Fingers and Toes"
	desc = "A special vendor for gloves and shoes!"
	product_ads = "Do you have fingers and toes? COVER THEM UP!;Show me your toes! Wait. NO DON'T! BUY NEW SHOES!;Don't leave prints, BUY SOME GLOVES!;Remember to check your shoes for micros! You don't have to let them out, but just check for them!;Fingers and Toes is not liable for micro entrapment or abuse under the feet of our patrons.!;This little piggy went WE WE WE all the way down to FINGERS AND TOES to pick up some sweet new gloves and shoes."
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "glovesnshoes"

/obj/machinery/vending/event/uniform //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "The Basics"
	desc = "A vendor using compressed matter cartridges to store large amounts of basic station uniforms."
	product_ads = "Don't get caught naked!;Pick up your uniform!;Using compressed matter cartridges and VERY ETHICAL labor practices, we bring you the uniforms you need!;No uniform? No problem!;We've got your covered!;The Basics is not responsible for being crushed under the amount of things inside our machines. DO NOT VEND IN EXCESS!!"
	icon_state = "loadout"
	vend_delay = 16

/obj/machinery/vending/event/accessory //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Looty Inc."
	desc = "A special vendor for accessories."
	product_ads = "Want shinies? We have the shinies.;Need that special something to complete your outfit? We have what you need!;Ditch that old dull dangly something you've got and pick up one of our shinies!;Bracelets, collars, scarfs rings and more! We have the fancy things you need!;Does your pet need a collar? We don't judge! Keep them in line with one of one of ours!;Top of the line materials! 'Hand crafted' goods!"
	icon_state = "accessory"
	vend_delay = 6

/obj/machinery/vending/event/clothing //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "General Jump"
	desc = "A special vendor using compressed matter cartridges to store large amounts of clothing."
	product_ads = "Tired of your grey jumpsuit? Spruce yourself up!;We have the outfit for you!;Don't let that grey jumpsuit get you down, get a ROBUST outfit right now!;Using compressed matter catridges and VERY ETHICAL labor practices to bring YOU the clothing you crave!;Are you sure you want to go to work in THAT?;All of our wares have a whole TWO pockets!"
	icon_state = "clothing"
	vend_delay = 16

/obj/machinery/vending/event/loadout_misc //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Bits and Bobs"
	desc = "A special vendor for things and also stuff!"
	product_ads = "You never know when you might need an umbrella.;Hey kid... want some cardemon cards?;Miscellaneous for your miscellaneous heart.;Who's bob? Wouldn't you like to know.;I'm sorry there's no grappling hooks in our umbrellas.;We sell things AND stuff."
	icon_state = "loadout_misc"


/obj/machinery/vending/event/overwear //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Big D's Best"
	desc = "A special vendor using compressed matter cartridges to store large amounts of overwear!"
	product_ads = "Dress your best! It's what big D would want.;Overwear for all occasions!;Big D has what you need if what you need is some form of jacket!;Need a new hoodie? Bid D has you covered.;Big D says you need a new suit!;Big D smiles when he sees you in one of his coats!"
	icon_state = "suit"
	vend_delay = 16

/obj/machinery/vending/event/gadget //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Chips Co."
	desc = "A special vendor for devices and gadgets."
	product_ads = "You can't RESIST our great deals!;Feeling disconnected? We have a gadget for you!;You know you have the capacity to buy our capacitors!;FILL THAT HOLE IN YOUR HEART WITH OUR PLASTIC DISTRACTIONS!!!;Devices for everyone! Chips Co.!;ROBUST INVENTORY, GREAT PRICES! ;DON'T FORGET THE oyPAD 13s PRO! ON SALE NOW, ONLY ONE THOUSAND THALERS!"
	icon_state = "gadgets"
	vend_delay = 11

/obj/machinery/vending/event/costume //FOR FACILITATING AND EQUIPPING EVENTS, DO NOT PLACE ON THE NORMAL MAP//
	name = "Thespian's Delight"
	desc = "Sometimes nerds need costumes!"
	product_ads = "Don't let your art be stifled!;Remember, practice makes perfect!;Break a leg!;Don't make me get the cane!;Thespian's Delight entering stage right!;Costumes for your acting needs!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "theater"

// Event Loadout Vending Machines End

// Event Food Vending Machines Start

/obj/machinery/vending/event/food //FOR FACILITATING/OUTFITTING EVENTS, DO NOT PUT THESE ON THE MAP//
	name = "Dog Food"
	desc = "Food made by dogs!"
	product_ads = "EAT FOOD!!!;Awooooooooooooooo!~;Made by actual dogs!;Now with twenty percent more taste!!!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "hotfood"
	vend_delay = 15

/obj/machinery/vending/event/food/safe //FOR FACILITATING/OUTFITTING EVENTS, DO NOT PUT THESE ON THE MAP//
	name = "Dog Food"
	desc = "Food made by dogs!"
	product_ads = "EAT FOOD!!!;Awooooooooooooooo!~;Made by actual dogs!;Now with twenty percent more taste!!!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "hotfood"
	vend_delay = 15

/obj/machinery/vending/event/food/ingredients //FOR FACILITATING/OUTFITTING EVENTS, DO NOT PUT THESE ON THE MAP//
	name = "Food Ingredients"
	desc = "Food made by dogs!"
	product_ads = "EAT FOOD!!!;Awooooooooooooooo!~;Made by actual dogs!;Now with twenty percent more taste!!!"
	icon = 'icons/obj/vending.dmi'
	icon_state = "hotfood"
	vend_delay = 15

// Event Food Vending Machines End

/obj/machinery/vending/emergencyfood
	name = "Food Cube Dispenser"
	desc = "An ominous machine dispensing food cubes. It will keep you fed, but at what cost?"
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "foodcube"
	product_ads = "Afraid to starve?;Starvation is not an option!;Add water before consumption.;Let me take care of you.;Dire circumstances call for food cubes, do not let the taste deter you."

/obj/machinery/vending/emergencyfood/filled

/obj/machinery/vending/cola/soft
	name = "Soft Robustdrinks"
	desc = "A different vendor brand for soft drinks, taking off very successfully with its unique imagery and equal stock."
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "Cola_Machine"

//////////////////////Bepis Drinks (04/29/2021)//////////////////////

/obj/machinery/vending/bepis
	name = "Bepis Softdrinks"
	desc = "A strange softdrink vendor that isn't owned by NanoTrasen... Why (and how) is it here?"
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "bepis"
	product_slogans = "Refreshing!;Have a sip, you won't believe the taste!;Puts the 'B' in Best Soda!"
	product_ads = "Refreshing!;Hope you're thirsty!;Please, have a drink!;Drink up!"

	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/bepis)
	configure(uses_power(idle = 211))

/obj/machinery/vending/altevian
	name = "Altevian Imported Meals"
	desc = "A vending machine containing imported foods from Altevian Hegemony. Delicious and nutritious. No natural ingridients guaranteed!"
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "rattevendor"
	product_slogans = "Spacer's choice!;Voidborn food for voidborn people!;Most processed foods ever!"
	product_ads = "Perfectly edible!;Squeaky clean foods!;Cheesed to meet you!;Made for spacers, by spacers, of spacers!"


/obj/machinery/vending/desatti
	name = "Desatti Catering"
	desc = "A vending machine from Desatti Catering, stocking traditional Sol snacks. Like the good ol' days, apparently."
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "desatti"
	product_slogans = "Keep calm and eat Desatti!;Don't be a smeg head, tuck in!;Go'an. 'Ave a cheeky nosh.;TAKE A BUTCHERS AT THIS!"
	product_ads = "Jaffa cakes are legally cakes!;Real synthetic processed pork!;What flavour could the shrimps really be!?;Tea recommended with every biscuit purchase!"


/obj/machinery/vending/nukie
	name = "Nukies Energy Drinks"
	desc = "A vending machine stocked full of the most potent energy drinks on the market."
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "nukie"
	product_slogans = "Contains one gram of caffeine!;Keep going, go on forever!;It'll blow you away!;Nukies is not responsible for any deaths occurred in a period of 24 hours after consuming our products!"
	product_ads = "Get your peach blasted!;Pop your cherry here!;Dare you swallow the bursting banana?;Try our limited edition flavour!"



// === restored from vending_machines_vr.dm: CHOMP loadout_misc override (re-adds capture_crystal/cheap + egy;
// was the last override in the original modular include order, lost to a merge-ordering bug). ===
/obj/machinery/vending/loadout/loadout_misc
