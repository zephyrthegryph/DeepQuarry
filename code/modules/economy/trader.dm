/obj/trader
	name = "trader"
	desc = "Some kind of trade thing."
	icon = 'icons/obj/vending.dmi'
	icon_state = "generic"
	anchored = TRUE
	density = TRUE
	unacidable = TRUE
	var/accepts = "coin"				// "coin" - "money" - "item" - determines the 'kind' of thing the machine will accept
	var/accepted_itemtype				//only for use with "item" mode - if set to a type path, it will count anything with that type path
	var/accepted_item_worth = 1			//only for use with "item" mode - when counted, things of the appropriate type will add this much to the banked funds
	var/list/bank					//Anything accepted by "money" or "item" mode will be marked down here
	var/coinbalance = 0					//only for use with coin mode - when you put a curious coin in, it adds the coins value to this number
	var/list/start_products	//Type paths entered here will spawn inside the trader and add themselves to the products list.
	// ALLOW(instance_list): d: the trader's live stock
	var/list/products = list()			//Anything in this list will be listed for sale
	var/list/prices			//Enter a type path with an associated number, and if the trader tries to sell something of that type, it will expect the number as the cost for that product
	var/list/multiple			//Enter a type path with an associated number, and the trader will have however many of that type to sell as the number you entered
	var/trading = FALSE					//'Busy' - Only one person can trade at a time.
	var/welcome_msg = "This machine accepts"	//The first part of the welcome message
	var/welcome_accepts_name = "curious coins"	//The name of the kind of thing the trader expects, automatically set except on "item" mode, where if you enter a value it will not change it.
	var/welcome_msg_finish = ". Would you like to browse the wares?"	//The final part of the welcome message.
	var/list/interact_sound	//The sounds that may play when you click it. It will pick one at random from this list. It only thinks about this if there's anything in the list.
	var/sound_cooldown = 0				//The sound can only play this often in deciseconds. Use '10 SECONDS' format to make it easier to read
	var/sound_lastplayed = 0			//Automatically set when the sound is played.
	var/pick_inventory = FALSE			//If true, when initialized the trader will randomly pick things from its start products list to set up
	var/pick_inventory_quantity = 0		//This is how many things will be picked if pick_inventory is TRUE
	var/move_trader = FALSE

/obj/trader/Initialize(mapload)
	. = ..()
	if(pick_inventory)
		while(pick_inventory_quantity > 0)
			var/t = pickweight(start_products || list())
			var/i = new t(src)
			LAZYREMOVE(start_products, t)
			products += i
			pick_inventory_quantity --
	else
		for(var/item in start_products)
			var/obj/p = new item(src)
			products += p
			LAZYREMOVE(start_products, item)
	if(move_trader)
		move_trader()

DECLARE_INTERACTIONS(/obj/trader, 	INTERACT_HAND("Trade", PROC_REF(interaction_trader_hand)), 	INTERACT_ITEM(null, PROC_REF(interaction_trader_item)))

/// Old attack_hand: start a trade with one customer at a time.
/obj/trader/proc/interaction_trader_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(trading)
		to_chat(user, span_notice("\The [src] is busy with someone else at the moment..."))
		return TRUE
	if(!products.len)
		to_chat(user, span_notice("\The [src] hasn't got anything to sell."))
		return TRUE
	trading = TRUE
	switch(accepts)
		if("coin")
			welcome_accepts_name = "curious coins"
		if("money")
			welcome_accepts_name = "Thalers"
		if("item")
			if(welcome_accepts_name == "curious coins")
				welcome_accepts_name = "a kind of item"
	// One customer at a time: any way the questions end frees the trader.
	om_flow_start(/datum/om/flow/trader_trade, user, src)
	return TRUE

/obj/trader/proc/trade_price(obj/item)
	return LAZYACCESS(prices, item.type) || 0

/// A customer (actor) trading with a trader (target): whether to trade, which product, a price
/// confirmation, then the change. The customer stays next to the trader throughout, and any way
/// the questions end frees the trader.
/datum/om/flow/trader_trade
	name = "trader trade"
	requires = PROMPT_ADJACENT
	var/obj/product
	/// The step waiting for an answer, for ended()'s messages.
	var/stage

/datum/om/flow/trader_trade/start()
	var/obj/trader/trader = target
	stage = "ask"
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(asked), buttons = TRUE, title = "[trader]", message = "[trader.welcome_msg][trader.welcome_accepts_name][trader.welcome_msg_finish]", choices = list("Yes","No","Return banked funds"), timeout = 10 SECONDS)

/datum/om/flow/trader_trade/ended(reason)
	if(stage == "change") // the trade is done; the trader is already free
		return
	var/obj/trader/trader = target
	if(trader)
		trader.trading = FALSE
	if(stage == "confirm" && reason == "declined")
		to_chat(actor, span_notice("You decided not to."))
	else if(reason != "cancelled" && reason != "declined" && reason != "gone")
		to_chat(actor, span_notice("You aren't close enough."))

/datum/om/flow/trader_trade/proc/asked(datum/om/prompt/choice/ask)
	var/obj/trader/trader = target
	if(ask.choice == "Return banked funds")
		trader.return_funds()
	if(ask.choice != "Yes")
		trader.trading = FALSE
		return
	if(length(trader.interact_sound) > 0)
		if((world.time - trader.sound_lastplayed) > trader.sound_cooldown)
			var/sound = DEFAULTPICK(trader.interact_sound, null)
			playsound(trader, sound, 25, FALSE, ignore_walls = FALSE)
			trader.sound_lastplayed = world.time
	stage = "product"
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(product_picked), title = "Trader", message = "What would you like? You have [trader.get_value(trader.accepts)] banked with this trader.", choices = trader.products, timeout = 30 SECONDS)

/datum/om/flow/trader_trade/proc/product_picked(datum/om/prompt/choice/ask)
	var/obj/trader/trader = target
	product = ask.choice
	if(!istype(product) || !(product in trader.products))
		to_chat(actor, span_notice("You decided not to get anything."))
		trader.trading = FALSE
		return
	var/p = trader.trade_price(product)
	if(p <= 0)
		trade()
		return
	stage = "confirm"
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(trade), title = "Confirm", message = "Are you sure? This costs [p].")

/datum/om/flow/trader_trade/proc/trade()
	var/obj/trader/trader = target
	var/mob/user = actor
	trader.trading = FALSE
	var/obj/input = product
	if(!istype(input) || !(input in trader.products))
		return
	var/t = input.type
	var/p = trader.trade_price(input)
	// The bank can have been drained while they chose.
	if(p > 0 && trader.get_value(trader.accepts) < p)
		to_chat(user, span_warning("You haven't provided enough funds!"))
		return
	if(t in trader.multiple)
		trader.multiple[t] -= 1
		var/temp = input
		input = new t(get_turf(user))
		if(LAZYACCESS(trader.multiple, t) <= 0)
			for(var/obj/d in trader.products)
				if(istype(d, temp))
					d.forceMove(get_turf(trader.loc))
					qdel(d)
	input.forceMove(get_turf(user))
	user.put_in_hands(input)
	trader.products -= input
	trader.deduct_value(p)
	product = null
	stage = "change"
	om_ask(user, /datum/om/prompt/choice, PROC_REF(change_answered), buttons = TRUE, title = "[trader]", message = "Would you like your change back, or would you like it to remain banked for later use? (Anyone can use banked funds)", choices = list("Keep it banked","I want my change"), timeout = 10 SECONDS)

/datum/om/flow/trader_trade/proc/change_answered(datum/om/prompt/choice/ask)
	var/obj/trader/trader = target
	if(ask.choice == "I want my change")
		trader.return_funds()
	else
		to_chat(actor, span_notice("You decided leave your change banked."))

/// Old attackby (ran ..() first): bank coins, cash or items; the base item handling still follows.
/obj/trader/proc/interaction_trader_item(mob/user, obj/item/O, datum/interaction/interaction)
	switch(accepts)
		if("coin")
			if(istype(O, /obj/item/aliencoin))
				var/obj/item/aliencoin/a = O
				coinbalance += a.value
				visible_message(span_notice("\The [src] accepts \the [user]'s [O]."))
				consume(a, user)
		if("money")
			if(istype(O, /obj/item/spacecash))
				var/obj/item/spacecash/w = O
				for(var/obj/item/spacecash/c in bank)
					var/loadsamoney = w.worth
					consume(w, user)
					c.worth += loadsamoney
					c.update_icon()
					loadsamoney = null
					visible_message(span_notice("\The [src] accepts \the [user]'s [O]."))
					return INTERACTION_HANDLED_PASS
				user.drop_item()
				w.forceMove(src.contents)
				LAZYADD(bank, w)
				visible_message(span_notice("\The [src] accepts \the [user]'s [w]."))
		if("item")
			if(istype(O, /obj))
				user.drop_item()
				O.forceMove(src.contents)
				LAZYADD(bank, O)
				visible_message(span_notice("\The [src] accepts \the [user]'s [O]."))
	return INTERACTION_HANDLED_PASS

/obj/trader/proc/get_value(kind)
	var/value = 0
	switch(kind)
		if("coin")
			value = coinbalance
		if("money")
			for(var/obj/c in bank)
				if(istype(c, /obj/item/spacecash))
					var/obj/item/spacecash/a = c
					value += a.worth
				else
					c.forceMove(get_turf(src))
					visible_message(span_warning("\The [src] drops the worthless [c]..."))
		if("item")
			for(var/obj/c in bank)
				if(istype(c, accepted_itemtype))
					value += accepted_item_worth
				else
					c.forceMove(get_turf(src))
					visible_message(span_warning("\The [src] drops the worthless [c]..."))
	return value

/obj/trader/proc/deduct_value(amount)
	switch(accepts)
		if("coin")
			coinbalance = max(0, coinbalance - amount)
		if("money")
			for(var/obj/c in bank)
				if(istype(c, /obj/item/spacecash))
					var/obj/item/spacecash/a = c
					a.worth -= amount
					a.update_icon()
					if(a.worth <= 0)
						LAZYREMOVE(bank, a)
						qdel(a)
		if("item")
			// Guard against a non-positive item worth, which would never decrement v
			// and spin forever (DoS). Also stop if the bank runs out of matching items.
			if(accepted_item_worth <= 0)
				return
			var/v = amount
			while(v > 0)
				var/removed_any = FALSE
				for(var/obj/c in bank)
					if(istype(c, accepted_itemtype))
						c.forceMove(get_turf(loc))
						qdel(c)
						v -= accepted_item_worth
						removed_any = TRUE
						if(v <= 0)
							break
				if(!removed_any)
					break

/obj/trader/proc/return_funds()
	var/u_get_refund = FALSE
	switch(accepts)
		if("coin")
			if(coinbalance)
				u_get_refund = TRUE
			while(coinbalance > 0)
				if(coinbalance >= 20)
					new /obj/item/aliencoin/phoron(get_turf(loc))
					coinbalance -= 20
				else if(coinbalance >= 10)
					new /obj/item/aliencoin/gold(get_turf(loc))
					coinbalance -= 10
				else if(coinbalance >= 5)
					new /obj/item/aliencoin/silver(get_turf(loc))
					coinbalance -= 5
				else
					new /obj/item/aliencoin/basic(get_turf(loc))
					coinbalance --
		if("money")
			for(var/obj/c in bank)
				u_get_refund = TRUE
				c.forceMove(get_turf(loc))
				LAZYREMOVE(bank, c)
		if("item")
			for(var/obj/c in bank)
				u_get_refund = TRUE
				c.forceMove(get_turf(loc))
				LAZYREMOVE(bank, c)
	if(u_get_refund)
		visible_message(span_notice("\The [src] drops the banked [welcome_accepts_name]."))
	else
		visible_message(span_notice("\The [src] doesn't have anything banked for you."))

/obj/trader/proc/move_trader()
	var/list/pt = list()
	for(var/obj/move_trader_landmark/t in world)
		if(t.trader_type == type)
			pt += t
	if(pt.len > 0)
		var/obj/dt = pick(pt)
		forceMove(get_turf(dt))
		dir = dt.dir
		log_admin("[src] has been placed at [loc], [x],[y],[z]")
	else
		log_and_message_admins("[src] tried to move itself but its target pick list was empty, so it was not moved. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)", null)

/obj/move_trader_landmark //You need to place the trader somewhere in the world and enable the 'move_trader' var. When the trader initializes, it will make a list of these landmarks and then move itself.
	name = "trader mover"
	desc = "A trader can be moved to here!"
	icon = 'icons/obj/landmark_vr.dmi'
	icon_state = "blue-x"
	invisibility = INVISIBILITY_ABSTRACT
	mouse_opacity = 0
	density = 0
	anchored = 1
	var/trader_type			//The type path for the trader you want to be able to land here.

/obj/trader/capture_crystal
	name = "curious trader"
	desc = "A tall metal cylander on a squarish base. It looks almost like a vending machine, but there's nowhere to swipe your card. It appears to accept some kind of triangle currency..."
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "cap_crys"
	interact_sound = list('sound/music/capture_crystal_1.ogg', 'sound/music/capture_crystal_2.ogg')
	sound_cooldown = 1 MINUTE
	start_products = list(
		/obj/item/capture_crystal/basic,
		/obj/item/capture_crystal/great,
		/obj/item/capture_crystal/ultra,
		/obj/item/capture_crystal/master,
		/obj/item/capture_crystal/random
	)
	prices = list(
		/obj/item/capture_crystal/basic = 5,
		/obj/item/capture_crystal/great = 10,
		/obj/item/capture_crystal/ultra = 15,
		/obj/item/capture_crystal/master = 100,
		/obj/item/capture_crystal/random = 10
	)
	multiple = list(
		/obj/item/capture_crystal/basic = 10,
		/obj/item/capture_crystal/great = 5,
		/obj/item/capture_crystal/ultra = 2)

/obj/trader/capture_crystal/cash
	accepts = "money"
	prices = list(
		/obj/item/capture_crystal/basic = 500,
		/obj/item/capture_crystal/great = 1000,
		/obj/item/capture_crystal/ultra = 1500,
		/obj/item/capture_crystal/master = 10000,
		/obj/item/capture_crystal/random = 1000
	)

/obj/trader/general
	name = "trader"
	desc = "A large canine woman. She might have a few things to sell."
	icon = 'icons/obj/traderx64.dmi'
	icon_state = "trader1"
	pixel_x = -16
	layer = ABOVE_MOB_LAYER
	plane = ABOVE_MOB_PLANE
	welcome_msg = "Hey there, welcome~ If you've got any"
	welcome_msg_finish = " then I may have something for you. Would you like to browse what I've got?"
	pick_inventory = TRUE
	pick_inventory_quantity = 5
	start_products = list(
		/obj/item/capture_crystal/basic = 100,
		/obj/item/capture_crystal/random = 50,
		/obj/item/perfect_tele = 10,
		/obj/item/chameleon = 25,
		/obj/item/gun/energy/sizegun = 25,
		/obj/item/slow_sizegun = 25,
		/obj/item/clothing/accessory/collar/shock/bluespace = 25,
		/obj/item/implant/sizecontrol = 25,
		/obj/item/clothing/under/hyperfiber/bluespace = 25,
		/obj/item/nif/authentic = 1,
		/obj/item/toy/bosunwhistle = 50,
		/obj/item/cell/infinite = 10,
		/obj/item/cell/void = 15,
		/obj/item/cell/device/weapon/recharge/alien = 10,
		/obj/item/reagent_containers/food/snacks/jellyfishcore = 50,
		/obj/item/denecrotizer = 10,
		/obj/item/clothing/shoes/boots/speed = 15,
		/obj/item/bluespace_harpoon = 20,
		/obj/item/telecube/randomized = 5,
		/obj/item/bodysnatcher = 20,
		/obj/item/survivalcapsule = 25,
		/obj/item/survivalcapsule/luxury = 20,
		/obj/item/survivalcapsule/luxurybar = 15,
		/obj/item/survivalcapsule/luxurycabin = 15,
		/obj/item/survivalcapsule/popcabin = 20,
		/obj/item/perfect_tele/frontier/unknown/one = 1
		)
	prices = list(
		/obj/item/capture_crystal/basic = 6,
		/obj/item/capture_crystal/random = 15,
		/obj/item/perfect_tele = 20,
		/obj/item/chameleon = 20,
		/obj/item/gun/energy/sizegun = 10,
		/obj/item/slow_sizegun = 10,
		/obj/item/clothing/accessory/collar/shock/bluespace = 10,
		/obj/item/implant/sizecontrol = 10,
		/obj/item/clothing/under/hyperfiber/bluespace = 10,
		/obj/item/nif/authentic = 100,
		/obj/item/toy/bosunwhistle = 1,
		/obj/item/cell/infinite = 20,
		/obj/item/cell/void = 20,
		/obj/item/cell/device/weapon/recharge/alien = 20,
		/obj/item/reagent_containers/food/snacks/jellyfishcore = 3,
		/obj/item/denecrotizer = 20,
		/obj/item/clothing/shoes/boots/speed = 20,
		/obj/item/bluespace_harpoon = 20,
		/obj/item/telecube/randomized = 50,
		/obj/item/bodysnatcher = 20,
		/obj/item/survivalcapsule = 10,
		/obj/item/survivalcapsule/luxury = 20,
		/obj/item/survivalcapsule/luxurybar = 25,
		/obj/item/survivalcapsule/popcabin = 10,
		/obj/item/perfect_tele/frontier/unknown/one = 30
		)
	multiple = list(
		/obj/item/capture_crystal/basic = 10,
		/obj/item/capture_crystal/random = 2,
		/obj/item/gun/energy/sizegun = 2,
		/obj/item/slow_sizegun = 2,
		/obj/item/clothing/accessory/collar/shock/bluespace = 2,
		/obj/item/implant/sizecontrol = 2,
		/obj/item/clothing/under/hyperfiber/bluespace = 2,
		/obj/item/reagent_containers/food/snacks/jellyfishcore = 10
		)

// The stock the trader spawned into itself at Initialize().
DECLARE_REF(/obj/trader, "products", OWNED_LIST, null)
