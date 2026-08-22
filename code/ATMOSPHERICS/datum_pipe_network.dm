/datum/pipe_network
	var/list/datum/gas_mixture/gases = list() //All of the gas_mixtures continuously connected in this network
	var/volume = 0	//caches the total volume for atmos machines to use in gas calculations

	var/list/obj/machinery/atmospherics/normal_members = list()
	var/list/datum/pipeline/line_members = list()
		//membership roster to go through for updates and what not

	var/list/leaks = list()

	/// TRUE while this network needs one reconciliation pass.
	var/update = TRUE
	/// Monotonic mutation generation used by sleeping dependants and diagnostics.
	var/revision = 1
	//var/datum/gas_mixture/air_transient = null


/datum/pipe_network/Destroy()
	STOP_PROCESSING_PIPENET(src)
	for(var/datum/pipeline/line_member in line_members)
		line_member.network = null
	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		normal_member.reassign_network(src, null)
	line_members = null
	normal_members = null
	gases = null // Do not qdel the gases, we don't own them.
	leaks = null
	return ..()

/datum/pipe_network/process()
	//Equalize gases amongst pipe if called for
	if(update)
		update = 0
		reconcile_air() //equalize_gases(gases)
		for(var/datum/pipeline/line_member in line_members)
			line_member.process_engineered_materials()

	if(length(leaks))
		listclearnulls(leaks) // Let's not have forever-seals.

	// Clean, sealed networks have no periodic work. mark_dirty() enrolls them again.
	if(!update && !length(leaks))
		STOP_PROCESSING_PIPENET(src)
		return PROCESS_KILL

	//Give pipelines their process call for pressure checking and what not. Have to remove pressure checks for the time being as pipes dont radiate heat - Mport
	//for(var/datum/pipeline/line_member in line_members)
	//	line_member.process()

/datum/pipe_network/proc/build_network(obj/machinery/atmospherics/start_normal, obj/machinery/atmospherics/reference)
	//Purpose: Generate membership roster
	//Notes: Assuming that members will add themselves to appropriate roster in network_expand()

	if(!start_normal)
		qdel(src)
		return

	start_normal.network_expand(src, reference)

	update_network_gases()

	if((normal_members.len>0)||(line_members.len>0))
		mark_dirty()
	else
		qdel(src)

/datum/pipe_network/proc/merge(datum/pipe_network/giver)
	if(giver==src) return 0

	normal_members |= giver.normal_members

	line_members |= giver.line_members

	leaks |= giver.leaks

	for(var/obj/machinery/atmospherics/normal_member in giver.normal_members)
		normal_member.reassign_network(giver, src)

	for(var/datum/pipeline/line_member in giver.line_members)
		line_member.network = src

	update_network_gases()
	return 1

/datum/pipe_network/proc/update_network_gases()
	//Go through membership roster and make sure gases is up to date

	gases = list()
	volume = 0

	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		var/result = normal_member.return_network_air(src)
		if(result) gases += result

	for(var/datum/pipeline/line_member in line_members)
		gases += line_member.air

	for(var/datum/gas_mixture/air in gases)
		volume += air.return_volume()
	mark_dirty()

/// Records an authoritative network mutation and schedules exactly one reconciliation pass.
/datum/pipe_network/proc/mark_dirty()
	update = TRUE
	revision++
	START_PROCESSING_PIPENET(src)

// pipenet gas equalization. The original /proc/equalize_gases pooled
// every member mixture's gases + thermal energy, then redistributed to each
// mixture proportionally to its volume share, with all mixtures ending at the
// pool average temperature.
//
// Implementation: build a per-gas-type pool by summing moles across every
// member mix, then for each member mix overwrite its gases dict to
// (pooled_moles * volume / total_volume). This redistributes gas from full
// pipes to empty pipes — a per-pipe `multiply()` won't because it scales
// existing content only and can't push gas into an empty mixture.
/datum/pipe_network/proc/reconcile_air()
	if(length(gases))
		call_ext(VERDIGRIS, "byond:equalize_all_hook_ffi")(gases)
