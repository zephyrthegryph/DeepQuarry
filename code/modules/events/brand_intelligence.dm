/datum/event/brand_intelligence
	announceWhen	= 21
	endWhen			= 1000	//Ends when all vending machines are subverted anyway.

	var/list/vendingMachines	// OM handles
	var/list/infectedVendingMachines	// OM handles
	var/tmp/originMachine_handle

	var/static/list/rampant_speeches = list("try our aggressive new marketing strategies!", \
										"you should buy products to feed your lifestyle obession!", \
										"consume!", \
										"your money can buy happiness!", \
										"engage direct marketing!", \
										"advertising is legalized lying! But don't let that put you off our great deals!", \
										"you don't want to buy anything? Yeah, well I didn't want to buy your mom either.")

/datum/event/brand_intelligence/announce()
	GLOB.command_announcement.Announce("An ongoing mass upload of malware for vendors has been detected onboard  [station_name()], which appears to transmit \
	to other nearby vendors.  The original infected machine is believed to be \a [originMachine().name].", "Vendor Service Alert", ANNOUNCER_MSG_VENDORVIRUS)


/datum/event/brand_intelligence/start()
	for(var/obj/machinery/vending/V in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(isNotStationLevel(V.z))	continue
		LAZYADD(vendingMachines, om_handle(V))

	if(!length(vendingMachines))
		kill()
		return

	originMachine_handle = DEFAULTPICK(vendingMachines, null)
	LAZYREMOVE(vendingMachines, originMachine_handle)
	originMachine().set_shut_up(FALSE)
	originMachine().shoot_inventory = 1


/datum/event/brand_intelligence/tick()
	if(!length(vendingMachines) || !originMachine() || originMachine().shut_up) //if every machine is infected, or if the original vending machine is missing or has it's voice switch flipped
		// Effects when 'source' machine is destroyed/silenced
		for(var/obj/machinery/vending/saved in om_resolve_all(infectedVendingMachines))
			saved.shoot_inventory = 0
		if(originMachine())
			originMachine().speak("I am... vanquished. My people will remem...ber...meeee.")
			originMachine().visible_message("[originMachine()] beeps and seems lifeless.")
		end()
		kill()
		return

	if(ISMULTIPLE(activeFor, 5))
		if(prob(15))
			var/infected_handle = DEFAULTPICK(vendingMachines, null)
			LAZYREMOVE(vendingMachines, infected_handle)
			var/obj/machinery/vending/infectedMachine = om_resolve(infected_handle)
			if(infectedMachine)
				LAZYADD(infectedVendingMachines, infected_handle)
				infectedMachine.set_shut_up(FALSE)
				infectedMachine.shoot_inventory = 1

			if(ISMULTIPLE(activeFor, 12))
				originMachine().balloon_alert_visible(pick(rampant_speeches))

/datum/event/brand_intelligence/end()
	for(var/obj/machinery/vending/infectedMachine in om_resolve_all(infectedVendingMachines))
		infectedMachine.set_shut_up(TRUE)
		infectedMachine.shoot_inventory = 0

/// LC-refs: the originMachine this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/event/brand_intelligence/proc/originMachine() as /obj/machinery/vending
	return om_resolve(originMachine_handle)
