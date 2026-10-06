/obj/machinery/computer/stockexchange
	name = "stock exchange computer"
	desc = "A console that connects to the galactic stock market. Stocks trading involves substantial risk of loss and is not suitable for every cargo technician."
	icon = 'icons/obj/computer.dmi'
	icon_state = "stockmarket"
	icon_screen = "stocks"
	icon_keyboard = "stockmarket_key"
	circuit = /obj/item/circuitboard/stockexchange
	var/logged_in = "Cargo Department"
	var/vmode = 1

	var/screen = "stocks"
	var/tmp/datum/stock/current_stock

	light_color = LIGHT_COLOR_GREEN

/obj/machinery/computer/stockexchange/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/stockexchange_attackby,
		/datum/interaction/machine_hand/stockexchange_use,
	)
	..()

/// Approximation: the old attackby unconditionally called ..() then always refreshed the UIs.
/// The ancestor call can't be replayed from here, so this declines (FALSE) to let the entry
/// fall through to the base attackby; the UI refresh now happens before that fallback rather
/// than after, an order approximation - see report.
/datum/interaction/machine_item/stockexchange_attackby
	id = "stockexchange_attackby"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/computer/stockexchange/proc/interaction_attackby

/obj/machinery/computer/stockexchange/proc/interaction_attackby(mob/user, obj/item/W, datum/interaction/interaction)
	SStgui.update_uis(src)
	return FALSE

/datum/interaction/machine_hand/stockexchange_use
	id = "stockexchange_use"
	name = "Use"
	effect = /obj/machinery/computer/stockexchange/proc/interaction_use

/obj/machinery/computer/stockexchange/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/stockexchange/proc/balance()
	if (!logged_in)
		return 0
	return SSsupply.budget_balance()

///// MAIN TGUI SCREEN /////

/obj/machinery/computer/stockexchange/proc/ui_act_logout(datum/act/op/A)
	add_fingerprint(A.actor)
	logged_in = null

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_buy(datum/act/op/A, share)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	if(!isnull(share) && !(share in ui_source_glob_stockexchange_stocks()))
		return FALSE
	if(isnull(share))
		return FALSE
	var/datum/stock/S = share
	if (S)
		buy_some_shares(S, user)

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_sell(datum/act/op/A, share)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	if(!isnull(share) && !(share in ui_source_glob_stockexchange_stocks()))
		return FALSE
	if(isnull(share))
		return FALSE
	var/datum/stock/S = share
	if (S)
		sell_some_shares(S, user)

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_check(datum/act/op/A)
	add_fingerprint(A.actor)
	screen = "logs"

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_archive(datum/act/op/A, share)
	add_fingerprint(A.actor)
	var/datum/stock/S = share
	if(S)
		rel_set(src, nameof(/obj/machinery/computer/stockexchange::current_stock), S)
		screen = "archive"

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_history(datum/act/op/A, share)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	if(!isnull(share) && !(share in ui_source_glob_stockexchange_stocks()))
		return FALSE
	if(isnull(share))
		return FALSE
	var/datum/stock/S = share
	if (S)
		S.displayValues(user)

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_backbutton(datum/act/op/A)
	add_fingerprint(A.actor)
	rel_clear(src, nameof(/obj/machinery/computer/stockexchange::current_stock))
	screen = "stocks"

/obj/machinery/computer/stockexchange/proc/ui_act_stocks_cycle_view(datum/act/op/A)
	add_fingerprint(A.actor)
	vmode++
	if (vmode > 1)
		vmode = 0

/// The list the UI_ARG_REF rows resolve refs in.
/obj/machinery/computer/stockexchange/proc/ui_source_glob_stockexchange_stocks()
	return GLOB.stockExchange.stocks

/obj/machinery/computer/stockexchange/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["screen"] = screen
	var/list/merged_1 = ui_data_obj_machinery_computer_stockexchange(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/computer/stockexchange's window data.
/obj/machinery/computer/stockexchange/proc/ui_data_obj_machinery_computer_stockexchange(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["stationName"] = using_map.station_name
	data["balance"] = balance()

	switch(screen)
		// Main Stocks List
		if("stocks")
			if (vmode)
				data["viewMode"] = "Full"
			else
				data["viewMode"] = "Compressed"

			for (var/datum/stock/S in GLOB.stockExchange.stocks)
				if (!S.last_read)
					S.last_read = list()
				if (!(logged_in in S.last_read))
					S.last_read[logged_in] = 0

			data["stocks"] = list()

			if (vmode)
				for (var/datum/stock/S in GLOB.stockExchange.stocks)
					var/mystocks = 0
					if (logged_in && (logged_in in S.shareholders))
						mystocks = LAZYACCESS(S.shareholders, logged_in)

					var/value = 0
					if (!S.bankrupt)
						value = S.current_value

					data["stocks"] += list(list(
						"REF" = REF(S),
						"valueChange" = S.disp_value_change, // > 0 is +, < 0 is -, else its =
						"bankrupt" = S.bankrupt,
						"ID" = S.short_name,
						"Name" = S.name,
						"Value" = value,
						"Owned" = mystocks,
						"Avail" = S.available_shares,
						"Products" = S.products,
					))

					var/news = 0
					if (logged_in)
						var/lrt = LAZYACCESS(S.last_read, logged_in)
						for (var/datum/article/A in S.articles)
							if (A.ticks > lrt)
								news = 1
								break
						if (!news)
							for (var/datum/stockEvent/E in S.events)
								if (E.last_change > lrt && !E.hidden)
									news = 1
			else
				for (var/datum/stock/S in GLOB.stockExchange.stocks)
					var/mystocks = 0
					if (logged_in && (logged_in in S.shareholders))
						mystocks = LAZYACCESS(S.shareholders, logged_in)

					var/unification = 0
					if (S.last_unification)
						unification = DisplayTimeText(world.time - S.last_unification)

					data["stocks"] += list(list(
						"REF" = REF(S),
						"bankrupt" = S.bankrupt,
						"ID" = S.short_name,
						"Name" = S.name,
						"Owned" = mystocks,
						"Avail" = S.available_shares,
						"Unification" = unification,
						"Products" = S.products,
					))

					var/news = 0
					if (logged_in)
						var/lrt = LAZYACCESS(S.last_read, logged_in)
						for (var/datum/article/A in S.articles)
							if (A.ticks > lrt)
								news = 1
								break
						if (!news)
							for (var/datum/stockEvent/E in S.events)
								if (E.last_change > lrt && !E.hidden)
									news = 1
									break

		// Stocks Logs Screen
		if("logs")
			data["logs"] = list()

			for(var/D in GLOB.stockExchange.logs)
				var/datum/stock_log/L = D

				if (istype(L, /datum/stock_log/buy))
					data["logs"] += list(list(
							"type" = "transaction_bought",
							"time" = L.time,
							"user_name" = L.user_name,
							"stocks" = L.stocks,
							"shareprice" = L.shareprice,
							"money" = L.money,
							"company_name" = L.company_name,
					))
				else if (istype(L, /datum/stock_log/sell))
					data["logs"] += list(list(
							"type" = "transaction_sold",
							"time" = L.time,
							"user_name" = L.user_name,
							"stocks" = L.stocks,
							"shareprice" = L.shareprice,
							"money" = L.money,
							"company_name" = L.company_name,
					))
				else if (istype(L, /datum/stock_log/borrow))
					data["logs"] += list(list(
							"type" = "borrow",
							"time" = L.time,
							"user_name" = L.user_name,
							"stocks" = L.stocks,
							"money" = L.money,
							"company_name" = L.company_name,
					))

		// Archive Screen
		if("archive")
			data["name"] = current_stock().name
			data["events"] = list()
			data["articles"] = list()

			for (var/datum/stockEvent/E in current_stock().events)
				if (E.hidden)
					continue
				data["events"] += list(list(
						"current_title" = E.current_title,
						"current_desc" = E.current_desc,
				))

			var/list/stock_articles = current_stock().articles
			for (var/article_index = length(stock_articles), article_index >= 1, article_index--) // articles are appended oldest first; show newest first
				var/datum/article/A = stock_articles[article_index]
				data["articles"] += list(list(
						"headline" = A.headline,
						"subtitle" = A.subtitle,
						"article" = A.article,
						"author" = A.author,
						"spacetime" = A.spacetime,
						"outlet" = A.outlet,
				))

		// Stock Graph
		if("graph")
			data["name"] = current_stock().name
			data["maxValue"] = 100
			data["values"] = current_stock().values

	return data

CAPABILITIES(/obj/machinery/computer/stockexchange)
	interface("StockExchange")
	without("ui_open")
	op("logout", ui_act("logout"), then(PROC_REF(ui_act_logout)))
	op("stocks_buy", ui_act("stocks_buy", arg("share", schema_ref(/datum/stock))), then(PROC_REF(ui_act_stocks_buy)))
	op("stocks_sell", ui_act("stocks_sell", arg("share", schema_ref(/datum/stock))), then(PROC_REF(ui_act_stocks_sell)))
	op("stocks_check", ui_act("stocks_check"), then(PROC_REF(ui_act_stocks_check)))
	op("stocks_archive", ui_act("stocks_archive", arg("share", schema_ref(/datum/stock))), then(PROC_REF(ui_act_stocks_archive)))
	op("stocks_history", ui_act("stocks_history", arg("share", schema_ref(/datum/stock))), then(PROC_REF(ui_act_stocks_history)))
	op("stocks_backbutton", ui_act("stocks_backbutton"), then(PROC_REF(ui_act_stocks_backbutton)))
	op("stocks_cycle_view", ui_act("stocks_cycle_view"), then(PROC_REF(ui_act_stocks_cycle_view)))

///// PROCS /////

/obj/machinery/computer/stockexchange/proc/sell_some_shares(datum/stock/S, mob/user)
	if (!user || !S)
		return
	var/li = logged_in
	if (!li)
		to_chat(user, span_danger("No active account on the console!"))
		return
	SSsupply.budget_balance()
	var/avail = LAZYACCESS(S.shareholders, logged_in)
	if (!avail)
		to_chat(user, span_danger("This account does not own any shares of [S.name]!"))
		return
	var/price = S.current_value
	open_request(S, /datum/prompt/number/stock_sell, TYPE_PROC_REF(/datum/stock, sell_shares_answered), answerer = user, subject = src, question = "How many shares? \n(Have: [avail], unit price: [price])", title = "Sell shares in [S.name]", default = 0)

/obj/machinery/computer/stockexchange/proc/sell_shares_apply(datum/stock/S, mob/user, amount)
	var/amt = min(round(amount), LAZYACCESS(S.shareholders, logged_in))
	var/total = amt * S.current_value
	if (!S.sellShares(logged_in, amt))
		to_chat(user, span_danger("Could not complete transaction."))
		return
	to_chat(user, span_notice("Sold [amt] shares of [S.name] at [S.current_value] a share for [total] credits."))
	GLOB.stockExchange.add_log(/datum/stock_log/sell, user.name, S.name, amt, S.current_value, total)

/obj/machinery/computer/stockexchange/proc/buy_some_shares(datum/stock/S, mob/user)
	if (!user || !S)
		return
	var/li = logged_in
	if (!li)
		to_chat(user, span_danger("No active account on the console!"))
		return
	var/b = balance()
	if (!isnum(b))
		to_chat(user, span_danger("No active account on the console!"))
		return
	var/avail = S.available_shares
	var/price = S.current_value
	var/canbuy = round(b / price)
	open_request(S, /datum/prompt/number/stock_buy, TYPE_PROC_REF(/datum/stock, buy_shares_answered), answerer = user, subject = src, question = "How many shares? \n(Available: [avail], unit price: [price], can buy: [canbuy])", title = "Buy shares in [S.name]", default = 0)

/obj/machinery/computer/stockexchange/proc/buy_shares_apply(datum/stock/S, mob/user, amount)
	var/amt = min(round(amount), S.available_shares, round(balance() / S.current_value))
	if (!S.buyShares(logged_in, amt))
		to_chat(user, span_danger("Could not complete transaction."))
		return

	var/total = amt * S.current_value
	to_chat(user, span_notice("Bought [amt] shares of [S.name] at [S.current_value] a share for [total] credits."))
	GLOB.stockExchange.add_log(/datum/stock_log/buy, user.name, S.name, amt, S.current_value,  total)

/obj/machinery/computer/stockexchange/proc/do_borrowing_deal(datum/borrow/B, mob/user)
	if (B.stock().borrow(B, logged_in))
		to_chat(user, span_notice("You successfully borrowed [B.share_amount] shares. Deposit: [B.deposit]."))
		GLOB.stockExchange.add_log(/datum/stock_log/borrow, user.name, B.stock().name, B.share_amount, B.deposit)
	else
		to_chat(user, span_danger("Could not complete transaction. Check your account balance."))

/// the current_stock this refers to (a relation view: null once it is deleted).
/obj/machinery/computer/stockexchange/proc/current_stock() as /datum/stock
	return current_stock

/datum/prompt/number/stock_sell
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/stock_sell/recheck_extra()
	if(QDELETED(owner) || QDELETED(subject) || QDELETED(answerer))
		return "gone"
	var/datum/stock/S = owner
	var/obj/machinery/computer/stockexchange/console = subject
	if(!console.logged_in)
		return "No active account on the console!"
	if(!LAZYACCESS(S.shareholders, console.logged_in))
		return "This account does not own any shares of [S.name]!"
	if(isnull(value))
		return null
	var/amt = min(round(value), LAZYACCESS(S.shareholders, console.logged_in))
	if((!(answerer in range(1, console)) && iscarbon(answerer)) || !amt)
		return "silent"
	if(!isnum(SSsupply.budget_balance()))
		return "No active account on the console!"

/datum/stock/proc/sell_shares_answered(datum/act/request/A)
	var/datum/prompt/number/stock_sell/request = A.request
	var/obj/machinery/computer/stockexchange/console = request.subject
	if(QDELETED(console) || QDELETED(request.answerer) || isnull(request.value))
		return
	if(A.answer)
		console.sell_shares_apply(src, request.answerer, request.value)
	else if(request.last_error && !(request.last_error in list("gone", "silent")))
		to_chat(request.answerer, span_danger(request.last_error))
	SStgui.update_uis(console)

/datum/prompt/number/stock_buy
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/stock_buy/recheck_extra()
	if(QDELETED(owner) || QDELETED(subject) || QDELETED(answerer))
		return "gone"
	var/datum/stock/S = owner
	var/obj/machinery/computer/stockexchange/console = subject
	if(!console.logged_in)
		return "No active account on the console!"
	if(!isnum(console.balance()))
		return "No active account on the console!"
	if(isnull(value))
		return null
	if(!(answerer in range(1, console)) && iscarbon(answerer))
		return "silent"
	if(!isnum(console.balance()))
		return "No active account on the console!"
	if(!min(round(value), S.available_shares, round(console.balance() / S.current_value)))
		return "silent"

/datum/stock/proc/buy_shares_answered(datum/act/request/A)
	var/datum/prompt/number/stock_buy/request = A.request
	var/obj/machinery/computer/stockexchange/console = request.subject
	if(QDELETED(console) || QDELETED(request.answerer) || isnull(request.value))
		return
	if(A.answer)
		console.buy_shares_apply(src, request.answerer, request.value)
	else if(request.last_error && !(request.last_error in list("gone", "silent")))
		to_chat(request.answerer, span_danger(request.last_error))
	SStgui.update_uis(console)
