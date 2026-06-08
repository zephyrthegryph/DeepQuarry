//Cactus, Speedbird, Dynasty, oh my
//Also, massive additions/refactors by Killian, because the original incarnation was full of holes
//Originally coded by above, massive refactor here to use datums instead of an if/else mess - Willbird
SUBSYSTEM_DEF(atc)
	name = "Air Traffic Control"
	priority = FIRE_PRIORITY_ATC
	runlevels = RUNLEVEL_GAME
	wait = 2 SECONDS
	flags = SS_BACKGROUND | SS_NO_FIRE // disable ATC chatter; flag also pulls SS out of fire list
	VAR_PRIVATE/next_tick = 0
	VAR_PRIVATE/datum/atc_chatter_type/chatter_datum = new() // don't change, override the chatter_box() proc
	VAR_PRIVATE/delay_min = 45 MINUTES				//How long between ATC traffic, minimum
	VAR_PRIVATE/delay_max = 90 MINUTES				//Ditto, maximum
							//Shorter delays means more traffic, which gives the impression of a busier system, but also means a lot more radio noise
	VAR_PRIVATE/backoff_delay = 5 MINUTES			//How long to back off if we can't talk and want to.  Default is 5 mins.
	VAR_PRIVATE/initial_delay = 15 MINUTES			//How long to wait before sending the first message of the shift.
	VAR_PRIVATE/squelched = FALSE					//If ATC is squelched currently

	// Channel frequency vars; unused while ATC is disabled (SS_NO_FIRE), retained for re-enable reference
	var/ertchannel
	var/medchannel
	var/engchannel
	var/secchannel
	var/sdfchannel

/datum/controller/subsystem/atc/Initialize()
	// ATC disabled fork-wide; skip channel allocation and report no-need.
	// To re-enable ATC: remove SS_NO_FIRE from flags, change Initialize() to
	// allocate channels + return SS_INIT_SUCCESS, and verify busy_space/ chatter
	// datums (code/modules/busy_space/) work with the loremaster data.
	return SS_INIT_NO_NEED

/datum/controller/subsystem/atc/fire()
	if(times_fired < 1)
		return
	if(times_fired == 1)
		next_tick = world.time + initial_delay
		INVOKE_ASYNC(src,PROC_REF(shift_starting))
		return
	if(world.time < next_tick)
		return
	if(squelched)
		next_tick = world.time + backoff_delay
		return
	next_tick = world.time + rand(delay_min,delay_max)
	INVOKE_ASYNC(src,PROC_REF(random_convo))

/datum/controller/subsystem/atc/proc/shift_starting()
	new /datum/atc_chatter/shift_start(null,null)

/datum/controller/subsystem/atc/proc/shift_ending()
	new /datum/atc_chatter/shift_end(null,null)

/datum/controller/subsystem/atc/proc/random_convo()
	// Pick from the organizations in the LOREMASTER, so we can find out what these ships are doing
	var/one = pick(GLOB.loremaster.organizations) //These will pick an index, not an instance
	var/two = pick(GLOB.loremaster.organizations)
	var/datum/lore/organization/source = GLOB.loremaster.organizations[one] //Resolve to the instances
	var/datum/lore/organization/secondary = GLOB.loremaster.organizations[two] //repurposed for new fun stuff

	//Random chance things for variety
	var/path = chatter_datum.chatter_box(source.org_type,secondary.org_type)
	new path(source,secondary)

/datum/controller/subsystem/atc/proc/reroute_traffic(yes = 1,silent = FALSE)
	if(yes)
		if(!squelched && !silent)
			msg("Rerouting traffic away from [using_map.station_name].")
		squelched = 1
	else
		if(squelched && !silent)
			msg("Resuming normal traffic routing around [using_map.station_name].")
		squelched = 0

/datum/controller/subsystem/atc/proc/msg(message,sender)
	ASSERT(message)
	GLOB.global_announcer.autosay("[message]", sender ? sender : "[using_map.dock_name] Control")

/datum/controller/subsystem/atc/proc/is_squelched()
	return squelched
