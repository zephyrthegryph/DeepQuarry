/* Alcohol */

// Basic

/datum/reagent/ethanol/absinthe
	name = REAGENT_ABSINTHE
	id = REAGENT_ID_ABSINTHE
	description = "Watch out that the Green Fairy doesn't come for you!"
	taste_description = "licorice"
	taste_mult = 1.5
	color = "#33EE00"
	strength = 12

	glass_name = REAGENT_ID_ABSINTHE
	glass_desc = "Wormwood, anise, oh my."

/datum/reagent/ethanol/ale
	name = REAGENT_ALE
	id = REAGENT_ID_ALE
	description = "A dark alcoholic beverage made by malted barley and yeast."
	taste_description = "hearty barley ale"
	color = "#4C3100"
	strength = 50

	glass_name = REAGENT_ID_ALE
	glass_desc = "A freezing pint of delicious ale"

	allergen_type = ALLERGEN_GRAINS //Barley is grain

/datum/reagent/ethanol/bluecuracao
	name = REAGENT_BLUECURACAO
	id = REAGENT_ID_BLUECURACAO
	description = "Exotically blue, fruity drink, distilled from oranges."
	taste_description = "oranges"
	taste_mult = 1.1
	color = "#0000CD"
	strength = 15

	glass_name = "blue curacao"
	glass_desc = "Exotically blue, fruity drink, distilled from oranges."

	allergen_type = ALLERGEN_FRUIT //Made from oranges(fruit)

/datum/reagent/ethanol/cognac
	name = REAGENT_COGNAC
	id = REAGENT_ID_COGNAC
	description = "A sweet and strongly alchoholic drink, made after numerous distillations and years of maturing. Classy as fornication."
	taste_description = "rich and smooth alcohol"
	taste_mult = 1.1
	color = "#AB3C05"
	strength = 15

	glass_name = REAGENT_ID_COGNAC
	glass_desc = "Damn, you feel like some kind of French aristocrat just by holding this."

	allergen_type = ALLERGEN_FRUIT //Cognac is made from wine which is made from grapes.

/datum/reagent/ethanol/firepunch
	name = REAGENT_FIREPUNCH
	id = REAGENT_ID_FIREPUNCH
	description = "Yo ho ho and a jar of honey."
	taste_description = "sharp butterscotch"
	color = "#ECB633"
	strength = 7

	glass_name = "fire punch"
	glass_desc = "Yo ho ho and a jar of honey."

/datum/reagent/ethanol/gin
	name = REAGENT_GIN
	id = REAGENT_ID_GIN
	description = "It's gin. In space. I say, good sir."
	taste_description = "an alcoholic christmas tree"
	color = "#0064C6"
	strength = 50

	glass_name = REAGENT_ID_GIN
	glass_desc = "A crystal clear glass of Griffeater gin."

	allergen_type = ALLERGEN_FRUIT //Made from juniper berries

/datum/reagent/ethanol/melonliquor
	name = REAGENT_MELONLIQUOR
	id = REAGENT_ID_MELONLIQUOR
	description = "A relatively sweet and fruity 46 proof liquor."
	taste_description = "fruity alcohol"
	color = "#138808" // rgb: 19, 136, 8
	strength = 50

	glass_name = "melon liquor"
	glass_desc = "A relatively sweet and fruity 46 proof liquor."

	allergen_type = ALLERGEN_FRUIT //Made from watermelons

/datum/reagent/ethanol/melonspritzer
	name = REAGENT_MELONSPRITZER
	id = REAGENT_ID_MELONSPRITZER
	description = "Melons: Citrus style."
	taste_description = "sour melon"
	color = "#934D5D"
	strength = 10

	glass_name = "melon spritzer"
	glass_desc = "Melons: Citrus style."
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_FRUIT //Made from watermelon juice, apple juice, and lime juice

/datum/reagent/ethanol/rum
	name = REAGENT_RUM
	id = REAGENT_ID_RUM
	description = "Yo-ho-ho and all that."
	taste_description = "spiked butterscotch"
	taste_mult = 1.1
	color = "#ECB633"
	strength = 15

	glass_name = REAGENT_ID_RUM
	glass_desc = "Makes you want to buy a ship and just go pillaging."

/datum/reagent/ethanol/sake //Made from rice, yes. Rice is technically a grain, but also kinda a psuedo-grain, so I don't count it for grain allergies.
	name = REAGENT_SAKE
	id = REAGENT_ID_SAKE
	description = "Anime's favorite drink."
	taste_description = "dry alcohol"
	color = "#DDDDDD"
	strength = 25

	glass_name = REAGENT_ID_SAKE
	glass_desc = "A glass of sake."

/datum/reagent/ethanol/sexonthebeach
	name = REAGENT_SEXONTHEBEACH
	id = REAGENT_ID_SEXONTHEBEACH
	description = "A concoction of vodka and a secret combination of orange juice and pomegranate."
	taste_description = "60% orange juice, 40% pomegranate, 100% alcohol"
	color = "#7051E3"
	strength = 15

	glass_name = "sex on the beach"
	glass_desc = "A concoction of vodka and a secret combination of orange juice and pomegranate."

	allergen_type = ALLERGEN_FRUIT //Made from orange juice

/datum/reagent/ethanol/tequila
	name = REAGENT_TEQUILA
	id = REAGENT_ID_TEQUILA
	description = "A strong and mildly flavored, Mexican produced spirit. Feeling thirsty hombre?"
	taste_description = "paint thinner"
	color = "#FFFF91"
	strength = 25

	glass_name = "Tequilla"
	glass_desc = "Now all that's missing is the weird colored shades!"

/datum/reagent/ethanol/vermouth
	name = REAGENT_VERMOUTH
	id = REAGENT_ID_VERMOUTH
	description = "You suddenly feel a craving for a martini..."
	taste_description = "dry alcohol"
	taste_mult = 1.3
	color = "#91FF91" // rgb: 145, 255, 145
	strength = 15

	glass_name = REAGENT_ID_VERMOUTH
	glass_desc = "You wonder why you're even drinking this straight."
	allergen_type = ALLERGEN_FRUIT //Vermouth is made from wine which is made from grapes(fruit)

/datum/reagent/ethanol/whiskey
	name = REAGENT_WHISKEY
	id = REAGENT_ID_WHISKEY
	description = "A superb and well-aged single-malt whiskey. Damn."
	taste_description = "molasses"
	color = "#4C3100"
	strength = 25

	glass_name = REAGENT_ID_WHISKEY
	glass_desc = "The silky, smokey whiskey goodness inside the glass makes the drink look very classy."

	allergen_type = ALLERGEN_GRAINS //Whiskey is also made from grain.

/datum/reagent/ethanol/redwine
	name = REAGENT_REDWINE
	id = REAGENT_ID_REDWINE
	description = "An premium alchoholic beverage made from distilled grape juice."
	taste_description = "bitter sweetness"
	color = "#7E4043" // rgb: 126, 64, 67
	strength = 15

	glass_name = "red wine"
	glass_desc = "A very classy looking drink."

	allergen_type = ALLERGEN_FRUIT //Wine is made from grapes (fruit)

/datum/reagent/ethanol/whitewine
	name = REAGENT_WHITEWINE
	id = REAGENT_ID_WHITEWINE
	description = "An premium alchoholic beverage made from fermenting of the non-coloured pulp of grapes."
	taste_description = "light fruity flavor"
	color = "#F4EFB0" // rgb: 244, 239, 176
	strength = 15

	glass_name = "white wine"
	glass_desc = "A very classy looking drink."

	allergen_type = ALLERGEN_FRUIT //Wine is made from grapes (fruit)

/datum/reagent/ethanol/carnoth
	name = REAGENT_CARNOTH
	id = REAGENT_ID_CARNOTH
	description = "An premium alchoholic beverage made with multiple hybridized species of grapes that give it a dark maroon coloration."
	taste_description = "alcoholic sweet flavor"
	color = "#5B0000" // rgb: 0, 100, 35
	strength = 20

	glass_name = REAGENT_ID_CARNOTH
	glass_desc = "A very classy looking drink."

	allergen_type = ALLERGEN_FRUIT //Wine is made from grapes (fruit)

/datum/reagent/ethanol/wine
	name = REAGENT_DEVELOPER_WARNING // Unit test ignore
	id = REAGENT_ID_DEVELOPER_WARNING

/datum/reagent/ethanol/wine/champagne
	name = REAGENT_CHAMPAGNE
	id = REAGENT_ID_CHAMPAGNE
	description = "A sparkling wine made with Pinot Noir, Pinot Meunier, and Chardonnay."
	taste_description = "fizzy bitter sweetness"
	color = "#D1B166"

	glass_name = REAGENT_ID_CHAMPAGNE
	glass_desc = "An even classier looking drink."

	allergen_type = ALLERGEN_FRUIT //Still wine, and still made from grapes (fruit)

/datum/reagent/ethanol/cider
	name = REAGENT_CIDER
	id = REAGENT_ID_CIDER
	description = "Hard? Soft? No-one knows but it'll get you drunk."
	taste_description = "tartness"
	color = "#CE9C00" // rgb: 206, 156, 0
	strength = 10

	glass_name = REAGENT_ID_CIDER
	glass_desc = "The second most Irish drink."
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_FRUIT //Made from fruit

// Cocktails


/datum/reagent/ethanol/acid_spit
	name = REAGENT_ACIDSPIT
	id = REAGENT_ID_ACIDSPIT
	description = "A drink for the daring, can be deadly if incorrectly prepared!"
	taste_description = "bitter tang"
	reagent_state = LIQUID
	color = "#365000"
	strength = 30

	glass_name = REAGENT_ACIDSPIT
	glass_desc = "A drink from the company archives. Made from live aliens."

	allergen_type = ALLERGEN_FRUIT //Made from wine (fruit)

/datum/reagent/ethanol/alliescocktail
	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from vodka(grain) as well as martini(vermouth(fruit) and gin(fruit))

/datum/reagent/ethanol/aloe
	name = REAGENT_ALOE
	id = REAGENT_ID_ALOE
	description = "So very, very, very good."
	taste_description = "sweet and creamy"
	color = "#B7EA75"
	strength = 15

	glass_name = REAGENT_ALOE
	glass_desc = "Very, very, very good."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY|ALLERGEN_GRAINS //Made from cream(dairy), whiskey(grains), and watermelon juice(fruit)

/datum/reagent/ethanol/amasec
	name = REAGENT_AMASEC
	id = REAGENT_ID_AMASEC
	description = "Official drink of the Gun Club!"
	taste_description = "dark and metallic"
	reagent_state = LIQUID
	color = "#FF975D"
	strength = 25

	glass_name = REAGENT_AMASEC
	glass_desc = "Always handy before combat!"

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from wine(fruit) and vodka(grains)

/datum/reagent/ethanol/andalusia
	name = REAGENT_ANDALUSIA
	id = REAGENT_ID_ANDALUSIA
	description = "A nice, strangely named drink."
	taste_description = "lemons"
	color = "#F4EA4A"
	strength = 15

	glass_name = REAGENT_ANDALUSIA
	glass_desc = "A nice, strange named drink."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from whiskey(grains) and lemonjuice (fruit)

/datum/reagent/ethanol/antifreeze
	name = REAGENT_ANTIFREEZE
	id = REAGENT_ID_ANTIFREEZE
	description = "Ultimate refreshment."
	taste_description = "ice cold vodka"
	color = "#56DEEA"
	strength = 12
	adj_temp = 20
	targ_temp = 330

	glass_name = REAGENT_ANTIFREEZE
	glass_desc = "The ultimate refreshment."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_DAIRY //Made from vodka(grains) and cream(dairy)

/datum/reagent/ethanol/atomicbomb
	name = REAGENT_ATOMICBOMB
	id = REAGENT_ID_ATOMICBOMB
	description = "Nuclear proliferation never tasted so good."
	taste_description = "coffee, almonds, and whiskey, with a kick"
	reagent_state = LIQUID
	color = "#666300"
	strength = 10
	druggy = 50

	glass_name = REAGENT_ATOMICBOMB
	glass_desc = "We cannot take legal responsibility for your actions after imbibing."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_DAIRY|ALLERGEN_FRUIT|ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from b52 which contains kahlua(coffee/caffeine), cognac(fruit), and irish cream(Whiskey(grains),cream(dairy))

/datum/reagent/ethanol/bahama_mama
	name = REAGENT_BAHAMAMAMA
	id = REAGENT_ID_BAHAMAMAMA
	description = "Tropical cocktail."
	taste_description = "lime and orange"
	color = "#FF7F3B"
	strength = 25

	glass_name = "Bahama Mama"
	glass_desc = "Tropical cocktail."

	allergen_type = ALLERGEN_FRUIT //Made from orange juice and lime juice

/datum/reagent/ethanol/bananahonk
	name = REAGENT_BANANAHONK
	id = REAGENT_ID_BANANAHONK
	description = "A drink from " + JOB_CLOWN + " Heaven."
	taste_description = "bananas and sugar"
	nutriment_factor = 1
	color = "#FFFF91"
	strength = 12

	glass_name = "Banana Honk"
	glass_desc = "A drink from Banana Heaven."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_DAIRY //Made from banana juice(fruit) and cream(dairy)

/datum/reagent/ethanol/barefoot
	name = REAGENT_BAREFOOT
	id = REAGENT_ID_BAREFOOT
	description = "Barefoot and pregnant."
	taste_description = "creamy berries"
	color = "#FFCDEA"
	strength = 30

	glass_name = REAGENT_BAREFOOT
	glass_desc = "Barefoot and pregnant."

	allergen_type = ALLERGEN_DAIRY|ALLERGEN_FRUIT //Made from berry juice (fruit), cream(dairy), and vermouth(fruit)

/datum/reagent/ethanol/bilk
	name = REAGENT_BILK
	id = REAGENT_ID_BILK
	description = "This appears to be beer mixed with milk. Disgusting."
	taste_description = "sour milk"
	color = "#895C4C"
	strength = 50
	nutriment_factor = 2

	glass_name = REAGENT_ID_BILK
	glass_desc = "A brew of milk and beer. For those alcoholics who fear osteoporosis."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_DAIRY //Made from milk(dairy) and beer(grains)

/datum/reagent/ethanol/black_russian
	name = REAGENT_BLACKRUSSIAN
	id = REAGENT_ID_BLACKRUSSIAN
	description = "For the lactose-intolerant. Still as classy as a White Russian."
	taste_description = "coffee"
	color = "#360000"
	strength = 15

	glass_name = REAGENT_BLACKRUSSIAN
	glass_desc = "For the lactose-intolerant. Still as classy as a White Russian."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from vodka(grains) and kahlua(coffee/caffeine)

/datum/reagent/ethanol/bloody_mary
	name = REAGENT_BLOODYMARY
	id = REAGENT_ID_BLOODYMARY
	description = "A strange yet pleasurable mixture made of vodka, tomato and lime juice. Or at least you THINK the red stuff is tomato juice."
	taste_description = "tomatoes with a hint of lime"
	color = "#B40000"
	strength = 15

	glass_name = REAGENT_BLOODYMARY
	glass_desc = "Tomato juice, mixed with Vodka and a lil' bit of lime. Tastes like liquid murder."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from vodka (grains), tomato juice(fruit), and lime juice(fruit)

/datum/reagent/ethanol/booger
	name = REAGENT_BOOGER
	id = REAGENT_ID_BOOGER
	description = "Ewww..."
	taste_description = "sweet 'n creamy"
	color = "#8CFF8C"
	strength = 30

	glass_name = REAGENT_BOOGER
	glass_desc = "Ewww..."

	allergen_type = ALLERGEN_DAIRY|ALLERGEN_FRUIT //Made from cream(dairy), banana juice(fruit), and watermelon juice(fruit)

/datum/reagent/ethanol/changeling_sting
	name = REAGENT_CHANGELINGSTING
	id = REAGENT_ID_CHANGELINGSTING
	description = "You take a tiny sip and feel a burning sensation..."
	taste_description = "constantly changing flavors"
	color = "#2E6671"
	strength = 10

	glass_name = REAGENT_CHANGELINGSTING
	glass_desc = "A stingy drink."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from screwdriver(vodka(grains), orange juice(fruit)), lime juice(fruit), and lemon juice(fruit)

/datum/reagent/ethanol/martini
	name = REAGENT_MARTINI
	id = REAGENT_ID_MARTINI
	description = "Vermouth with Gin. Not quite how 007 enjoyed it, but still delicious."
	taste_description = "dry class"
	color = "#0064C8"
	strength = 25

	glass_name = "classic martini"
	glass_desc = "Damn, the bartender even stirred it, not shook it."

	allergen_type = ALLERGEN_FRUIT //Made from gin(fruit) and vermouth(fruit)

/datum/reagent/ethanol/cuba_libre
	name = REAGENT_CUBALIBRE
	id = REAGENT_ID_CUBALIBRE
	description = "Rum, mixed with cola and a splash of lime. Viva la revolucion."
	taste_description = "cola with lime"
	nutriment_factor = 1.5
	color = "#3E1B00"
	strength = 30

	glass_name = REAGENT_CUBALIBRE
	glass_desc = "A classic mix of rum, cola, and lime."
	allergen_type = ALLERGEN_STIMULANT //Cola

/datum/reagent/ethanol/rum_and_cola
	name = REAGENT_RUMANDCOLA
	id = REAGENT_ID_RUMANDCOLA
	description = "A classic mix of sugar with more sugar."
	taste_description = "cola"
	color = "#3E1B00"
	strength = 30

	glass_name = "rum and cola"
	glass_desc = "A classic mix of rum and cola."

/datum/reagent/ethanol/demonsblood
	name = REAGENT_DEMONSBLOOD
	id = REAGENT_ID_DEMONSBLOOD
	description = "This thing makes the hair on the back of your neck stand up."
	taste_description = "sweet tasting iron"
	taste_mult = 1.5
	nutriment_factor = 1.5
	color = "#820000"
	strength = 15

	glass_name = "Demons' Blood"
	glass_desc = "Just looking at this thing makes the hair on the back of your neck stand up."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Made from space mountain wind(fruit) and dr.gibb(caffeine)

/datum/reagent/ethanol/devilskiss
	name = REAGENT_DEVILSKISS
	id = REAGENT_ID_DEVILSKISS
	description = "Creepy time!"
	taste_description = "bitter iron"
	color = "#A68310"
	strength = 15

	glass_name = "Devil's Kiss"
	glass_desc = "Creepy time!"
	allergen_type = ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Made from kahlua (Coffee)

/datum/reagent/ethanol/driestmartini
	name = REAGENT_DRIESTMARTINI
	id = REAGENT_ID_DRIESTMARTINI
	description = "Only for the experienced. You think you see sand floating in the glass."
	taste_description = "a beach"
	nutriment_factor = 1
	color = "#2E6671"
	strength = 12

	glass_name = REAGENT_DRIESTMARTINI
	glass_desc = "Only for the experienced. You think you see sand floating in the glass."
	allergen_type = ALLERGEN_FRUIT //Made from gin(fruit)

/datum/reagent/ethanol/ginfizz
	name = REAGENT_GINFIZZ
	id = REAGENT_ID_GINFIZZ
	description = "Refreshingly lemony, deliciously dry."
	taste_description = "dry, tart lemons"
	color = "#FFFFAE"
	strength = 30

	glass_name = "gin fizz"
	glass_desc = "Refreshingly lemony, deliciously dry."

	allergen_type = ALLERGEN_FRUIT //Made from gin(fruit) and lime juice(fruit)

/datum/reagent/ethanol/grog
	name = REAGENT_GROG
	id = REAGENT_ID_GROG
	description = "Watered-down rum, pirate approved!"
	taste_description = "a poor excuse for alcohol"
	reagent_state = LIQUID
	color = "#FFBB00"
	strength = 100

	glass_name = REAGENT_ID_GROG
	glass_desc = "A fine and cepa drink for Space."

/datum/reagent/ethanol/erikasurprise
	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from ale (grains), lime juice (fruit), whiskey(grains), banana juice(fruit)

/datum/reagent/ethanol/gargle_blaster
	name = REAGENT_GARGLEBLASTER
	id = REAGENT_ID_GARGLEBLASTER
	description = "Whoah, this stuff looks volatile!"
	taste_description = "your brains smashed out by a lemon wrapped around a gold brick"
	taste_mult = 5
	reagent_state = LIQUID
	color = "#7F00FF"
	strength = 10
	druggy = 15

	glass_name = REAGENT_GARGLEBLASTER
	glass_desc = "Does... does this mean that Arthur and Ford are on the station? Oh joy."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from vodka(grains), gin(fruit), whiskey(grains), cognac(fruit), and lime juice(fruit)

/datum/reagent/ethanol/gintonic
	name = REAGENT_GINTONIC
	id = REAGENT_ID_GINTONIC
	description = "An all time classic, mild cocktail."
	taste_description = "mild and tart"
	color = "#0064C8"
	strength = 50

	glass_name = "gin and tonic"
	glass_desc = "A mild but still great cocktail. Drink up, like a true Englishman."

	allergen_type = ALLERGEN_FRUIT //Made from gin(fruit)

/datum/reagent/ethanol/goldschlager
	name = REAGENT_GOLDSCHLAGER
	id = REAGENT_ID_GOLDSCHLAGER
	description = "100 proof cinnamon schnapps, made for alcoholic teen girls on spring break."
	taste_description = "burning cinnamon"
	taste_mult = 1.3
	color = "#F4E46D"
	strength = 15

	glass_name = REAGENT_GOLDSCHLAGER
	glass_desc = "100 proof that teen girls will drink anything with gold in it."

	allergen_type = ALLERGEN_GRAINS //Made from vodka(grains)

/datum/reagent/ethanol/hippies_delight
	name = REAGENT_HIPPIESDELIGHT
	id = REAGENT_ID_HIPPIESDELIGHT
	description = "You just don't get it maaaan."
	taste_description = "giving peace a chance"
	reagent_state = LIQUID
	color = "#FF88FF"
	strength = 15
	druggy = 50

	glass_name = "Hippie's Delight"
	glass_desc = "A drink enjoyed by people during the 1960's."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from gargle blaster which contains vodka(grains), gin(fruit), whiskey(grains), cognac(fruit), and lime juice(fruit)
	//Also, yes. Mushrooms produce psilocybin; however, it's also still just a chemical compound, and not necessarily going to trigger a fungi allergy.

/datum/reagent/ethanol/hooch
	name = REAGENT_HOOCH
	id = REAGENT_ID_HOOCH
	description = "Either someone's failure at cocktail making or attempt in alchohol production. In any case, do you really want to drink that?"
	taste_description = "pure alcohol"
	color = "#4C3100"
	strength = 25
	toxicity = 2

	glass_name = REAGENT_HOOCH
	glass_desc = "You've really hit rock bottom now... your liver packed its bags and left last night."

/datum/reagent/ethanol/iced_beer
	name = REAGENT_ICEDBEER
	id = REAGENT_ID_ICEDBEER
	description = "A beer which is so cold the air around it freezes."
	taste_description = "refreshingly cold"
	color = "#FFD300"
	strength = 50
	adj_temp = -20
	targ_temp = 280

	glass_name = "iced beer"
	glass_desc = "A beer so frosty, the air around it freezes."
	glass_special = list(DRINK_ICE)
	allergen_type = ALLERGEN_GRAINS //Made from beer(grains)

/datum/reagent/ethanol/irishcarbomb
	name = REAGENT_IRISHCARBOMB
	id = REAGENT_ID_IRISHCARBOMB
	description = "Mmm, tastes like chocolate cake..."
	taste_description = "delicious anger"
	color = "#2E6671"
	strength = 15

	glass_name = REAGENT_IRISHCARBOMB
	glass_desc = "An irish car bomb."

	allergen_type = ALLERGEN_DAIRY|ALLERGEN_GRAINS //Made from ale(grains) and irish cream(whiskey(grains), cream(dairy))

/datum/reagent/ethanol/irish_cream
	name = REAGENT_IRISHCREAM
	id = REAGENT_ID_IRISHCREAM
	description = "Whiskey-imbued cream, what else would you expect from the Irish."
	taste_description = "creamy alcohol"
	color = "#DDD9A3"
	strength = 25

	glass_name = "Irish cream"
	glass_desc = "It's cream, mixed with whiskey. What else would you expect from the Irish?"

	allergen_type = ALLERGEN_DAIRY|ALLERGEN_GRAINS //Made from cream(dairy) and whiskey(grains)

/datum/reagent/ethanol/longislandicedtea
	name = REAGENT_LONGISLANDICEDTEA
	id = REAGENT_ID_LONGISLANDICEDTEA
	description = "The liquor cabinet, brought together in a delicious mix. Intended for middle-aged alcoholic women only."
	taste_description = "sweet tea, with a kick"
	color = "#895B1F"
	strength = 12

	glass_name = "Long Island iced tea"
	glass_desc = "The liquor cabinet, brought together in a delicious mix. Intended for middle-aged alcoholic women only."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Made from vodka(grains), cola(caffeine) and gin(fruit)

/datum/reagent/ethanol/manhattan
	name = REAGENT_MANHATTAN
	id = REAGENT_ID_MANHATTAN
	description = "The Detective's undercover drink of choice. He never could stomach gin..."
	taste_description = "mild dryness"
	color = "#C13600"
	strength = 15

	glass_name = REAGENT_MANHATTAN
	glass_desc = "The Detective's undercover drink of choice. He never could stomach gin..."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from whiskey(grains), and vermouth(fruit)

/datum/reagent/ethanol/manhattan_proj
	name = REAGENT_MANHATTANPROJ
	id = REAGENT_ID_MANHATTANPROJ
	description = "A scientist's drink of choice, for pondering ways to blow up the station."
	taste_description = "death, the destroyer of worlds"
	color = "#C15D00"
	strength = 10
	druggy = 30

	glass_name = REAGENT_MANHATTANPROJ
	glass_desc = "A scientist's drink of choice, for thinking how to blow up the station."
	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from manhattan which is made from whiskey(grains), and vermouth(fruit)

/datum/reagent/ethanol/manly_dorf
	name = REAGENT_MANLYDORF
	id = REAGENT_ID_MANLYDORF
	description = "Beer and Ale, brought together in a delicious mix. Intended for true men only."
	taste_description = "hair on your chest and your chin"
	color = "#4C3100"
	strength = 25

	glass_name = REAGENT_MANLYDORF
	glass_desc = "A manly concotion made from Ale and Beer. Intended for true men only."

	allergen_type = ALLERGEN_GRAINS //Made from beer(grains) and ale(grains)

/datum/reagent/ethanol/margarita
	name = REAGENT_MARGARITA
	id = REAGENT_ID_MARGARITA
	description = "On the rocks with salt on the rim. Arriba~!"
	taste_description = "dry and salty"
	color = "#8CFF8C"
	strength = 15

	glass_name = REAGENT_ID_MARGARITA
	glass_desc = "On the rocks with salt on the rim. Arriba~!"

	allergen_type = ALLERGEN_FRUIT | ALLERGEN_SALT //Made from lime juice(fruit)

/datum/reagent/ethanol/mead
	name = REAGENT_MEAD
	id = REAGENT_ID_MEAD
	description = "A Viking's drink, though a cheap one."
	taste_description = "sweet yet alcoholic"
	reagent_state = LIQUID
	color = "#FFBB00"
	strength = 30
	nutriment_factor = 1

	glass_name = REAGENT_ID_MEAD
	glass_desc = "A Viking's beverage, though a cheap one."

/datum/reagent/ethanol/moonshine
	name = REAGENT_MOONSHINE
	id = REAGENT_ID_MOONSHINE
	description = "You've really hit rock bottom now... your liver packed its bags and left last night."
	taste_description = "bitterness"
	taste_mult = 2.5
	color = "#0064C8"
	strength = 12

	glass_name = REAGENT_ID_MOONSHINE
	glass_desc = "You've really hit rock bottom now... your liver packed its bags and left last night."

/datum/reagent/ethanol/patron
	name = REAGENT_PATRON
	id = REAGENT_ID_PATRON
	description = "Tequila with silver in it, a favorite of alcoholic women in the club scene."
	taste_description = "metallic paint thinner"
	color = "#585840"
	strength = 30

	glass_name = REAGENT_PATRON
	glass_desc = "Drinking patron in the bar, with all the subpar ladies."

/datum/reagent/ethanol/red_mead
	name = REAGENT_REDMEAD
	id = REAGENT_ID_REDMEAD
	description = "The true Viking's drink! Even though it has a strange red color."
	taste_description = "sweet and salty alcohol"
	color = "#C73C00"
	strength = 30

	glass_name = "red mead"
	glass_desc = "A true Viking's beverage, though its color is strange."

	allergen_type = ALLERGEN_SALT

/datum/reagent/ethanol/sbiten
	name = REAGENT_SBITEN
	id = REAGENT_ID_SBITEN
	description = "A spicy Vodka! Might be a bit hot for the little guys!"
	taste_description = "hot and spice"
	color = "#FFA371"
	strength = 15
	adj_temp = 50
	targ_temp = 360

	glass_name = REAGENT_SBITEN
	glass_desc = "A spicy mix of Vodka and Spice. Very hot."

	allergen_type = ALLERGEN_GRAINS //Made from vodka(grains)

/datum/reagent/ethanol/silencer
	name = REAGENT_SILENCER
	id = REAGENT_ID_SILENCER
	description = "A drink from " + JOB_MIME + " Heaven."
	taste_description = "a pencil eraser"
	taste_mult = 1.2
	nutriment_factor = 1
	color = "#FFFFFF"
	strength = 12

	glass_name = REAGENT_SILENCER
	glass_desc = "A drink from mime Heaven."
	allergen_type = ALLERGEN_DAIRY //Made from cream (dairy)

/datum/reagent/ethanol/singulo
	name = REAGENT_SINGULO
	id = REAGENT_ID_SINGULO
	description = "A blue-space beverage!"
	taste_description = "concentrated matter"
	color = "#2E6671"
	strength = 10

	glass_name = REAGENT_SINGULO
	glass_desc = "A blue-space beverage."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from vodka(grains) and wine(fruit)

/datum/reagent/ethanol/snowwhite
	name = REAGENT_SNOWWHITE
	id = REAGENT_ID_SNOWWHITE
	description = "A cold refreshment"
	taste_description = "refreshing cold"
	nutriment_factor = 1.5
	color = "#FFFFFF"
	strength = 30

	glass_name = REAGENT_SNOWWHITE
	glass_desc = "A cold refreshment."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_FRUIT|ALLERGEN_STIMULANT //made from Pineapple juice(fruit), lemon_lime(fruit), and kahlua(coffee/caffine)

/datum/reagent/ethanol/suidream
	name = REAGENT_SUIDREAM
	id = REAGENT_ID_SUIDREAM
	description = "Comprised of: White soda, blue curacao, melon liquor."
	taste_description = "fruit"
	nutriment_factor = 1.5
	color = "#00A86B"
	strength = 100

	glass_name = REAGENT_SUIDREAM
	glass_desc = "A froofy, fruity, and sweet mixed drink. Understanding the name only brings shame."

	allergen_type = ALLERGEN_FRUIT //Made from blue curacao(fruit) and melon liquor(fruit)

/datum/reagent/ethanol/syndicatebomb
	name = REAGENT_SYNDICATEBOMB
	id = REAGENT_ID_SYNDICATEBOMB
	description = "Tastes like terrorism!"
	taste_description = "strong alcohol"
	color = "#2E6671"
	strength = 10

	glass_name = REAGENT_SYNDICATEBOMB
	glass_desc = "Tastes like terrorism!"

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from beer(grain) and whiskeycola(whiskey(grain) and cola(caffeine))

/datum/reagent/ethanol/tequila_sunrise
	name = REAGENT_TEQUILASUNRISE
	id = REAGENT_ID_TEQUILASUNRISE
	description = "Tequila and orange juice. Much like a Screwdriver, only Mexican~."
	taste_description = "oranges"
	color = "#FFE48C"
	strength = 25

	glass_name = "Tequilla Sunrise"
	glass_desc = "Oh great, now you feel nostalgic about sunrises back on Earth..."

/datum/reagent/ethanol/threemileisland
	name = REAGENT_THREEMILEISLAND
	id = REAGENT_ID_THREEMILEISLAND
	description = "Made for a woman, strong enough for a man."
	taste_description = "dry"
	color = "#666340"
	strength = 10
	druggy = 50

	glass_name = "Three Mile Island iced tea"
	glass_desc = "A glass of this is sure to prevent a meltdown."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from long island iced tea(vodka(grains) and gin(fruit))

/datum/reagent/ethanol/toxins_special
	name = REAGENT_PHORONSPECIAL
	id = REAGENT_ID_PHORONSPECIAL
	description = "This thing is literally on fire!"
	taste_description = "spicy toxins"
	reagent_state = LIQUID
	color = "#7F00FF"
	strength = 10
	adj_temp = 15
	targ_temp = 330

	glass_name = REAGENT_PHORONSPECIAL
	glass_desc = "Whoah, this thing is on fire!"

	allergen_type = ALLERGEN_FRUIT //Made from vermouth(fruit)

/datum/reagent/ethanol/vodkamartini
	name = REAGENT_VODKAMARTINI
	id = REAGENT_ID_VODKAMARTINI
	description = "Vodka with Gin. Not quite how 007 enjoyed it, but still delicious."
	taste_description = "shaken, not stirred"
	color = "#0064C8"
	strength = 12

	glass_name = "vodka martini"
	glass_desc ="A bastardization of the classic martini. Still great."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //made from vodka(grains) and vermouth(fruit)

/datum/reagent/ethanol/vodkatonic
	name = REAGENT_VODKATONIC
	id = REAGENT_ID_VODKATONIC
	description = "For when a gin and tonic isn't Russian enough."
	taste_description = "tart bitterness"
	color = "#0064C8" // rgb: 0, 100, 200
	strength = 15

	glass_name = "vodka and tonic"
	glass_desc = "For when a gin and tonic isn't Russian enough."

	allergen_type = ALLERGEN_GRAINS //Made from vodka(grains)

/datum/reagent/ethanol/white_russian
	name = REAGENT_WHITERUSSIAN
	id = REAGENT_ID_WHITERUSSIAN
	description = "That's just, like, your opinion, man..."
	taste_description = "coffee icecream"
	color = "#A68340"
	strength = 15

	glass_name = REAGENT_WHITERUSSIAN
	glass_desc = "A very nice looking drink. But that's just, like, your opinion, man."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_GRAINS|ALLERGEN_DAIRY|ALLERGEN_STIMULANT //Made from black russian(vodka(grains), kahlua(coffee/caffeine)) and cream(dairy)

/datum/reagent/ethanol/whiskey_cola
	name = REAGENT_WHISKEYCOLA
	id = REAGENT_ID_WHISKEYCOLA
	description = "Whiskey, mixed with cola. Surprisingly refreshing."
	taste_description = "cola with an alcoholic undertone"
	nutriment_factor = 1.5
	color = "#3E1B00"
	strength = 25

	glass_name = "whiskey cola"
	glass_desc = "An innocent-looking mixture of cola and Whiskey. Delicious."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from whiskey(grains) and cola(caffeine)

/datum/reagent/ethanol/whiskeysoda
	name = REAGENT_WHISKEYSODA
	id = REAGENT_ID_WHISKEYSODA
	description = "Ultimate refreshment."
	taste_description = "carbonated whiskey"
	nutriment_factor = 1.5
	color = "#EAB300"
	strength = 15

	glass_name = "whiskey soda"
	glass_desc = "Ultimate refreshment."

	allergen_type = ALLERGEN_GRAINS //Made from whiskey(grains)

/datum/reagent/ethanol/specialwhiskey // I have no idea what this is and where it comes from
	name = REAGENT_SPECIALWHISKEY
	id = REAGENT_ID_SPECIALWHISKEY
	description = "Just when you thought regular station whiskey was good... This silky, amber goodness has to come along and ruin everything. The smell of it singes your nostrils."
	taste_description = "unspeakable whiskey bliss"
	color = "#523600"
	strength = 7

	glass_name = "special blend whiskey"
	glass_desc = "Just when you thought regular station whiskey was good... This silky, amber goodness has to come along and ruin everything."

	allergen_type = ALLERGEN_GRAINS //Whiskey(grains)

/datum/reagent/ethanol/sakebomb
	name = REAGENT_SAKEBOMB
	id = REAGENT_ID_SAKEBOMB
	description = "Alcohol in more alcohol."
	taste_description = "thick, dry alcohol"
	color = "#FFFF7F"
	strength = 12
	nutriment_factor = 1

	glass_name = REAGENT_SAKEBOMB
	glass_desc = "Some sake mixed into a pint of beer."

	allergen_type = ALLERGEN_GRAINS //Made from beer(grains)

/datum/reagent/ethanol/tamagozake
	name = REAGENT_TAMAGOZAKE
	id = REAGENT_ID_TAMAGOZAKE
	description = "Sake, egg, and sugar. A disgusting folk cure."
	taste_description = "eggy booze"
	color = "#E8C477"
	strength = 30
	nutriment_factor = 3

	glass_name = REAGENT_TAMAGOZAKE
	glass_desc = "An egg cracked into sake and sugar."
	allergen_type = ALLERGEN_EGGS //Made with eggs

/datum/reagent/ethanol/ginzamary
	name = REAGENT_GINZAMARY
	id = REAGENT_ID_GINZAMARY
	description = "An alcoholic drink made with vodka, sake, and juices."
	taste_description = "spicy tomato sake"
	color = "#FF3232"
	strength = 25

	glass_name = REAGENT_GINZAMARY
	glass_desc = "Tomato juice, vodka, and sake make something not quite completely unlike a Bloody Mary."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from vodka(grains) and tomatojuice(fruit)

/datum/reagent/ethanol/tokyorose
	name = REAGENT_TOKYOROSE
	id = REAGENT_ID_TOKYOROSE
	description = "A pale pink cocktail made with sake and berry juice."
	taste_description = "fruity booze"
	color = "#FA8072"
	strength = 35

	glass_name = REAGENT_TOKYOROSE
	glass_desc = "It's kinda pretty!"

	allergen_type = ALLERGEN_FRUIT //Made from berryjuice

/datum/reagent/ethanol/saketini
	name = REAGENT_SAKETINI
	id = REAGENT_ID_SAKETINI
	description = "For when you're too weeb for a real martini."
	taste_description = "dry alcohol"
	color = "#0064C8"
	strength = 15

	glass_name = REAGENT_SAKETINI
	glass_desc = "What are you doing drinking this outside of New Kyoto?"

	allergen_type = ALLERGEN_FRUIT //Made from gin(fruit)

/datum/reagent/ethanol/erebusmoonrise
	name = REAGENT_EREBUSMOONRISE
	id = REAGENT_ID_EREBUSMOONRISE
	description = "A deeply alcoholic mix, popular in Nyx."
	taste_description = "hard alcohol"
	color = "#947459"
	strength = 10

	glass_name = REAGENT_EREBUSMOONRISE
	glass_desc = "A deeply alcoholic mix, popular in Nyx."

	allergen_type = ALLERGEN_GRAINS //Made from whiskey(grains) and Vodka(grains)

/datum/reagent/ethanol/balloon
	name = REAGENT_BALLOON
	id = REAGENT_ID_BALLOON
	description = "A strange drink invented in the aerostats of Venus."
	taste_description = "strange alcohol"
	color = "#FAEBD7"
	strength = 66

	glass_name = REAGENT_BALLOON
	glass_desc = "A strange drink invented in the aerostats of Venus."

	allergen_type = ALLERGEN_DAIRY|ALLERGEN_FRUIT //Made from blue curacao(fruit) and cream(dairy)

/datum/reagent/ethanol/natunabrandy
	name = REAGENT_NATUNABRANDY
	id = REAGENT_ID_NATUNABRANDY
	description = "On Natuna, they do the best with what they have."
	taste_description = "watered-down beer"
	color = "#FFFFCC"
	strength = 80

	glass_name = REAGENT_NATUNABRANDY
	glass_desc = "On Natuna, they do the best with what they have."
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_GRAINS //Made from beer(grains)

/datum/reagent/ethanol/euphoria
	name = REAGENT_EUPHORIA
	id = REAGENT_ID_EUPHORIA
	description = "Invented by a Eutopian marketing team, this is one of the most expensive cocktails in existence."
	taste_description = "impossibly rich alcohol"
	color = "#614126"
	strength = 9

	glass_name = REAGENT_EUPHORIA
	glass_desc = "Invented by a Eutopian marketing team, this is one of the most expensive cocktails in existence."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from specialwhiskey(grain) and cognac(fruit)

/datum/reagent/ethanol/xanaducannon
	name = REAGENT_XANADUCANNON
	id = REAGENT_ID_XANADUCANNON
	description = "Common in the entertainment districts of Titan."
	taste_description = "sweet alcohol"
	nutriment_factor = 1.5
	color = "#614126"
	strength = 50

	glass_name = REAGENT_XANADUCANNON
	glass_desc = "Common in the entertainment districts of Titan."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from ale(grain) and dr.gibb(caffeine)

/datum/reagent/ethanol/debugger
	name = REAGENT_DEBUGGER
	id = REAGENT_ID_DEBUGGER
	description = "From Shelf. Not for human consumption."
	taste_description = "oily bitterness"
	nutriment_factor = 10
	color = "#d3d3d3"
	strength = 32

	glass_name = REAGENT_DEBUGGER
	glass_desc = "From Shelf. Not for human consumption."
	allergen_type = ALLERGEN_VEGETABLE //Made from corn oil(vegetable)

/datum/reagent/ethanol/spacersbrew
	name = REAGENT_SPACERSBREW
	id = REAGENT_ID_SPACERSBREW
	description = "Ethanol and orange soda. A common emergency drink on frontier colonies."
	taste_description = "bitter oranges"
	nutriment_factor = 1.5
	color = "#ffc04c"
	strength = 43

	glass_name = REAGENT_SPACERSBREW
	glass_desc = "Ethanol and orange soda. A common emergency drink on frontier colonies."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Made from brownstar(orange juice(fruit) + cola(caffeine)

/datum/reagent/ethanol/binmanbliss
	name = REAGENT_BINMANBLISS
	id = REAGENT_ID_BINMANBLISS
	description = "A dry cocktail popular on Binma."
	taste_description = "very dry alcohol"
	color = "#c3c3c3"
	strength = 24

	glass_name = REAGENT_BINMANBLISS
	glass_desc = "A dry cocktail popular on Binma."

/datum/reagent/ethanol/chrysanthemum
	name = REAGENT_CHRYSANTHEMUM
	id = REAGENT_ID_CHRYSANTHEMUM
	description = "An exotic cocktail from New Kyoto."
	taste_description = "fruity liquor"
	color = "#9999FF"
	strength = 35

	glass_name = REAGENT_CHRYSANTHEMUM
	glass_desc = "An exotic cocktail from New Kyoto."

	allergen_type = ALLERGEN_FRUIT //Made from melon liquor(fruit)

/datum/reagent/ethanol/bitters
	name = REAGENT_BITTERS
	id = REAGENT_ID_BITTERS
	description = "An aromatic, typically alcohol-based infusions of bittering botanticals and flavoring agents like fruit peels, spices, dried flowers, and herbs."
	taste_description = "sharp bitterness"
	color = "#9b6241" // rgb(155, 98, 65)
	strength = 50

	glass_name = REAGENT_BITTERS
	glass_desc = "An aromatic, typically alcohol-based infusions of bittering botanticals and flavoring agents like fruit peels, spices, dried flowers, and herbs."

/datum/reagent/ethanol/winebrandy
	name = REAGENT_WINEBRANDY
	id = REAGENT_ID_WINEBRANDY
	description = "A premium spirit made from distilled wine."
	taste_description = "very sweet dried fruit with many elegant notes"
	color = "#4C130B" // rgb(76,19,11)
	strength = 20

	glass_name = REAGENT_WINEBRANDY
	glass_desc = "A very classy looking after-dinner drink."

	allergen_type = ALLERGEN_FRUIT //Made from wine, which is made from fruit

/datum/reagent/ethanol/morningafter
	name = REAGENT_MORNINGAFTER
	id = REAGENT_ID_MORNINGAFTER
	description = "The finest hair of the dog, coming up!"
	taste_description = "bitter regrets"
	color = "#482000" // rgb(72, 32, 0)
	strength = 60

	glass_name = REAGENT_MORNINGAFTER
	glass_desc = "The finest hair of the dog, coming up!"

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Made from sbiten(vodka(grain)) and coffee(coffee/caffine)

/datum/reagent/ethanol/vesper
	name = REAGENT_VESPER
	id = REAGENT_ID_VESPER
	description = "A dry martini, ice cold and well shaken."
	taste_description = "lemony class"
	color = "#cca01c" // rgb(204, 160, 28)
	strength = 20

	glass_name = REAGENT_VESPER
	glass_desc = "A dry martini, ice cold and well shaken."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from wine(fruit), vodka(grain), and gin(fruit)

/datum/reagent/ethanol/rotgut
	name = REAGENT_ROTGUT
	id = REAGENT_ID_ROTGUT
	description = "A heinous combination of clashing flavors."
	taste_description = "plague and coldsweats"
	nutriment_factor = 1.5
	color = "#3a6617" // rgb(58, 102, 23)
	strength = 10

	glass_name = REAGENT_ROTGUT
	glass_desc = "Why are you doing this to yourself?"

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_STIMULANT //Made from whiskey(grains), cola (caffeine) and vodka(grains)

/datum/reagent/ethanol/screamingviking
	name =REAGENT_SCREAMINGVIKING
	id = REAGENT_ID_SCREAMINGVIKING
	description = "A boozy, citrus-packed brew."
	taste_description = "the bartender's frustration"
	color = "#c6c603" // rgb(198, 198, 3)
	strength = 9

	glass_name =REAGENT_SCREAMINGVIKING
	glass_desc = "A boozy, citrus-packed brew."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from martini(gin(fruit), vermouth(fruit)), vodka tonic(vodka(grain)), and lime juice(fruit)

/datum/reagent/ethanol/robustin
	name = REAGENT_ROBUSTIN
	id = REAGENT_ID_ROBUSTIN
	description = "A bootleg brew of all the worst things on station."
	taste_description = "cough syrup and fire"
	color = "#6b0145" // rgb(107, 1, 69)
	strength = 10

	glass_name = REAGENT_ROBUSTIN
	glass_desc = "A bootleg brew of all the worst things on station."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_DAIRY //Made from antifreeze(vodka(grains),cream(dairy)) and vodka(grains)

/datum/reagent/ethanol/virginsip
	name = REAGENT_VIRGINSIP
	id = REAGENT_ID_VIRGINSIP
	description = "A perfect martini, watered down and ruined."
	taste_description = "emasculation and failure"
	color = "#2E6671" // rgb(46, 102, 113)
	strength = 60

	glass_name = REAGENT_VIRGINSIP
	glass_desc = "A perfect martini, watered down and ruined."

	allergen_type = ALLERGEN_FRUIT //Made from driest martini(gin(fruit))

/datum/reagent/ethanol/jellyshot
	name = REAGENT_JELLYSHOT
	id = REAGENT_ID_JELLYSHOT
	description = "A thick and vibrant alcoholic gel, perfect for the night life."
	taste_description = "thick, alcoholic cherry gel"
	color = "#e00b0b" // rgb(224, 11, 11)
	strength = 10

	glass_name = REAGENT_JELLYSHOT
	glass_desc = "A thick and vibrant alcoholic gel, perfect for the night life."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from cherry jelly(fruit), and vodka(grains)

/datum/reagent/ethanol/cloverclub
	name = REAGENT_CLOVERCLUB
	id = REAGENT_ID_CLOVERCLUB
	description = "A light and refreshing raspberry cocktail."
	taste_description = "sweet raspberry"
	color = "#dd00a6" // rgb(221, 0, 166)
	strength = 30

	glass_name = REAGENT_CLOVERCLUB
	glass_desc = "A light and refreshing raspberry cocktail."

	allergen_type = ALLERGEN_FRUIT //Made from berry juice(fruit), lemon juice(fruit), and gin(fruit)

/datum/reagent/ethanol/negroni
	name = REAGENT_NEGRONI
	id = REAGENT_ID_NEGRONI
	description = "A dark, complicated mix of gin and campari... classy."
	taste_description = "summer nights and wood smoke"
	color = "#77000d" // rgb(119, 0, 13)
	strength = 25

	glass_name = REAGENT_NEGRONI
	glass_desc = "A dark, complicated blend, perfect for relaxing nights by the fire."

	allergen_type = ALLERGEN_FRUIT //Made from gin(fruit) and vermouth(fruit)

/datum/reagent/ethanol/whiskeysour
	name = REAGENT_WHISKEYSOUR
	id = REAGENT_ID_WHISKEYSOUR
	description = "A smokey, refreshing lemoned whiskey."
	taste_description = "smoke and citrus"
	color = "#a0692e" // rgb(160, 105, 46)
	strength = 20

	glass_name = REAGENT_WHISKEYSOUR
	glass_desc = "A smokey, refreshing lemoned whiskey."

	allergen_type = ALLERGEN_GRAINS|ALLERGEN_FRUIT //Made from whiskey(grains) and lemon juice(fruit)

/datum/reagent/ethanol/oldfashioned
	name = REAGENT_OLDFASHIONED
	id = REAGENT_ID_OLDFASHIONED
	description = "A classic mix of whiskey and sugar... simple and direct."
	taste_description = "smokey, divine whiskey"
	color = "#774410" // rgb(119, 68, 16)
	strength = 15

	glass_name = REAGENT_OLDFASHIONED
	glass_desc = "A classic mix of whiskey and sugar... simple and direct."

	allergen_type = ALLERGEN_GRAINS //Made from whiskey(grains)

/datum/reagent/ethanol/daiquiri
	name = REAGENT_DAIQUIRI
	id = REAGENT_ID_DAIQUIRI
	description = "Refeshing rum and citrus. Time for a tropical get away."
	taste_description = "refreshing citrus and rum"
	color = "#d1ff49" // rgb(209, 255, 73
	strength = 25

	glass_name = REAGENT_DAIQUIRI
	glass_desc = "Refeshing rum and citrus. Time for a tropical get away."

	allergen_type = ALLERGEN_FRUIT //Made from lime juice(fruit)

/datum/reagent/ethanol/mojito
	name = REAGENT_MOJITO
	id = REAGENT_ID_MOJITO
	description = "Minty rum and citrus, made for sailing."
	taste_description = "minty rum and lime"
	color = "#d1ff49" // rgb(209, 255, 73
	strength = 30

	glass_name = REAGENT_MOJITO
	glass_desc = "Minty rum and citrus, made for sailing."
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_FRUIT //Made from lime juice(fruit)

/datum/reagent/ethanol/paloma
	name = REAGENT_PALOMA
	id = REAGENT_ID_PALOMA
	description = "Tequila and citrus, iced just right..."
	taste_description = "grapefruit and cold fire"
	color = "#ffb070" // rgb(255, 176, 112)
	strength = 20

	glass_name = REAGENT_PALOMA
	glass_desc = "Tequila and citrus, iced just right..."
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_FRUIT //Made from orange juice(fruit)

/datum/reagent/ethanol/piscosour
	name = REAGENT_PISCOSOUR
	id = REAGENT_ID_PISCOSOUR
	description = "Wine Brandy, Lemon, and a dream. A South American classic"
	taste_description = "light sweetness"
	color = "#f9f96b" // rgb(249, 249, 107)
	strength = 30

	glass_name = REAGENT_PISCOSOUR
	glass_desc = "South American bliss, served ice cold."

	allergen_type = ALLERGEN_FRUIT //Made from wine brandy(fruit), and lemon juice(fruit)

/datum/reagent/ethanol/coldfront
	name = REAGENT_COLDFRONT
	id = REAGENT_ID_COLDFRONT
	description = "Minty, rich, and painfully cold. It's a blizzard in a cup."
	taste_description = "biting cold"
	color = "#ffe8c4" // rgb(255, 232, 196)
	strength = 30
	adj_temp = -20
	targ_temp = 220 //Dangerous to certain races. Drink in moderation.

	glass_name = REAGENT_COLDFRONT
	glass_desc = "Minty, rich, and painfully cold. It's a blizzard in a cup."

	allergen_type = ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Made from iced coffee(coffee)
	coolant_modifier = 1.15

/datum/reagent/ethanol/mintjulep
	name = REAGENT_MINTJULEP
	id = REAGENT_ID_MINTJULEP
	description = "Minty and refreshing, perfect for a hot day."
	taste_description = "refreshing mint"
	color = "#bbfc8a" // rgb(187, 252, 138)
	strength = 25
	adj_temp = -5

	glass_name = REAGENT_MINTJULEP
	glass_desc = "Minty and refreshing, perfect for a hot day."

/datum/reagent/ethanol/godsake
	name = REAGENT_GODSAKE
	id = REAGENT_ID_GODSAKE
	description = "Anime's favorite drink."
	taste_description = "the power of god and anime"
	color = "#DDDDDD"
	strength = 25

	glass_name = "God's Sake"
	glass_desc = "A glass of sake."

/datum/reagent/ethanol/holywine
	name = REAGENT_HOLYWINE
	id = REAGENT_ID_HOLYWINE
	description = "A premium alcoholic beverage made from distilled angel blood."
	taste_description = "wings in a glass, and a hint of grape"
	color = "#C4921E"
	strength = 20

	glass_name = REAGENT_HOLYWINE
	glass_desc = "A very pious looking drink."
	glass_icon = DRINK_ICON_NOISY

	allergen_type = ALLERGEN_FRUIT //Made from grapes(fruit)

/datum/reagent/ethanol/holy_mary
	name = REAGENT_HOLYMARY
	id = REAGENT_ID_HOLYMARY
	description = "A strange yet pleasurable mixture made of vodka, angel's ichor and lime juice. Or at least you THINK the yellow stuff is angel's ichor."
	taste_description = "grapes with a hint of lime"
	color = "#DCAE12"
	strength = 20

	glass_name = REAGENT_HOLYMARY
	glass_desc = "Angel's Ichor, mixed with Vodka and a lil' bit of lime. Tastes like liquid ascension."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from vodka(grain), holy wine(fruit), and lime juice(fruit)

/datum/reagent/ethanol/angelswrath
	name = REAGENT_ANGELSWRATH
	id = REAGENT_ID_ANGELSWRATH
	description = "This thing makes the hair on the back of your neck stand up."
	taste_description = "sweet victory and sour iron"
	taste_mult = 1.5
	nutriment_factor = 1.5
	color = "#F3C906"
	strength = 30

	glass_name = "Angels' Wrath"
	glass_desc = "Just looking at this thing makes you sweat."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list(DRINK_FIZZ)

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_STIMULANT //Made from space mountain wind(fruit), dr.gibb(caffine) and holy wine(fruit)

/datum/reagent/ethanol/angelskiss
	name = REAGENT_ANGELSKISS
	id = REAGENT_ID_ANGELSKISS
	description = "Miracle time!"
	taste_description = "sweet forgiveness and bitter iron"
	color = "#AD772B"
	strength = 25

	glass_name = "Angel's Kiss"
	glass_desc = "Miracle time!"

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Made from holy wine(fruit), and kahlua(coffee)

/datum/reagent/ethanol/ichor_mead
	name = REAGENT_ICHORMEAD
	id = REAGENT_ID_ICHORMEAD
	description = "A trip to Valhalla."
	taste_description = "valhalla"
	color = "#955B37"
	strength = 30

	glass_name = REAGENT_ICHORMEAD
	glass_desc = "A trip to Valhalla."

	allergen_type = ALLERGEN_FRUIT //Made from holy wine(fruit)

/datum/reagent/ethanol/schnapps_pep
	name = REAGENT_SCHNAPPSPEP
	id = REAGENT_ID_SCHNAPPSPEP
	description = "Achtung, pfefferminze."
	taste_description = "minty alcohol"
	color = "#8FC468"
	strength = 25

	glass_name = "peppermint schnapps"
	glass_desc = "A glass of peppermint schnapps. It seems like it'd be better, mixed."

/datum/reagent/ethanol/schnapps_pea
	name = REAGENT_SCHNAPPSPEA
	id = REAGENT_ID_SCHNAPPSPEA
	description = "Achtung, fruchtig."
	taste_description = "peaches"
	color = "#d67d4d"
	strength = 25

	glass_name = "peach schnapps"
	glass_desc = "A glass of peach schnapps. It seems like it'd be better, mixed."

	allergen_type = ALLERGEN_FRUIT //Made from peach(fruit)

/datum/reagent/ethanol/schnapps_lem
	name = REAGENT_SCHNAPPSLEM
	id = REAGENT_ID_SCHNAPPSLEM
	description = "Childhood memories are not included."
	taste_description = "sweet, lemon-y alcohol"
	color = "#FFFF00"
	strength = 25

	glass_name = "lemonade schnapps"
	glass_desc = "A glass of lemonade schnapps. It seems like it'd be better, mixed."

	allergen_type = ALLERGEN_FRUIT //Made from lemons(fruit)

/datum/reagent/ethanol/jager
	name = REAGENT_JAGER
	id = REAGENT_ID_JAGER
	description = "A complex alcohol that leaves you feeling all warm inside."
	taste_description = "complex, rich alcohol"
	color = "#7f6906"
	strength = 25

	glass_name = "schusskonig"
	glass_desc = "A glass of schusskonig digestif. Good for shooting or mixing."

/datum/reagent/ethanol/fusionnaire
	name = REAGENT_FUSIONNAIRE
	id = REAGENT_ID_FUSIONNAIRE
	description = "A drink for the brave."
	taste_description = "a painfully alcoholic lemon soda with an undertone of mint"
	color = "#6BB486"
	strength = 9

	glass_name = REAGENT_ID_FUSIONNAIRE
	glass_desc = "A relatively new cocktail, mostly served in the bars of NanoTrasen owned stations."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from lemon juice(fruit), vodka(grains), and lemon schnapps(fruit)

/datum/reagent/drink/soda/kompot
	name = REAGENT_KOMPOT
	id = REAGENT_ID_KOMPOT
	description = "A traditional Eastern European beverage once used to preserve fruit in the 1980s"
	taste_description = "refreshingly sweet and fruity"
	color = "#ed9415" // rgb: 237, 148, 21
	adj_drowsy = -1
	adj_temp = -6
	glass_name = REAGENT_ID_KOMPOT
	glass_desc = "A glass of refreshing kompot."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/ethanol/kvass
	name = REAGENT_KVASS
	id = REAGENT_ID_KVASS
	description = "A traditional fermented Slavic and Baltic beverage commonly made from rye bread."
	taste_description = "a warm summer day at babushka's cabin"
	color = "#b78315" // rgb: 183, 131, 21
	strength = 95 //It's just soda to Russians
	nutriment_factor = 2
	glass_name = REAGENT_ID_KVASS
	glass_desc = "A hearty glass of Slavic brew."

/datum/reagent/cinnamonpowder
	name = REAGENT_CINNAMONPOWDER
	id = REAGENT_ID_CINNAMONPOWDER
	description = "Cinnamon, a spice made from tree bark, ground into a fine powder. Probably not a good idea to eat on its own!"
	taste_description= "sweet spice with a hint of wood"
	color = "#a96622"

	glass_name = REAGENT_ID_CINNAMONPOWDER
	glass_desc = "A glass of ground cinnamon. Dare you take the challenge?"

	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/gelatin
	name = REAGENT_GELATIN
	id = REAGENT_ID_GELATIN
	description = "It doesnt taste like anything."
	taste_description = REAGENT_ID_NOTHING
	color = "#aaabcf"

	glass_name = REAGENT_GELATIN
	glass_desc = "It's like flavourless slime."

	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/nutriment
	nutriment_factor = 10

/datum/reagent/toxin/meatcolony
	name = REAGENT_MEATCOLONY
	id = REAGENT_ID_MEATCOLONY
	description = "Specialised cells designed to produce a large amount of meat once activated, whilst manufacturers have managed to stop these cells from taking over the body when ingested, it's still poisonous."
	taste_description = "a fibrous mess"
	reagent_state = LIQUID
	color = "#ff2424"
	strength = 10
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/toxin/plantcolony
	name = REAGENT_PLANTCOLONY
	id = REAGENT_ID_PLANTCOLONY
	description = "Specialised cells designed to produce a large amount of nutriment once activated, whilst manufacturers have managed to stop these cells from taking over the body when ingested, it's still poisonous."
	taste_description = "a fibrous mess"
	reagent_state = LIQUID
	color = "#7ce01f"
	strength = 10
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/nutriment/grubshake
	name = REAGENT_GRUBSHAKE
	id = REAGENT_ID_GRUBSHAKE
	description = "An odd fluid made from grub guts, supposedly filling."
	taste_description = "sparkles"
	taste_mult = 1.3
	nutriment_factor = 5
	color = "#fff200"
	wiki_flag = WIKI_DRINK

/datum/reagent/lipozine/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjust_nutrition(-20 * removed)

/datum/reagent/ethanol/pink_russian
	name = REAGENT_PINKRUSSIAN
	id = REAGENT_ID_PINKRUSSIAN
	description = "Like a White Russian but with 100% more pink!"
	taste_description = "strawberry icecream, with a coffee kick"
	color = "#d789bd"
	strength = 15

	glass_name = REAGENT_PINKRUSSIAN
	glass_desc = "A very pink drink, yet with strong sense of power to it."

/datum/reagent/ethanol/originalsin
	name = REAGENT_ORIGINALSIN
	id = REAGENT_ID_ORIGINALSIN
	description = "Angel Ichor, entirely transformed by one drop of apple juice"
	taste_description = "the apple Eve gave to Adam"
	color = "#99CC35"
	strength = 17

	glass_name = REAGENT_ORIGINALSIN
	glass_desc = "A drink so fine, you may just risk eternal damnation!"

/datum/reagent/ethanol/newyorksour
	name = REAGENT_NEWYORKSOUR
	id = REAGENT_ID_NEWYORKSOUR
	description = "Whiskey sour, with a layer of wine and egg white."
	taste_description = "refreshing lemoned whiskey, smoothed with wine"
	color = "#FFBF3C"
	strength = 17

	glass_name = REAGENT_NEWYORKSOUR
	glass_desc = "A carefully poured three layered drink"

/datum/reagent/ethanol/windgarita
	name = REAGENT_WINDGARITA
	id = REAGENT_ID_WINDGARITA
	description = "A highly questionable combination of margarita and Space Mountain Wind"
	taste_description = "like sin, and some tequilia"
	color = "#90D93D"
	strength = 15

	glass_name = REAGENT_WINDGARITA
	glass_desc = "Who the hell comes up with these drinks?!"

/datum/reagent/ethanol/mudslide
	name = REAGENT_MUDSLIDE
	id = REAGENT_ID_MUDSLIDE
	description = "Vodka, Kahlua and Irish Cream together at last."
	taste_description = "a mocha milkshake, with a splash of vodka."
	color = "#8B6338"
	strength = 13

	glass_name = REAGENT_MUDSLIDE
	glass_desc = "A richly coloured drink, comes with a chocolate garnish!"

/datum/reagent/ethanol/bulldog
	name = REAGENT_BULLDOG
	id = REAGENT_ID_BULLDOG
	description = "An inventive kahlua recipe."
	taste_description = "fizzy, creamy, soda and coffee hell"
	strength = 30
	color = "#d3785d"

	glass_name = REAGENT_BULLDOG
	glass_desc = "It looks like someone poured cola in a cup of coffee."

/datum/reagent/ethanol/sbagliato
	name = REAGENT_SBAGLIATO
	id = REAGENT_ID_SBAGLIATO
	description = "A drink invented because a bartender was too drunk."
	taste_description = "sweet bubbly wine and vermouth"
	strength = 30
	color = "#d3785d"

	glass_name = REAGENT_SBAGLIATO
	glass_desc = "Bubbles constantly pop up to the surface with a quiet fizz."

/datum/reagent/ethanol/italiancrisis
	name = REAGENT_ITALIANCRISIS
	id = REAGENT_ID_ITALIANCRISIS
	description = "This drink was concocted by a madwoman, causing the Italian Crisis of 2123."
	taste_description = "cola, fruit, fizz, coffee, and cream swirled together in an old boot"
	strength = 20
	druggy = 0
	halluci = 0
	color = "#d3785d"

	glass_name = REAGENT_ITALIANCRISIS
	glass_desc = "This drink looks like it was a mistake."

/datum/reagent/ethanol/sugarrush
	name = REAGENT_SUGARRUSH
	id = REAGENT_ID_SUGARRUSH
	description = "A favorite drink amongst poor bartenders living in Neo Detroit."
	taste_description = "sweet bubblegum vodka"
	strength = 30
	color = "#d3785d"

	glass_name = REAGENT_SUGARRUSH
	glass_desc = "This looks like it might rot your teeth out."

/datum/reagent/ethanol/lotus
	name = REAGENT_LOTUS
	id = REAGENT_ID_LOTUS
	description = "The result of making one mistake after another and trying to cover it up with sugar."
	taste_description = "rich, sweet fruit and even more sugar"
	strength = 25
	color = "#d3785d"

	glass_name = REAGENT_LOTUS
	glass_desc = "A promotional drink for a movie that only ever played in Neo Detroit theatres."

/datum/reagent/ethanol/shroomjuice
	name = REAGENT_SHROOMJUICE
	id = REAGENT_ID_SHROOMJUICE
	description = "The mushroom farmer didn't sort through their stock very well."
	taste_description = "sweet and sour citrus with a savory kick"
	strength = 100
	druggy = 30
	halluci = 30
	color = "#d3785d"

	glass_name = REAGENT_SHROOMJUICE
	glass_desc = "Touch fuzzy, get dizzy."

/datum/reagent/ethanol/lovemaker
	name = REAGENT_LOVEMAKER
	id = REAGENT_ID_LOVEMAKER
	description = "A drink said to help one find true love."
	taste_description = "sweet fruit and honey"
	strength = 30
	druggy = 0
	halluci = 0
	adj_temp = 10
	targ_temp = 360
	color = "#d3785d"

	glass_name = REAGENT_LOVEMAKER
	glass_desc = "A drink said to help one find the perfect fuck."

/datum/reagent/ethanol/honeyshot
	name = REAGENT_HONEYSHOT
	id = REAGENT_ID_HONEYSHOT
	description = "The perfect drink for bees."
	taste_description = "sweet tart grenadine flavored with honey"
	strength = 40
	color = "#d3785d"

	glass_name = REAGENT_HONEYSHOT
	glass_desc = "A glass of golden liquid."

/datum/reagent/ethanol/appletini
	name = REAGENT_APPLETINI
	id = REAGENT_ID_APPLETINIT
	description = "A classic cocktail using every grandma's favorite fruit."
	taste_description = "green sour apple with a hint of alcohol"
	strength = 45
	color = "#d3785d"

	glass_name = REAGENT_APPLETINI
	glass_desc = "The perfect fruit cocktail for a fancy night at the bar."

/datum/reagent/ethanol/glowingappletini
	name = REAGENT_GLOWINGAPPLETINI
	id = REAGENT_ID_GLOWINGAPPLETINI
	description = "A new nuclear take on a pre-modern classic!"
	taste_description = "overwhelmingly sour apples powered by a nuclear fission reactor"
	strength = 30
	druggy = 20
	color = "#d3785d"

	glass_name = REAGENT_GLOWINGAPPLETINI
	glass_desc = "The atomic option to fruity cocktails."

/datum/reagent/ethanol/scsatw
	name = REAGENT_SCSATW
	id = REAGENT_ID_SCSATW
	description = "The screwdriver's bigger cousin."
	taste_description = "smooth, savory booze and tangy orange juice"
	strength = 30
	druggy = 0
	halluci = 0
	color = "#d3785d"

	glass_name = REAGENT_SCSATW
	glass_desc = "The best accessory to daydrinking."

/datum/reagent/drink/choccymilk
	name = REAGENT_CHOCCYMILK
	id = REAGENT_ID_CHOCCYMILK
	description = "Coco and milk, a timeless classic."
	taste_description = "sophisticated bittersweet chocolate mixed with silky, creamy, whole milk"
	color = "#d3785d"

	glass_name = REAGENT_CHOCCYMILK
	glass_desc = "The most iconic duo in the galaxy, chocolate, and milk."

/datum/reagent/ethanol/redspaceflush
	name = REAGENT_REDSPACEFLUSH
	id = REAGENT_ID_REDSPACEFLUSH
	description = "A drink made by imbueing the essence of redspace into the spirits."
	taste_description = "whiskey and rum strung out through a hellish dimensional rift"
	strength = 30
	druggy = 10
	color = "#d3785d"

	glass_name = REAGENT_REDSPACEFLUSH
	glass_desc = "A drink imbued with the very essence of Redspace."

/datum/reagent/drink/graveyard
	name = REAGENT_GRAVEYARD
	id = REAGENT_ID_GRAVEYARD
	description = "The result of taking a cup and filling it with all the drinks at the fountain."
	taste_description = "sugar and fizz"
	color = "#d3785d"

	glass_name = REAGENT_GRAVEYARD
	glass_desc = "Hahaha softdrink machine go pshshhhhh..."

/datum/reagent/ethanol/bigbeer
	name = REAGENT_BIGBEER
	id = REAGENT_ID_BIGBEER
	description = "Bars in Neo Detroit started to sell this drink when the city put mandatory drink limits in 2289."
	taste_description = "beer, but bigger"
	strength = 40
	color = "#d3785d"

	glass_name = REAGENT_BIGBEER
	glass_desc = "The Neo Detroit beer and ale cocktail, perfect for your average drunk."

/datum/reagent/ethanol/manager_summoner
	name = REAGENT_MANAGERSUMMONER
	id = REAGENT_ID_MANAGERSUMMONER
	description = "A horrifying cocktail for those who desperately want feel above their peers."
	taste_description = "bitter and sweet, with a hint of superiority"
	strength = 30
	color = "#c9716b"

	glass_name = REAGENT_MANAGERSUMMONER
	glass_desc = "The dreaded red juice of those who insist on taking advantage of minor positions of power to make the lives of bar staff unbearable."

/datum/reagent/drink/sweettea
	name = REAGENT_SWEETTEA
	id = REAGENT_ID_SWEETTEA
	description = "Tea that is sweetened with some form of sweetener."
	taste_description = "tea that is sweet"
	color = "#d3785d"

	glass_name = REAGENT_SWEETTEA
	glass_desc = "A southern classic. Southern what? You know, southern."

/datum/reagent/ethanol/unsweettea
	name = REAGENT_UNSWEETTEA
	id = REAGENT_ID_UNSWEETTEA
	description = "A sick experiment to take the sweetness out of tea after sugar has been added resulted in this."
	taste_description = "bland, slightly bitter, discount black tea"
	strength = 80
	druggy = 10
	color = "#d3785d"

	glass_name = REAGENT_UNSWEETTEA
	glass_desc = "A drink with all the calories of sweet tea, but with none of the satisfaction. Slightly psychoactive."

//////////////////////Bepis Drinks (04/29/2021)//////////////////////

/datum/reagent/drink/soda/bepis_cola
	name = REAGENT_BEPIS
	id = REAGENT_ID_BEPIS
	description = "A weird cola-like beverage."
	taste_description = "bepsi"
	reagent_state = LIQUID
	color = "#100800"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_BEPIS
	glass_desc = "A glass of weird cola beverage."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/buzz_fuzz
	name = REAGENT_BUZZFUZZ
	id = REAGENT_ID_BUZZFUZZ
	description = "A delicious frontier beverage that's simply a Hive of Flavour!"
	taste_description = "carbonated honey and pollen"
	reagent_state = LIQUID
	color = "#8CFF00"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_BUZZFUZZ
	glass_desc = "A glass that's stinging with flavour."
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/sprited_cranberry
	name = REAGENT_SPRITEDCRANBERRY
	id = REAGENT_ID_SPRITEDCRANBERRY
	description = "A winter spiced cranberry drink. Perfect for year-round consumption."
	taste_description = "sweet spiced cranberry"
	reagent_state = LIQUID
	color = "#fffafa"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_SPRITEDCRANBERRY
	glass_desc = "A glass of sprited cranberry"
	glass_special = list(DRINK_FIZZ)

/datum/reagent/drink/soda/shamblers
	name = REAGENT_SHAMBLERS
	id = REAGENT_ID_SHAMBLERS
	description = "A strange off-brand beverage that's bursting with flavor."
	taste_description = "carbonated metallic soda"
	reagent_state = LIQUID
	color = "#f00060"
	adj_drowsy = -3
	adj_temp = -5

	glass_name = REAGENT_SHAMBLERS
	glass_desc = "A glass of something shambly"
	glass_special = list(DRINK_FIZZ)

////////////////END BrainzSnax Reagents////////////////

/datum/reagent/nutriment/protein_powder
	name = REAGENT_PROTEINPOWDER
	id = REAGENT_ID_PROTEINPOWDER
	description = "Pure, powdered protein commonly used as a meal supplement."
	taste_description = "powdery protein"
	color = "#f4e6dd"

/datum/reagent/nutriment/protein_shake
	name = REAGENT_PROTEINSHAKE
	id = REAGENT_ID_PROTEINSHAKE
	description = "A mixture of water and protein commonly used as a meal supplement."
	taste_description = "pure protein"
	color = "#ebd8cb"
	wiki_flag = WIKI_DRINK

/datum/reagent/nutriment/protein_powder/vanilla
	name = REAGENT_VANILLAPROTEINPOWDER
	id = REAGENT_ID_VANILLAPROTEINPOWDER
	description = "Pure, powdered protein commonly used as a meal supplement. This one has added vanilla flavoring."
	taste_description = "powdery vanilla"
	color = "#fff7d2"

/datum/reagent/nutriment/protein_shake/vanilla
	name = REAGENT_VANILLAPROTEINSHAKE
	id = REAGENT_ID_VANILLAPROTEINSHAKER
	description = "A mixture of water and protein commonly used as a meal supplement. This one has added vanilla flavoring."
	taste_description = "vanilla"
	color = "#faefbc"

/datum/reagent/nutriment/protein_powder/banana
	name = REAGENT_BANANAPROTEINPOWDER
	id = REAGENT_ID_BANANAPROTEINPOWDER
	description = "Pure, powdered protein commonly used as a meal supplement. This one has added banana flavoring."
	taste_description = "powdery banana"
	color = "#faefbc"

/datum/reagent/nutriment/protein_shake/banana
	name = REAGENT_BANANAPROTEINSHAKE
	id = REAGENT_ID_BANANAPROTEINSHAKE
	description = "A mixture of water and protein commonly used as a meal supplement. This one has added banana flavoring."
	taste_description = "banana"
	color = "#e6daa1"

/datum/reagent/nutriment/protein_powder/chocolate
	name = REAGENT_CHOCOLATEPROTEINPOWDER
	id = REAGENT_ID_CHOCOLATEPROTEINPOWDER
	description = "Pure, powdered protein commonly used as a meal supplement. This one has added chocolate flavoring."
	taste_description = "powdery chocolate"
	color = "#865b3e"

/datum/reagent/nutriment/protein_shake/chocolate
	name = REAGENT_CHOCOLATEPROTEINSHAKE
	id = REAGENT_ID_CHOCOLATEPROTEINSHAKE
	description = "A mixture of water and protein commonly used as a meal supplement. This one has added chocolate flavoring."
	taste_description = "chocolate"
	color = "#644730"

/datum/reagent/nutriment/protein_powder/strawberry
	name = REAGENT_STRAWBERRYPROTEINPOWDER
	id = REAGENT_ID_STRAWBERRYPROTEINPOWDER
	description = "Pure, powdered protein commonly used as a meal supplement. This one has added strawberry flavoring."
	taste_description = "powdery strawberry"
	color = "#eba1a1"

/datum/reagent/nutriment/protein_shake/strawberry
	name = REAGENT_STRAWBERRYPROTEINSHAKE
	id = REAGENT_ID_STRAWBERRYPROTEINSHAKE
	description = "A mixture of water and protein commonly used as a meal supplement. This one has added strawberry flavoring."
	taste_description = "strawberry"
	color = "#e28585"

//SOUPS. Don't use the base soup reagent.
/datum/reagent/drink/soup
	name = REAGENT_SOUP
	id = REAGENT_ID_SOUP
	description = "An indistinct soupy mass of nominal goodness, but questionable flavour."
	taste_description = "upsettingly bland soup"
	color = "#9a9a9a"
	nutrition = 30	//same as base nutriment

/datum/reagent/drink/soup/tomato
	name = REAGENT_TOMATOSOUP
	id = REAGENT_ID_TOMATOSOUP
	description = "A thick and creamy tomato soup. Delicious! Definitely not ketchup."
	taste_description = "rich, creamy tomato"
	color = "#e4612d"
	allergen_type = ALLERGEN_FRUIT //tomatoes are fruit, etc. etc.

/datum/reagent/drink/soup/mushroom
	name = REAGENT_MUSHROOMSOUP
	id = REAGENT_ID_MUSHROOMSOUP
	description = "A rich, earthy mushroom soup."
	taste_description = "earthy mushrooms"
	color = "#a59a83"
	allergen_type = ALLERGEN_FUNGI //shrooms!

/datum/reagent/drink/soup/chicken
	name = REAGENT_CHICKENSOUP
	id = REAGENT_ID_CHICKENSOUP
	description = "A fairly thick, warming chicken-based soup."
	taste_description = "savoury chicken goodness"
	color = "#d4c574"
	allergen_type = ALLERGEN_MEAT //plain ol' chimken

/datum/reagent/drink/soup/chicken_noodle
	name = REAGENT_CHICKENNOODLESOUP
	id = REAGENT_ID_CHICKENNOODLESOUP
	description = "A thin chicken broth with added noodles. If you're lucky there might be some chunks of chicken and veggies in there! Maybe."
	taste_description = "savoury chicken-noodle goodness"
	color = "#a27a41"
	allergen_type = ALLERGEN_MEAT|ALLERGEN_GRAINS|ALLERGEN_VEGETABLE //chicken + grain-based noodles + veggie chunks

/datum/reagent/drink/soup/onion
	name = REAGENT_ONIONSOUP
	id = REAGENT_ID_ONIONSOUP
	description = "A humble staple of humanity throughout the centuries."
	taste_description = "caramelized onions"
	color = "#5d3918"
	allergen_type = ALLERGEN_VEGETABLE //onions are veg, right?

/datum/reagent/drink/soup/vegetable
	name = REAGENT_VEGETABLESOUP
	id = REAGENT_ID_VEGETABLESOUP
	description = "A mix of various kinds of tasty vegetables, in soup format!"
	taste_description = "mixed vegetables"
	color = "#824005"
	allergen_type = ALLERGEN_VEGETABLE //mixed veg

/datum/reagent/drink/soup/beet
	name = REAGENT_BEETSOUP
	id = REAGENT_ID_BEETSOUP
	description = "A hearty mix of tomatoes and beets, with a meat stock base."
	taste_description = "sour tomatoes and some killer beets"
	color = "#471b1c"
	allergen_type = ALLERGEN_MEAT|ALLERGEN_FRUIT|ALLERGEN_VEGETABLE //meat stock, tomatoes, and beets

/datum/reagent/drink/soup/hot_and_sour
	name = REAGENT_HOTNSOURSOUP
	id = REAGENT_ID_HOTNSOURSOUP
	description = "A spicy tofu-based soup."
	taste_description = "spicy, sour tofu"
	color = "#5f1b06"
	allergen_type = ALLERGEN_BEANS|ALLERGEN_VEGETABLE|ALLERGEN_FUNGI //tofu is soy-based, ergo, beans. base recipe also uses cabbage and mushroom.

/////////Energy Drinks/////////

/datum/reagent/drink/coffee/nukie

	name = REAGENT_NUKIE
	id = REAGENT_ID_NUKIE
	description = "An extremely concentrated caffinated drink."
	color = "#102838"
	adj_temp = 0
	adj_dizzy = 0
	adj_drowsy = -5
	adj_sleepy = -10
	dermal_absorption = 0.15 //Nukies are build different.

	glass_name = REAGENT_ID_NUKIE
	glass_desc = "A drink to perk you up and refresh you!"
	overdose = REAGENTS_OVERDOSE

	taste_description = "flavourless energy"

/datum/reagent/drink/coffee/nukie/peach
	name = REAGENT_NUKIEPEACH
	id = REAGENT_ID_NUKIEPEACH
	color = "#ffc76e"
	taste_description = "battery acid with a hint of artificial peach"

/datum/reagent/drink/coffee/nukie/pear
	name = REAGENT_NUKIEPEAR
	id = REAGENT_ID_NUKIEPEAR
	color = "#d4c03d"
	taste_description = "electrostimulation with a hint of artificial pear"

/datum/reagent/drink/coffee/nukie/cherry
	name = REAGENT_NUKIECHERRY
	id = REAGENT_ID_NUKIECHERRY
	color = "#b00707"
	taste_description = "the rapid acceleration of tooth decay with a hint of artificial cherry"

/datum/reagent/drink/coffee/nukie/melon
	name = REAGENT_NUKIEMELON
	id = REAGENT_ID_NUKIEMELON
	color = "#00bf06"
	taste_description = "something is crawling under your skin with a hint of artificial melon"

/datum/reagent/drink/coffee/nukie/banana
	name = REAGENT_NUKIEBANANA
	id = REAGENT_ID_NUKIEBANANA
	color = "#ffee00"
	taste_description = "imminent cardiac arrest with a hint of something that doesn't really taste like banana at all but is clearly intending to be banana"

/datum/reagent/drink/coffee/nukie/rose
	name = REAGENT_NUKIEROSE
	id = REAGENT_ID_NUKIEROSE
	color = "#ff7df4"
	taste_description = "paint stripper, space cleaner and some sort of cheap perfume"

/datum/reagent/drink/coffee/nukie/lemon
	name = REAGENT_NUKIELEMON
	id = REAGENT_ID_NUKIELEMON
	color = "#c3ff00"
	taste_description = "something that once resembled lemon mixed thoroughly with literal toxic waste"

/datum/reagent/drink/coffee/nukie/fruit
	name = REAGENT_NUKIEFRUIT
	id = REAGENT_ID_NUKIEFRUIT
	color = "#b300ff"
	taste_description = "the colour purple"

/datum/reagent/drink/coffee/nukie/special
	name = REAGENT_NUKIESPECIAL
	id = REAGENT_ID_NUKIESPECIAL
	color = "#ffffff"
	taste_description = "sitting in your college dorm one week before your exams start, staring at a screen without anything particularly interesting on, knowing that you should really be studying, but you can put it off for another day right? Plus your friends are gonna be getting on soon and there's an event starting that you need to prep for"

/datum/reagent/drink/coffee/nukie/mega

	name = REAGENT_NUKIEMEGA
	id = REAGENT_ID_NUKIEMEGA
	description = "An extremely dangerously concentrated caffinated drink."
	color = "#102838"
	adj_temp = 0
	adj_dizzy = 0
	adj_drowsy = -5
	adj_sleepy = -10

	glass_name = REAGENT_ID_NUKIE
	glass_desc = "A drink that might just explode your heart!"
	overdose = 5

	taste_description = "flavourless energy"

////////////////////////////////////////////////
/////////DRINKS////////////////////////////////
//////////////////////////////////////////////

/datum/reagent/drink/tea/cherrytea
	name = REAGENT_CHERRYTEA
	id = REAGENT_ID_CHERRYTEA
	description = "A tasty mixture of cherries and tea. It's apparently good for you!"
	color = "#c15962"
	taste_description = "black tea with lots of cherries"

	glass_name = "cherry tea"
	glass_desc = "A tasty mixture of cherries and tea. It's apparently good for you!"

	cup_name = "cup of cherry tea"
	cup_desc = "A tasty mixture of cherries and tea. It's apparently good for you!"

/datum/reagent/drink/tea/watermelontea
	name = REAGENT_WATERMELONTEA
	id = REAGENT_ID_WATERMELONTEA
	description = "A tasty mixture of watermelon and tea. It's apparently good for you!"
	color = "#9f2c2c"
	taste_description = "black tea with sweet watermelon for flavouring"

	glass_name = "watermelon tea"
	glass_desc = "A tasty mixture of watermelon and tea. It's apparently good for you!"

	cup_name = "cup of watermelon tea"
	cup_desc = "A tasty mixture of watermelon and tea. It's apparently good for you!"

/datum/reagent/drink/tea/matcha_latte //Putting this as tea to inherit tea variables. Should not have the same antitoxin action as matcha so it can be placed in a dispenser without breaking balance.
	name = REAGENT_MATCHALATTE
	id = REAGENT_ID_MATCHALATTE
	description = "A nice and tasty beverage to enjoy while studying."
	taste_description = "creamy, vegetal sweetness"
	color = "#b1c48c"
	adj_temp = 5

	glass_name = "matcha latte"
	glass_desc = "A nice and refreshing beverage while you are studying."

	cup_icon_state = "cup_latte"
	cup_name = "cup of matcha latte"
	cup_desc = "A nice and refreshing beverage while you are studying."

/datum/reagent/slimedrink
	name = REAGENT_SLIMEDRINK
	id = REAGENT_ID_SLIMEDRINK
	description = "A gooey semi-liquid produced from your fellow slimey crew members."
	taste_description = "jiggly"
	taste_mult = 1.3
	reagent_state = LIQUID
	color = "#8bdce5"

	glass_name = REAGENT_SLIMEDRINK
	glass_desc = "Slime thats safe to drink (relatively)"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/drink/soda
	ingest_met = REM * 5 //Makes it so soda metabolizes faster, since without this increase, the nutrients it currently gives does nothing. Also, metabolises faster then normal nutrients due to being soda.

/datum/reagent/ethanol/spiderdrink
	name = REAGENT_SPIDERDRINK
	id = REAGENT_ID_SPIDERDRINK
	description = "A fresh drink consisting of cloned spiderlings who are intoxicated by a healthy dose of absinthe."
	taste_description = "TOO MANY LEGS"
	color = "#526062" // rgb(82, 96, 98)
	strength = 15

	glass_name = REAGENT_SPIDERDRINK
	glass_desc = "A glass filled to the brim with tiny drunk spiderlings. Lets hope they dont escape."

/datum/reagent/ethanol/snaps
	name = REAGENT_SNAPS
	id = REAGENT_ID_SNAPS
	description = "Burns the nose and throat and soothes it with a herby aftertaste...Barely."
	taste_description = "strong spirit and a little dill"
	color = "e6d670" // rgb: 230, 214, 112
	strength = 15

	glass_name = "akvavit"
	glass_desc = "Burns the nose and throat, and soothes it with a herby aftertaste...Barely."

/datum/reagent/ethanol/bluetrain
	name = REAGENT_BLUETRAIN
	id = REAGENT_ID_BLUETRAIN
	description = "A drink only a fool or a very desperate creature would consume."
	taste_description = "someone who decided to pour ice cold motor oil down your throat and finish it off with a large shot of burning pure alcohol."
	color = "#c8a5dc"
	adj_temp = -10
	targ_temp = 220
	strength = 10

	glass_name = REAGENT_BLUETRAIN
	glass_desc = "A glass of what can only be described as the bastard child between coolant and alcohol made by a madman."

/datum/reagent/drink/lowpower
	treatment_tags = list(TREAT_ANTITOXIN = 0.1)
	name = REAGENT_LOWPOWER
	id = REAGENT_ID_LOWPOWER
	description = "Smells, and tastes like lemon.. with a hint of Ozone, for whatever reason. It glows softly."
	taste_description = "creamy lemonade, with some zest"
	color = "#5d8d39"

	glass_name = REAGENT_ID_LOWPOWER
	glass_desc = "Smells, and tastes like lemon.. with a hint of Ozone, for whatever reason. It glows softly."

/datum/reagent/ethanol/flapper
	name = REAGENT_FLAPPER
	id = REAGENT_ID_FLAPPER
	description = "A common drink among blood-drinkers, and those who just wanna drink. Tinnibat be damned."
	taste_description = "a bloody good time"
	color = "#763424"
	strength = 15

	glass_name = REAGENT_ID_FLAPPER
	glass_desc = "A common drink among blood-drinkers, and those who just wanna drink. Tinnibat be damned."

/datum/reagent/toxin/oilslide
	name = REAGENT_OILSLIDE
	id = REAGENT_ID_OILSLIDE
	description = "Tasty, if you're a synth, not so much for organics."
	taste_description = "oil, slime, and fuel! Tastes also like synthetic backwash"
	color = "#331a1a"

	glass_name = REAGENT_ID_OILSLIDE
	glass_desc = "Tasty, if you're a synth, not so much for organics."
	wiki_flag = WIKI_DRINK

/datum/reagent/ethanol/sitonmyface
	name = REAGENT_SITONMYFACE
	id = REAGENT_ID_SITONMYFACE
	description = "A drink made of irish coffee and nuts, mostly known for its vulgar name. Makes for a great pickup line though!"
	taste_description = "creamy coffee and alcohol, and nuts"
	color = "#896750"
	strength = 15

	glass_name = REAGENT_SITONMYFACE
	glass_desc = "A drink made of irish coffee and nuts, mostly known for its vulgar name. Makes for a great pickup line though!"

/datum/reagent/ethanol/hachi
	name = REAGENT_HACHI
	id = REAGENT_ID_HACHI
	description = "An unusual fusion of bourbon and sake infused with lemon juice, and mushrooms. Sweet, savory, but mostly weird."
	taste_description = "sweet lemons, black pepper, and savory mushroom"
	color = "#DC971D"
	strength = 20

/datum/reagent/drink/freshtea
	treatment_tags = list(TREAT_ANTITOXIN = 0.3)
	name = REAGENT_FRESHTEA
	id = REAGENT_ID_FRESHTEA //Not meant to be obtainable, this is to define effects for teas made from grown teas.
	description = "Tasty green tea, it has antioxidants, it's good for you! Fresh means it's even healthier!"
	taste_description = "green tea"
	color = "#cac162"
	adj_dizzy = -4
	adj_drowsy = -1
	adj_sleepy = -3
	adj_temp = 20

	glass_name = "green tea"
	glass_desc = "Tasty green tea, it has antioxidants, it's good for you!"

	cup_icon_state = "cup_tea"
	cup_name = "cup of tea"
	cup_desc = "Tasty green tea, it has antioxidants, it's good for you!"

// Fresh tea's antitoxin action is its treatment_tags profile (higher than other tea, still worse than dylovene).

/datum/reagent/drink/freshtea/green
	name = REAGENT_FRESHGREENTEA
	id = REAGENT_ID_FRESHTEAGREEN
	description = "Floral green tea, it has antioxidants, it's good for you! Fresh means it's even healthier!"
	taste_description = "floral with vegetal notes and a slightly bitter aftertaste"
	color = "#cac162"

	glass_name = "green tea"
	glass_desc = "Floral green tea, it has antioxidants, it's fresh and good for you!"

	cup_icon_state = "cup_tea"
	cup_name = "cup of tea"
	cup_desc = "Floral green tea, it has antioxidants, it's fresh and good for you!"

/datum/reagent/drink/tealeavesgreen
	name = REAGENT_TEALEAVESGREEN
	id = REAGENT_ID_TEALEAVESGREEN
	description = "Prepared green tea, just waiting for hot water."
	taste_description = "overwhelmingly bitter with faint floral notes"
	color = "#56761d"

	glass_name = "tea leaves"
	glass_desc = "Dry tea leaves in a cup. Just add hot water!"

/datum/reagent/drink/teamush
	name = REAGENT_TEAMUSH
	id = REAGENT_ID_TEAMUSH
	description = "Mashed tea leaves, a bit like grass clippings. You can't make proper tea out of this now."
	taste_description = "overwhelmingly bitter plant"
	color = "#7db72d"

	glass_name = "blended plant"
	glass_desc = "Chunky, mashed up plant of some sort. Looks kinda gross."

/datum/reagent/drink/instantteapowdergreen
	name = REAGENT_INSTANTTEAPOWDERGREEN
	id = REAGENT_ID_INSTANTTEAPOWDERGREEN
	description = "Green tea powder missing all the goodness of green tea." //Heathen.
	taste_description = "strong bitterness with a subtle chemical aftertaste"
	color = "#56761d"

	glass_name = "tea powder"
	glass_desc = "Instant green tea powder. Just add water for imitation green tea!"

/datum/reagent/drink/instantteagreen
	name = REAGENT_INSTANTTEAGREEN
	id = REAGENT_ID_INSTANTTEAGREEN
	description = "Convenient green tea missing all the goodness of actual green tea." //It's not even hot.
	taste_description = "bitterness with a subtle chemical aftertaste"
	color = "#cac162"

	glass_name = "green tea"
	glass_desc = "Green tea. It smells a bit off."

	cup_icon_state = "cup_tea"
	cup_name = "cup of tea"
	cup_desc = "Green tea. It smells a bit off."

/datum/reagent/drink/matchapowder
	name = REAGENT_MATCHAPOWDER
	id = REAGENT_ID_MATCHAPOWDER
	description = "Finely ground green tea. This is about the highest quality matcha you can prepare without traditional methods."
	taste_description = "heavy bitterness"
	color = "#86a443"

	glass_name = "matcha powder"
	glass_desc = "Matcha powder, waiting for brewing."

/datum/reagent/drink/matcha
	treatment_tags = list(TREAT_ANTITOXIN = 0.45)
	name = REAGENT_MATCHA
	id = REAGENT_ID_MATCHA
	description = "A form of green tea where the leaf is ground and suspended in water rather than steeped. This is considered cooking grade."
	taste_description = "floral, full-bodied bitterness with a subtle, earthy sweetness"
	color = "#9bc265"
	adj_dizzy = -4
	adj_drowsy = -1
	adj_sleepy = -3
	adj_temp = 20

	glass_name = REAGENT_ID_MATCHA
	glass_desc = "Heavenly matcha. Good for body and spirit."

	cup_icon_state = "cup_tea"
	cup_name = "cup of matcha"
	cup_desc = "Heavenly matcha. Good for body and spirit."

// Matcha's antitoxin action is its treatment_tags profile (almost on par with dylovene).

/datum/reagent/drink/bubbleteawatermelon
	name = REAGENT_BUBBLETEAWATERMELON
	id = REAGENT_ID_BUBBLETEAWATERMELON
	description = "A tea with milk and watermelon in it and gelatin balls as well."
	taste_description = "creamy tea and watermelon"
	color = "#b83333"

	glass_name = "watermelon bubble tea"
	glass_desc = "A sweet tea with tasty little flavoured gelatin balls in it, this one is with watermelon."

/datum/reagent/drink/bubbleteastrawberry
	name = REAGENT_BUBBLETEASTRAWBERRY
	id = REAGENT_ID_BUBBLETEASTRAWBERRY
	description = "A tea with milk and strawberry in it and gelatin balls as well."
	taste_description = "creamy tea and strawberry"
	color = "#eb6c77"

	glass_name = "strawberry bubble tea"
	glass_desc = "A sweet tea with tasty little flavoured gelatin balls in it, this one is with strawberry."

/datum/reagent/drink/bubbleteacherry
	name = REAGENT_BUBBLETEACHERRY
	id = REAGENT_ID_BUBBLETEACHERRY
	description = "A tea with milk and cherry in it and gelatin balls as well."
	taste_description = "creamy tea and cherry"
	color = "#801e28"

	glass_name = "cherry bubble tea"
	glass_desc = "A sweet tea with tasty little flavoured gelatin balls in it, this one is with cherry."

/datum/reagent/drink/bubbleteacoffee
	name = REAGENT_BUBBLETEACOFFEE
	id = REAGENT_ID_BUBBLETEACOFFEE
	description = "A tea with milk and coffee in it and gelatin balls as well."
	taste_description = "creamy tea and coffee"
	color = "#482910"

	glass_name = "coffee bubble tea"
	glass_desc = "A sweet tea with tasty little flavoured gelatin balls in it, this one is with coffee."

/datum/reagent/drink/bubbleteabanana
	name = REAGENT_BUBBLETEABANANA
	id = REAGENT_ID_BUBBLETEABANANA
	description = "A tea with milk and banana in it and gelatin balls as well."
	taste_description = "creamy tea and banana"
	color = "#c3af00"

	glass_name = "banana bubble tea"
	glass_desc = "A sweet tea with tasty little flavoured gelatin balls in it, this one is with banana."

/datum/reagent/drink/horchata
	name = REAGENT_HORCHATA
	id = REAGENT_ID_HORCHATA
	description = "A sweet and cold rice milk beverage."
	taste_description = "sweet rice milk and cinnamon"
	color = "#ebcdc1"
	adj_temp = -5

	glass_name = REAGENT_ID_HORCHATA
	glass_desc = "A sweet and cold rice milk beverage."

/datum/reagent/ethanol/narsour
	name = REAGENT_NARSOUR
	id = REAGENT_ID_NARSOUR
	description = "Side effects include self-mutilation and hoarding plasteel."
	taste_description = "blood and runes"
	color = "#7D1717"
	strength = 10

	glass_icon_state = REAGENT_ID_NARSOUR
	glass_name = REAGENT_NARSOUR
	glass_desc = "A new hit cocktail inspired by THE ARM Breweries will have you shouting Fuu ma'jin in no time!"

/datum/reagent/ethanol/cogchamp
	name = REAGENT_COGCHAMP
	id = REAGENT_ID_COGCHAMP
	description = "Now you can fill yourself with the power of Ratvar!"
	taste_description = "brass taste with a hint of oil"
	color = rgb(255, 201, 49)
	strength = 10

	glass_icon_state = "cogchamp"
	glass_name = REAGENT_COGCHAMP
	glass_desc = "Not even Ratvar's Four Generals could withstand this!  Qevax Jryy!"

/datum/reagent/infusedarachnidslammer
	name = REAGENT_INFUSEDARACHNIDSLAMMER
	id = REAGENT_ID_INFUSEDARACHNIDSLAMMER
	description = "When Arachnid Slammer is metabolized you get a concortion of chemicals that breaks down slower. While the alcohol is burned off, the new compounds seems dormant, like they're waiting for some malicious toxin.."
	taste_description = "flat watered down Arachnid Slammer and a brewing tempest"
	reagent_state = LIQUID
	color = "#8040FF"
	scannable = 1
	metabolism = REM
	ingest_met = REM

	glass_name = "infused arachnid slammer"
	glass_desc = "A pint of metabolized Arachnid Slammer. Even if its flat it still somehow foams and sparkles as well as bubbles more actively when spiders are nearby."
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/infusedarachnidslammer/enragedarachnidslammer
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.3,
	)
	factors = alist(STAT_ANALGESIA = 80, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_ENRAGEDARACHNIDSLAMMER
	id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER
	description = "The best term to scientifically describe this concortion is that the compounds of the Arachnid Slammer are going into a raging frenzy from spider toxin. Its now functioning like a form of potent chemical-based white blood cells that aims to break down harmful compounds and repair the body."
	taste_description = "cold burning liquid rage and the urge to destroy any spider you see"

	glass_name = "enraged arachnid slammer"
	glass_desc = "A pint of Enraged Arachnid Slammer. It bubbles and sparkles fiercly as if it was in a berserking state!"

	wiki_flag = WIKI_DRINK
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/drink/pilk
	name = REAGENT_PILK
	id = REAGENT_ID_PILK
	description = "A forbidden mixture that dates back to the early days of space civilization, its creation is known to have caused at least one or two massacres."
	taste_description = "heresy"
	color = "#4C3100"

	glass_name = REAGENT_PILK
	glass_desc = "Why would you do this to yourself?"

	cup_name = "glass of Pilk"
	cup_desc = "A glass of regret."

//Ported Drinks
/datum/reagent/ethanol/alliescocktail
	name = REAGENT_ALLIESCOCKTAIL
	id = REAGENT_ID_ALLIESCOCKTAIL
	description = "A drink made from your allies. Not as sweet as those made from your enemies."
	taste_description = "bitter yet free"
	color = "#60f8f8" // rgb(96, 248, 248)
	strength = 45

	glass_name = "Allies cocktail"
	glass_desc = "A drink made from your allies."

/datum/reagent/ethanol/squirt_cider
	name = REAGENT_SQUIRTCIDER
	id = REAGENT_ID_SQUIRTCIDER
	description = "Fermented squirt extract with a nose of stale bread and ocean water. Whatever a squirt is."
	taste_description = "stale bread with a staler aftertaste"
	color = "#FF0000" // rgb(255, 0, 0)
	strength = 40
	glass_name = REAGENT_SQUIRTCIDER
	glass_desc = "Squirt cider will toughen you right up. Too bad about the musty aftertaste."
	nutriment_factor = 2

/datum/reagent/ethanol/fringe_weaver
	name = REAGENT_FRINGEWEAVER
	id = REAGENT_ID_FRINGEWEAVER
	description = "Bubbly, classy, and undoubtedly strong - a Glitch City classic."
	taste_description = "ethylic alcohol with a hint of sugar"
	color = "#FFEAC4" // rgb(255, 234, 197)
	strength = 10
	glass_name = REAGENT_FRINGEWEAVER
	glass_desc = "It's a wonder it doesn't spill out of the glass."

/datum/reagent/ethanol/duplex
	name = REAGENT_DUPLEX
	id = REAGENT_ID_DUPLEX
	description = "An inseparable combination of two fruity drinks."
	taste_description = "green apples and blue raspberries"
	color = "#50e5cf" // rgb(80, 229, 207)
	strength = 50
	glass_name = REAGENT_DUPLEX
	glass_desc = "To imbibe one component separately from the other is consider a great faux pas."

/datum/reagent/ethanol/hiveminderaser
	name = REAGENT_HIVEMINDERASER
	id = REAGENT_ID_HIVEMINDERASER
	description = "A vessel of pure flavor."
	taste_description = "psychic links"
	color = "#FF80FC" // rgb(255, 128, 252)
	strength = 50
	glass_name = REAGENT_HIVEMINDERASER
	glass_desc = "For when even mindshields can't save you."

/datum/reagent/ethanol/erikasurprise
	name = REAGENT_ERIKASURPRISE
	id = REAGENT_ID_ERIKASURPRISE
	description = "The surprise is, it's green!"
	taste_description = "tartness and bananas"
	color = "#2E6671" // rgb(46, 102, 113)
	strength = 75
	glass_name = REAGENT_ERIKASURPRISE
	glass_desc = "The surprise is, it's green!"

////////////////////////////////////////////////
/////////FOODSTUFF/////////////////////////////
//////////////////////////////////////////////

//YW drinks
/datum/reagent/ethanol/wormblood
	name = REAGENT_WORMBLOOD
	id = REAGENT_ID_WORMBLOOD
	description = "Who had the grand idea to bottle THE BLOOD OF A WORM."
	taste_description = "Wriggly cave fungus"
	color = "#827A00"
	strength = 30
	druggy = 10

	glass_name = "Worm blood"
	glass_desc = "Who had the grand idea to bottle THE BLOOD OF A WORM."
	glass_icon_state = "wormblood"
	glass_center_of_mass_x = 16
	glass_center_of_mass_y = 8
	glass_icon_file = 'icons/obj/drinks_yw.dmi'

/datum/reagent/blondiemix
	name = REAGENT_BLONDIEMIX
	id = REAGENT_ID_BLONDIEMIX
	description = "A dry mix for making delicious blondies."
	reagent_state = SOLID
	color = "#f3b44e"

	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
