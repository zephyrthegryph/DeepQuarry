/datum/data/pda/app/supply_orders
	name = "Cargo Orders"
	icon = "box"
	template = "pda_supply_orders"

/datum/data/pda/app/supply_orders/update_ui(mob/living/user, list/data)
	var/datum/money_account/account = pda().id ? get_account(pda().id.associated_account_number) : null
	var/list/orders = list()
	if(account)
		for(var/index = length(supply_order_history()), index >= 1, index--)
			var/datum/supply_order/order = supply_order_history()[index]
			if(!order.personal_order || order.funding_account_number != account.account_number)
				continue
			orders.Add(list(list(
				"ref" = "\ref[order]",
				"number" = order.ordernum,
				"name" = order.name,
				"status" = order.status,
				"cost" = SSsupply.pack_price(order.supply_pack_of()),
				"reason" = order.comment,
				"ordered_at" = order.ordered_at,
				"approved_by" = order.approved_by,
				"can_cancel" = order.status == SUP_ORDER_REQUESTED
			)))
	data["supply_order_account"] = account?.account_number
	data["personal_supply_orders"] = orders

CAPABILITIES(/datum/data/pda/app/supply_orders)
	op("cancel_personal_order", ui_act("cancel_personal_order", arg("ref", schema_ref(/datum/supply_order))), then(PROC_REF(ui_act_cancel_personal_order)))
/datum/data/pda/app/supply_orders/proc/ui_act_cancel_personal_order(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!isnull(ref) && !(ref in order_history()))
		return FALSE
	if(pda().loc != user || !pda().id)
		return FALSE
	var/datum/money_account/account = get_account(pda().id.associated_account_number)
	var/datum/supply_order/order = ref
	if(!order)
		return FALSE
	return SSsupply.cancel_personal_order(order, account, user)

/// The supply order history, for the UI's order refs.
/datum/data/pda/app/supply_orders/proc/order_history()
	return supply_order_history()
