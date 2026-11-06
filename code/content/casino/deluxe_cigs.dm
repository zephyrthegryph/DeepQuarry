/obj/machinery/vending/deluxe_cigs
	name = "Premium Tobacco Distributor"
	desc = "A top of the line smokes vendor that carries some of the finest tobacco based goods in the frontier."
	icon = 'icons/obj/casino.dmi'
	icon_state = "premiumcigs"
	products = list(/obj/item/storage/fancy/cigar = 15,
					/obj/item/storage/fancy/cigarettes/carcinomas = 15,
					/obj/item/storage/fancy/cigarettes/professionals = 15,
					/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba = 30,
					/obj/item/clothing/mask/smokable/cigarette/cigar/havana = 30,
					/obj/item/storage/box/matches = 5,
					/obj/item/flame/lighter/zippo = 10
					)

	contraband = list()
	vend_delay = 15
	req_access = list(ACCESS_BAR)
	req_log_access = ACCESS_BAR
	has_logs = 1
	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/deluxe_cigs)
	configure(uses_power(idle = 211))

/obj/machinery/vending/deluxe_cigs/open
	req_access = null
	req_log_access = null
