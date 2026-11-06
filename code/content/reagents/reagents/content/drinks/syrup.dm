/datum/reagent/drink/syrup
	name = REAGENT_SYRUP
	id = REAGENT_ID_SYRUP
	description = "A generic, sugary syrup."
	taste_description = "sweetness"
	color = "#fffbe8"
	cup_prefix = "extra sweet"

	glass_name = REAGENT_ID_SYRUP
	glass_desc = "That is just way too much syrup to drink on its own."
	allergen_type = ALLERGEN_SUGARS

	overdose = REAGENTS_OVERDOSE *1.5

/datum/reagent/drink/syrup/overdose(mob/living/carbon/M, alien)
	if(inert_for(M))
		return
	M.status_adjust(STAT_DIZZY, 1)

/datum/reagent/drink/syrup/pumpkin
	name = REAGENT_SYRUPPUMPKIN
	id = REAGENT_ID_SYRUPPUMPKIN
	description = "A sugary syrup that tastes of pumpkin spice."
	taste_description = "pumpkin spice"
	color = "#e0b439"
	cup_prefix = "pumpkin spice"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/caramel
	name = REAGENT_SYRUPCARAMEL
	id = REAGENT_ID_SYRUPCARAMEL
	description = "A sugary syrup that tastes of caramel."
	taste_description = "caramel"
	color = "#b47921"
	cup_prefix = "caramel"

/datum/reagent/drink/syrup/scaramel
	name = REAGENT_SYRUPSALTEDCARAMEL
	id = REAGENT_ID_SYRUPSALTEDCARAMEL
	description = "A sugary syrup that tastes of salted caramel."
	taste_description = "salty caramel"
	color = "#9f6714"
	cup_prefix = "salted caramel"

/datum/reagent/drink/syrup/irish
	name = REAGENT_SYRUPIRISH
	id = REAGENT_ID_SYRUPIRISH
	description = "A sugary syrup that tastes of a light, sweet cream."
	taste_description = "creaminess"
	color = "#ead3b0"
	cup_prefix = "irish"

/datum/reagent/drink/syrup/almond
	name = REAGENT_SYRUPALMOND
	id = REAGENT_ID_SYRUPALMOND
	description = "A sugary syrup that tastes of almonds."
	taste_description = "almonds"
	color = "#ffb64a"
	cup_prefix = "almond"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_SEEDS

/datum/reagent/drink/syrup/cinnamon
	name = REAGENT_SYRUPCINNAMON
	id = REAGENT_ID_SYRUPCINNAMON
	description = "A sugary syrup that tastes of cinnamon."
	taste_description = "cinnamon"
	color = "#ec612a"
	cup_prefix = "cinnamon"

/datum/reagent/drink/syrup/pistachio
	name = REAGENT_SYRUPPISTACHIO
	id = REAGENT_ID_SYRUPPISTACHIO
	description = "A sugary syrup that tastes of pistachio."
	taste_description = "pistachio"
	color = "#c9eb59"
	cup_prefix = "pistachio"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_SEEDS

/datum/reagent/drink/syrup/vanilla
	name = REAGENT_SYRUPVANILLA
	id = REAGENT_ID_SYRUPVANILLA
	description = "A sugary syrup that tastes of vanilla."
	taste_description = "vanilla"
	color = "#eaebd1"
	cup_prefix = REAGENT_ID_VANILLA

/datum/reagent/drink/syrup/toffee
	name = REAGENT_SYRUPTOFFEE
	id = REAGENT_ID_SYRUPTOFFEE
	description = "A sugary syrup that tastes of toffee."
	taste_description = "toffee"
	color = "#aa7143"
	cup_prefix = "toffee"

/datum/reagent/drink/syrup/cherry
	name = REAGENT_SYRUPCHERRY
	id = REAGENT_ID_SYRUPCHERRY
	description = "A sugary syrup that tastes of cherries."
	taste_description = "cherries"
	color = "#ff0000"
	cup_prefix = "cherry"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/butterscotch
	name = REAGENT_SYRUPBUTTERSCOTCH
	id = REAGENT_ID_SYRUPBUTTERSCOTCH
	description = "A sugary syrup that tastes of butterscotch."
	taste_description = "butterscotch"
	color = "#e6924e"
	cup_prefix = "butterscotch"

/datum/reagent/drink/syrup/chocolate
	name = REAGENT_SYRUPCHOCOLATE
	id = REAGENT_ID_SYRUPCHOCOLATE
	description = "A sugary syrup that tastes of chocolate."
	taste_description = REAGENT_ID_CHOCOLATE
	color = "#873600"
	cup_prefix = REAGENT_ID_CHOCOLATE

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_CHOCOLATE

/datum/reagent/drink/syrup/wchocolate
	name = REAGENT_SYRUPWHITECHOCOLATE
	id = REAGENT_ID_SYRUPWHITECHOCOLATE
	description = "A sugary syrup that tastes of white chocolate."
	taste_description = "white chocolate"
	color = "#c4c6a5"
	cup_prefix = "white chocolate"

	allergen_type = ALLERGEN_SUGARS //|ALLERGEN_CHOCOLATE //commenting this out and leaving this comment to inform that WHITE CHOCOLATE IS NOT CHOCOLATE!!!!

/datum/reagent/drink/syrup/strawberry
	name = REAGENT_SYRUPSTRAWBERRY
	id = REAGENT_ID_SYRUPSTRAWBERRY
	description = "A sugary syrup that tastes of strawberries."
	taste_description = "strawberries"
	color = "#ff2244"
	cup_prefix = "strawberry"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/coconut
	name = REAGENT_SYRUPCOCONUT
	id = REAGENT_ID_SYRUPCOCONUT
	description = "A sugary syrup that tastes of coconut."
	taste_description = "coconut"
	color = "#ffffff"
	cup_prefix = "coconut"

	allergen_type = ALLERGEN_SUGARS|ALLERGEN_FRUIT

/datum/reagent/drink/syrup/ginger
	name = REAGENT_SYRUPGINGER
	id = REAGENT_ID_SYRUPGINGER
	description = "A sugary syrup that tastes of ginger."
	taste_description = "ginger"
	color = "#d09740"
	cup_prefix = "ginger"

/datum/reagent/drink/syrup/gingerbread
	name = REAGENT_SYRUPGINGERBREAD
	id = REAGENT_ID_SYRUPGINGERBREAD
	description = "A sugary syrup that tastes of gingerbread."
	taste_description = "gingerbread"
	color = "#b6790f"
	cup_prefix = "gingerbread"

/datum/reagent/drink/syrup/peppermint
	name = REAGENT_SYRUPPEPPERMINT
	id = REAGENT_ID_SYRUPPEPPERMINT
	description = "A sugary syrup that tastes of peppermint."
	taste_description = "peppermint"
	color = "#9ce06e"
	cup_prefix = "peppermint"

/datum/reagent/drink/syrup/birthday_cake
	name = REAGENT_SYRUPBIRTHDAY
	id = REAGENT_ID_SYRUPBIRTHDAY
	description = "A sugary syrup that tastes of an overload of sweetness."
	taste_description = "far too much sugar"
	color = "#ff00e6"
	cup_prefix = "birthday cake"
