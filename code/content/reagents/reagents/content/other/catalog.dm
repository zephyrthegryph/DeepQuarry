/* Paint and crayons */

/datum/reagent/crayon_dust
	name = REAGENT_CRAYONDUST
	id = REAGENT_ID_CRAYONDUST
	description = "Intensely coloured powder obtained by grinding crayons."
	taste_description = "powdered wax"
	reagent_state = SOLID
	dermal_absorption = 0 //no
	color = "#888888"
	overdose = 10
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/crayon_dust/red
	name = REAGENT_CRAYONDUSTRED
	id = REAGENT_ID_CRAYONDUSTRED
	color = "#FE191A"

/datum/reagent/crayon_dust/orange
	name = REAGENT_CRAYONDUSTORANGE
	id = REAGENT_ID_CRAYONDUSTORANGE
	color = "#FFBE4F"

/datum/reagent/crayon_dust/yellow
	name = REAGENT_CRAYONDUSTYELLOW
	id = REAGENT_ID_CRAYONDUSTYELLOW
	color = "#FDFE7D"

/datum/reagent/crayon_dust/green
	name = REAGENT_CRAYONDUSTGREEN
	id = REAGENT_ID_CRAYONDUSTGREEN
	color = "#18A31A"

/datum/reagent/crayon_dust/blue
	name = REAGENT_CRAYONDUSTBLUE
	id = REAGENT_ID_CRAYONDUSTBLUE
	color = "#247CFF"

/datum/reagent/crayon_dust/purple
	name = REAGENT_CRAYONDUSTPURPLE
	id = REAGENT_ID_CRAYONDUSTPURPLE
	color = "#CC0099"

/datum/reagent/crayon_dust/grey //Mime
	name = REAGENT_CRAYONDUSTGREY
	id = REAGENT_ID_CRAYONDUSTGREY
	color = "#808080"

/datum/reagent/crayon_dust/brown //Rainbow
	name = REAGENT_CRAYONDUSTBROWN
	id = REAGENT_ID_CRAYONDUSTBROWN
	color = "#846F35"

/datum/reagent/marker_ink
	name = REAGENT_MARKERINK
	id = REAGENT_ID_MARKERINK
	description = "Intensely coloured ink used in markers."
	taste_description = "extremely bitter"
	reagent_state = LIQUID
	dermal_absorption = 0 //NO
	color = "#888888"
	overdose = 10
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/marker_ink/black
	name = REAGENT_MARKERINKBLACK
	id = REAGENT_ID_MARKERINKBLACK
	color = "#000000"

/datum/reagent/marker_ink/red
	name = REAGENT_MARKERINKRED
	id = REAGENT_ID_MARKERINKRED
	color = "#FE191A"

/datum/reagent/marker_ink/orange
	name = REAGENT_MARKERINKORANGE
	id = REAGENT_ID_MARKERINKORANGE
	color = "#FFBE4F"

/datum/reagent/marker_ink/yellow
	name = REAGENT_MARKERINKYELLOW
	id = REAGENT_ID_MARKERINKYELLOW
	color = "#FDFE7D"

/datum/reagent/marker_ink/green
	name = REAGENT_MARKERINKGREEN
	id = REAGENT_ID_MARKERINKGREEN
	color = "#18A31A"

/datum/reagent/marker_ink/blue
	name = REAGENT_MARKERINKBLUE
	id = REAGENT_ID_MARKERINKBLUE
	color = "#247CFF"

/datum/reagent/marker_ink/purple
	name = REAGENT_MARKERINKPURPLE
	id = REAGENT_ID_MARKERINKPURPLE
	color = "#CC0099"

/datum/reagent/marker_ink/grey //Mime
	name = REAGENT_MARKERINKGREY
	id = REAGENT_ID_MARKERINKGREY
	color = "#808080"

/datum/reagent/marker_ink/brown //Rainbow
	name = REAGENT_MARKERINKBROWN
	id = REAGENT_ID_MARKERINKBROWN
	color = "#846F35"

/datum/reagent/gold
	name = REAGENT_GOLD
	id = REAGENT_ID_GOLD
	description = "Gold is a dense, soft, shiny metal and the most malleable and ductile metal known."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#F7C430"
	supply_conversion_value = 2 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/silver
	name = REAGENT_SILVER
	id = REAGENT_ID_SILVER
	description = "A soft, white, lustrous transition metal, it has the highest electrical conductivity of any element and the highest thermal conductivity of any metal."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#D0D0D0"
	supply_conversion_value = 1 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/platinum
	name = REAGENT_PLATINUM
	id = REAGENT_ID_PLATINUM
	description = "Platinum is a dense, malleable, ductile, highly unreactive, precious, gray-white transition metal.  It is very resistant to corrosion."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#777777"
	supply_conversion_value = 5 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/hydrogen/deuterium
	name = REAGENT_DEUTERIUM
	id = REAGENT_ID_DEUTERIUM
	description = "A isotope of hydrogen. It has one extra neutron, and shares all chemical characteristics with hydrogen."
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 1 // It's ALMOST water

/datum/reagent/hydrogen/tritium
	name = REAGENT_TRITIUM
	id = REAGENT_ID_TRITIUM
	description = "A radioactive isotope of hydrogen. It has two extra neutrons, and shares all other chemical characteristics with hydrogen."
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 1 // It's ALMOST water

/datum/reagent/lithium/lithium6
	name = REAGENT_LITHIUM6
	id = REAGENT_ID_LITHIUM6
	description = "An isotope of lithium. It has 3 neutrons, but shares all chemical characteristics with regular lithium."
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/helium/helium3
	name = REAGENT_HELIUM3
	id = REAGENT_ID_HELIUM3
	description = "An isotope of helium. It only has one neutron, but shares all chemical characteristics with regular helium."
	taste_mult = 0
	reagent_state = GAS
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 2

/datum/reagent/boron/boron11
	name = REAGENT_BORON11
	id = REAGENT_ID_BORON11
	description = "An isotope of boron. It has 6 neutrons."
	taste_description = "metallic" // Apparently noone on the internet knows what boron tastes like. Or at least they won't share
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/ammonia
	name = REAGENT_AMMONIA
	id = REAGENT_ID_AMMONIA
	description = "A caustic substance commonly used in fertilizer or household cleaners."
	taste_description = "mordant"
	taste_mult = 2
	reagent_state = GAS
	scannable = SCANNABLE_ADVANCED
	color = "#404030"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 1.25

/datum/reagent/diethylamine
	name = REAGENT_DIETHYLAMINE
	id = REAGENT_ID_DIETHYLAMINE
	description = "A secondary amine, mildly corrosive."
	taste_description = REAGENT_ID_IRON
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#604030"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/lye
	name = REAGENT_LYE
	id = REAGENT_ID_LYE
	description = "Also known as sodium hydroxide. As a profession making this is somewhat underwhelming."
	taste_description = "acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#FFFFD6" // very very light yellow"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/fluorosurfactant // Foam precursor
	name = REAGENT_FLUOROSURFACTANT
	id = REAGENT_ID_FLUOROSURFACTANT
	description = "A perfluoronated sulfonic acid that forms a foam when mixed with water."
	taste_description = "metal"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#9E6B38"
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/foaming_agent // Metal foaming agent. This is lithium hydride. Add other recipes (e.g. LiH + H2O -> LiOH + H2) eventually.
	name = REAGENT_FOAMINGAGENT
	id = REAGENT_ID_FOAMINGAGENT
	description = "A agent that yields metallic foam when mixed with light metal and a strong acid."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#664B63"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/glycerol
	name = REAGENT_GLYCEROL
	id = REAGENT_ID_GLYCEROL
	description = "Glycerol is a simple polyol compound. Glycerol is sweet-tasting and of low toxicity."
	taste_description = "sweetness"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 0.95

/datum/reagent/nitroglycerin //This immediately explode as soon as it reacts, so you can't actually obtain this.
	name = REAGENT_NITROGLYCERIN
	id = REAGENT_ID_NITROGLYCERIN
	description = "Nitroglycerin is a heavy, colorless, oily, explosive liquid obtained by nitrating glycerol."
	taste_description = "oil"
	reagent_state = LIQUID
	scannable = SCANNABLE_UNSCANNABLE
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/ultraglue
	name = REAGENT_GLUE
	id = REAGENT_ID_GLUE
	scannable = SCANNABLE_ADVANCED
	description = "An extremely powerful bonding agent."
	taste_description = "a special education class"
	color = "#FFFFCC"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/woodpulp
	name = REAGENT_WOODPULP
	id = REAGENT_ID_WOODPULP
	scannable = SCANNABLE_ADVANCED
	description = "A mass of wood fibers."
	taste_description = "wood"
	reagent_state = LIQUID
	color = "#B97A57"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/nutriment/biomass
	name = REAGENT_BIOMASS
	id = REAGENT_ID_BIOMASS
	description = "A slurry of compounds that contains the basic requirements for life."
	taste_description = "salty meat"
	reagent_state = LIQUID
	color = "#DF9FBF"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	coolant_modifier = -2 //Ew

/datum/reagent/mineralfluid
	name = REAGENT_MINERALIZEDFLUID
	id = REAGENT_ID_MINERALIZEDFLUID
	scannable = SCANNABLE_ADVANCED
	description = "A warm, mineral-rich fluid."
	taste_description = "salt"
	reagent_state = LIQUID
	color = "#ff205255"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI
	coolant_modifier = -2.5

/datum/reagent/nutriment/fishbait
	name = REAGENT_FISHBAIT
	id = REAGENT_ID_FISHBAIT
	description = "A natural slurry that particularily appeals to fish."
	taste_description = "slimy dirt"
	reagent_state = LIQUID
	color = "#62764E"
	nutriment_factor = 15
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/nutriment/paper //Paper is made from cellulose. You can eat it. It doesn't fill you up very much at all.
	name = "Paper"
	id = "paper"
	description = "Soggy, ground up paper"
	taste_description = "paper"
	reagent_state = SOLID
	color = "e6e6e6" //not quite white
	nutriment_factor = 2 // 5 times worse than nutriment

/datum/reagent/carpet
	name = REAGENT_LIQUIDCARPET
	id = REAGENT_ID_LIQUIDCARPET
	scannable = SCANNABLE_ADVANCED
	description = "Liquified carpet fibers, ready for dyeing."
	reagent_state = LIQUID
	color = "#b51d05"
	taste_description = "carpet"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/carpet/black
	name = REAGENT_LIQUIDCARPETB
	id = REAGENT_ID_LIQUIDCARPETB
	description = "Black Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#000000"
	taste_description = "rare and ashy carpet"

/datum/reagent/carpet/blue
	name = REAGENT_LIQUIDCARPETBLU
	id = REAGENT_ID_LIQUIDCARPETBLU
	description = "Blue Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#3f4aee"
	taste_description = "commanding carpet"

/datum/reagent/carpet/turquoise
	name = REAGENT_LIQUIDCARPETTUR
	id = REAGENT_ID_LIQUIDCARPETTUR
	description = "Turquoise Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#0592b5"
	taste_description = "water-logged carpet"

/datum/reagent/carpet/sblue
	name = REAGENT_LIQUIDCARPETSBLU
	id = REAGENT_ID_LIQUIDCARPETSBLU
	description = "Silver Blue Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#0011ff"
	taste_description = "sterile and medicinal carpet"

/datum/reagent/carpet/clown
	name = REAGENT_LIQUIDCARPETC
	id = REAGENT_ID_LIQUIDCARPETC
	description = "Clown Carpet Fibers.... No clowns were harmed in the making of this."
	reagent_state = LIQUID
	color = "#e925be"
	taste_description = "clown shoes and banana peels"

/datum/reagent/carpet/purple
	name = REAGENT_LIQUIDCARPETP
	id = REAGENT_ID_LIQUIDCARPETP
	description = "Purple Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#a614d3"
	taste_description = "bleeding edge carpet research"

/datum/reagent/carpet/orange
	name = REAGENT_LIQUIDCARPETO
	id = REAGENT_ID_LIQUIDCARPETO
	description = "Orange Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#f16e16"
	taste_description = "extremely overengineered carpet"

/datum/reagent/essential_oil
	name = REAGENT_ESSENTIALOIL
	id = REAGENT_ID_ESSENTIALOIL
	scannable = SCANNABLE_ADVANCED
	description = "A slurry of compounds that contains the basic requirements for life."
	taste_description = "a mixture of thick, sweet, salty, salty and spicy flavours that all blend together to not be very nice at all"
	reagent_state = LIQUID
	color = "#e8e2b0"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/nutriment/pitcher_nectar //Pitcher plant reagent, doubles plant growth speed.
	name = REAGENT_PITCHERNECTAR
	id = REAGENT_ID_PITCHERNECTAR
	description = "An odd, sticky slurry which promotes rapid plant growth."
	taste_description = "pineapple"
	reagent_state = LIQUID
	nutriment_factor = 60
	color = "#a839a2"

//////SAP IN UNREFINED FORM////

/datum/reagent/toxin/bluesap //This is the first sap. Blue one.
	name = REAGENT_BLUESAP
	id = REAGENT_ID_BLUESAP
	description = "Glowing blue liquid."
	reagent_state = LIQUID
	color = "#91f9ff" // rgb(145, 249, 255)
	metabolism = 0.01
	strength = 10//Don't drink it
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/purplesap
	name = REAGENT_ID_PURPLESAP
	id = REAGENT_PURPLESAP
	description = "Purple liquid. It is very sticky and smells of ammonia."
	color = "#7a48a0"
	taste_description = "Ammonia"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/orangesap
	name = REAGENT_ORANGESAP
	id = REAGENT_ID_ORANGESAP
	description = "Orange liquid. It wobbles around a bit like jelly."
	color = "#e0962f"
	taste_description = "Ammonia"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

//Special toxins for solargrubs
/datum/reagent/grubshock
	name = REAGENT_SHOCKCHEM //in other words a painful shock
	id = REAGENT_ID_SHOCKCHEM
	description = "A liquid that quickly dissapates to deliver a painful shock."
	reagent_state = LIQUID
	color = "#E4EC2F"
	metabolism = 2.50
	scannable = SCANNABLE_ADVANCED
	var/power = 9
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/grubshock/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_ELECTRIC, removed * power * 0.2, source = src)
