// Heist shuttles
/obj/machinery/computer/shuttle_control/multi/heist
	name = "skipjack control console"
	req_access = list(ACCESS_SYNDICATE)
	shuttle_tag = "Skipjack"

// The old multi-destination Skipjack was removed: southern_cross defines its own
// /datum/shuttle/autodock/web_shuttle/heist (same "Skipjack" name) on the web-shuttle
// system, and having both register CRASHed at startup ("shuttle 'Skipjack' already
// defined"). The console above binds by shuttle_tag/name, so it still resolves.
