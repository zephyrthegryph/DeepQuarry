/transformation/chem/instant/drinks

/transformation/chem/instant/drinks/grapejuice

CAPABILITIES(/transformation/chem/instant/drinks/grapejuice)
	configure(transformation(name = REAGENT_GRAPEJUICE, id = REAGENT_ID_GRAPEJUICE,
		takes = list(reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_INSTANTGRAPE, 1)),
		makes = list(reagent(REAGENT_ID_GRAPEJUICE, 3))))

/transformation/chem/instant/drinks/orangejuice

CAPABILITIES(/transformation/chem/instant/drinks/orangejuice)
	configure(transformation(name = REAGENT_ORANGEJUICE, id = REAGENT_ID_ORANGEJUICE,
		takes = list(reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_INSTANTORANGE, 1)),
		makes = list(reagent(REAGENT_ID_ORANGEJUICE, 3))))

/transformation/chem/instant/drinks/watermelonjuice

CAPABILITIES(/transformation/chem/instant/drinks/watermelonjuice)
	configure(transformation(name = REAGENT_WATERMELONJUICE, id = REAGENT_ID_WATERMELONJUICE,
		takes = list(reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_INSTANTWATERMELON, 1)),
		makes = list(reagent(REAGENT_ID_WATERMELONJUICE, 3))))

/transformation/chem/instant/drinks/applejuice

CAPABILITIES(/transformation/chem/instant/drinks/applejuice)
	configure(transformation(name = REAGENT_APPLEJUICE, id = REAGENT_ID_APPLEJUICE,
		takes = list(reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_INSTANTAPPLE, 1)),
		makes = list(reagent(REAGENT_ID_APPLEJUICE, 3))))

/transformation/chem/instant/drinks/goldschlager

CAPABILITIES(/transformation/chem/instant/drinks/goldschlager)
	configure(transformation(name = REAGENT_GOLDSCHLAGER, id = REAGENT_ID_GOLDSCHLAGER,
		takes = list(reagent(REAGENT_ID_VODKA, 10), reagent(REAGENT_ID_GOLD, 1)),
		makes = list(reagent(REAGENT_ID_GOLDSCHLAGER, 10))))

/transformation/chem/instant/drinks/patron

CAPABILITIES(/transformation/chem/instant/drinks/patron)
	configure(transformation(name = REAGENT_PATRON, id = REAGENT_ID_PATRON,
		takes = list(reagent(REAGENT_ID_TEQUILA, 10), reagent(REAGENT_ID_SILVER, 1)), makes = list(reagent(REAGENT_ID_PATRON, 10))))

/transformation/chem/instant/drinks/bilk

CAPABILITIES(/transformation/chem/instant/drinks/bilk)
	configure(transformation(name = REAGENT_BILK, id = REAGENT_ID_BILK, takes = list(reagent(REAGENT_ID_MILK, 1), reagent(REAGENT_ID_BEER, 1)),
		makes = list(reagent(REAGENT_ID_BILK, 2))))

/transformation/chem/instant/drinks/icetea

CAPABILITIES(/transformation/chem/instant/drinks/icetea)
	configure(transformation(name = REAGENT_ICETEA, id = REAGENT_ID_ICETEA, takes = list(reagent(REAGENT_ID_ICE, 1), reagent(REAGENT_ID_TEA, 2)),
		makes = list(reagent(REAGENT_ID_ICETEA, 3))))

/transformation/chem/instant/drinks/icecoffee

CAPABILITIES(/transformation/chem/instant/drinks/icecoffee)
	configure(transformation(name = REAGENT_ICECOFFEE, id = REAGENT_ID_ICECOFFEE,
		takes = list(reagent(REAGENT_ID_ICE, 1), reagent(REAGENT_ID_COFFEE, 2)), makes = list(reagent(REAGENT_ID_ICECOFFEE, 3))))

/transformation/chem/instant/drinks/icecoffee/alt

CAPABILITIES(/transformation/chem/instant/drinks/icecoffee/alt)
	configure(transformation(name = "Iced Drip Coffee", id = REAGENT_ID_ICECOFFEE + "_drip",
		takes = list(reagent(REAGENT_ID_ICE, 1), reagent(REAGENT_ID_DRIPCOFFEE, 2)),
		makes = list(reagent(REAGENT_ID_ICECOFFEE, 3))))

/transformation/chem/instant/drinks/blackeye

CAPABILITIES(/transformation/chem/instant/drinks/blackeye)
	configure(transformation(name = REAGENT_BLACKEYE, id = REAGENT_ID_BLACKEYE,
		takes = list(reagent(REAGENT_ID_DRIPCOFFEE, 1), reagent(REAGENT_ID_COFFEE, 1)),
		makes = list(reagent(REAGENT_ID_BLACKEYE, 1))))

/transformation/chem/instant/drinks/americano

CAPABILITIES(/transformation/chem/instant/drinks/americano)
	configure(transformation(name = REAGENT_AMERICANO, id = REAGENT_ID_AMERICANO,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_LONGBLACK, 2)),
		makes = list(reagent(REAGENT_ID_AMERICANO, 3))))

/transformation/chem/instant/drinks/long_black

CAPABILITIES(/transformation/chem/instant/drinks/long_black)
	configure(transformation(name = REAGENT_LONGBLACK, id = REAGENT_ID_LONGBLACK,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_COFFEE, 1)), makes = list(reagent(REAGENT_ID_LONGBLACK, 2))))

/transformation/chem/instant/drinks/macchiato

CAPABILITIES(/transformation/chem/instant/drinks/macchiato)
	configure(transformation(name = REAGENT_MACCHIATO, id = REAGENT_ID_MACCHIATO,
		takes = list(reagent(REAGENT_ID_MILK, 1), reagent(REAGENT_ID_COFFEE, 2)), makes = list(reagent(REAGENT_ID_MACCHIATO, 3))))

/transformation/chem/instant/drinks/cortado

CAPABILITIES(/transformation/chem/instant/drinks/cortado)
	configure(transformation(name = REAGENT_CORTADO, id = REAGENT_ID_CORTADO,
		takes = list(reagent(REAGENT_ID_MACCHIATO, 3), reagent(REAGENT_ID_MILKFOAM, 1)),
		makes = list(reagent(REAGENT_ID_CORTADO, 4))))

/transformation/chem/instant/drinks/breve

CAPABILITIES(/transformation/chem/instant/drinks/breve)
	configure(transformation(name = REAGENT_BREVE, id = REAGENT_ID_BREVE, takes = list(reagent(REAGENT_ID_CORTADO, 4), reagent(REAGENT_ID_CREAM, 1)),
		makes = list(reagent(REAGENT_ID_BREVE, 5))))

/transformation/chem/instant/drinks/cappuccino

CAPABILITIES(/transformation/chem/instant/drinks/cappuccino)
	configure(transformation(name = REAGENT_CAPPUCCINO, id = REAGENT_ID_CAPPUCCINO,
		takes = list(reagent(REAGENT_ID_MILK, 1), reagent(REAGENT_ID_MILKFOAM, 1), reagent(REAGENT_ID_CORTADO, 4)),
		makes = list(reagent(REAGENT_ID_CAPPUCCINO, 6))))

/transformation/chem/instant/drinks/flat_white

CAPABILITIES(/transformation/chem/instant/drinks/flat_white)
	configure(transformation(name = REAGENT_FLATWHITE, id = REAGENT_ID_FLATWHITE,
		takes = list(reagent(REAGENT_ID_MILK, 2), reagent(REAGENT_ID_DRIPCOFFEE, 1)),
		makes = list(reagent(REAGENT_ID_FLATWHITE, 3))))

/transformation/chem/instant/drinks/mocha

CAPABILITIES(/transformation/chem/instant/drinks/mocha)
	configure(transformation(name = REAGENT_MOCHA, id = REAGENT_ID_MOCHA + "_milk",
		takes = list(reagent(REAGENT_ID_MILK, 1), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_MILKFOAM, 1), reagent(REAGENT_ID_HOTCOCO, 2), reagent(REAGENT_ID_BREVE, 5)),
		makes = list(reagent(REAGENT_ID_MOCHA, 10))))

/transformation/chem/instant/drinks/mocha/alt //incase they use cream before milk

CAPABILITIES(/transformation/chem/instant/drinks/mocha/alt)
	configure(transformation(name = REAGENT_MOCHA, id = REAGENT_ID_MOCHA + "_cream",
		takes = list(reagent(REAGENT_ID_CREAM, 2), reagent(REAGENT_ID_HOTCOCO, 2), reagent(REAGENT_ID_CAPPUCCINO, 6)),
		makes = list(reagent(REAGENT_ID_MOCHA, 10))))

/transformation/chem/instant/drinks/vienna

CAPABILITIES(/transformation/chem/instant/drinks/vienna)
	configure(transformation(name = REAGENT_VIENNA, id = REAGENT_ID_VIENNA, takes = list(reagent(REAGENT_ID_CREAM, 2), reagent(REAGENT_ID_COFFEE, 1)),
		makes = list(reagent(REAGENT_ID_VIENNA, 3))))

/transformation/chem/instant/drinks/nuka_cola

CAPABILITIES(/transformation/chem/instant/drinks/nuka_cola)
	configure(transformation(name = "Nuclear Cola", id = REAGENT_ID_NUKACOLA, takes = list(reagent(REAGENT_ID_URANIUM, 1), reagent(REAGENT_ID_COLA, 5)),
		makes = list(reagent(REAGENT_ID_NUKACOLA, 5))))

/transformation/chem/instant/drinks/moonshine

CAPABILITIES(/transformation/chem/instant/drinks/moonshine)
	configure(transformation(name = REAGENT_MOONSHINE, id = REAGENT_ID_MOONSHINE, takes = list(reagent(REAGENT_ID_NUTRIMENT, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_MOONSHINE, 10))))

/transformation/chem/instant/drinks/grenadine

CAPABILITIES(/transformation/chem/instant/drinks/grenadine)
	configure(transformation(name = REAGENT_GRENADINE, id = REAGENT_ID_GRENADINE, takes = list(reagent(REAGENT_ID_BERRYJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_GRENADINE, 10))))

/transformation/chem/instant/drinks/wine

CAPABILITIES(/transformation/chem/instant/drinks/wine)
	configure(transformation(name = "Wine", id = REAGENT_ID_REDWINE, takes = list(reagent(REAGENT_ID_GRAPEJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_REDWINE, 10))))

/transformation/chem/instant/drinks/pwine

CAPABILITIES(/transformation/chem/instant/drinks/pwine)
	configure(transformation(name = REAGENT_PWINE, id = REAGENT_ID_PWINE, takes = list(reagent(REAGENT_ID_POISONBERRYJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_PWINE, 10))))

/transformation/chem/instant/drinks/melonliquor

CAPABILITIES(/transformation/chem/instant/drinks/melonliquor)
	configure(transformation(name = REAGENT_MELONLIQUOR, id = REAGENT_ID_MELONLIQUOR, takes = list(reagent(REAGENT_ID_WATERMELONJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_MELONLIQUOR, 10))))

/transformation/chem/instant/drinks/bluecuracao

CAPABILITIES(/transformation/chem/instant/drinks/bluecuracao)
	configure(transformation(name = REAGENT_BLUECURACAO, id = REAGENT_ID_BLUECURACAO, takes = list(reagent(REAGENT_ID_ORANGEJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_BLUECURACAO, 10))))

/transformation/chem/instant/drinks/spacebeer

CAPABILITIES(/transformation/chem/instant/drinks/spacebeer)
	configure(transformation(name = "Space Beer", id = "spacebeer", takes = list(reagent(REAGENT_ID_CORNOIL, 5), reagent(REAGENT_ID_FLOUR, 5)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_BEER, 10))))

/transformation/chem/instant/drinks/vodka

CAPABILITIES(/transformation/chem/instant/drinks/vodka)
	configure(transformation(name = REAGENT_VODKA, id = REAGENT_ID_VODKA, takes = list(reagent(REAGENT_ID_POTATOJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_VODKA, 10))))

/transformation/chem/instant/drinks/cider

CAPABILITIES(/transformation/chem/instant/drinks/cider)
	configure(transformation(name = REAGENT_CIDER, id = REAGENT_ID_CIDER, takes = list(reagent(REAGENT_ID_APPLEJUICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_CIDER, 10))))


/transformation/chem/instant/drinks/sake

CAPABILITIES(/transformation/chem/instant/drinks/sake)
	configure(transformation(name = REAGENT_SAKE, id = REAGENT_ID_SAKE, takes = list(reagent(REAGENT_ID_RICE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_SAKE, 10))))

/transformation/chem/instant/drinks/kahlua

CAPABILITIES(/transformation/chem/instant/drinks/kahlua)
	configure(transformation(name = REAGENT_KAHLUA, id = REAGENT_ID_KAHLUA, takes = list(reagent(REAGENT_ID_COFFEE, 5), reagent(REAGENT_ID_SUGAR, 5)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_KAHLUA, 5))))

/transformation/chem/instant/drinks/gin_tonic

CAPABILITIES(/transformation/chem/instant/drinks/gin_tonic)
	configure(transformation(name = REAGENT_GINTONIC, id = REAGENT_ID_GINTONIC, takes = list(reagent(REAGENT_ID_GIN, 2), reagent(REAGENT_ID_TONIC, 1)),
		makes = list(reagent(REAGENT_ID_GINTONIC, 3))))

/transformation/chem/instant/drinks/rum_and_cola

CAPABILITIES(/transformation/chem/instant/drinks/rum_and_cola)
	configure(transformation(name = REAGENT_RUMANDCOLA, id = REAGENT_ID_RUMANDCOLA,
		takes = list(reagent(REAGENT_ID_RUM, 2), reagent(REAGENT_ID_COLA, 1)), makes = list(reagent(REAGENT_ID_RUMANDCOLA, 3))))

/transformation/chem/instant/drinks/cuba_libre

CAPABILITIES(/transformation/chem/instant/drinks/cuba_libre)
	configure(transformation(name = REAGENT_CUBALIBRE, id = REAGENT_ID_CUBALIBRE,
		takes = list(reagent(REAGENT_ID_RUMANDCOLA, 3), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_CUBALIBRE, 3))))

/transformation/chem/instant/drinks/martini

CAPABILITIES(/transformation/chem/instant/drinks/martini)
	configure(transformation(name = REAGENT_MARTINI, id = REAGENT_ID_MARTINI, takes = list(reagent(REAGENT_ID_GIN, 2), reagent(REAGENT_ID_VERMOUTH, 1)),
		blocked_by = list(reagent(REAGENT_ID_BITTERS, 1)), makes = list(reagent(REAGENT_ID_MARTINI, 3))))

/transformation/chem/instant/drinks/vodkamartini

CAPABILITIES(/transformation/chem/instant/drinks/vodkamartini)
	configure(transformation(name = REAGENT_VODKAMARTINI, id = REAGENT_ID_VODKAMARTINI,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_VERMOUTH, 1)),
		makes = list(reagent(REAGENT_ID_VODKAMARTINI, 3))))

/transformation/chem/instant/drinks/white_russian

CAPABILITIES(/transformation/chem/instant/drinks/white_russian)
	configure(transformation(name = REAGENT_WHITERUSSIAN, id = REAGENT_ID_WHITERUSSIAN,
		takes = list(reagent(REAGENT_ID_BLACKRUSSIAN, 2), reagent(REAGENT_ID_CREAM, 1)),
		makes = list(reagent(REAGENT_ID_WHITERUSSIAN, 3))))

/transformation/chem/instant/drinks/whiskey_cola

CAPABILITIES(/transformation/chem/instant/drinks/whiskey_cola)
	configure(transformation(name = REAGENT_WHISKEYCOLA, id = REAGENT_ID_WHISKEYCOLA,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_COLA, 1)),
		makes = list(reagent(REAGENT_ID_WHISKEYCOLA, 3))))

/transformation/chem/instant/drinks/screwdriver

CAPABILITIES(/transformation/chem/instant/drinks/screwdriver)
	configure(transformation(name = REAGENT_SCREWDRIVERCOCKTAIL, id = REAGENT_ID_SCREWDRIVERCOCKTAIL,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_ORANGEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_SCREWDRIVERCOCKTAIL, 3))))

/transformation/chem/instant/drinks/bloody_mary

CAPABILITIES(/transformation/chem/instant/drinks/bloody_mary)
	configure(transformation(name = REAGENT_BLOODYMARY, id = REAGENT_ID_BLOODYMARY,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_TOMATOJUICE, 3), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_BLOODYMARY, 6))))

/transformation/chem/instant/drinks/gargle_blaster

CAPABILITIES(/transformation/chem/instant/drinks/gargle_blaster)
	configure(transformation(name = REAGENT_GARGLEBLASTER, id = REAGENT_ID_GARGLEBLASTER,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_GIN, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_COGNAC, 1), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_GARGLEBLASTER, 6))))

/transformation/chem/instant/drinks/brave_bull

CAPABILITIES(/transformation/chem/instant/drinks/brave_bull)
	configure(transformation(name = REAGENT_BRAVEBULL, id = REAGENT_ID_BRAVEBULL,
		takes = list(reagent(REAGENT_ID_TEQUILA, 2), reagent(REAGENT_ID_KAHLUA, 1)),
		makes = list(reagent(REAGENT_ID_BRAVEBULL, 3))))

/transformation/chem/instant/drinks/tequila_sunrise

CAPABILITIES(/transformation/chem/instant/drinks/tequila_sunrise)
	configure(transformation(name = "Tequilla Sunrise", id = REAGENT_ID_TEQUILASUNRISE,
		takes = list(reagent(REAGENT_ID_TEQUILA, 2), reagent(REAGENT_ID_ORANGEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_TEQUILASUNRISE, 3))))

/transformation/chem/instant/drinks/phoron_special

CAPABILITIES(/transformation/chem/instant/drinks/phoron_special)
	configure(transformation(name = REAGENT_PHORONSPECIAL, id = REAGENT_ID_PHORONSPECIAL,
		takes = list(reagent(REAGENT_ID_RUM, 2), reagent(REAGENT_ID_VERMOUTH, 2), reagent(REAGENT_ID_PHORON, 2)),
		makes = list(reagent(REAGENT_ID_PHORONSPECIAL, 6))))

/transformation/chem/instant/drinks/beepsky_smash

CAPABILITIES(/transformation/chem/instant/drinks/beepsky_smash)
	configure(transformation(name = "Beepksy Smash", id = "beepksysmash",
		takes = list(reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_BEEPSKYSMASH, 2))))

/transformation/chem/instant/drinks/doctor_delight

CAPABILITIES(/transformation/chem/instant/drinks/doctor_delight)
	configure(transformation(name = REAGENT_DOCTORSDELIGHT, id = "doctordelight",
		takes = list(reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_TOMATOJUICE, 1), reagent(REAGENT_ID_ORANGEJUICE, 1), reagent(REAGENT_ID_CREAM, 2), reagent(REAGENT_ID_TRICORDRAZINE, 1)),
		makes = list(reagent(REAGENT_ID_DOCTORSDELIGHT, 6))))

/transformation/chem/instant/drinks/irish_cream

CAPABILITIES(/transformation/chem/instant/drinks/irish_cream)
	configure(transformation(name = REAGENT_IRISHCREAM, id = REAGENT_ID_IRISHCREAM,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_CREAM, 1)),
		blocked_by = list(reagent(REAGENT_ID_WATERMELONJUICE, 1)), makes = list(reagent(REAGENT_ID_IRISHCREAM, 3))))

/transformation/chem/instant/drinks/manly_dorf

CAPABILITIES(/transformation/chem/instant/drinks/manly_dorf)
	configure(transformation(name = REAGENT_MANLYDORF, id = REAGENT_ID_MANLYDORF, takes = list(reagent(REAGENT_ID_BEER, 1), reagent(REAGENT_ID_ALE, 2)),
		makes = list(reagent(REAGENT_ID_MANLYDORF, 3))))

/transformation/chem/instant/drinks/hooch

CAPABILITIES(/transformation/chem/instant/drinks/hooch)
	configure(transformation(name = REAGENT_HOOCH, id = REAGENT_ID_HOOCH,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_ETHANOL, 2), reagent(REAGENT_ID_FUEL, 1)),
		makes = list(reagent(REAGENT_ID_HOOCH, 3))))

/transformation/chem/instant/drinks/irish_coffee

CAPABILITIES(/transformation/chem/instant/drinks/irish_coffee)
	configure(transformation(name = REAGENT_IRISHCOFFEE, id = REAGENT_ID_IRISHCOFFEE,
		takes = list(reagent(REAGENT_ID_IRISHCREAM, 1), reagent(REAGENT_ID_COFFEE, 1)),
		makes = list(reagent(REAGENT_ID_IRISHCOFFEE, 2))))

/transformation/chem/instant/drinks/b52

CAPABILITIES(/transformation/chem/instant/drinks/b52)
	configure(transformation(name = REAGENT_B52, id = REAGENT_ID_B52,
		takes = list(reagent(REAGENT_ID_IRISHCREAM, 1), reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_COGNAC, 1)),
		makes = list(reagent(REAGENT_ID_B52, 3))))

/transformation/chem/instant/drinks/atomicbomb

CAPABILITIES(/transformation/chem/instant/drinks/atomicbomb)
	configure(transformation(name = REAGENT_ATOMICBOMB, id = REAGENT_ID_ATOMICBOMB,
		takes = list(reagent(REAGENT_ID_B52, 10), reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_ATOMICBOMB, 10))))

/transformation/chem/instant/drinks/margarita

CAPABILITIES(/transformation/chem/instant/drinks/margarita)
	configure(transformation(name = REAGENT_MARGARITA, id = REAGENT_ID_MARGARITA,
		takes = list(reagent(REAGENT_ID_TEQUILA, 2), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_MARGARITA, 3))))

/transformation/chem/instant/drinks/longislandicedtea

CAPABILITIES(/transformation/chem/instant/drinks/longislandicedtea)
	configure(transformation(name = REAGENT_LONGISLANDICEDTEA, id = REAGENT_ID_LONGISLANDICEDTEA,
		takes = list(reagent(REAGENT_ID_VODKA, 1), reagent(REAGENT_ID_GIN, 1), reagent(REAGENT_ID_TEQUILA, 1), reagent(REAGENT_ID_RUMANDCOLA, 3)),
		makes = list(reagent(REAGENT_ID_LONGISLANDICEDTEA, 6))))

/transformation/chem/instant/drinks/threemileisland

CAPABILITIES(/transformation/chem/instant/drinks/threemileisland)
	configure(transformation(name = REAGENT_THREEMILEISLAND, id = REAGENT_ID_THREEMILEISLAND,
		takes = list(reagent(REAGENT_ID_LONGISLANDICEDTEA, 10), reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_THREEMILEISLAND, 10))))

/transformation/chem/instant/drinks/whiskeysoda

CAPABILITIES(/transformation/chem/instant/drinks/whiskeysoda)
	configure(transformation(name = REAGENT_WHISKEYSODA, id = REAGENT_ID_WHISKEYSODA,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_WHISKEYSODA, 3))))

/transformation/chem/instant/drinks/black_russian

CAPABILITIES(/transformation/chem/instant/drinks/black_russian)
	configure(transformation(name = REAGENT_BLACKRUSSIAN, id = REAGENT_ID_BLACKRUSSIAN,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_KAHLUA, 1)),
		makes = list(reagent(REAGENT_ID_BLACKRUSSIAN, 3))))

/transformation/chem/instant/drinks/manhattan

CAPABILITIES(/transformation/chem/instant/drinks/manhattan)
	configure(transformation(name = REAGENT_MANHATTAN, id = REAGENT_ID_MANHATTAN,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_VERMOUTH, 1)),
		makes = list(reagent(REAGENT_ID_MANHATTAN, 3))))

/transformation/chem/instant/drinks/manhattan_proj

CAPABILITIES(/transformation/chem/instant/drinks/manhattan_proj)
	configure(transformation(name = REAGENT_MANHATTANPROJ, id = REAGENT_ID_MANHATTANPROJ,
		takes = list(reagent(REAGENT_ID_MANHATTAN, 10), reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_MANHATTANPROJ, 10))))

/transformation/chem/instant/drinks/vodka_tonic

CAPABILITIES(/transformation/chem/instant/drinks/vodka_tonic)
	configure(transformation(name = REAGENT_VODKATONIC, id = REAGENT_ID_VODKATONIC,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_TONIC, 1)), makes = list(reagent(REAGENT_ID_VODKATONIC, 3))))

/transformation/chem/instant/drinks/gin_fizz

CAPABILITIES(/transformation/chem/instant/drinks/gin_fizz)
	configure(transformation(name = REAGENT_GINFIZZ, id = REAGENT_ID_GINFIZZ,
		takes = list(reagent(REAGENT_ID_GIN, 1), reagent(REAGENT_ID_SODAWATER, 1), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_GINFIZZ, 3))))

/transformation/chem/instant/drinks/bahama_mama

CAPABILITIES(/transformation/chem/instant/drinks/bahama_mama)
	configure(transformation(name = REAGENT_BAHAMAMAMA, id = REAGENT_ID_BAHAMAMAMA,
		takes = list(reagent(REAGENT_ID_RUM, 2), reagent(REAGENT_ID_ORANGEJUICE, 2), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_BAHAMAMAMA, 6))))

/transformation/chem/instant/drinks/singulo

CAPABILITIES(/transformation/chem/instant/drinks/singulo)
	configure(transformation(name = REAGENT_SINGULO, id = REAGENT_ID_SINGULO,
		takes = list(reagent(REAGENT_ID_VODKA, 5), reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_REDWINE, 5)),
		makes = list(reagent(REAGENT_ID_SINGULO, 10))))

/transformation/chem/instant/drinks/alliescocktail

CAPABILITIES(/transformation/chem/instant/drinks/alliescocktail)
	configure(transformation(name = REAGENT_ALLIESCOCKTAIL, id = REAGENT_ID_ALLIESCOCKTAIL,
		takes = list(reagent(REAGENT_ID_MARTINI, 1), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_ALLIESCOCKTAIL, 2))))

/transformation/chem/instant/drinks/demonsblood

CAPABILITIES(/transformation/chem/instant/drinks/demonsblood)
	configure(transformation(name = REAGENT_DEMONSBLOOD, id = REAGENT_ID_DEMONSBLOOD,
		takes = list(reagent(REAGENT_ID_RUM, 3), reagent(REAGENT_ID_SPACEMOUNTAINWIND, 1), reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_DRGIBB, 1)),
		makes = list(reagent(REAGENT_ID_DEMONSBLOOD, 6))))

/transformation/chem/instant/drinks/booger

CAPABILITIES(/transformation/chem/instant/drinks/booger)
	configure(transformation(name = REAGENT_BOOGER, id = REAGENT_ID_BOOGER,
		takes = list(reagent(REAGENT_ID_CREAM, 2), reagent(REAGENT_ID_BANANA, 1), reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_WATERMELONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_BOOGER, 5))))

/transformation/chem/instant/drinks/antifreeze

CAPABILITIES(/transformation/chem/instant/drinks/antifreeze)
	configure(transformation(name = REAGENT_ANTIFREEZE, id = REAGENT_ID_ANTIFREEZE,
		takes = list(reagent(REAGENT_ID_VODKA, 1), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_ANTIFREEZE, 3))))

/transformation/chem/instant/drinks/barefoot

CAPABILITIES(/transformation/chem/instant/drinks/barefoot)
	configure(transformation(name = REAGENT_BAREFOOT, id = REAGENT_ID_BAREFOOT,
		takes = list(reagent(REAGENT_ID_BERRYJUICE, 1), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_VERMOUTH, 1)),
		makes = list(reagent(REAGENT_ID_BAREFOOT, 3))))

/transformation/chem/instant/drinks/grapesoda

CAPABILITIES(/transformation/chem/instant/drinks/grapesoda)
	configure(transformation(name = REAGENT_GRAPESODA, id = REAGENT_ID_GRAPESODA,
		takes = list(reagent(REAGENT_ID_GRAPEJUICE, 2), reagent(REAGENT_ID_COLA, 1)),
		makes = list(reagent(REAGENT_ID_GRAPESODA, 3))))

/transformation/chem/instant/drinks/sbiten

CAPABILITIES(/transformation/chem/instant/drinks/sbiten)
	configure(transformation(name = REAGENT_SBITEN, id = REAGENT_ID_SBITEN,
		takes = list(reagent(REAGENT_ID_VODKA, 10), reagent(REAGENT_ID_CAPSAICIN, 1)),
		makes = list(reagent(REAGENT_ID_SBITEN, 10))))

/transformation/chem/instant/drinks/red_mead

CAPABILITIES(/transformation/chem/instant/drinks/red_mead)
	configure(transformation(name = REAGENT_REDMEAD, id = REAGENT_ID_REDMEAD, takes = list(reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_MEAD, 1)),
		makes = list(reagent(REAGENT_ID_REDMEAD, 2))))

/transformation/chem/instant/drinks/mead

CAPABILITIES(/transformation/chem/instant/drinks/mead)
	configure(transformation(name = REAGENT_MEAD, id = REAGENT_ID_MEAD, takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_MEAD, 2))))

/transformation/chem/instant/drinks/iced_beer

CAPABILITIES(/transformation/chem/instant/drinks/iced_beer)
	configure(transformation(name = REAGENT_ICEDBEER, id = REAGENT_ID_ICEDBEER,
		takes = list(reagent(REAGENT_ID_BEER, 10), reagent(REAGENT_ID_FROSTOIL, 1)),
		makes = list(reagent(REAGENT_ID_ICEDBEER, 10))))

/transformation/chem/instant/drinks/iced_beer2

CAPABILITIES(/transformation/chem/instant/drinks/iced_beer2)
	configure(transformation(name = REAGENT_ICEDBEER, id = REAGENT_ID_ICEDBEER + "_ice",
		takes = list(reagent(REAGENT_ID_BEER, 5), reagent(REAGENT_ID_ICE, 1)), makes = list(reagent(REAGENT_ID_ICEDBEER, 6))))

/transformation/chem/instant/drinks/grog

CAPABILITIES(/transformation/chem/instant/drinks/grog)
	configure(transformation(name = REAGENT_GROG, id = REAGENT_ID_GROG, takes = list(reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_GROG, 2))))

/transformation/chem/instant/drinks/soy_latte

CAPABILITIES(/transformation/chem/instant/drinks/soy_latte)
	configure(transformation(name = REAGENT_SOYLATTE, id = REAGENT_ID_SOYLATTE,
		takes = list(reagent(REAGENT_ID_COFFEE, 1), reagent(REAGENT_ID_SOYMILK, 1)), makes = list(reagent(REAGENT_ID_SOYLATTE, 2))))

/transformation/chem/instant/drinks/cafe_latte

CAPABILITIES(/transformation/chem/instant/drinks/cafe_latte)
	configure(transformation(name = REAGENT_CAFELATTE, id = REAGENT_ID_CAFELATTE,
		takes = list(reagent(REAGENT_ID_FLATWHITE, 1), reagent(REAGENT_ID_MILK, 1)),
		makes = list(reagent(REAGENT_ID_CAFELATTE, 2))))

/transformation/chem/instant/drinks/acidspit

CAPABILITIES(/transformation/chem/instant/drinks/acidspit)
	configure(transformation(name = REAGENT_ACIDSPIT, id = REAGENT_ID_ACIDSPIT,
		takes = list(reagent(REAGENT_ID_SACID, 1), reagent(REAGENT_ID_REDWINE, 5)), makes = list(reagent(REAGENT_ID_ACIDSPIT, 6))))

/transformation/chem/instant/drinks/amasec

CAPABILITIES(/transformation/chem/instant/drinks/amasec)
	configure(transformation(name = REAGENT_AMASEC, id = REAGENT_ID_AMASEC,
		takes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_REDWINE, 5), reagent(REAGENT_ID_VODKA, 5)),
		makes = list(reagent(REAGENT_ID_AMASEC, 10))))

/transformation/chem/instant/drinks/changeling_sting

CAPABILITIES(/transformation/chem/instant/drinks/changeling_sting)
	configure(transformation(name = REAGENT_CHANGELINGSTING, id = REAGENT_ID_CHANGELINGSTING,
		takes = list(reagent(REAGENT_ID_SCREWDRIVERCOCKTAIL, 1), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_LEMONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_CHANGELINGSTING, 3))))

/transformation/chem/instant/drinks/aloe

CAPABILITIES(/transformation/chem/instant/drinks/aloe)
	configure(transformation(name = REAGENT_ALOE, id = REAGENT_ID_ALOE,
		takes = list(reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_WATERMELONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_ALOE, 3))))

/transformation/chem/instant/drinks/andalusia

CAPABILITIES(/transformation/chem/instant/drinks/andalusia)
	configure(transformation(name = REAGENT_ANDALUSIA, id = REAGENT_ID_ANDALUSIA,
		takes = list(reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_LEMONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_ANDALUSIA, 3))))

/transformation/chem/instant/drinks/snowwhite

CAPABILITIES(/transformation/chem/instant/drinks/snowwhite)
	configure(transformation(name = REAGENT_SNOWWHITE, id = REAGENT_ID_SNOWWHITE,
		takes = list(reagent(REAGENT_ID_PINEAPPLEJUICE, 1), reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_LEMONLIME, 1), reagent(REAGENT_ID_EGG, 1), reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_SNOWWHITE, 2))))

/transformation/chem/instant/drinks/irishcarbomb

CAPABILITIES(/transformation/chem/instant/drinks/irishcarbomb)
	configure(transformation(name = REAGENT_IRISHCARBOMB, id = REAGENT_ID_IRISHCARBOMB,
		takes = list(reagent(REAGENT_ID_ALE, 1), reagent(REAGENT_ID_IRISHCREAM, 1)),
		makes = list(reagent(REAGENT_ID_IRISHCARBOMB, 2))))

/transformation/chem/instant/drinks/syndicatebomb

CAPABILITIES(/transformation/chem/instant/drinks/syndicatebomb)
	configure(transformation(name = REAGENT_SYNDICATEBOMB, id = REAGENT_ID_SYNDICATEBOMB,
		takes = list(reagent(REAGENT_ID_BEER, 1), reagent(REAGENT_ID_WHISKEYCOLA, 1)),
		makes = list(reagent(REAGENT_ID_SYNDICATEBOMB, 2))))

/transformation/chem/instant/drinks/erikasurprise

CAPABILITIES(/transformation/chem/instant/drinks/erikasurprise)
	configure(transformation(name = REAGENT_ERIKASURPRISE, id = REAGENT_ID_ERIKASURPRISE,
		takes = list(reagent(REAGENT_ID_ALE, 2), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_BANANA, 1), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_ERIKASURPRISE, 6))))

/transformation/chem/instant/drinks/devilskiss

CAPABILITIES(/transformation/chem/instant/drinks/devilskiss)
	configure(transformation(name = REAGENT_DEVILSKISS, id = REAGENT_ID_DEVILSKISS,
		takes = list(reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_RUM, 1)),
		makes = list(reagent(REAGENT_ID_DEVILSKISS, 3))))

/transformation/chem/instant/drinks/hippiesdelight

CAPABILITIES(/transformation/chem/instant/drinks/hippiesdelight)
	configure(transformation(name = "Hippies Delight", id = REAGENT_ID_HIPPIESDELIGHT,
		takes = list(reagent(REAGENT_ID_PSILOCYBIN, 1), reagent(REAGENT_ID_GARGLEBLASTER, 1)),
		makes = list(reagent(REAGENT_ID_HIPPIESDELIGHT, 2))))

/transformation/chem/instant/drinks/bananahonk

CAPABILITIES(/transformation/chem/instant/drinks/bananahonk)
	configure(transformation(name = "Banana Honk", id = REAGENT_ID_BANANAHONK,
		takes = list(reagent(REAGENT_ID_BANANA, 1), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_BANANAHONK, 3))))

/transformation/chem/instant/drinks/silencer

CAPABILITIES(/transformation/chem/instant/drinks/silencer)
	configure(transformation(name = REAGENT_SILENCER, id = REAGENT_ID_SILENCER,
		takes = list(reagent(REAGENT_ID_NOTHING, 1), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_SILENCER, 3))))

/transformation/chem/instant/drinks/driestmartini

CAPABILITIES(/transformation/chem/instant/drinks/driestmartini)
	configure(transformation(name = REAGENT_DRIESTMARTINI, id = REAGENT_ID_DRIESTMARTINI,
		takes = list(reagent(REAGENT_ID_NOTHING, 1), reagent(REAGENT_ID_GIN, 1)),
		makes = list(reagent(REAGENT_ID_DRIESTMARTINI, 2))))

/transformation/chem/instant/drinks/lemonade

CAPABILITIES(/transformation/chem/instant/drinks/lemonade)
	configure(transformation(name = REAGENT_LEMONADE, id = REAGENT_ID_LEMONADE,
		takes = list(reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_LEMONADE, 3))))

/transformation/chem/instant/drinks/melonade

CAPABILITIES(/transformation/chem/instant/drinks/melonade)
	configure(transformation(name = REAGENT_MELONADE, id = REAGENT_ID_MELONADE,
		takes = list(reagent(REAGENT_ID_WATERMELONJUICE, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_MELONADE, 3))))

/transformation/chem/instant/drinks/appleade

CAPABILITIES(/transformation/chem/instant/drinks/appleade)
	configure(transformation(name = REAGENT_APPLEADE, id = REAGENT_ID_APPLEADE,
		takes = list(reagent(REAGENT_ID_APPLEJUICE, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_APPLEADE, 3))))

/transformation/chem/instant/drinks/pineappleade

CAPABILITIES(/transformation/chem/instant/drinks/pineappleade)
	configure(transformation(name = REAGENT_PINEAPPLEADE, id = REAGENT_ID_PINEAPPLEADE,
		takes = list(reagent(REAGENT_ID_PINEAPPLEJUICE, 2), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_SODAWATER, 2), reagent(REAGENT_ID_HONEY, 1)),
		makes = list(reagent(REAGENT_ID_PINEAPPLEADE, 5))))

/transformation/chem/instant/drinks/driverspunch

CAPABILITIES(/transformation/chem/instant/drinks/driverspunch)
	configure(transformation(name = "Driver`s Punch", id = REAGENT_ID_DRIVERSPUNCH,
		takes = list(reagent(REAGENT_ID_APPLEADE, 2), reagent(REAGENT_ID_ORANGEJUICE, 1), reagent(REAGENT_ID_MINT, 1), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_DRIVERSPUNCH, 3))))

/transformation/chem/instant/drinks/mintapplesparkle

CAPABILITIES(/transformation/chem/instant/drinks/mintapplesparkle)
	configure(transformation(name = REAGENT_MINTAPPLESPARKLE, id = REAGENT_ID_MINTAPPLESPARKLE,
		takes = list(reagent(REAGENT_ID_APPLEADE, 2), reagent(REAGENT_ID_MINT, 1)),
		blocked_by = list(reagent(REAGENT_ID_SODAWATER, 1)), makes = list(reagent(REAGENT_ID_MINTAPPLESPARKLE, 3))))

/transformation/chem/instant/drinks/berrycordial

CAPABILITIES(/transformation/chem/instant/drinks/berrycordial)
	configure(transformation(name = REAGENT_BERRYCORDIAL, id = REAGENT_ID_BERRYCORDIAL,
		takes = list(reagent(REAGENT_ID_BERRYJUICE, 4), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_LEMONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_BERRYCORDIAL, 5))))

/transformation/chem/instant/drinks/tropicalfizz

CAPABILITIES(/transformation/chem/instant/drinks/tropicalfizz)
	configure(transformation(name = REAGENT_TROPICALFIZZ, id = REAGENT_ID_TROPICALFIZZ,
		takes = list(reagent(REAGENT_ID_SODAWATER, 6), reagent(REAGENT_ID_BERRYJUICE, 1), reagent(REAGENT_ID_MINT, 1), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_PINEAPPLEJUICE, 1)),
		blocked_by = list(reagent(REAGENT_ID_SUGAR, 1)), makes = list(reagent(REAGENT_ID_TROPICALFIZZ, 8))))

/transformation/chem/instant/drinks/melonspritzer

CAPABILITIES(/transformation/chem/instant/drinks/melonspritzer)
	configure(transformation(name = REAGENT_MELONSPRITZER, id = REAGENT_ID_MELONSPRITZER,
		takes = list(reagent(REAGENT_ID_WATERMELONJUICE, 2), reagent(REAGENT_ID_REDWINE, 2), reagent(REAGENT_ID_APPLEJUICE, 1), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_MELONSPRITZER, 6))))

/transformation/chem/instant/drinks/fauxfizz

CAPABILITIES(/transformation/chem/instant/drinks/fauxfizz)
	configure(transformation(name = REAGENT_FAUXFIZZ, id = REAGENT_ID_FAUXFIZZ,
		takes = list(reagent(REAGENT_ID_SODAWATER, 2), reagent(REAGENT_ID_BERRYJUICE, 1), reagent(REAGENT_ID_APPLEJUICE, 1), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_HONEY, 1)),
		blocked_by = list(reagent(REAGENT_ID_SUGAR, 1)), makes = list(reagent(REAGENT_ID_FAUXFIZZ, 6))))

/transformation/chem/instant/drinks/firepunch

CAPABILITIES(/transformation/chem/instant/drinks/firepunch)
	configure(transformation(name = REAGENT_FIREPUNCH, id = REAGENT_ID_FIREPUNCH,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_RUM, 2)),
		blocked_by = list(reagent(REAGENT_ID_LIMEJUICE, 1)), makes = list(reagent(REAGENT_ID_FIREPUNCH, 3))))

/transformation/chem/instant/drinks/kiraspecial

CAPABILITIES(/transformation/chem/instant/drinks/kiraspecial)
	configure(transformation(name = REAGENT_KIRASPECIAL, id = REAGENT_ID_KIRASPECIAL,
		takes = list(reagent(REAGENT_ID_ORANGEJUICE, 1), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_KIRASPECIAL, 3))))

/transformation/chem/instant/drinks/brownstar

CAPABILITIES(/transformation/chem/instant/drinks/brownstar)
	configure(transformation(name = REAGENT_BROWNSTAR, id = REAGENT_ID_BROWNSTAR,
		takes = list(reagent(REAGENT_ID_ORANGEJUICE, 2), reagent(REAGENT_ID_COLA, 1)),
		makes = list(reagent(REAGENT_ID_BROWNSTAR, 3))))

/transformation/chem/instant/drinks/brownstar_decaf

CAPABILITIES(/transformation/chem/instant/drinks/brownstar_decaf)
	configure(transformation(name = REAGENT_BROWNSTARDECAF, id = REAGENT_ID_BROWNSTARDECAF,
		takes = list(reagent(REAGENT_ID_ORANGEJUICE, 2), reagent(REAGENT_ID_DECAFCOLA, 1)),
		makes = list(reagent(REAGENT_ID_BROWNSTARDECAF, 3))))

/transformation/chem/instant/drinks/milkshake

CAPABILITIES(/transformation/chem/instant/drinks/milkshake)
	configure(transformation(name = REAGENT_MILKSHAKE, id = REAGENT_ID_MILKSHAKE,
		takes = list(reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_ICE, 2), reagent(REAGENT_ID_MILK, 2)),
		blocked_by = list(reagent(REAGENT_ID_PEANUTBUTTER, 1)), makes = list(reagent(REAGENT_ID_MILKSHAKE, 5))))

/transformation/chem/instant/drinks/peanutmilkshake

CAPABILITIES(/transformation/chem/instant/drinks/peanutmilkshake)
	configure(transformation(name = "Peanutbutter Milkshake", id = REAGENT_ID_PEANUTMILKSHAKE,
		takes = list(reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_ICE, 1), reagent(REAGENT_ID_PEANUTBUTTER, 2), reagent(REAGENT_ID_MILK, 1)),
		makes = list(reagent(REAGENT_ID_PEANUTMILKSHAKE, 5))))

/transformation/chem/instant/drinks/rewriter

CAPABILITIES(/transformation/chem/instant/drinks/rewriter)
	configure(transformation(name = REAGENT_REWRITER, id = REAGENT_ID_REWRITER,
		takes = list(reagent(REAGENT_ID_SPACEMOUNTAINWIND, 1), reagent(REAGENT_ID_COFFEE, 1)),
		makes = list(reagent(REAGENT_ID_REWRITER, 2))))

/transformation/chem/instant/drinks/suidream

CAPABILITIES(/transformation/chem/instant/drinks/suidream)
	configure(transformation(name = REAGENT_SUIDREAM, id = REAGENT_ID_SUIDREAM,
		takes = list(reagent(REAGENT_ID_SPACEUP, 1), reagent(REAGENT_ID_BLUECURACAO, 1), reagent(REAGENT_ID_MELONLIQUOR, 1)),
		makes = list(reagent(REAGENT_ID_SUIDREAM, 3))))

/transformation/chem/instant/drinks/shirleytemple

CAPABILITIES(/transformation/chem/instant/drinks/shirleytemple)
	configure(transformation(name = REAGENT_SHIRLEYTEMPLE, id = REAGENT_ID_SHIRLEYTEMPLE,
		takes = list(reagent(REAGENT_ID_GINGERALE, 4), reagent(REAGENT_ID_GRENADINE, 1)),
		makes = list(reagent(REAGENT_ID_SHIRLEYTEMPLE, 5))))

/transformation/chem/instant/drinks/royrogers

CAPABILITIES(/transformation/chem/instant/drinks/royrogers)
	configure(transformation(name = REAGENT_ROYROGERS, id = REAGENT_ID_ROYROGERS,
		takes = list(reagent(REAGENT_ID_SHIRLEYTEMPLE, 5), reagent(REAGENT_ID_LEMONLIME, 2)),
		makes = list(reagent(REAGENT_ID_ROYROGERS, 7))))

/transformation/chem/instant/drinks/collinsmix

CAPABILITIES(/transformation/chem/instant/drinks/collinsmix)
	configure(transformation(name = REAGENT_COLLINSMIX, id = REAGENT_ID_COLLINSMIX,
		takes = list(reagent(REAGENT_ID_LEMONLIME, 3), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_COLLINSMIX, 4))))

/transformation/chem/instant/drinks/arnoldpalmer

CAPABILITIES(/transformation/chem/instant/drinks/arnoldpalmer)
	configure(transformation(name = REAGENT_ARNOLDPALMER, id = REAGENT_ID_ARNOLDPALMER,
		takes = list(reagent(REAGENT_ID_ICETEA, 1), reagent(REAGENT_ID_LEMONADE, 1)),
		makes = list(reagent(REAGENT_ID_ARNOLDPALMER, 2))))

/transformation/chem/instant/drinks/sakebomb

CAPABILITIES(/transformation/chem/instant/drinks/sakebomb)
	configure(transformation(name = REAGENT_SAKEBOMB, id = REAGENT_ID_SAKEBOMB, takes = list(reagent(REAGENT_ID_BEER, 2), reagent(REAGENT_ID_SAKE, 1)),
		makes = list(reagent(REAGENT_ID_SAKEBOMB, 3))))

/transformation/chem/instant/drinks/tamagozake

CAPABILITIES(/transformation/chem/instant/drinks/tamagozake)
	configure(transformation(name = REAGENT_TAMAGOZAKE, id = REAGENT_ID_TAMAGOZAKE,
		takes = list(reagent(REAGENT_ID_SAKE, 10), reagent(REAGENT_ID_SUGAR, 5), reagent(REAGENT_ID_EGG, 3)),
		makes = list(reagent(REAGENT_ID_TAMAGOZAKE, 15))))

/transformation/chem/instant/drinks/ginzamary

CAPABILITIES(/transformation/chem/instant/drinks/ginzamary)
	configure(transformation(name = REAGENT_GINZAMARY, id = REAGENT_ID_GINZAMARY,
		takes = list(reagent(REAGENT_ID_SAKE, 2), reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_TOMATOJUICE, 1)),
		makes = list(reagent(REAGENT_ID_GINZAMARY, 5))))

/transformation/chem/instant/drinks/tokyorose

CAPABILITIES(/transformation/chem/instant/drinks/tokyorose)
	configure(transformation(name = REAGENT_TOKYOROSE, id = REAGENT_ID_TOKYOROSE,
		takes = list(reagent(REAGENT_ID_SAKE, 1), reagent(REAGENT_ID_BERRYJUICE, 1)),
		makes = list(reagent(REAGENT_ID_TOKYOROSE, 2))))

/transformation/chem/instant/drinks/saketini

CAPABILITIES(/transformation/chem/instant/drinks/saketini)
	configure(transformation(name = REAGENT_SAKETINI, id = REAGENT_ID_SAKETINI, takes = list(reagent(REAGENT_ID_SAKE, 1), reagent(REAGENT_ID_GIN, 1)),
		makes = list(reagent(REAGENT_ID_SAKETINI, 2))))

/transformation/chem/instant/drinks/elysiumfacepunch

CAPABILITIES(/transformation/chem/instant/drinks/elysiumfacepunch)
	configure(transformation(name = REAGENT_ELYSIUMFACEPUNCH, id = REAGENT_ID_ELYSIUMFACEPUNCH,
		takes = list(reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_LEMONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_ELYSIUMFACEPUNCH, 2))))

/transformation/chem/instant/drinks/erebusmoonrise

CAPABILITIES(/transformation/chem/instant/drinks/erebusmoonrise)
	configure(transformation(name = REAGENT_EREBUSMOONRISE, id = REAGENT_ID_EREBUSMOONRISE,
		takes = list(reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_VODKA, 1), reagent(REAGENT_ID_TEQUILA, 1)),
		makes = list(reagent(REAGENT_ID_EREBUSMOONRISE, 3))))

/transformation/chem/instant/drinks/balloon

CAPABILITIES(/transformation/chem/instant/drinks/balloon)
	configure(transformation(name = REAGENT_BALLOON, id = REAGENT_ID_BALLOON,
		takes = list(reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_BLUECURACAO, 1)),
		makes = list(reagent(REAGENT_ID_BALLOON, 2))))

/transformation/chem/instant/drinks/natunabrandy

CAPABILITIES(/transformation/chem/instant/drinks/natunabrandy)
	configure(transformation(name = REAGENT_NATUNABRANDY, id = REAGENT_ID_NATUNABRANDY,
		takes = list(reagent(REAGENT_ID_BEER, 1), reagent(REAGENT_ID_SODAWATER, 2)),
		makes = list(reagent(REAGENT_ID_NATUNABRANDY, 3))))

/transformation/chem/instant/drinks/euphoria

CAPABILITIES(/transformation/chem/instant/drinks/euphoria)
	configure(transformation(name = REAGENT_EUPHORIA, id = REAGENT_ID_EUPHORIA,
		takes = list(reagent(REAGENT_ID_SPECIALWHISKEY, 1), reagent(REAGENT_ID_COGNAC, 2)),
		makes = list(reagent(REAGENT_ID_EUPHORIA, 3))))

/transformation/chem/instant/drinks/xanaducannon

CAPABILITIES(/transformation/chem/instant/drinks/xanaducannon)
	configure(transformation(name = REAGENT_XANADUCANNON, id = REAGENT_ID_XANADUCANNON,
		takes = list(reagent(REAGENT_ID_ALE, 1), reagent(REAGENT_ID_DRGIBB, 1)), makes = list(reagent(REAGENT_ID_XANADUCANNON, 2))))

/transformation/chem/instant/drinks/debugger

CAPABILITIES(/transformation/chem/instant/drinks/debugger)
	configure(transformation(name = REAGENT_DEBUGGER, id = REAGENT_ID_DEBUGGER,
		takes = list(reagent(REAGENT_ID_FUEL, 1), reagent(REAGENT_ID_SUGAR, 2), reagent(REAGENT_ID_COOKINGOIL, 2)),
		makes = list(reagent(REAGENT_ID_DEBUGGER, 5))))

/transformation/chem/instant/drinks/spacersbrew

CAPABILITIES(/transformation/chem/instant/drinks/spacersbrew)
	configure(transformation(name = REAGENT_SPACERSBREW, id = REAGENT_ID_SPACERSBREW,
		takes = list(reagent(REAGENT_ID_BROWNSTAR, 4), reagent(REAGENT_ID_ETHANOL, 1)),
		makes = list(reagent(REAGENT_ID_SPACERSBREW, 5))))

/transformation/chem/instant/drinks/binmanbliss

CAPABILITIES(/transformation/chem/instant/drinks/binmanbliss)
	configure(transformation(name = REAGENT_BINMANBLISS, id = REAGENT_ID_BINMANBLISS,
		takes = list(reagent(REAGENT_ID_SAKE, 1), reagent(REAGENT_ID_TEQUILA, 1)),
		makes = list(reagent(REAGENT_ID_BINMANBLISS, 2))))

/transformation/chem/instant/drinks/chrysanthemum

CAPABILITIES(/transformation/chem/instant/drinks/chrysanthemum)
	configure(transformation(name = REAGENT_CHRYSANTHEMUM, id = REAGENT_ID_CHRYSANTHEMUM,
		takes = list(reagent(REAGENT_ID_SAKE, 1), reagent(REAGENT_ID_MELONLIQUOR, 1)),
		makes = list(reagent(REAGENT_ID_CHRYSANTHEMUM, 2))))

/transformation/chem/instant/drinks/deathbell

CAPABILITIES(/transformation/chem/instant/drinks/deathbell)
	configure(transformation(name = REAGENT_DEATHBELL, id = REAGENT_ID_DEATHBELL,
		takes = list(reagent(REAGENT_ID_ANTIFREEZE, 1), reagent(REAGENT_ID_GARGLEBLASTER, 1), reagent(REAGENT_ID_SYNDICATEBOMB, 1)),
		makes = list(reagent(REAGENT_ID_DEATHBELL, 3))))

/transformation/chem/instant/drinks/bitters

CAPABILITIES(/transformation/chem/instant/drinks/bitters)
	configure(transformation(name = REAGENT_BITTERS, id = REAGENT_ID_BITTERS, takes = list(reagent(REAGENT_ID_MINT, 5)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5)), makes = list(reagent(REAGENT_ID_BITTERS, 5))))

/transformation/chem/instant/drinks/soemmerfire

CAPABILITIES(/transformation/chem/instant/drinks/soemmerfire)
	configure(transformation(name = REAGENT_SOEMMERFIRE, id = REAGENT_ID_SOEMMERFIRE,
		takes = list(reagent(REAGENT_ID_MANHATTAN, 2), reagent(REAGENT_ID_CONDENSEDCAPSAICIN, 1)),
		makes = list(reagent(REAGENT_ID_SOEMMERFIRE, 3))))

/transformation/chem/instant/drinks/winebrandy

CAPABILITIES(/transformation/chem/instant/drinks/winebrandy)
	configure(transformation(name = "Wine brandy", id = REAGENT_ID_WINEBRANDY, takes = list(reagent(REAGENT_ID_REDWINE, 10)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 10)), makes = list(reagent(REAGENT_ID_WINEBRANDY, 5))))

/transformation/chem/instant/drinks/love_potion

CAPABILITIES(/transformation/chem/instant/drinks/love_potion)
	configure(transformation(name = REAGENT_LOVEPOTION, id = REAGENT_ID_LOVEPOTION,
		takes = list(reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_BERRYJUICE, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_LOVEPOTION, 3))))

/transformation/chem/instant/drinks/morningafter

CAPABILITIES(/transformation/chem/instant/drinks/morningafter)
	configure(transformation(name = REAGENT_MORNINGAFTER, id = REAGENT_ID_MORNINGAFTER,
		takes = list(reagent(REAGENT_ID_SBITEN, 1), reagent(REAGENT_ID_COFFEE, 5)),
		makes = list(reagent(REAGENT_ID_MORNINGAFTER, 6))))

/transformation/chem/instant/drinks/vesper

CAPABILITIES(/transformation/chem/instant/drinks/vesper)
	configure(transformation(name = REAGENT_VESPER, id = REAGENT_ID_VESPER,
		takes = list(reagent(REAGENT_ID_GIN, 3), reagent(REAGENT_ID_VODKA, 1), reagent(REAGENT_ID_REDWINE, 1)),
		makes = list(reagent(REAGENT_ID_VESPER, 4))))

/transformation/chem/instant/drinks/rotgut

CAPABILITIES(/transformation/chem/instant/drinks/rotgut)
	configure(transformation(name = REAGENT_ROTGUT, id = REAGENT_ID_ROTGUT,
		takes = list(reagent(REAGENT_ID_VODKA, 3), reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_COLA, 3)),
		makes = list(reagent(REAGENT_ID_ROTGUT, 8))))

/transformation/chem/instant/drinks/entdraught

CAPABILITIES(/transformation/chem/instant/drinks/entdraught)
	configure(transformation(name = REAGENT_ENTDRAUGHT, id = REAGENT_ID_ENTDRAUGHT,
		takes = list(reagent(REAGENT_ID_TONIC, 1), reagent(REAGENT_ID_HOLYWATER, 1), reagent(REAGENT_ID_HONEY, 1)),
		makes = list(reagent(REAGENT_ID_ENTDRAUGHT, 3))))

/transformation/chem/instant/drinks/voxdelight

CAPABILITIES(/transformation/chem/instant/drinks/voxdelight)
	configure(transformation(name = REAGENT_VOXDELIGHT, id = REAGENT_ID_VOXDELIGHT,
		takes = list(reagent(REAGENT_ID_PHORON, 3), reagent(REAGENT_ID_FUEL, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_VOXDELIGHT, 4))))

/transformation/chem/instant/drinks/screamingviking

CAPABILITIES(/transformation/chem/instant/drinks/screamingviking)
	configure(transformation(name = REAGENT_SCREAMINGVIKING, id = REAGENT_ID_SCREAMINGVIKING,
		takes = list(reagent(REAGENT_ID_MARTINI, 2), reagent(REAGENT_ID_VODKATONIC, 2), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_RUM, 1)),
		makes = list(reagent(REAGENT_ID_SCREAMINGVIKING, 6))))

/transformation/chem/instant/drinks/vilelemon

CAPABILITIES(/transformation/chem/instant/drinks/vilelemon)
	configure(transformation(name = REAGENT_VILELEMON, id = REAGENT_ID_VILELEMON,
		takes = list(reagent(REAGENT_ID_LEMONADE, 5), reagent(REAGENT_ID_SPACEMOUNTAINWIND, 1)),
		makes = list(reagent(REAGENT_ID_VILELEMON, 6))))

/transformation/chem/instant/drinks/dreamcream

CAPABILITIES(/transformation/chem/instant/drinks/dreamcream)
	configure(transformation(name = REAGENT_DREAMCREAM, id = REAGENT_ID_DREAMCREAM,
		takes = list(reagent(REAGENT_ID_MILK, 2), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_HONEY, 1)),
		makes = list(reagent(REAGENT_ID_DREAMCREAM, 4))))

/transformation/chem/instant/drinks/robustin

CAPABILITIES(/transformation/chem/instant/drinks/robustin)
	configure(transformation(name = REAGENT_ROBUSTIN, id = REAGENT_ID_ROBUSTIN,
		takes = list(reagent(REAGENT_ID_ANTIFREEZE, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_FUEL, 1), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_ROBUSTIN, 4))))

/transformation/chem/instant/drinks/virginsip

CAPABILITIES(/transformation/chem/instant/drinks/virginsip)
	configure(transformation(name = REAGENT_VIRGINSIP, id = REAGENT_ID_VIRGINSIP,
		takes = list(reagent(REAGENT_ID_DRIESTMARTINI, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_VIRGINSIP, 2))))

/transformation/chem/instant/drinks/chocoshake

CAPABILITIES(/transformation/chem/instant/drinks/chocoshake)
	configure(transformation(name = REAGENT_CHOCOSHAKE, id = REAGENT_ID_CHOCOSHAKE,
		takes = list(reagent(REAGENT_ID_MILKSHAKE, 1), reagent(REAGENT_ID_COCO, 1)),
		makes = list(reagent(REAGENT_ID_CHOCOSHAKE, 2))))

/transformation/chem/instant/drinks/berryshake

CAPABILITIES(/transformation/chem/instant/drinks/berryshake)
	configure(transformation(name = REAGENT_BERRYSHAKE, id = REAGENT_ID_BERRYSHAKE,
		takes = list(reagent(REAGENT_ID_MILKSHAKE, 1), reagent(REAGENT_ID_BERRYJUICE, 1)),
		makes = list(reagent(REAGENT_ID_BERRYSHAKE, 2))))

/transformation/chem/instant/drinks/coffeeshake

CAPABILITIES(/transformation/chem/instant/drinks/coffeeshake)
	configure(transformation(name = REAGENT_COFFEESHAKE, id = REAGENT_ID_COFFEESHAKE,
		takes = list(reagent(REAGENT_ID_MILKSHAKE, 1), reagent(REAGENT_ID_COFFEE, 1)),
		makes = list(reagent(REAGENT_ID_COFFEESHAKE, 2))))

/transformation/chem/instant/drinks/jellyshot

CAPABILITIES(/transformation/chem/instant/drinks/jellyshot)
	configure(transformation(name = REAGENT_JELLYSHOT, id = REAGENT_ID_JELLYSHOT,
		takes = list(reagent(REAGENT_ID_CHERRYJELLY, 4), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_JELLYSHOT, 5))))

/transformation/chem/instant/drinks/slimeshot

CAPABILITIES(/transformation/chem/instant/drinks/slimeshot)
	configure(transformation(name = REAGENT_SLIMESHOT, id = REAGENT_ID_SLIMESHOT,
		takes = list(reagent(REAGENT_ID_SLIMEJELLY, 4), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_SLIMESHOT, 5))))

/transformation/chem/instant/drinks/negroni

CAPABILITIES(/transformation/chem/instant/drinks/negroni)
	configure(transformation(name = REAGENT_NEGRONI, id = REAGENT_ID_NEGRONI,
		takes = list(reagent(REAGENT_ID_GIN, 1), reagent(REAGENT_ID_BITTERS, 1), reagent(REAGENT_ID_VERMOUTH, 1)),
		makes = list(reagent(REAGENT_ID_NEGRONI, 3))))

/transformation/chem/instant/drinks/cloverclub

CAPABILITIES(/transformation/chem/instant/drinks/cloverclub)
	configure(transformation(name = REAGENT_CLOVERCLUB, id = REAGENT_ID_CLOVERCLUB,
		takes = list(reagent(REAGENT_ID_BERRYJUICE, 1), reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_GIN, 3)),
		makes = list(reagent(REAGENT_ID_CLOVERCLUB, 5))))

/transformation/chem/instant/drinks/oldfashioned

CAPABILITIES(/transformation/chem/instant/drinks/oldfashioned)
	configure(transformation(name = REAGENT_OLDFASHIONED, id = REAGENT_ID_OLDFASHIONED,
		takes = list(reagent(REAGENT_ID_WHISKEY, 3), reagent(REAGENT_ID_BITTERS, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_OLDFASHIONED, 5))))

/transformation/chem/instant/drinks/whiskeysour

CAPABILITIES(/transformation/chem/instant/drinks/whiskeysour)
	configure(transformation(name = REAGENT_WHISKEYSOUR, id = REAGENT_ID_WHISKEYSOUR,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_WHISKEYSOUR, 4))))

/transformation/chem/instant/drinks/daiquiri

CAPABILITIES(/transformation/chem/instant/drinks/daiquiri)
	configure(transformation(name = REAGENT_DAIQUIRI, id = REAGENT_ID_DAIQUIRI,
		takes = list(reagent(REAGENT_ID_RUM, 3), reagent(REAGENT_ID_LIMEJUICE, 2), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_DAIQUIRI, 6))))

/transformation/chem/instant/drinks/mintjulep

CAPABILITIES(/transformation/chem/instant/drinks/mintjulep)
	configure(transformation(name = REAGENT_MINTJULEP, id = REAGENT_ID_MINTJULEP,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_MINT, 1)),
		makes = list(reagent(REAGENT_ID_MINTJULEP, 4))))

/transformation/chem/instant/drinks/paloma

CAPABILITIES(/transformation/chem/instant/drinks/paloma)
	configure(transformation(name = REAGENT_PALOMA, id = REAGENT_ID_PALOMA,
		takes = list(reagent(REAGENT_ID_SODAWATER, 1), reagent(REAGENT_ID_TEQUILASUNRISE, 2)),
		makes = list(reagent(REAGENT_ID_PALOMA, 3))))

/transformation/chem/instant/drinks/mojito

CAPABILITIES(/transformation/chem/instant/drinks/mojito)
	configure(transformation(name = REAGENT_MOJITO, id = REAGENT_ID_MOJITO,
		takes = list(reagent(REAGENT_ID_RUM, 3), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_MINT, 1)),
		makes = list(reagent(REAGENT_ID_MOJITO, 5))))

/transformation/chem/instant/drinks/virgin_mojito

CAPABILITIES(/transformation/chem/instant/drinks/virgin_mojito)
	configure(transformation(name = REAGENT_VIRGINMOJITO, id = REAGENT_ID_VIRGINMOJITO,
		takes = list(reagent(REAGENT_ID_SODAWATER, 3), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_MINT, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_VIRGINMOJITO, 5))))

/transformation/chem/instant/drinks/piscosour

CAPABILITIES(/transformation/chem/instant/drinks/piscosour)
	configure(transformation(name = REAGENT_PISCOSOUR, id = REAGENT_ID_PISCOSOUR,
		takes = list(reagent(REAGENT_ID_WINEBRANDY, 1), reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_PISCOSOUR, 3))))

/transformation/chem/instant/drinks/coldfront

CAPABILITIES(/transformation/chem/instant/drinks/coldfront)
	configure(transformation(name = REAGENT_COLDFRONT, id = REAGENT_ID_COLDFRONT,
		takes = list(reagent(REAGENT_ID_ICECOFFEE, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_MINT, 1)),
		makes = list(reagent(REAGENT_ID_COLDFRONT, 3))))

/transformation/chem/instant/drinks/godsake

CAPABILITIES(/transformation/chem/instant/drinks/godsake)
	configure(transformation(name = REAGENT_GODSAKE, id = REAGENT_ID_GODSAKE,
		takes = list(reagent(REAGENT_ID_SAKE, 2), reagent(REAGENT_ID_HOLYWATER, 1)), makes = list(reagent(REAGENT_ID_GODSAKE, 3))))

/transformation/chem/instant/drinks/godka //Why you would put this in your body, I don't know.

CAPABILITIES(/transformation/chem/instant/drinks/godka)
	configure(transformation(name = REAGENT_GODKA, id = REAGENT_ID_GODKA,
		takes = list(reagent(REAGENT_ID_VODKA, 1), reagent(REAGENT_ID_HOLYWATER, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_CARTHATOLINE, 1)),
		catalysts = list(reagent(REAGENT_ID_ENZYME, 5), reagent(REAGENT_ID_HOLYWATER, 5)),
		makes = list(reagent(REAGENT_ID_GODKA, 1))))

/transformation/chem/instant/drinks/holywine

CAPABILITIES(/transformation/chem/instant/drinks/holywine)
	configure(transformation(name = REAGENT_HOLYWINE, id = REAGENT_ID_HOLYWINE,
		takes = list(reagent(REAGENT_ID_GRAPEJUICE, 5), reagent(REAGENT_ID_GOLD, 5)),
		catalysts = list(reagent(REAGENT_ID_HOLYWATER, 5)), makes = list(reagent(REAGENT_ID_HOLYWINE, 10))))

/transformation/chem/instant/drinks/holy_mary

CAPABILITIES(/transformation/chem/instant/drinks/holy_mary)
	configure(transformation(name = REAGENT_HOLYMARY, id = REAGENT_ID_HOLYMARY,
		takes = list(reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_HOLYWINE, 3), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_HOLYMARY, 6))))

/transformation/chem/instant/drinks/angelskiss

CAPABILITIES(/transformation/chem/instant/drinks/angelskiss)
	configure(transformation(name = REAGENT_ANGELSKISS, id = REAGENT_ID_ANGELSKISS,
		takes = list(reagent(REAGENT_ID_HOLYWINE, 1), reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_RUM, 1)),
		makes = list(reagent(REAGENT_ID_ANGELSKISS, 3))))

/transformation/chem/instant/drinks/angelswrath

CAPABILITIES(/transformation/chem/instant/drinks/angelswrath)
	configure(transformation(name = REAGENT_ANGELSWRATH, id = REAGENT_ID_ANGELSWRATH,
		takes = list(reagent(REAGENT_ID_RUM, 3), reagent(REAGENT_ID_SPACEMOUNTAINWIND, 1), reagent(REAGENT_ID_HOLYWINE, 1), reagent(REAGENT_ID_DRGIBB, 1)),
		makes = list(reagent(REAGENT_ID_ANGELSWRATH, 6))))

/transformation/chem/instant/drinks/ichor_mead

CAPABILITIES(/transformation/chem/instant/drinks/ichor_mead)
	configure(transformation(name = REAGENT_ICHORMEAD, id = REAGENT_ID_ICHORMEAD,
		takes = list(reagent(REAGENT_ID_HOLYWINE, 1), reagent(REAGENT_ID_MEAD, 1)), makes = list(reagent(REAGENT_ID_ICHORMEAD, 2))))

/transformation/chem/instant/drinks/oilslick

CAPABILITIES(/transformation/chem/instant/drinks/oilslick)
	configure(transformation(name = REAGENT_OILSLICK, id = REAGENT_ID_OILSLICK,
		takes = list(reagent(REAGENT_ID_COOKINGOIL, 2), reagent(REAGENT_ID_HONEY, 1)),
		makes = list(reagent(REAGENT_ID_OILSLICK, 3))))

/transformation/chem/instant/drinks/slimeslam

CAPABILITIES(/transformation/chem/instant/drinks/slimeslam)
	configure(transformation(name = "Slick Slime Slammer", id = REAGENT_ID_SLIMESLAMMER,
		takes = list(reagent(REAGENT_ID_COOKINGOIL, 2), reagent(REAGENT_ID_PEANUTBUTTER, 1)),
		makes = list(reagent(REAGENT_ID_SLIMESLAMMER, 3))))

/transformation/chem/instant/drinks/virginsexonthebeach

CAPABILITIES(/transformation/chem/instant/drinks/virginsexonthebeach)
	configure(transformation(name = REAGENT_VIRGINSEXONTHEBEACH, id = REAGENT_ID_VIRGINSEXONTHEBEACH,
		takes = list(reagent(REAGENT_ID_ORANGEJUICE, 3), reagent(REAGENT_ID_GRENADINE, 2)),
		makes = list(reagent(REAGENT_ID_VIRGINSEXONTHEBEACH, 5))))

/transformation/chem/instant/drinks/sexonthebeach

CAPABILITIES(/transformation/chem/instant/drinks/sexonthebeach)
	configure(transformation(name = REAGENT_SEXONTHEBEACH, id = REAGENT_ID_SEXONTHEBEACH,
		takes = list(reagent(REAGENT_ID_VIRGINSEXONTHEBEACH, 5), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_SEXONTHEBEACH, 6))))

/transformation/chem/instant/drinks/eggnog

CAPABILITIES(/transformation/chem/instant/drinks/eggnog)
	configure(transformation(name = REAGENT_EGGNOG, id = REAGENT_ID_EGGNOG,
		takes = list(reagent(REAGENT_ID_MILK, 5), reagent(REAGENT_ID_CREAM, 5), reagent(REAGENT_ID_SUGAR, 5), reagent(REAGENT_ID_EGG, 3)),
		makes = list(reagent(REAGENT_ID_EGGNOG, 15))))

/transformation/chem/instant/drinks/nuclearwaste_radium

CAPABILITIES(/transformation/chem/instant/drinks/nuclearwaste_radium)
	configure(transformation(name = REAGENT_NUCLEARWASTE + " 226", id = "nuclearwasterad",
		takes = list(reagent(REAGENT_ID_OILSLICK, 1), reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_NUCLEARWASTE, 2))))

/transformation/chem/instant/drinks/nuclearwaste_uranium

CAPABILITIES(/transformation/chem/instant/drinks/nuclearwaste_uranium)
	configure(transformation(name = REAGENT_NUCLEARWASTE + " 238", id = "nuclearwasteuran",
		takes = list(reagent(REAGENT_ID_OILSLICK, 2), reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_NUCLEARWASTE, 3))))

/transformation/chem/instant/drinks/sodaoil

CAPABILITIES(/transformation/chem/instant/drinks/sodaoil)
	configure(transformation(name = REAGENT_SODAOIL, id = REAGENT_ID_SODAOIL,
		takes = list(reagent(REAGENT_ID_COOKINGOIL, 4), reagent(REAGENT_ID_SODAWATER, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_TRICORDRAZINE, 1)),
		makes = list(reagent(REAGENT_ID_SODAOIL, 6))))

/transformation/chem/instant/drinks/fusionnaire

CAPABILITIES(/transformation/chem/instant/drinks/fusionnaire)
	configure(transformation(name = REAGENT_FUSIONNAIRE, id = REAGENT_ID_FUSIONNAIRE,
		takes = list(reagent(REAGENT_ID_LEMONJUICE, 3), reagent(REAGENT_ID_VODKA, 2), reagent(REAGENT_ID_SCHNAPPSPEP, 1), reagent(REAGENT_ID_SCHNAPPSLEM, 1), reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_FUSIONNAIRE, 9))))


///////////////////////////////////////////////////////////////////////////////////
/// Special drinks
/transformation/chem/instant/drinks/grubshake

CAPABILITIES(/transformation/chem/instant/drinks/grubshake)
	configure(transformation(name = "Grub protein drink", id = REAGENT_ID_GRUBSHAKE,
		takes = list(reagent(REAGENT_ID_SHOCKCHEM, 5), reagent(REAGENT_ID_WATER, 25)),
		makes = list(reagent(REAGENT_ID_GRUBSHAKE, 30))))

/transformation/chem/instant/drinks/burnout

CAPABILITIES(/transformation/chem/instant/drinks/burnout)
	configure(transformation(name = REAGENT_BURNOUT, id = REAGENT_ID_BURNOUT,
		takes = list(reagent(REAGENT_ID_ANTIFREEZE, 1), reagent(REAGENT_ID_DEATHBELL, 1), reagent(REAGENT_ID_LOVEMAKER, 1)),
		makes = list(reagent(REAGENT_ID_BURNOUT, 3))))

/transformation/chem/instant/drinks/monstertamer

CAPABILITIES(/transformation/chem/instant/drinks/monstertamer)
	configure(transformation(name = REAGENT_MONSTERTAMER, id = REAGENT_ID_MONSTERTAMER,
		takes = list(reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_PROTEIN, 1)),
		makes = list(reagent(REAGENT_ID_MONSTERTAMER, 2))))

/transformation/chem/instant/drinks/bigbeer

CAPABILITIES(/transformation/chem/instant/drinks/bigbeer)
	configure(transformation(name = REAGENT_BIGBEER, id = REAGENT_ID_BIGBEER,
		takes = list(reagent(REAGENT_ID_SYNDICATEBOMB, 1), reagent(REAGENT_ID_MANLYDORF, 1), reagent(REAGENT_ID_GROG, 1)),
		makes = list(reagent(REAGENT_ID_BIGBEER, 3))))

/transformation/chem/instant/drinks/sweettea

CAPABILITIES(/transformation/chem/instant/drinks/sweettea)
	configure(transformation(name = "Sweetened Tea", id = REAGENT_ID_SWEETTEA,
		takes = list(reagent(REAGENT_ID_ICETEA, 2), reagent(REAGENT_ID_SUGAR, 1)), makes = list(reagent(REAGENT_ID_SWEETTEA, 3))))

/transformation/chem/instant/drinks/unsweettea

CAPABILITIES(/transformation/chem/instant/drinks/unsweettea)
	configure(transformation(name = REAGENT_UNSWEETTEA, id = REAGENT_ID_UNSWEETTEA,
		takes = list(reagent(REAGENT_ID_SWEETTEA, 3), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_UNSWEETTEA, 2))))

/transformation/chem/instant/drinks/galacticpanic

CAPABILITIES(/transformation/chem/instant/drinks/galacticpanic)
	configure(transformation(name = REAGENT_GALACTICPANIC, id = REAGENT_ID_GALACTICPANIC,
		takes = list(reagent(REAGENT_ID_GARGLEBLASTER, 1), reagent(REAGENT_ID_SINGULO, 1), reagent(REAGENT_ID_PHORONSPECIAL, 1), reagent(REAGENT_ID_NEUROTOXIN, 1), reagent(REAGENT_ID_ATOMICBOMB, 1), reagent(REAGENT_ID_HIPPIESDELIGHT, 1)),
		makes = list(reagent(REAGENT_ID_GALACTICPANIC, 6))))

/transformation/chem/instant/drinks/bulldog

CAPABILITIES(/transformation/chem/instant/drinks/bulldog)
	configure(transformation(name = REAGENT_BULLDOG, id = REAGENT_ID_BULLDOG,
		takes = list(reagent(REAGENT_ID_WHITERUSSIAN, 4), reagent(REAGENT_ID_COLA, 1)),
		makes = list(reagent(REAGENT_ID_BULLDOG, 4))))

/transformation/chem/instant/drinks/sbagliato

CAPABILITIES(/transformation/chem/instant/drinks/sbagliato)
	configure(transformation(name = REAGENT_SBAGLIATO, id = REAGENT_ID_SBAGLIATO,
		takes = list(reagent(REAGENT_ID_REDWINE, 1), reagent(REAGENT_ID_VERMOUTH, 1), reagent(REAGENT_ID_SODAWATER, 1)),
		makes = list(reagent(REAGENT_ID_SBAGLIATO, 3))))

/transformation/chem/instant/drinks/italiancrisis

CAPABILITIES(/transformation/chem/instant/drinks/italiancrisis)
	configure(transformation(name = REAGENT_ITALIANCRISIS, id = REAGENT_ID_ITALIANCRISIS,
		takes = list(reagent(REAGENT_ID_BULLDOG, 1), reagent(REAGENT_ID_SBAGLIATO, 1)),
		makes = list(reagent(REAGENT_ID_ITALIANCRISIS, 2))))

/transformation/chem/instant/drinks/sugarrush

CAPABILITIES(/transformation/chem/instant/drinks/sugarrush)
	configure(transformation(name = REAGENT_SUGARRUSH, id = REAGENT_ID_SUGARRUSH,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_SODAWATER, 1), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_SUGARRUSH, 3))))

/transformation/chem/instant/drinks/lotus

CAPABILITIES(/transformation/chem/instant/drinks/lotus)
	configure(transformation(name = REAGENT_LOTUS, id = REAGENT_ID_LOTUS,
		takes = list(reagent(REAGENT_ID_SBAGLIATO, 1), reagent(REAGENT_ID_SUGARRUSH, 1)),
		makes = list(reagent(REAGENT_ID_LOTUS, 2))))

/transformation/chem/instant/drinks/shroomjuice

CAPABILITIES(/transformation/chem/instant/drinks/shroomjuice)
	configure(transformation(name = REAGENT_SHROOMJUICE, id = REAGENT_ID_SHROOMJUICE,
		takes = list(reagent(REAGENT_ID_PSILOCYBIN, 1), reagent(REAGENT_ID_APPLEJUICE, 1), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_SHROOMJUICE, 3))))

/transformation/chem/instant/drinks/russianroulette

CAPABILITIES(/transformation/chem/instant/drinks/russianroulette)
	configure(transformation(name = REAGENT_RUSSIANROULETTE, id = REAGENT_ID_RUSSIANROULETTE,
		takes = list(reagent(REAGENT_ID_WHITERUSSIAN, 5), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_RUSSIANROULETTE, 6))))

/transformation/chem/instant/drinks/lovemaker

CAPABILITIES(/transformation/chem/instant/drinks/lovemaker)
	configure(transformation(name = REAGENT_LOVEMAKER, id = REAGENT_ID_LOVEMAKER,
		takes = list(reagent(REAGENT_ID_HONEY, 1), reagent(REAGENT_ID_SEXONTHEBEACH, 5)),
		makes = list(reagent(REAGENT_ID_LOVEMAKER, 6))))

/transformation/chem/instant/drinks/honeyshot

CAPABILITIES(/transformation/chem/instant/drinks/honeyshot)
	configure(transformation(name = REAGENT_HONEYSHOT, id = REAGENT_ID_HONEYSHOT,
		takes = list(reagent(REAGENT_ID_HONEY, 1), reagent(REAGENT_ID_VODKA, 1), reagent(REAGENT_ID_GRENADINE, 1)),
		makes = list(reagent(REAGENT_ID_HONEYSHOT, 3))))

/transformation/chem/instant/drinks/appletini

CAPABILITIES(/transformation/chem/instant/drinks/appletini)
	configure(transformation(name = REAGENT_APPLETINI, id = REAGENT_ID_APPLETINIT,
		takes = list(reagent(REAGENT_ID_APPLEJUICE, 2), reagent(REAGENT_ID_VODKA, 1)),
		makes = list(reagent(REAGENT_ID_APPLETINIT, 3))))

/transformation/chem/instant/drinks/glowingappletini

CAPABILITIES(/transformation/chem/instant/drinks/glowingappletini)
	configure(transformation(name = REAGENT_GLOWINGAPPLETINI, id = REAGENT_ID_GLOWINGAPPLETINI,
		takes = list(reagent(REAGENT_ID_APPLETINIT, 5), reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_GLOWINGAPPLETINI, 6))))

/transformation/chem/instant/drinks/scsatw

CAPABILITIES(/transformation/chem/instant/drinks/scsatw)
	configure(transformation(name = REAGENT_SCSATW, id = REAGENT_ID_SCSATW,
		takes = list(reagent(REAGENT_ID_SCREWDRIVERCOCKTAIL, 3), reagent(REAGENT_ID_RUM, 1), reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_GIN, 1)),
		makes = list(reagent(REAGENT_ID_SCSATW, 6))))

/transformation/chem/instant/drinks/choccymilk

CAPABILITIES(/transformation/chem/instant/drinks/choccymilk)
	configure(transformation(name = REAGENT_CHOCCYMILK, id = REAGENT_ID_CHOCCYMILK,
		takes = list(reagent(REAGENT_ID_MILK, 3), reagent(REAGENT_ID_COCO, 1)), blocked_by = list(reagent(REAGENT_ID_ENZYME, 1)),
		makes = list(reagent(REAGENT_ID_CHOCCYMILK, 4))))

/transformation/chem/instant/drinks/redspaceflush

CAPABILITIES(/transformation/chem/instant/drinks/redspaceflush)
	configure(transformation(name = "Redspace Flush", id = REAGENT_ID_REDSPACEFLUSH,
		takes = list(reagent(REAGENT_ID_RUM, 2), reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_REDSPACEFLUSH, 6))))

/transformation/chem/instant/drinks/graveyard

CAPABILITIES(/transformation/chem/instant/drinks/graveyard)
	configure(transformation(name = REAGENT_GRAVEYARD, id = REAGENT_ID_GRAVEYARD,
		takes = list(reagent(REAGENT_ID_COLA, 1), reagent(REAGENT_ID_SPACEMOUNTAINWIND, 1), reagent(REAGENT_ID_DRGIBB, 1), reagent(REAGENT_ID_SPACEUP, 1)),
		makes = list(reagent(REAGENT_ID_GRAVEYARD, 4))))

/transformation/chem/instant/drinks/hairoftherat

CAPABILITIES(/transformation/chem/instant/drinks/hairoftherat)
	configure(transformation(name = REAGENT_HAIROFTHERAT, id = REAGENT_ID_HAIROFTHERAT,
		takes = list(reagent(REAGENT_ID_MONSTERTAMER, 2), reagent(REAGENT_ID_NUTRIMENT, 1)),
		makes = list(reagent(REAGENT_ID_HAIROFTHERAT, 3))))

/transformation/chem/instant/drinks/pink_russian

CAPABILITIES(/transformation/chem/instant/drinks/pink_russian)
	configure(transformation(name = REAGENT_PINKRUSSIAN, id = REAGENT_ID_PINKRUSSIAN,
		takes = list(reagent(REAGENT_ID_BLACKRUSSIAN, 2), reagent(REAGENT_ID_BERRYSHAKE, 1)),
		makes = list(reagent(REAGENT_ID_PINKRUSSIAN, 3))))

/transformation/chem/instant/drinks/originalsin

CAPABILITIES(/transformation/chem/instant/drinks/originalsin)
	configure(transformation(name = REAGENT_ORIGINALSIN, id = REAGENT_ID_ORIGINALSIN, takes = list(reagent(REAGENT_ID_HOLYWINE, 1)),
		catalysts = list(reagent(REAGENT_ID_APPLEJUICE, 1)), makes = list(reagent(REAGENT_ID_ORIGINALSIN, 1))))

/transformation/chem/instant/drinks/windgarita

CAPABILITIES(/transformation/chem/instant/drinks/windgarita)
	configure(transformation(name = REAGENT_WINDGARITA, id = REAGENT_ID_WINDGARITA,
		takes = list(reagent(REAGENT_ID_MARGARITA, 3), reagent(REAGENT_ID_SPACEMOUNTAINWIND, 2), reagent(REAGENT_ID_MELONLIQUOR, 1)),
		makes = list(reagent(REAGENT_ID_WINDGARITA, 6))))

/transformation/chem/instant/drinks/newyorksour

CAPABILITIES(/transformation/chem/instant/drinks/newyorksour)
	configure(transformation(name = REAGENT_NEWYORKSOUR, id = REAGENT_ID_NEWYORKSOUR,
		takes = list(reagent(REAGENT_ID_WHISKEYSOUR, 3), reagent(REAGENT_ID_REDWINE, 2), reagent(REAGENT_ID_EGG, 1)),
		makes = list(reagent(REAGENT_ID_NEWYORKSOUR, 6))))

/transformation/chem/instant/drinks/mudslide

CAPABILITIES(/transformation/chem/instant/drinks/mudslide)
	configure(transformation(name = REAGENT_MUDSLIDE, id = REAGENT_ID_MUDSLIDE,
		takes = list(reagent(REAGENT_ID_BLACKRUSSIAN, 1), reagent(REAGENT_ID_IRISHCREAM, 1)),
		makes = list(reagent(REAGENT_ID_MUDSLIDE, 2))))

/transformation/chem/instant/drinks/protein_shake

CAPABILITIES(/transformation/chem/instant/drinks/protein_shake)
	configure(transformation(name = REAGENT_PROTEINSHAKE, id = REAGENT_ID_PROTEINSHAKE,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_PROTEINPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_PROTEINSHAKE, 5))))

/transformation/chem/instant/drinks/protein_shake/vanilla

CAPABILITIES(/transformation/chem/instant/drinks/protein_shake/vanilla)
	configure(transformation(name = REAGENT_VANILLAPROTEINSHAKE, id = REAGENT_ID_VANILLAPROTEINSHAKER,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_VANILLAPROTEINPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_VANILLAPROTEINSHAKER, 5))))

/transformation/chem/instant/drinks/protein_shake/banana

CAPABILITIES(/transformation/chem/instant/drinks/protein_shake/banana)
	configure(transformation(name = REAGENT_BANANAPROTEINSHAKE, id = REAGENT_ID_BANANAPROTEINSHAKE,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_BANANAPROTEINPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_BANANAPROTEINSHAKE, 5))))

/transformation/chem/instant/drinks/protein_shake/chocolate

CAPABILITIES(/transformation/chem/instant/drinks/protein_shake/chocolate)
	configure(transformation(name = REAGENT_CHOCOLATEPROTEINSHAKE, id = REAGENT_ID_CHOCOLATEPROTEINSHAKE,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_CHOCOLATEPROTEINPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_CHOCOLATEPROTEINSHAKE, 5))))

/transformation/chem/instant/drinks/protein_shake/strawberry

CAPABILITIES(/transformation/chem/instant/drinks/protein_shake/strawberry)
	configure(transformation(name = REAGENT_STRAWBERRYPROTEINSHAKE, id = REAGENT_ID_STRAWBERRYPROTEINSHAKE,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_STRAWBERRYPROTEINPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_STRAWBERRYPROTEINSHAKE, 5))))

/transformation/chem/instant/drinks/manager_summoner

CAPABILITIES(/transformation/chem/instant/drinks/manager_summoner)
	configure(transformation(name = REAGENT_MANAGERSUMMONER, id = REAGENT_ID_MANAGERSUMMONER,
		takes = list(reagent(REAGENT_ID_MARGARITA, 1), reagent(REAGENT_ID_REDWINE, 1), reagent(REAGENT_ID_ESSENTIALOIL, 1)),
		makes = list(reagent(REAGENT_ID_MANAGERSUMMONER, 3))))


/transformation/chem/instant/instantteapowder/green

CAPABILITIES(/transformation/chem/instant/instantteapowder/green)
	configure(transformation(id = REAGENT_ID_INSTANTTEAPOWDERGREEN, takes = list(reagent(REAGENT_ID_TEAMUSH, 10), reagent(REAGENT_ID_FROSTOIL, 1)),
		makes = list(reagent(REAGENT_ID_INSTANTTEAPOWDERGREEN, 10))))

/transformation/chem/instant/instanttea/green

CAPABILITIES(/transformation/chem/instant/instanttea/green)
	configure(transformation(id = REAGENT_ID_INSTANTTEAGREEN, takes = list(reagent(REAGENT_ID_INSTANTTEAPOWDERGREEN, 1), reagent(REAGENT_ID_WATER, 9)),
		makes = list(reagent(REAGENT_ID_INSTANTTEAGREEN, 10))))

/transformation/chem/instant/drinks/spiderdrink

CAPABILITIES(/transformation/chem/instant/drinks/spiderdrink)
	configure(transformation(name = REAGENT_SPIDERDRINK, id = REAGENT_ID_SPIDERDRINK,
		takes = list(reagent(REAGENT_ID_SPIDERTOXIN, 1), reagent(REAGENT_ID_CLONEXADONE, 5), reagent(REAGENT_ID_ABSINTHE, 4)),
		makes = list(reagent(REAGENT_ID_SPIDERDRINK, 10))))

/transformation/chem/instant/drinks/bubbleteawatermelon

CAPABILITIES(/transformation/chem/instant/drinks/bubbleteawatermelon)
	configure(transformation(name = REAGENT_BUBBLETEAWATERMELON, id = REAGENT_ID_BUBBLETEAWATERMELON,
		takes = list(reagent(REAGENT_ID_GELATIN, 2), reagent(REAGENT_ID_WATERMELONTEA, 6), reagent(REAGENT_ID_MILK, 2)),
		makes = list(reagent(REAGENT_ID_BUBBLETEAWATERMELON, 10))))

/transformation/chem/instant/drinks/bubbleteastrawberry

CAPABILITIES(/transformation/chem/instant/drinks/bubbleteastrawberry)
	configure(transformation(name = REAGENT_BUBBLETEASTRAWBERRY, id = REAGENT_ID_BUBBLETEASTRAWBERRY,
		takes = list(reagent(REAGENT_ID_GELATIN, 2), reagent(REAGENT_ID_BERRYTEA, 6), reagent(REAGENT_ID_MILK, 2)),
		makes = list(reagent(REAGENT_ID_BUBBLETEASTRAWBERRY, 10))))

/transformation/chem/instant/drinks/bubbleteacherry

CAPABILITIES(/transformation/chem/instant/drinks/bubbleteacherry)
	configure(transformation(name = REAGENT_BUBBLETEACHERRY, id = REAGENT_ID_BUBBLETEACHERRY,
		takes = list(reagent(REAGENT_ID_GELATIN, 2), reagent(REAGENT_ID_CHERRYTEA, 6), reagent(REAGENT_ID_MILK, 2)),
		makes = list(reagent(REAGENT_ID_BUBBLETEACHERRY, 10))))

/transformation/chem/instant/drinks/bubbleteacoffee

CAPABILITIES(/transformation/chem/instant/drinks/bubbleteacoffee)
	configure(transformation(name = REAGENT_BUBBLETEACOFFEE, id = REAGENT_ID_BUBBLETEACOFFEE,
		takes = list(reagent(REAGENT_ID_GELATIN, 2), reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_CAFELATTE, 3)),
		makes = list(reagent(REAGENT_ID_BUBBLETEACOFFEE, 10))))

/transformation/chem/instant/drinks/bubbleteabanana

CAPABILITIES(/transformation/chem/instant/drinks/bubbleteabanana)
	configure(transformation(name = REAGENT_BUBBLETEABANANA, id = REAGENT_ID_BUBBLETEABANANA,
		takes = list(reagent(REAGENT_ID_GELATIN, 2), reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_BANANA, 1), reagent(REAGENT_ID_MILK, 2)),
		makes = list(reagent(REAGENT_ID_BUBBLETEABANANA, 10))))

/transformation/chem/instant/drinks/horchata

CAPABILITIES(/transformation/chem/instant/drinks/horchata)
	configure(transformation(name = REAGENT_HORCHATA, id = REAGENT_ID_HORCHATA,
		takes = list(reagent(REAGENT_ID_MILK, 1), reagent(REAGENT_ID_SUGAR, 2), reagent(REAGENT_ID_RICE, 2)),
		makes = list(reagent(REAGENT_ID_HORCHATA, 5))))

/transformation/chem/instant/drinks/bluetrain

CAPABILITIES(/transformation/chem/instant/drinks/bluetrain)
	configure(transformation(name = "Blue train", id = REAGENT_ID_BLUETRAIN,
		takes = list(reagent(REAGENT_ID_COOLANT, 2), reagent(REAGENT_ID_ETHANOL, 2), reagent(REAGENT_ID_NUTRIMENT, 1)),
		makes = list(reagent(REAGENT_ID_BLUETRAIN, 5))))

/transformation/chem/instant/drinks/lowpower

CAPABILITIES(/transformation/chem/instant/drinks/lowpower)
	configure(transformation(name = REAGENT_LOWPOWER, id = REAGENT_ID_LOWPOWER,
		takes = list(reagent(REAGENT_ID_LEMONADE, 1), reagent(REAGENT_ID_CREAM, 1), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LOWPOWER, 3))))

/transformation/chem/instant/drinks/jackbrew

CAPABILITIES(/transformation/chem/instant/drinks/jackbrew)
	configure(transformation(name = "Jack's brew", id = REAGENT_ID_JACKBREW,
		takes = list(reagent(REAGENT_ID_IRISHCOFFEE, 1), reagent(REAGENT_ID_HYPERZINE, 1)),
		makes = list(reagent(REAGENT_ID_JACKBREW, 2))))

/transformation/chem/instant/drinks/bookwyrm

CAPABILITIES(/transformation/chem/instant/drinks/bookwyrm)
	configure(transformation(name = REAGENT_BOOKWYRM, id = REAGENT_ID_BOOKWYRM,
		takes = list(reagent(REAGENT_ID_COLDFRONT, 1), reagent(REAGENT_ID_LIMEJUICE, 1), reagent(REAGENT_ID_STOXIN, 1)),
		makes = list(reagent(REAGENT_ID_BOOKWYRM, 3))))

/transformation/chem/instant/drinks/highpower

CAPABILITIES(/transformation/chem/instant/drinks/highpower)
	configure(transformation(name = "The high power", id = REAGENT_ID_HIGHPOWER,
		takes = list(reagent(REAGENT_ID_LOWPOWER, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_HIGHPOWER, 3))))

/transformation/chem/instant/drinks/flapper

CAPABILITIES(/transformation/chem/instant/drinks/flapper)
	configure(transformation(name = REAGENT_FLAPPER, id = REAGENT_ID_FLAPPER,
		takes = list(reagent(REAGENT_ID_WHISKEY, 1), reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_FLAPPER, 3))))

/transformation/chem/instant/toxin/oilslide

CAPABILITIES(/transformation/chem/instant/toxin/oilslide)
	configure(transformation(name = REAGENT_OILSLIDE, id = REAGENT_ID_OILSLIDE,
		takes = list(reagent(REAGENT_ID_MOONSHINE, 1), reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_FUEL, 1)),
		makes = list(reagent(REAGENT_ID_OILSLIDE, 3))))

/transformation/chem/instant/drinks/sitonmyface

CAPABILITIES(/transformation/chem/instant/drinks/sitonmyface)
	configure(transformation(name = REAGENT_SITONMYFACE, id = REAGENT_ID_SITONMYFACE,
		takes = list(reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_IRISHCREAM, 1), reagent(REAGENT_ID_PEANUTBUTTER, 1)),
		makes = list(reagent(REAGENT_ID_SITONMYFACE, 3))))

/transformation/chem/instant/drinks/hachi

CAPABILITIES(/transformation/chem/instant/drinks/hachi)
	configure(transformation(name = REAGENT_HACHI, id = REAGENT_ID_HACHI,
		takes = list(reagent(REAGENT_ID_WHISKEY, 2), reagent(REAGENT_ID_SAKE, 1), reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_PSILOCYBIN, 1)),
		makes = list(reagent(REAGENT_ID_HACHI, 5))))

/transformation/chem/instant/drinks/narsour

CAPABILITIES(/transformation/chem/instant/drinks/narsour)
	configure(transformation(name = "Nar'sour", id = REAGENT_ID_NARSOUR,
		takes = list(reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_LEMONJUICE, 1), reagent(REAGENT_ID_DEMONSBLOOD, 1)),
		makes = list(reagent(REAGENT_ID_NARSOUR, 3)), says = "The mixture develops a sinister glow.",
		plays = SFX_EFFECTS_SINGLEBEAT))

/transformation/chem/instant/drinks/cogchamp

CAPABILITIES(/transformation/chem/instant/drinks/cogchamp)
	configure(transformation(name = REAGENT_COGCHAMP, id = REAGENT_ID_COGCHAMP,
		takes = list(reagent(REAGENT_ID_COGNAC, 1), reagent(REAGENT_ID_FUEL, 1), reagent(REAGENT_ID_SCREWDRIVERCOCKTAIL, 1)),
		makes = list(reagent(REAGENT_ID_COGCHAMP, 3)),
		says = "You hear faint sounds of gears turning as the mixture gives off virulent plumes of steam.",
		plays = SFX_MACHINES_CLOCKCULT_STEAM_WHOOSH))

//thirteen loko possible to make now, so easier to make arachnid slammer - Jack

/transformation/chem/instant/drinks/thirteenloko

CAPABILITIES(/transformation/chem/instant/drinks/thirteenloko)
	configure(transformation(name = REAGENT_THIRTEENLOKO, id = REAGENT_ID_THIRTEENLOKO,
		takes = list(reagent(REAGENT_ID_BEER, 1), reagent(REAGENT_ID_TEQUILA, 1), reagent(REAGENT_ID_COFFEE, 1)),
		makes = list(reagent(REAGENT_ID_THIRTEENLOKO, 3))))

//Arachnid slammer reactions - Jack

/transformation/chem/instant/drinks/arachnidslammer

CAPABILITIES(/transformation/chem/instant/drinks/arachnidslammer)
	configure(transformation(name = REAGENT_ARACHNIDSLAMMER, id = REAGENT_ID_ARACHNIDSLAMMER,
		takes = list(reagent(REAGENT_ID_ALE, 1), reagent(REAGENT_ID_THIRTEENLOKO, 1), reagent(REAGENT_ID_HYPERZINE, 1)),
		makes = list(reagent(REAGENT_ID_ARACHNIDSLAMMER, 3)),
		says = "The concortion of ale, energy drink and stimulants starts to heavily foam and fizzle, even sparkle a little."))

/transformation/chem/instant/drinks/enragedarachnidslammer

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER,
		takes = list(reagent(REAGENT_ID_INFUSEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_SPIDERTOXIN, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 5)),
		says = "The dormant Arachnid Slammer bubbles and fizzles loudly as it gets enraged by the spider toxin and breaks it down!"))

/transformation/chem/instant/drinks/enragedarachnidslammer1

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer1)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "1",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_CYANIDE, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer2

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer2)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "2",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_CHLORALHYDRATE, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer3

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer3)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "3",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_STIMM, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer4

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer4)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "4",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_CRYOTOXIN, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer5

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer5)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "5",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_CRYPTOBIOLIN, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer6

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer6)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "6",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_STOXIN, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer7

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer7)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "7",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_CONDENSEDCAPSAICINV, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer8

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer8)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "8",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer9

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer9)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "9",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_THERMITEV, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/enragedarachnidslammer10

CAPABILITIES(/transformation/chem/instant/drinks/enragedarachnidslammer10)
	configure(transformation(name = REAGENT_ENRAGEDARACHNIDSLAMMER, id = REAGENT_ID_ENRAGEDARACHNIDSLAMMER + "10",
		takes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 1), reagent(REAGENT_ID_SEROTROTIUMV, 1)),
		makes = list(reagent(REAGENT_ID_ENRAGEDARACHNIDSLAMMER, 0.1))))

/transformation/chem/instant/drinks/pilk

CAPABILITIES(/transformation/chem/instant/drinks/pilk)
	configure(transformation(name = REAGENT_PILK, id = REAGENT_ID_PILK, takes = list(reagent(REAGENT_ID_MILK, 1), reagent(REAGENT_ID_COLA, 1)),
		makes = list(reagent(REAGENT_ID_PILK, 2))))

// Drinks from Horizon

/transformation/chem/instant/drinks/fetching_fizz

CAPABILITIES(/transformation/chem/instant/drinks/fetching_fizz)
	configure(transformation(name = REAGENT_FETCHINGFIZZ, id = REAGENT_ID_FETCHINGFIZZ,
		takes = list(reagent(REAGENT_ID_NUKACOLA, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_FETCHINGFIZZ, 3))))

/transformation/chem/instant/drinks/hearty_punch

CAPABILITIES(/transformation/chem/instant/drinks/hearty_punch)
	configure(transformation(name = REAGENT_HEARTYPUNCH, id = REAGENT_ID_HEARTYPUNCH,
		takes = list(reagent(REAGENT_ID_BRAVEBULL, 5), reagent(REAGENT_ID_SYNDICATEBOMB, 5), reagent(REAGENT_ID_ABSINTHE, 5)),
		makes = list(reagent(REAGENT_ID_HEARTYPUNCH, 1))))

/transformation/chem/instant/drinks/squirt_cider

CAPABILITIES(/transformation/chem/instant/drinks/squirt_cider)
	configure(transformation(name = REAGENT_SQUIRTCIDER, id = REAGENT_ID_SQUIRTCIDER,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_TOMATOJUICE, 1), reagent(REAGENT_ID_NUTRIMENT, 1)),
		makes = list(reagent(REAGENT_ID_SQUIRTCIDER, 3))))

/transformation/chem/instant/drinks/fringe_weaver

CAPABILITIES(/transformation/chem/instant/drinks/fringe_weaver)
	configure(transformation(name = REAGENT_FRINGEWEAVER, id = REAGENT_ID_FRINGEWEAVER,
		takes = list(reagent(REAGENT_ID_ETHANOL, 9), reagent(REAGENT_ID_SUGAR, 1)), blocked_by = list(reagent(REAGENT_ID_FUEL, 1)),
		makes = list(reagent(REAGENT_ID_FRINGEWEAVER, 10))))

/transformation/chem/instant/drinks/crevice_spike

CAPABILITIES(/transformation/chem/instant/drinks/crevice_spike)
	configure(transformation(name = REAGENT_CREVICESPIKE, id = REAGENT_ID_CREVICESPIKE,
		takes = list(reagent(REAGENT_ID_LIMEJUICE, 2), reagent(REAGENT_ID_CAPSAICIN, 4)),
		makes = list(reagent(REAGENT_ID_CREVICESPIKE, 6))))

/transformation/chem/instant/drinks/duplex

CAPABILITIES(/transformation/chem/instant/drinks/duplex)
	configure(transformation(name = REAGENT_DUPLEX, id = REAGENT_ID_DUPLEX,
		takes = list(reagent(REAGENT_ID_CIDER, 2), reagent(REAGENT_ID_APPLEJUICE, 1), reagent(REAGENT_ID_BERRYJUICE, 1)),
		makes = list(reagent(REAGENT_ID_DUPLEX, 4))))

/transformation/chem/instant/drinks/mauna_loa

CAPABILITIES(/transformation/chem/instant/drinks/mauna_loa)
	configure(transformation(name = REAGENT_MAUNALOA, id = REAGENT_ID_MAUNALOA,
		takes = list(reagent(REAGENT_ID_CAPSAICIN, 2), reagent(REAGENT_ID_KAHLUA, 1), reagent(REAGENT_ID_BAHAMAMAMA, 2)),
		makes = list(reagent(REAGENT_ID_MAUNALOA, 5))))

/transformation/chem/instant/drinks/hiveminderaser

CAPABILITIES(/transformation/chem/instant/drinks/hiveminderaser)
	configure(transformation(name = REAGENT_HIVEMINDERASER, id = REAGENT_ID_HIVEMINDERASER,
		takes = list(reagent(REAGENT_ID_BLACKRUSSIAN, 2), reagent(REAGENT_ID_THIRTEENLOKO, 1), reagent(REAGENT_ID_GRENADINE, 1)),
		makes = list(reagent(REAGENT_ID_HIVEMINDERASER, 4))))

//YW drinks
/transformation/chem/instant/drinks/wormblood

CAPABILITIES(/transformation/chem/instant/drinks/wormblood)
	configure(transformation(name = "Wormblood", id = REAGENT_ID_WORMBLOOD,
		takes = list(reagent(REAGENT_ID_BOOGER, 1), reagent(REAGENT_ID_PSILOCYBIN, 1)),
		makes = list(reagent(REAGENT_ID_WORMBLOOD, 2))))
