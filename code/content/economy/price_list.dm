// For convenience and easier comparing and maintaining of item prices,
// all these will be defined here and sorted in different sections.

// The item price in thalers. atom/movable so we can also assign a price to animals and other things.
// (price_tag is the atom_rules type trait: configure(atom_rules(price_tag = N)))

// The proc that is called when the price is being asked for. Use this to refer to another object if necessary.
/atom/movable/proc/get_item_cost()
	return atom_rules_of(src).price_tag


//***************//
//---Beverages---//
//***************//

/datum/reagent/var/price_tag = 0


// Juices, soda and similar //

/datum/reagent/water
	price_tag = 2

/datum/reagent/drink/juice
	price_tag = 2

/datum/reagent/toxin/poisonberryjuice
	price_tag = 2

/datum/reagent/drink/milk
	price_tag = 2

/datum/reagent/drink/soda
	price_tag = 2

/datum/reagent/drink/doctor_delight
	price_tag = 2

/datum/reagent/drink/nothing
	price_tag = 2

/datum/reagent/drink/milkshake
	price_tag = 2

/datum/reagent/drink/roy_rogers
	price_tag = 2

/datum/reagent/drink/shirley_temple
	price_tag = 2

/datum/reagent/drink/arnold_palmer
	price_tag = 2

/datum/reagent/drink/collins_mix
	price_tag = 2


// Beer //

/datum/reagent/ethanol/ale
	price_tag = 2

/datum/reagent/ethanol/beer
	price_tag = 2


// Hot Drinks //

/datum/reagent/drink/rewriter
	price_tag = 3

/datum/reagent/drink/tea
	price_tag = 3

/datum/reagent/drink/coffee
	price_tag = 3

/datum/reagent/drink/hot_coco
	price_tag = 3

/obj/item/reagent_containers/food/drinks/coffee

/obj/item/reagent_containers/food/drinks/tea

/obj/item/reagent_containers/food/drinks/h_chocolate


// Spirituous liquors //

/datum/reagent/ethanol/irish_cream
	price_tag = 5

/datum/reagent/ethanol/absinthe
	price_tag = 5

/datum/reagent/ethanol/bluecuracao
	price_tag = 5

/datum/reagent/ethanol/deadrum
	price_tag = 5

/datum/reagent/ethanol/gin
	price_tag = 5

/datum/reagent/ethanol/coffee/kahlua
	price_tag = 5

/datum/reagent/ethanol/melonliquor
	price_tag = 5

/datum/reagent/ethanol/rum
	price_tag = 5

/datum/reagent/ethanol/tequila
	price_tag = 5

/datum/reagent/ethanol/thirteenloko
	price_tag = 5

/datum/reagent/ethanol/vodka
	price_tag = 5

/datum/reagent/ethanol/whiskey
	price_tag = 5

/datum/reagent/ethanol/specialwhiskey
	price_tag = 5

/datum/reagent/ethanol/patron
	price_tag = 5

/datum/reagent/ethanol/goldschlager
	price_tag = 5

/datum/reagent/ethanol/coffee/brave_bull // Not an original liquor in its own. But since it's a mix of purely Tequila
	price_tag = 5						 // and Kahlua, it's basically just another one and gets the same price.


// Wines //

/datum/reagent/ethanol/wine
	price_tag = 8

/datum/reagent/ethanol/cognac
	price_tag = 8

/datum/reagent/ethanol/sake
	price_tag = 8

/datum/reagent/ethanol/vermouth
	price_tag = 8

/datum/reagent/ethanol/pwine
	price_tag = 8


// Cocktails //

/datum/reagent/ethanol/acid_spit
	price_tag = 4

/datum/reagent/ethanol/alliescocktail
	price_tag = 4

/datum/reagent/ethanol/aloe
	price_tag = 4

/datum/reagent/ethanol/amasec
	price_tag = 4

/datum/reagent/ethanol/andalusia
	price_tag = 4

/datum/reagent/ethanol/antifreeze
	price_tag = 4

/datum/reagent/ethanol/atomicbomb
	price_tag = 4

/datum/reagent/ethanol/coffee/b52
	price_tag = 4

/datum/reagent/ethanol/bahama_mama
	price_tag = 4

/datum/reagent/ethanol/barefoot
	price_tag = 4

/datum/reagent/ethanol/beepsky_smash
	price_tag = 4

/datum/reagent/ethanol/bilk
	price_tag = 4

/datum/reagent/ethanol/black_russian
	price_tag = 4

/datum/reagent/ethanol/bloody_mary
	price_tag = 4

/datum/reagent/ethanol/booger
	price_tag = 4

/datum/reagent/ethanol/coffee/brave_bull
	price_tag = 4

/datum/reagent/ethanol/changeling_sting
	price_tag = 4

/datum/reagent/ethanol/martini
	price_tag = 4

/datum/reagent/ethanol/cuba_libre
	price_tag = 4

/datum/reagent/ethanol/rum_and_cola
	price_tag = 4

/datum/reagent/ethanol/demonsblood
	price_tag = 4

/datum/reagent/ethanol/devilskiss
	price_tag = 4

/datum/reagent/ethanol/driestmartini
	price_tag = 4

/datum/reagent/ethanol/ginfizz
	price_tag = 4

/datum/reagent/ethanol/grog
	price_tag = 4

/datum/reagent/ethanol/erikasurprise
	price_tag = 4

/datum/reagent/ethanol/gargle_blaster
	price_tag = 4

/datum/reagent/ethanol/gintonic
	price_tag = 4

/datum/reagent/ethanol/hippies_delight
	price_tag = 4

/datum/reagent/ethanol/iced_beer
	price_tag = 4

/datum/reagent/ethanol/irishcarbomb
	price_tag = 4

/datum/reagent/ethanol/coffee/irishcoffee
	price_tag = 4

/datum/reagent/ethanol/longislandicedtea
	price_tag = 4

/datum/reagent/ethanol/manhattan
	price_tag = 4

/datum/reagent/ethanol/manhattan_proj
	price_tag = 4

/datum/reagent/ethanol/manly_dorf
	price_tag = 4

/datum/reagent/ethanol/margarita
	price_tag = 4

/datum/reagent/ethanol/mead
	price_tag = 4

/datum/reagent/ethanol/moonshine
	price_tag = 4

/datum/reagent/ethanol/neurotoxin
	price_tag = 4

/datum/reagent/ethanol/red_mead
	price_tag = 4

/datum/reagent/ethanol/sbiten
	price_tag = 4

/datum/reagent/ethanol/screwdrivercocktail
	price_tag = 4

/datum/reagent/ethanol/silencer
	price_tag = 4

/datum/reagent/ethanol/singulo
	price_tag = 4

/datum/reagent/ethanol/snowwhite
	price_tag = 4

/datum/reagent/ethanol/suidream
	price_tag = 4

/datum/reagent/ethanol/syndicatebomb
	price_tag = 4

/datum/reagent/ethanol/tequila_sunrise
	price_tag = 4

/datum/reagent/ethanol/threemileisland
	price_tag = 4

/datum/reagent/ethanol/toxins_special
	price_tag = 4

/datum/reagent/ethanol/vodkamartini
	price_tag = 4

/datum/reagent/ethanol/vodkatonic
	price_tag = 4

/datum/reagent/ethanol/white_russian
	price_tag = 4

/datum/reagent/ethanol/whiskey_cola
	price_tag = 4

/datum/reagent/ethanol/whiskeysoda
	price_tag = 4

/datum/reagent/ethanol/binmanbliss
	price_tag = 4

/datum/reagent/ethanol/xanaducannon
	price_tag = 4

/datum/reagent/ethanol/balloon
	price_tag = 4

/datum/reagent/ethanol/coffee/elysiumfacepunch
	price_tag = 4

/datum/reagent/ethanol/saketini
	price_tag = 4

/datum/reagent/ethanol/tokyorose
	price_tag = 4

/datum/reagent/ethanol/ginzamary
	price_tag = 4

/datum/reagent/ethanol/tamagozake
	price_tag = 4

/datum/reagent/ethanol/sakebomb
	price_tag = 4

/datum/reagent/ethanol/erebusmoonrise
	price_tag = 4

// The Cheap Shit //

/datum/reagent/ethanol/hooch
	price_tag = 2

/datum/reagent/ethanol/debugger
	price_tag = 2

/datum/reagent/ethanol/spacersbrew
	price_tag = 2

/datum/reagent/ethanol/natunabrandy
	price_tag = 2

// Cocktails without alcohol //

/datum/reagent/ethanol/bananahonk
	price_tag = 3

// From the machine //

/obj/item/reagent_containers/food/drinks/cans/cola

/obj/item/reagent_containers/food/drinks/cans/space_mountain_wind

/obj/item/reagent_containers/food/drinks/cans/dr_gibb

/obj/item/reagent_containers/food/drinks/cans/starkist

/obj/item/reagent_containers/food/drinks/cans/waterbottle

/obj/item/reagent_containers/food/drinks/cans/space_up

/obj/item/reagent_containers/food/drinks/cans/iced_tea

/obj/item/reagent_containers/food/drinks/cans/grape_juice

/obj/item/reagent_containers/food/drinks/cans/gingerale

//***************//
//----Bottles----//
//***************//

// Juices, soda and similar //

/obj/item/reagent_containers/food/drinks/bottle/cola

/obj/item/reagent_containers/food/drinks/bottle/space_up

/obj/item/reagent_containers/food/drinks/bottle/space_mountain_wind

/obj/item/reagent_containers/food/drinks/bottle/orangejuice

/obj/item/reagent_containers/food/drinks/bottle/applejuice

/obj/item/reagent_containers/food/drinks/bottle/cream

/obj/item/reagent_containers/food/drinks/bottle/tomatojuice

/obj/item/reagent_containers/food/drinks/bottle/limejuice


// Beer //

/obj/item/reagent_containers/food/drinks/bottle/small/beer

/obj/item/reagent_containers/food/drinks/bottle/small/ale


// Spirituous Liquors //

/obj/item/reagent_containers/food/drinks/bottle/absinthe

/obj/item/reagent_containers/food/drinks/bottle/bluecuracao

/obj/item/reagent_containers/food/drinks/bottle/gin

/obj/item/reagent_containers/food/drinks/bottle/kahlua

/obj/item/reagent_containers/food/drinks/bottle/melonliquor

/obj/item/reagent_containers/food/drinks/bottle/rum

/obj/item/reagent_containers/food/drinks/bottle/tequila

/obj/item/reagent_containers/food/drinks/bottle/vodka

/obj/item/reagent_containers/food/drinks/bottle/whiskey

/obj/item/reagent_containers/food/drinks/bottle/specialwhiskey

/obj/item/reagent_containers/food/drinks/bottle/patron

/obj/item/reagent_containers/food/drinks/bottle/goldschlager

/obj/item/reagent_containers/food/drinks/bottle/bottleofnothing

/obj/item/reagent_containers/food/drinks/bottle/grenadine


// Wines //

/obj/item/reagent_containers/food/drinks/bottle/wine

/obj/item/reagent_containers/food/drinks/bottle/cognac

/obj/item/reagent_containers/food/drinks/bottle/vermouth

/obj/item/reagent_containers/food/drinks/bottle/pwine

/obj/item/reagent_containers/food/drinks/bottle/sake

/obj/item/reagent_containers/food/drinks/bottle/jager

//***************//
//---Foodstuff---//
//***************//

// Snacks //

/obj/item/reagent_containers/food/snacks/candy

/obj/item/reagent_containers/food/snacks/sosjerky

/obj/item/reagent_containers/food/snacks/unajerky

/obj/item/reagent_containers/food/snacks/cheesiehonkers

CAPABILITIES(/obj/item/reagent_containers/food/snacks/cheesiehonkers)
	configure(atom_rules(price_tag = 1, description_fluff = "The origins of the flourescent orange dust produced by Cheesie Honkers is considered a trade secret, despite having been leaked on the exonet decades ago. It's the cheese."))
	configure(item_handling(center_x = 15, center_y = 9))

/obj/item/reagent_containers/food/snacks/tastybread

/obj/item/reagent_containers/food/snacks/no_raisin

CAPABILITIES(/obj/item/reagent_containers/food/snacks/no_raisin)
	configure(atom_rules(price_tag = 1, description_fluff = "Originally Raisin Blend no. 4, 4noraisins obtained their current name in the Skadi Positronic Exclusion Crisis of 2442, where they were rebranded as part of the protests. The exclusion crisis, so the story goes, involved positronic immigration being banned for no raisin."))
	configure(item_handling(center_x = 15, center_y = 4))

/obj/item/reagent_containers/food/snacks/packaged/spacetwinkie

/obj/item/reagent_containers/food/snacks/skrellsnacks

/obj/item/reagent_containers/food/snacks/chips

/obj/item/reagent_containers/food/drinks/dry_ramen


// Burger //

/obj/item/reagent_containers/food/snacks/brainburger

/obj/item/reagent_containers/food/snacks/ghostburger

CAPABILITIES(/obj/item/reagent_containers/food/snacks/ghostburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))

/obj/item/reagent_containers/food/snacks/human/burger

/obj/item/reagent_containers/food/snacks/cheeseburger

/obj/item/reagent_containers/food/snacks/monkeyburger

/obj/item/reagent_containers/food/snacks/fishburger

/obj/item/reagent_containers/food/snacks/tofuburger

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tofuburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/roburger

CAPABILITIES(/obj/item/reagent_containers/food/snacks/roburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))

/obj/item/reagent_containers/food/snacks/roburgerbig

CAPABILITIES(/obj/item/reagent_containers/food/snacks/roburgerbig)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))

/obj/item/reagent_containers/food/snacks/xenoburger

/obj/item/reagent_containers/food/snacks/clownburger

/obj/item/reagent_containers/food/snacks/mimeburger

CAPABILITIES(/obj/item/reagent_containers/food/snacks/mimeburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))

/obj/item/reagent_containers/food/snacks/spellburger

CAPABILITIES(/obj/item/reagent_containers/food/snacks/spellburger)
	configure(atom_rules(price_tag = 2))

/obj/item/reagent_containers/food/snacks/jellyburger

CAPABILITIES(/obj/item/reagent_containers/food/snacks/jellyburger)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 11))

/obj/item/reagent_containers/food/snacks/bigbiteburger

/obj/item/reagent_containers/food/snacks/superbiteburger


// Sandwiches //

/obj/item/reagent_containers/food/snacks/sandwich

/obj/item/reagent_containers/food/snacks/toastedsandwich

/obj/item/reagent_containers/food/snacks/grilledcheese

/obj/item/reagent_containers/food/snacks/jellysandwich

CAPABILITIES(/obj/item/reagent_containers/food/snacks/jellysandwich)
	configure(atom_rules(price_tag = 3))
	configure(item_handling(center_x = 16, center_y = 8))


// Cookies and Candies //

/obj/item/reagent_containers/food/snacks/cookie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/cookie)
	configure(atom_rules(price_tag = 1))

/obj/item/reagent_containers/food/snacks/chocolatebar

/obj/item/reagent_containers/food/snacks/chocolateegg

/obj/item/reagent_containers/food/snacks/candy_corn

/obj/item/reagent_containers/food/snacks/donut

/obj/item/reagent_containers/food/snacks/donut/chaos

/obj/item/reagent_containers/food/snacks/popcorn

/obj/item/reagent_containers/food/snacks/fortunecookie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/fortunecookie)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 15, center_y = 14))

/obj/item/reagent_containers/food/snacks/candiedapple

CAPABILITIES(/obj/item/reagent_containers/food/snacks/candiedapple)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 15, center_y = 13))

/obj/item/reagent_containers/food/snacks/plumphelmetbiscuit

/obj/item/reagent_containers/food/snacks/chawanmushi

/obj/item/reagent_containers/food/snacks/cracker


// Full meals //

/obj/item/reagent_containers/food/snacks/friedegg

/obj/item/reagent_containers/food/snacks/tofurkey

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tofurkey)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 8))

/obj/item/reagent_containers/food/snacks/carpmeat

/obj/item/reagent_containers/food/snacks/fishfingers

/obj/item/reagent_containers/food/snacks/omelette

/obj/item/reagent_containers/food/snacks/berryclafoutis

CAPABILITIES(/obj/item/reagent_containers/food/snacks/berryclafoutis)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/waffles

CAPABILITIES(/obj/item/reagent_containers/food/snacks/waffles)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 15, center_y = 11))

/obj/item/reagent_containers/food/snacks/eggplantparm

CAPABILITIES(/obj/item/reagent_containers/food/snacks/eggplantparm)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 11))

/obj/item/reagent_containers/food/snacks/soylentgreen

/obj/item/reagent_containers/food/snacks/soylenviridians

CAPABILITIES(/obj/item/reagent_containers/food/snacks/soylenviridians)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 15, center_y = 11))

/obj/item/reagent_containers/food/snacks/wingfangchu

/obj/item/reagent_containers/food/snacks/monkeykabob

/obj/item/reagent_containers/food/snacks/tofukabob

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tofukabob)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 17, center_y = 15))

/obj/item/reagent_containers/food/snacks/cubancarp

/obj/item/reagent_containers/food/snacks/loadedbakedpotato

/obj/item/reagent_containers/food/snacks/fries

/obj/item/reagent_containers/food/snacks/spagetti

/obj/item/reagent_containers/food/snacks/cheesyfries

/obj/item/reagent_containers/food/snacks/enchiladas

/obj/item/reagent_containers/food/snacks/taco

/obj/item/reagent_containers/food/snacks/monkeysdelight

/obj/item/reagent_containers/food/snacks/fishandchips

/obj/item/reagent_containers/food/snacks/rofflewaffles

/obj/item/reagent_containers/food/snacks/stew

/obj/item/reagent_containers/food/snacks/stewedsoymeat

CAPABILITIES(/obj/item/reagent_containers/food/snacks/stewedsoymeat)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/boiledspagetti

CAPABILITIES(/obj/item/reagent_containers/food/snacks/boiledspagetti)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/boiledrice

CAPABILITIES(/obj/item/reagent_containers/food/snacks/boiledrice)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 17, center_y = 11))

/obj/item/reagent_containers/food/snacks/ricepudding

CAPABILITIES(/obj/item/reagent_containers/food/snacks/ricepudding)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 17, center_y = 11))

/obj/item/reagent_containers/food/snacks/pastatomato

/obj/item/reagent_containers/food/snacks/meatballspagetti

/obj/item/reagent_containers/food/snacks/spesslaw

/obj/item/reagent_containers/food/snacks/carrotfries

/obj/item/reagent_containers/food/snacks/appletart

/obj/item/reagent_containers/food/snacks/sliceable/pizza

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/pizza)
	configure(atom_rules(price_tag = 5))

/obj/item/reagent_containers/food/snacks/slice/margherita

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/margherita)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/slice/meatpizza

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/meatpizza)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/slice/mushroompizza

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/mushroompizza)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/slice/vegetablepizza

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/vegetablepizza)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))

// Baked Goods //

/obj/item/reagent_containers/food/snacks/poppypretzel

CAPABILITIES(/obj/item/reagent_containers/food/snacks/poppypretzel)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/baguette

/obj/item/reagent_containers/food/snacks/jelliedtoast

CAPABILITIES(/obj/item/reagent_containers/food/snacks/jelliedtoast)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 8))

/obj/item/reagent_containers/food/snacks/twobread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/twobread)
	configure(atom_rules(price_tag = 2, description_fluff = "The most popular recipe from the Morpheus Cyberkinetics cookbook 'Calories for Organics'"))
	configure(item_handling(center_x = 15, center_y = 12))

/obj/item/reagent_containers/food/snacks/sliceable/meatbread

/obj/item/reagent_containers/food/snacks/slice/meatbread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/meatbread)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 16))

/obj/item/reagent_containers/food/snacks/sliceable/xenomeatbread

/obj/item/reagent_containers/food/snacks/slice/xenomeatbread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/xenomeatbread)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/sliceable/bananabread

/obj/item/reagent_containers/food/snacks/slice/bananabread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/bananabread)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 8))

/obj/item/reagent_containers/food/snacks/sliceable/tofubread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/tofubread)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 9))

/obj/item/reagent_containers/food/snacks/slice/tofubread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/tofubread)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/sliceable/bread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/bread)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 9))

/obj/item/reagent_containers/food/snacks/slice/bread

/obj/item/reagent_containers/food/snacks/sliceable/creamcheesebread

/obj/item/reagent_containers/food/snacks/slice/creamcheesebread

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/creamcheesebread)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))


// Soups //

/obj/item/reagent_containers/food/snacks/meatballsoup

/obj/item/reagent_containers/food/snacks/slimesoup

/obj/item/reagent_containers/food/snacks/bloodsoup

/obj/item/reagent_containers/food/snacks/clownstears

/obj/item/reagent_containers/food/snacks/vegetablesoup

/obj/item/reagent_containers/food/snacks/nettlesoup

/obj/item/reagent_containers/food/snacks/mysterysoup

/obj/item/reagent_containers/food/snacks/wishsoup

/obj/item/reagent_containers/food/snacks/hotchili

/obj/item/reagent_containers/food/snacks/coldchili

/obj/item/reagent_containers/food/snacks/tomatosoup

/obj/item/reagent_containers/food/snacks/milosoup

/obj/item/reagent_containers/food/snacks/mushroomsoup

/obj/item/reagent_containers/food/snacks/beetsoup


// Pies //

/obj/item/reagent_containers/food/snacks/pie

/obj/item/reagent_containers/food/snacks/meatpie

/obj/item/reagent_containers/food/snacks/tofupie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tofupie)
	configure(atom_rules(price_tag = 4))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/plump_pie

/obj/item/reagent_containers/food/snacks/xemeatpie

/obj/item/reagent_containers/food/snacks/applepie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/applepie)
	configure(atom_rules(price_tag = 4))
	configure(item_handling(center_x = 16, center_y = 13))

/obj/item/reagent_containers/food/snacks/cherrypie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/cherrypie)
	configure(atom_rules(price_tag = 4))
	configure(item_handling(center_x = 16, center_y = 11))


// Cakes //

/obj/item/reagent_containers/food/snacks/sliceable/carrotcake

/obj/item/reagent_containers/food/snacks/slice/carrotcake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/carrotcake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/braincake

/obj/item/reagent_containers/food/snacks/slice/braincake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/braincake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 12))

/obj/item/reagent_containers/food/snacks/sliceable/cheesecake

/obj/item/reagent_containers/food/snacks/slice/cheesecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/cheesecake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/plaincake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/plaincake)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/plaincake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/plaincake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/orangecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/orangecake)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/orangecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/orangecake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/limecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/limecake)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/limecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/limecake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/lemoncake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/lemoncake)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/lemoncake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/lemoncake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/chocolatecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/chocolatecake)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/chocolatecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/chocolatecake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/birthdaycake

/obj/item/reagent_containers/food/snacks/slice/birthdaycake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/birthdaycake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/applecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/applecake)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/applecake

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/applecake)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/sliceable/pumpkinpie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/pumpkinpie)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/snacks/slice/pumpkinpie

CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/pumpkinpie)
	configure(atom_rules(price_tag = 1))
	configure(item_handling(center_x = 16, center_y = 12))


// Misc //

/obj/item/reagent_containers/food/snacks/boiledegg

/obj/item/reagent_containers/food/snacks/donkpocket

/obj/item/reagent_containers/food/snacks/sausage

/obj/item/reagent_containers/food/snacks/muffin

CAPABILITIES(/obj/item/reagent_containers/food/snacks/muffin)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 17, center_y = 4))

/obj/item/reagent_containers/food/snacks/tossedsalad

CAPABILITIES(/obj/item/reagent_containers/food/snacks/tossedsalad)
	configure(atom_rules(price_tag = 2))
	configure(item_handling(center_x = 17, center_y = 11))

/obj/item/reagent_containers/food/snacks/validsalad

/obj/item/reagent_containers/food/snacks/dionaroast

/obj/item/pizzabox/get_item_cost()
	return pizza?.get_item_cost()


//***************//
//----Smokes-----//
//***************//

/obj/item/storage/fancy/cigarettes

/obj/item/storage/fancy/cigarettes/luckystars

/obj/item/storage/fancy/cigarettes/jerichos

/obj/item/storage/fancy/cigarettes/menthols

/obj/item/storage/fancy/cigar

/obj/item/storage/fancy/cigarettes/carcinomas

/obj/item/storage/fancy/cigarettes/professionals

/obj/item/storage/box/matches

/obj/item/flame/lighter

/obj/item/flame/lighter/zippo

//******************************//
//|IN THIS MOMENT I AM EUPHORIC|//
//******************************//

/datum/reagent/ethanol/euphoria
	price_tag = 30


/datum/reagent/ethanol/snaps
	price_tag = 5

/obj/item/storage/fancy/cigarettes/yw/mauser
