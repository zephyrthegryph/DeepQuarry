/obj/machinery/vending/deluxe_dinner
	name = "Deluxe Dining Distributor"
	desc = "A top of the line and experimental food vendor, it uses bluespace technology for storage!"
	icon = 'icons/obj/casino.dmi'
	icon_state = "premiumfood"

	vend_delay = 15
	req_access = list(ACCESS_BAR)
	req_log_access = ACCESS_BAR
	has_logs = 1
	vending_sound = "machines/vending/vending_cans.ogg"

CAPABILITIES(/obj/machinery/vending/deluxe_dinner)
	configure(uses_power(idle = 211))

/obj/machinery/vending/deluxe_dinner/open
	req_access = null
	req_log_access = null
