/datum/data/pda/app/service_receipts
	name = "Service Receipts"
	icon = "receipt"
	template = "pda_service_receipts"

/datum/data/pda/app/service_receipts/update_ui(mob/living/user, list/data)
	var/datum/money_account/account = pda.id ? get_account(pda.id.associated_account_number) : null
	data["service_receipt_account"] = account?.account_number
	data["service_receipts"] = account ? SSsupply.service_invoice_rows(account.account_number) : list()
