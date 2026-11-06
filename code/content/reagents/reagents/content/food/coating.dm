// Aurora Cooking Port Insertion Begin

/*
	Coatings are used in cooking. Dipping food items in a reagent container with a coating in it
	allows it to be covered in that, which will add a masked overlay to the sprite.
	Coatings have both a raw and a cooked image. Raw coating is generally unhealthy
	Generally coatings are intended for deep frying foods
*/
/datum/reagent/nutriment/coating
	name = REAGENT_COATING
	id = REAGENT_ID_COATING
	nutriment_factor = 6 //Less dense than the food itself, but coatings still add extra calories
	var/messaged = 0
	var/icon_raw
	var/icon_cooked
	var/coated_adj = "coated"
	var/cooked_name = "coating"

/datum/reagent/nutriment/coating/affect_ingest(mob/living/carbon/M, alien, removed)

	//We'll assume that the batter isnt going to be regurgitated and eaten by someone else. Only show this once
	if(data["cooked"] != 1)
		if (!messaged)
			to_chat(M, span_warning("Ugh, this raw [name] tastes disgusting."))
			nutriment_factor *= 0.5
			messaged = 1

		//Raw coatings will sometimes cause vomiting. 75% chance of this happening.
		if(prob(75))
			M.vomit()
	..()

/datum/reagent/nutriment/coating/initialize_data(newdata) // Called when the reagent is created.
	..()
	if (!data)
		data = list()
	else
		if (isnull(data["cooked"]))
			data["cooked"] = 0
		return
	data["cooked"] = 0
	if (holder && holder.my_atom && istype(holder.my_atom,/obj/item/reagent_containers/food/snacks))
		data["cooked"] = 1
		set_name(cooked_name)

		//Batter which is part of objects at compiletime spawns in a cooked state

/// Coating data always requires a "cooked" key.
TYPE_TABLE(/datum/reagent/nutriment/coating, get_data_schema, list("cooked"))

//Handles setting the temperature when oils are mixed
/datum/reagent/nutriment/coating/mix_data(newdata, newamount)
	if (!data)
		data = list()
	if(!newdata || isnull(newdata["cooked"]))
		return

	data["cooked"] = newdata["cooked"]

/datum/reagent/nutriment/coating/batter
	name = REAGENT_BATTER
	cooked_name = REAGENT_ID_BATTER
	id = REAGENT_ID_BATTER
	color = "#f5f4e9"
	reagent_state = LIQUID
	icon_raw = "batter_raw"
	icon_cooked = "batter_cooked"
	coated_adj = "battered"
	allergen_type = ALLERGEN_GRAINS | ALLERGEN_EGGS //Made with flour(grain), and eggs(eggs)

/datum/reagent/nutriment/coating/beerbatter
	factors = alist(STAT_INTOXICATION = 0.02) //Very slightly alcoholic
	name = REAGENT_BEERBATTER
	cooked_name = "beer batter"
	id = REAGENT_ID_BEERBATTER
	color = "#f5f4e9"
	reagent_state = LIQUID
	icon_raw = "batter_raw"
	icon_cooked = "batter_cooked"
	coated_adj = "beer-battered"
	allergen_type = ALLERGEN_GRAINS | ALLERGEN_EGGS //Made with flour(grain), eggs(eggs), and beer(grain)
