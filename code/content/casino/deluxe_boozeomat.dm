//Original Casino Code created by Shadowfire117#1269 - Ported from CHOMPstation
//Modified by GhostActual#2055 for use with VOREstation

//
//The code for Casino Vendors
//Devs Feel free to modify this to vend what you please
//

//
//Locked Vendors (require access to use)
//
/obj/machinery/vending/deluxe_boozeomat
	name = "Deluxe Drink Distributor"
	desc = "A top of the line and experimental drink vendor, it uses bluespace technology for storage!"
	icon = 'icons/obj/casino.dmi'
	icon_state = "premiumbooze"

	vend_delay = 15
	req_access = list(ACCESS_BAR)
	req_log_access = ACCESS_BAR
	has_logs = 1

CAPABILITIES(/obj/machinery/vending/deluxe_boozeomat)
	configure(uses_power(idle = 211))

//
//Unlocked Vendors
//
/obj/machinery/vending/deluxe_boozeomat/open
	req_access = null
	req_log_access = null
