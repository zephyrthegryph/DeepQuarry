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

/obj/machinery/computer/stockexchange/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/stockexchange, "logout", ui_act_logout)
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_logout)
	logged_in = null

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_buy", ui_act_stocks_buy, UI_ARG_REF("share", "proc:ui_source_glob_stockexchange_stocks", /datum/stock))
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_buy)
	var/datum/stock/S = params["share"]
	if (S)
		buy_some_shares(S, ui.user)

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_sell", ui_act_stocks_sell, UI_ARG_REF("share", "proc:ui_source_glob_stockexchange_stocks", /datum/stock))
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_sell)
	var/datum/stock/S = params["share"]
	if (S)
		sell_some_shares(S, ui.user)

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_check", ui_act_stocks_check)
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_check)
	screen = "logs"

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_archive", ui_act_stocks_archive, UI_ARG_REF("share", null, /datum/stock))
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_archive)
	var/datum/stock/S = params["share"]
	if(S)
		rel_set(src, nameof(/obj/machinery/computer/stockexchange::current_stock), S)
		screen = "archive"

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_history", ui_act_stocks_history, UI_ARG_REF("share", "proc:ui_source_glob_stockexchange_stocks", /datum/stock))
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_history)
	var/datum/stock/S = params["share"]
	if (S)
		S.displayValues(ui.user)

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_backbutton", ui_act_stocks_backbutton)
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_backbutton)
	rel_clear(src, nameof(/obj/machinery/computer/stockexchange::current_stock))
	screen = "stocks"

UI_ACT(/obj/machinery/computer/stockexchange, "stocks_cycle_view", ui_act_stocks_cycle_view)
UI_ACT_PROC(/obj/machinery/computer/stockexchange, ui_act_stocks_cycle_view)
	vmode++
	if (vmode > 1)
		vmode = 0

/// The list the UI_ARG_REF rows resolve refs in.
/obj/machinery/computer/stockexchange/proc/ui_source_glob_stockexchange_stocks()
	return GLOB.stockExchange.stocks

UI_DATA_REPLACE(/obj/machinery/computer/stockexchange, "screen:num", "merge:ui_data_obj_machinery_computer_stockexchange{stationName:text,balance:unknown,viewMode:text,stocks:list,logs:list,name:text,events:list,articles:list,maxValue:num,values:list}")

/// The computed part of /obj/machinery/computer/stockexchange's window data (declared on its UI_DATA row).
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

DECLARE_UI(/obj/machinery/computer/stockexchange, "StockExchange")

///// PROCS /////

/obj/machinery/computer/stockexchange/proc/sell_some_shares(datum/stock/S, mob/user)
	if (!user || !S)
		return
	var/li = logged_in
	if (!li)
		to_chat(user, span_danger("No active account on the console!"))
		return
	var/b = SSsupply.budget_balance()
	var/avail = LAZYACCESS(S.shareholders, logged_in)
	if (!avail)
		to_chat(user, span_danger("This account does not own any shares of [S.name]!"))
		return
	var/price = S.current_value
	var/_answer_k289 = rerun_ask(user, "k289", PROC_REF(sell_some_shares), args, /datum/om/prompt/number, message = "How many shares? \n(Have: [avail], unit price: [price])", title = "Sell shares in [S.name]", default = 0)
	if(isnull(_answer_k289))
		return
	var/amt = round(_answer_k289)
	amt = min(amt, LAZYACCESS(S.shareholders, logged_in))

	if (!user || (!(user in range(1, src)) && iscarbon(user)))
		return
	if (!amt)
		return
	if (li != logged_in)
		return
	b = SSsupply.budget_balance()
	if (!isnum(b))
		to_chat(user, span_danger("No active account on the console!"))
		return

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
	var/_answer_k324 = rerun_ask(user, "k324", PROC_REF(buy_some_shares), args, /datum/om/prompt/number, message = "How many shares? \n(Available: [avail], unit price: [price], can buy: [canbuy])", title = "Buy shares in [S.name]", default = 0)
	if(isnull(_answer_k324))
		return
	var/amt = round(_answer_k324)
	if (!user || (!(user in range(1, src)) && iscarbon(user)))
		return
	if (li != logged_in)
		return
	b = balance()
	if (!isnum(b))
		to_chat(user, span_danger("No active account on the console!"))
		return

	amt = min(amt, S.available_shares, round(b / S.current_value))
	if (!amt)
		return
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
