////////////////////////////////////////////////////////////////////////////////
/// Drinks.
////////////////////////////////////////////////////////////////////////////////
/obj/item/reagent_containers/food/drinks
	name = "drink"
	desc = "yummy"
	icon = 'icons/obj/drinks.dmi'
	drop_sound = SFX_ITEMS_DROP_DRINKGLASS
	pickup_sound =  SFX_ITEMS_PICKUP_DRINKGLASS
	icon_state = null
	/// Open from the start (a can is shut until it is opened).
	var/open_at_start = TRUE
	amount_per_transfer_from_this = 5
	max_transfer_amount = 50
	volume = 50
	var/trash = null
	var/cant_open = 0
	var/cant_chance = 0
	/// Monotonic serving sequence used by the generic contract event ledger.
	var/contract_consumption_sequence = 0

	var/is_can = FALSE

	/// Yims
	food_can_insert_micro = TRUE

	///Var for attack_self chain
	var/special_handling = FALSE

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/reagent_containers/food/drinks/proc/roll_cant_open(datum/roller/R)
	return R.chance(cant_chance) ? TRUE : cant_open

/obj/item/reagent_containers/food/drinks/on_reagent_change()
	if (reagents.reagent_list.len > 0)
		var/datum/reagent/reagent = reagents.get_master_reagent()
		if(reagent.price_tag)
			price_tag = reagent.price_tag
		else
			price_tag = null
	return

/// A drink that is shut takes nobody.
/obj/item/reagent_containers/food/drinks/stuffing_free(datum/act/op/A)
	return is_open_container()

/obj/item/reagent_containers/food/drinks/micro_stuffed_messages(mob/user, mob/living/micro)
	to_chat(user, span_warning("You drop [micro] into \the [src]."))
	to_chat(micro, span_warning("[user] drops you into \the [src]."))

// A drink is a holder of its volume that is open or shut (a lid that is only a state: a can is opened by using it, once), that is sipped from by yourself and
// fed to others in three seconds (in any stance unless it is a blow), poured from and into, and filled from a tank. What a sip tells and leaves behind is
// sipped() and, a moment after the transfer, On_Consume().
CAPABILITIES(/obj/item/reagent_containers/food/drinks)
	reagent_container(
		volume = nameof(volume),
		lid = TRUE,
		lid_visible = FALSE,
		starts_open = nameof(open_at_start),
		taps = list(/obj/structure/reagent_dispensers),
		rests_on = REAGENT_CONTAINER_CAN_BE_PLACED_INTO_DEFAULT,
		feed = TRUE,
		splash = FALSE,
		ingest_hostile = TRUE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this),
		transfer_min = nameof(min_transfer_amount),
		transfer_max = nameof(max_transfer_amount))
	op("open", in_hand(), when(cond_not(REAGENT_CONTAINER_LID_OPEN)), label("Open it"), then(PROC_REF(opened_in_hand)))
	extend("reagent_container.drink", then(PROC_REF(sipped)))
	extend("reagent_container.feed", begins(PROC_REF(feeding_begins)), then(PROC_REF(sipped)))
	rolls(nameof(cant_open), PROC_REF(roll_cant_open))

/// Used in hand while it is shut: it is opened (or found to have no ring pull).
/obj/item/reagent_containers/food/drinks/proc/opened_in_hand(datum/act/op/A)
	open(A.actor)
	return OP_OK

/// The one who feeds another is seen to begin.
/obj/item/reagent_containers/food/drinks/proc/feeding_begins(datum/act/A)
	var/datum/act/op/O = A
	other_feed_message_start(O.actor, O.target)
	return null

/// A sip: what the one drinking is told and hears, and (a moment after it has been taken) what it did to the drink.
/obj/item/reagent_containers/food/drinks/proc/sipped(datum/act/op/A)
	var/mob/living/eater = A.target
	var/mob/feeder = A.actor
	if(eater == feeder)
		self_feed_message(feeder)
	else
		other_feed_message_finish(feeder, eater)
	feed_sound(feeder)
	after(src, 1 TICK, TYPE_PROC_REF(/obj/item/reagent_containers/food/drinks, sipped_after), key = "sipped", with = list(eater, feeder, reagents.total_volume))
	return OP_OK

/// The sip has been taken: it counts if the drink lost anything.
/obj/item/reagent_containers/food/drinks/proc/sipped_after(mob/living/eater, mob/feeder, volume_before)
	if(QDELETED(src))
		return
	On_Consume(eater, feeder, reagents.total_volume != volume_before)

/obj/item/reagent_containers/food/drinks/proc/On_Consume(mob/living/eater, mob/feeder, changed = FALSE)
	if(SScontracts && eater && changed)
		contract_consumption_sequence++
		var/mob/living/living_feeder = feeder
		emit_contract_event(CONTRACT_EVENT_FOOD_CONSUMED, list(
			"department" = DEPARTMENT_CIVILIAN,
			"subject_id" = SScontracts.subject_identity(eater)?.id,
			"item_type" = type,
			"food_kind" = "drink",
			"sale_invoice_id" = economic_sale_invoice_id,
			"portion" = 1,
			"finished" = !reagents.total_volume,
			"detail" = "[eater] consumed a serving from [src].",
		), "drink-consumed:[REF(src)]:[contract_consumption_sequence]", src, living_feeder, eater)
	if(!feeder)
		feeder = eater

	if(food_inserted_micros && food_inserted_micros.len)
		for(var/mob/living/micro in food_inserted_micros)
			if(!can_food_vore(eater, micro))
				continue

			var/do_nom = FALSE

			if(!reagents.total_volume)
				do_nom = TRUE
			else
				var/nom_chance = (1 - (reagents.total_volume / volume))*100
				if(prob(nom_chance))
					do_nom = TRUE

			if(do_nom)
				eater.vore_selected.nom_atom(micro)
				own_take_member(src, nameof(food_inserted_micros), micro)

	if(!reagents.total_volume && changed)
		act_message(eater, src, MSG_SELF(span_notice("You finish drinking from %T%.")), MSG_OTHERS(span_notice("%U% finishes drinking from %T%.")))
		if(trash)
			feeder.drop_from_inventory(src)	//so icons update :[
			if(ispath(trash,/obj/item))
				var/obj/item/TrashItem = new trash(feeder)
				feeder.put_in_hands(TrashItem)
			else if(istype(trash,/obj/item))
				feeder.put_in_hands(trash)
			consume(src, feeder)
	return

/obj/item/reagent_containers/food/drinks/on_rag_wipe(obj/item/reagent_containers/glass/rag/R)
	wash(CLEAN_SCRUB)

/// Old attack_self. `special_pass` is set when a subtype (the bottle) calls it directly to force the open.
/obj/item/reagent_containers/food/drinks/proc/drinks_self(mob/user, obj/item/held, datum/interaction/interaction, special_pass)
	if(special_handling && !special_pass)
		return FALSE
	if(!is_open_container() && !(is_can && interaction.stance == I_HURT))
		open(user)
	return TRUE

/obj/item/reagent_containers/food/drinks/proc/open(mob/user)
	if(!cant_open)
		play_sfx(src, SFX_CANOPEN, volume = rand(10,50))
		GLOB.cans_opened_roundstat++
		to_chat(user, span_notice("You open [src] with an audible pop!"))
		cap_key_set(src, REAGENT_CONTAINER_LID_OPEN, TRUE)
	else
		to_chat(user, span_warning("...wait a second, this one doesn't have a ring pull. It's not a <b>can</b>, it's a <b>can't!</b>"))
		name = "\improper can't of [initial(name)]"	//don't update the name until they try to open it

/obj/item/reagent_containers/food/drinks/self_feed_message(mob/user)
	if(amount_per_transfer_from_this == volume)	//I wanted to use a switch, but switch statements can't use vars and the maximum volume of containers varies
		to_chat(user, span_notice("You knock back the entire [src] in one go!"))
	else if(amount_per_transfer_from_this == 1)
		to_chat(user, span_notice("You take a dainty little sip from \the [src]."))
	else if(amount_per_transfer_from_this <= 4)	//below the standard 5
		to_chat(user, span_notice("You take a modest sip from \the [src]."))
	else if(amount_per_transfer_from_this <= 10)	//the standard five to a bit more
		to_chat(user, span_notice("You swallow a gulp from \the [src]."))
	else if(amount_per_transfer_from_this <= 30)
		to_chat(user, span_notice("You take a long drag from \the [src]."))
	else if(amount_per_transfer_from_this <= 60)
		to_chat(user, span_notice("You chug from \the [src]!"))
	else	//default message as a fallback
		to_chat(user, span_notice("You swallow a gulp from \the [src]."))

/obj/item/reagent_containers/food/drinks/feed_sound(mob/user)
	play_sfx(src, SFX_ITEMS_DRINK, volume = rand(10, 50))

/obj/item/reagent_containers/food/drinks/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(cant_open)
			. += span_warning("It doesn't have a ring pull!")
		if(food_inserted_micros && food_inserted_micros.len)
			. += span_notice("It has [english_list(food_inserted_micros)] [!reagents?.total_volume ? "sitting" : "floating"] in it.")
		if(!reagents?.total_volume)
			. += span_notice("It is empty!")
		else if (reagents.total_volume <= volume * 0.25)
			. += span_notice("It is almost empty!")
		else if (reagents.total_volume <= volume * 0.66)
			. += span_notice("It is half full!")
		else if (reagents.total_volume <= volume * 0.90)
			. += span_notice("It is almost full!")
		else
			. += span_notice("It is full!")

////////////////////////////////////////////////////////////////////////////////
/// Drinks. END
////////////////////////////////////////////////////////////////////////////////

/obj/item/reagent_containers/food/drinks/golden_cup
	desc = "A golden cup"
	name = "golden cup"
	icon_state = "golden_cup"
	item_state = "" //nope :(
	w_class = ITEMSIZE_LARGE
	force = 14
	throwforce = 10
	amount_per_transfer_from_this = 20
	max_transfer_amount = null
	volume = 150

/obj/item/reagent_containers/food/drinks/golden_cup/on_reagent_change()
	..()

///////////////////////////////////////////////Drinks
//Notes by Darem: Drinks are simply containers that start preloaded. Unlike condiments, the contents can be ingested directly
//	rather then having to add it to something else first. They should only contain liquids. They have a default container size of 50.
//	Formatting is the same as food.

/obj/item/reagent_containers/food/drinks/milk
	name = "milk carton"
	desc = "It's milk. White and nutritious goodness!"
	description_fluff = "A product of NanoPastures. Who would have thought that cows would thrive in zero-G?"
	icon_state = "milk"
	item_state = "carton"
	center_of_mass_x = 16
	center_of_mass_y = 9
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

CAPABILITIES(/obj/item/reagent_containers/food/drinks/milk)
	configure(reagents(add = list(REAGENT_ID_MILK = 50)))

/obj/item/reagent_containers/food/drinks/soymilk
	name = "soymilk carton"
	desc = "It's soy milk. White and nutritious goodness!"
	description_fluff = "A product of NanoPastures. For those skeptical that cows can thrive in zero-G."
	icon_state = "soymilk"
	item_state = "carton"
	center_of_mass_x = 16
	center_of_mass_y = 9
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

CAPABILITIES(/obj/item/reagent_containers/food/drinks/soymilk)
	configure(reagents(add = list(REAGENT_ID_SOYMILK = 50)))

/obj/item/reagent_containers/food/drinks/smallmilk
	name = "small milk carton"
	desc = "It's milk. White and nutritious goodness!"
	description_fluff = "A product of NanoPastures. Who would have thought that cows would thrive in zero-G?"
	volume = 30
	icon_state = "mini-milk"
	item_state = "carton"
	center_of_mass_x = 16
	center_of_mass_y = 9
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

CAPABILITIES(/obj/item/reagent_containers/food/drinks/smallmilk)
	configure(reagents(add = list(REAGENT_ID_MILK = 30)))

/obj/item/reagent_containers/food/drinks/smallchocmilk
	name = "small chocolate milk carton"
	desc = "It's milk! This one is in delicious chocolate flavour."
	description_fluff = "A product of NanoPastures. Who would have thought that cows would thrive in zero-G?"
	volume = 30
	icon_state = "mini-milk_choco"
	item_state = "carton"
	center_of_mass_x = 16
	center_of_mass_y = 9
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

CAPABILITIES(/obj/item/reagent_containers/food/drinks/smallchocmilk)
	configure(reagents(add = list(REAGENT_ID_CHOCOLATEMILK = 30)))

/obj/item/reagent_containers/food/drinks/coffee
	name = "\improper Robust Coffee"
	desc = "Careful, the beverage you're about to enjoy is extremely hot."
	description_fluff = "Fresh coffee is almost unheard of outside of planets and stations where it is grown. Robust Coffee proudly advertises the six separate times it is freeze-dried during the production process of every cup of instant."
	icon_state = "coffee"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 15
	center_of_mass_y = 10
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/coffee)
	configure(reagents(add = list(REAGENT_ID_COFFEE = 30)))

/obj/item/reagent_containers/food/drinks/tea
	name = "cup of Duke Purple tea"
	desc = "An insult to Duke Purple is an insult to the Space Queen! Any proper gentleman will fight you, if you sully this tea."
	description_fluff = "Duke Purple is NanoPasture's proprietary strain of black tea, noted for its strong but otherwise completely non-distinctive flavour."
	icon_state = "chai_vended"
	item_state = "coffee"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 16
	center_of_mass_y = 14
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/tea)
	configure(reagents(add = list(REAGENT_ID_TEA = 30)))

/obj/item/reagent_containers/food/drinks/decaf_tea
	name = "cup of Count Mauve decaffeinated tea"
	desc = "Why should bedtime stop you from enjoying a nice cuppa?"
	description_fluff = "Count Mauve is a milder strain of NanoPasture's proprietary black tea, noted for its strong but otherwise completely non-distinctive flavour and total lack of caffeination."
	icon_state = "chai_vended"
	item_state = "coffee"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 16
	center_of_mass_y = 14
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/decaf_tea)
	configure(reagents(add = list(REAGENT_ID_TEADECAF = 30)))

/obj/item/reagent_containers/food/drinks/ice
	name = "cup of ice"
	desc = "Careful, cold ice, do not chew."
	icon_state = "ice"
	center_of_mass_x = 15
	center_of_mass_y = 10
CAPABILITIES(/obj/item/reagent_containers/food/drinks/ice)
	configure(reagents(add = list(REAGENT_ID_ICE = 30)))

/obj/item/reagent_containers/food/drinks/h_chocolate
	name = "cup of Counselor's Choice hot cocoa"
	desc = "Who needs character traits when you can enjoy a hot mug of cocoa?"
	description_fluff = "Counselor's Choice brand hot cocoa is made with a blend of hot water and non-dairy milk powder substitute, in a compromise destined to annoy all parties."
	icon_state = "coffee"
	item_state = "hot_choc"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 15
	center_of_mass_y = 13
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/h_chocolate)
	configure(reagents(add = list(REAGENT_ID_HOTCOCO = 30)))

/obj/item/reagent_containers/food/drinks/greentea
	name = "cup of green tea"
	desc = "Exceptionally traditional, delightfully subtle."
	description_fluff = "Tea remains an important tradition in many cultures originating on Earth. Among these, green tea is probably the most traditional of the bunch... Though the vending machines of the modern era hardly do it justice."
	icon_state = "greentea_vended"
	item_state = "coffee"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 16
	center_of_mass_y = 14
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/greentea)
	configure(reagents(add = list(REAGENT_ID_GREENTEA = 30)))

/obj/item/reagent_containers/food/drinks/chaitea
	name = "cup of chai tea"
	desc = "The name is redundant but the flavor is delicious!"
	description_fluff = "Chai Tea - tea blended with a spice mix of cinnamon and cloves - borders on a national drink on Kishar."
	icon_state = "chai_vended"
	item_state = "coffee"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 16
	center_of_mass_y = 14
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/chaitea)
	configure(reagents(add = list(REAGENT_ID_CHAITEA = 30)))

/obj/item/reagent_containers/food/drinks/decaf
	name = "cup of decaf coffee"
	desc = "Coffee with all the wake-up sucked out."
	description_fluff = "A trial run on two NanoTrasen stations in 2481 attempted to replace all vending machine coffee with decaf in order to combat an epidemic of caffeine addiction. After two days, three major industrial accidents and a death, the initiative was cancelled. Decaf is now thankfully optional."
	icon_state = "coffee"
	item_state = "coffee"
	trash = /obj/item/trash/coffee
	center_of_mass_x = 16
	center_of_mass_y = 14
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/decaf)
	configure(reagents(add = list(REAGENT_ID_DECAF = 30)))

/obj/item/reagent_containers/food/drinks/dry_ramen
	name = "Cup Ramen"
	desc = "Just add 10ml water and boil! A taste that reminds you of your school years."
	description_fluff = "Konohagakure Brand Ramen has been an instant meal staple for centuries. Cheap, quick and available in over two hundred varieties - though most taste like artifical chicken."
	icon_state = "ramen"
	trash = /obj/item/trash/ramen
	center_of_mass_x = 16
	center_of_mass_y = 11
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

CAPABILITIES(/obj/item/reagent_containers/food/drinks/dry_ramen)
	configure(reagents(add = list(REAGENT_ID_DRYRAMEN = 30)))

/obj/item/reagent_containers/food/drinks/sillycup
	name = "paper cup"
	desc = "A paper water cup."
	icon_state = "water_cup_e"
	max_transfer_amount = null
	volume = 10
	center_of_mass_x = 16
	center_of_mass_y = 12
	drop_sound = SFX_ITEMS_DROP_PAPERCUP
	pickup_sound = SFX_ITEMS_PICKUP_PAPERCUP

/obj/item/reagent_containers/food/drinks/sillycup/on_reagent_change()
	..()
	if(reagents.total_volume)
		icon_state = "water_cup"
	else
		icon_state = "water_cup_e"

CAPABILITIES(/obj/item/reagent_containers/food/drinks/sillycup)
	drag_onto(PROC_REF(drop_input))

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). An empty cup dropped on a cooler goes back in it.
/obj/item/reagent_containers/food/drinks/sillycup/proc/drop_input(datum/act/input/A)
	if(cup_return_with_actor(A.actor, A.over))
		return TRUE
	return INPUT_FALLTHROUGH

/// TRUE consumes the same empty-cup/cooler branch even when its range or capacity check refuses.
/obj/item/reagent_containers/food/drinks/sillycup/proc/cup_return_with_actor(mob/user, obj/over_object)
	if(!reagents.total_volume && istype(over_object, /obj/structure/reagent_dispensers/water_cooler))
		if(over_object.Adjacent(user))
			var/obj/structure/reagent_dispensers/water_cooler/W = over_object
			if(W.cupholder && W.cups < 10)
				var/message = span_notice("You put the [src] in the cup dispenser.")
				if(!consume(src, user))
					return TRUE
				W.cups++
				to_chat(user, message)
		return TRUE
	return FALSE

//////////////////////////drinkingglass and shaker//
//Note by Darem: This code handles the mixing of drinks. New drinks go in three places: In Chemistry-Reagents.dm (for the drink
//	itself), in Chemistry-Recipes.dm (for the reaction that changes the components into the drink), and here (for the drinking glass
//	icon states.

/obj/item/reagent_containers/food/drinks/shaker
	name = "shaker"
	desc = "A metal shaker to mix drinks in."
	icon_state = "shaker"
	amount_per_transfer_from_this = 10
	volume = 120
	center_of_mass_x = 17
	center_of_mass_y = 10

/obj/item/reagent_containers/food/drinks/shaker/on_reagent_change()
	..()

/obj/item/reagent_containers/food/drinks/teapot
	name = "teapot"
	desc = "An elegant teapot. It simply oozes class."
	icon_state = "teapot"
	item_state = "teapot"
	amount_per_transfer_from_this = 10
	volume = 120
	center_of_mass_x = 17
	center_of_mass_y = 7

/obj/item/reagent_containers/food/drinks/teapot/on_reagent_change()
	..()

/obj/item/reagent_containers/food/drinks/flask
	name = "\improper " + JOB_SITE_MANAGER + "'s flask"
	desc = "A metal flask belonging to the " + JOB_SITE_MANAGER

	icon_state = "flask"
	volume = 60
	center_of_mass_x = 17
	center_of_mass_y = 7

/obj/item/reagent_containers/food/drinks/flask/on_reagent_change()
	..()

/obj/item/reagent_containers/food/drinks/flask/shiny
	name = "shiny flask"
	desc = "A shiny metal flask. It appears to have a Greek symbol inscribed on it."
	icon_state = "shinyflask"

/obj/item/reagent_containers/food/drinks/flask/lithium
	name = "lithium flask"
	desc = "A flask with a Lithium Atom symbol on it."
	icon_state = "lithiumflask"

/obj/item/reagent_containers/food/drinks/flask/detflask
	name = "\improper " + JOB_DETECTIVE + "'s flask"
	desc = "A metal flask with a leather band and golden badge belonging to the detective."
	icon_state = "detflask"
	volume = 60
	center_of_mass_x = 17
	center_of_mass_y = 8

/obj/item/reagent_containers/food/drinks/flask/barflask
	name = "flask"
	desc = "For those who can't be bothered to hang out at the bar to drink."
	icon_state = "barflask"
	volume = 60
	center_of_mass_x = 17
	center_of_mass_y = 7

/obj/item/reagent_containers/food/drinks/flask/vacuumflask
	name = "vacuum flask"
	desc = "Keeping your drinks at the perfect temperature since 1892."
	icon_state = "vacuumflask"
	volume = 60
	center_of_mass_x = 15
	center_of_mass_y = 4
