/datum/data/pda/app/supply_orders
	name = "Cargo Orders"
	icon = "box"
	template = "pda_supply_orders"

/datum/data/pda/app/supply_orders/update_ui(mob/living/user, list/data)
	var/datum/money_account/account = pda.id ? get_account(pda.id.associated_account_number) : null
	var/list/orders = list()
	if(account)
		for(var/index = length(SSsupply.order_history), index >= 1, index--)
			var/datum/supply_order/order = SSsupply.order_history[index]
			if(!order.personal_order || order.funding_account_number != account.account_number)
				continue
			orders.Add(list(list(
				"ref" = "\ref[order]",
				"number" = order.ordernum,
				"name" = order.name,
				"status" = order.status,
				"cost" = SSsupply.pack_price(order.object),
				"reason" = order.comment,
				"ordered_at" = order.ordered_at,
				"approved_by" = order.approved_by,
				"can_cancel" = order.status == SUP_ORDER_REQUESTED
			)))
	data["supply_order_account"] = account?.account_number
	data["personal_supply_orders"] = orders

/datum/data/pda/app/supply_orders/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	if(action != "cancel_personal_order" || pda.loc != ui.user || !pda.id)
		return FALSE
	var/datum/money_account/account = get_account(pda.id.associated_account_number)
	var/datum/supply_order/order = locate(params["ref"])
	if(!(order in SSsupply.order_history))
		return FALSE
	return SSsupply.cancel_personal_order(order, account, ui.user)
