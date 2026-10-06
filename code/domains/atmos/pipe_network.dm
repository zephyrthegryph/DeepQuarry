/datum/pipe_network
	/// The sole gas inventory for every fixed port and pipeline in this network. Owned: the
	/// member ports' air1/air2/... and pipelines' air are PROTO views naming it (atmos_air_set()).
	var/datum/gas_mixture/air

	/// Membership rosters: two-sided with each member's network_memberships.
	var/list/obj/machinery/atmospherics/normal_members
	var/list/datum/pipeline/line_members

	var/list/leaks = list() // ALLOW(instance_list): the network's leaking nodes: filled and cleared in place while the network runs
	/// Runtime reservoirs connected through portable connectors: owner -> volume.
	var/list/external_air_volumes

	/// TRUE while this network needs one reconciliation pass.
	var/update = TRUE
	/// Monotonic mutation generation: gas_touched() and the topology and leak marks move it (diagnostics and tests read it).
	var/revision = 1
	/// Region wrapper retained by the Rust topology owner. Legacy component code
	/// may request deletion, but only the Rust commit may actually retire it.
	var/rust_authoritative = FALSE

CAPABILITIES(/datum/pipe_network)
	links(/datum/pipe_network::normal_members, /obj/machinery/atmospherics::network_memberships, a_many = TRUE, b_many = TRUE)
	links(/datum/pipe_network::line_members, /datum/pipeline::network_memberships, a_many = TRUE, b_many = TRUE)
	owns_one(nameof(air), /datum/gas_mixture)


// Rust-owned networks refuse deletion.
/datum/pipe_network/lifecycle_keep(force)
	return rust_authoritative

// A legacy network hands each member its share of the gas before the topology splits.
/datum/pipe_network/lifecycle_unbind()
	..()
	STOP_PROCESSING_PIPENET(src)
	// External reservoirs are real containers and must take their volume share
	// with them before the fixed topology is split into independent port mixes.
	for(var/atom/movable/owner as anything in external_air_volumes?.Copy())
		detach_external_air(owner, FALSE)
	// Sever ownership before calling into members.  Atmos topology destruction can
	// re-enter network teardown (especially during explosions); retaining these
	// lists until after the callbacks made the entire graph one GC cycle.
	var/list/old_line_members = line_members?.Copy()
	var/list/old_normal_members = normal_members?.Copy()
	// A retired Rust wrapper has no members (and its mixture may already be released): no gas to split, no volume to read.
	var/network_volume = (length(old_line_members) || length(old_normal_members)) ? volume() : 0
	for(var/datum/pipeline/line_member in old_line_members)
		line_member.detach_network_air(src, air, network_volume)
	for(var/obj/machinery/atmospherics/normal_member in old_normal_members)
		normal_member.detach_network_air(src, air, network_volume)
	// The rosters and each line's `network` view are relations (cleared in phase 4); a
	// member's reassign_network() is the domain consequence (its network1/2 slot).
	rel_clear(src, nameof(leaks))
	external_air_volumes = null
	for(var/obj/machinery/atmospherics/normal_member in old_normal_members)
		normal_member.reassign_network(src, null)
	rel_clear(src, nameof(air))

/// The network's total volume in litres: read from the Rust mixture, which is the only copy.
/datum/pipe_network/proc/volume()
	return air ? air.return_volume() : 0

/datum/pipe_network/proc/add_normal_member(obj/machinery/atmospherics/member)
	if(!member || QDELETED(member))
		return FALSE
	rel_add(src, nameof(normal_members), member)
	return TRUE

/datum/pipe_network/proc/add_line_member(datum/pipeline/member)
	if(!member || QDELETED(member))
		return FALSE
	rel_add(src, nameof(line_members), member)
	return TRUE

/// One reconciliation pass for a dirty network, run by SSair's pipenet phase (SSair.dm
/// process_pipenets()) only while the network is queued (mark_topology_dirty()/mark_leak_dirty()): engineered
/// pipe materials and the batched leak exchange (vg_batch_mingle_hook). Gas flow itself is Rust.
/// Once settled it takes itself off the queue (STOP_PROCESSING_PIPENET).
/datum/pipe_network/proc/reconcile()
	var/needs_leak_followup = FALSE
	//Equalize gases amongst pipe if called for
	if(update)
		update = 0
		for(var/datum/pipeline/line_member in line_members)
			line_member.process_engineered_materials()

	if(length(leaks))
		listclearnulls(leaks) // Let's not have forever-seals.
		var/list/valid_leaks = list()
		var/list/leak_operations = list()
		for(var/obj/machinery/atmospherics/pipe/leak as anything in leaks)
			var/datum/gas_mixture/environment = leak.loc?.return_air()
			if(QDELETED(leak) || !leak.leaking || !leak.parent?.air || !environment)
				rel_remove(src, nameof(leaks), leak)
				continue
			valid_leaks += leak
			// List union (`+=`) removes duplicate datum values. Several holes in the
			// same pipeline deliberately share one reservoir, so append by index to
			// preserve the fixed three-values-per-face FFI protocol.
			var/operation_offset = length(leak_operations)
			leak_operations.len += 3
			leak_operations[operation_offset + 1] = leak.parent.air
			leak_operations[operation_offset + 2] = environment
			leak_operations[operation_offset + 3] = leak.volume
		var/list/leak_residuals = length(leak_operations) ? vg_batch_mingle_hook(leak_operations) : null
		for(var/i = 1 to length(valid_leaks))
			var/obj/machinery/atmospherics/pipe/leak = valid_leaks[i]
			if(i <= length(leak_residuals) && leak_residuals[i])
				needs_leak_followup = TRUE
			else
				leak.hibernate_stable_leak()

	// Leak membership is reactive state consumed by automatic shutoff valves;
	// the individual exposed pipe owns gas exchange and hibernation. Keeping the
	// entire pipenet scheduled merely because it contains a sleeping leak repeats
	// an empty reconciliation pass forever.
	if(!update && !needs_leak_followup)
		STOP_PROCESSING_PIPENET(src)

	//Give pipelines their process call for pressure checking and what not. Have to remove pressure checks for the time being as pipes dont radiate heat - Mport
	//for(var/datum/pipeline/line_member in line_members)
	//	line_member.process()

/datum/pipe_network/proc/merge(datum/pipe_network/giver)
	if(!giver || giver == src || QDELETED(giver))
		return 0

	var/list/giver_normal_members = giver.normal_members?.Copy()
	var/list/giver_line_members = giver.line_members?.Copy()
	var/list/giver_leaks = giver.leaks?.Copy()
	var/list/giver_external = giver.external_air_volumes

	var/giver_volume = giver.volume()
	var/combined_volume = volume() + giver_volume
	if(!air)
		rel_set(src, nameof(air), new /datum/gas_mixture(max(giver_volume, 1)))
	if(giver.air)
		air.merge(giver.air)
	air.set_volume(max(combined_volume, 1))

	for(var/obj/machinery/atmospherics/pipe/giver_leak as anything in giver_leaks)
		rel_add(src, nameof(leaks), giver_leak)

	for(var/obj/machinery/atmospherics/normal_member in giver_normal_members)
		normal_member.bind_network_air(giver, air)
		rel_remove(giver, nameof(giver.normal_members), normal_member)
		rel_add(src, nameof(normal_members), normal_member)
		normal_member.reassign_network(giver, src)

	for(var/datum/pipeline/line_member in giver_line_members)
		line_member.bind_network_air(giver, air)
		rel_remove(giver, nameof(giver.line_members), line_member)
		rel_add(src, nameof(line_members), line_member)
		rel_set(line_member, nameof(line_member.network), src)

	if(length(giver_external))
		if(!external_air_volumes)
			external_air_volumes = list()
		for(var/atom/movable/owner as anything in giver_external)
			external_air_volumes[owner] = giver_external[owner] // ALLOW(ownership): reservoir -> volume numbers, drained by detach_external_air() in lifecycle_unbind(); the reservoir owns its own air
			owner.set_port_network_air(air)

	// The receiving network now owns every transferred member.  Leaving the
	// donor's lists populated retained a second copy of the whole pipenet forever.
	STOP_PROCESSING_PIPENET(giver)
	rel_clear(giver, nameof(giver.leaks))
	giver.external_air_volumes = null
	own_clear(giver, nameof(air), OWN_DELETE)
	consumed(giver, src)
	mark_topology_dirty()
	return 1

/datum/pipe_network/proc/update_network_gases()
	// Topology construction begins with one temporary mixture per pipeline/device
	// port. Pool them once, bind every port to one authoritative mixture, and
	// delete the obsolete handles. Routine processing never redistributes gas.
	var/list/old_gases = list()
	var/total_volume = 0

	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		var/result = normal_member.return_network_air(src)
		if(result)
			for(var/datum/gas_mixture/member_air in result)
				old_gases |= member_air

	for(var/datum/pipeline/line_member in line_members)
		old_gases |= line_member.air

	for(var/datum/gas_mixture/member_air in old_gases)
		total_volume += member_air.return_volume()

	var/datum/gas_mixture/network_air = new(max(total_volume, 1))
	for(var/datum/gas_mixture/member_air in old_gases)
		network_air.merge(member_air)
	network_air.set_volume(max(total_volume, 1))
	// A previous authoritative mixture is among old_gases (merged above): detach it so
	// rel_set() doesn't dispose of it while members still name it; it goes below.
	if(air)
		rel_take(src, nameof(air))
	rel_set(src, nameof(air), network_air)
	// Binding deletes each port's private mixture (atmos_air_set()); what is left over
	// (the previous network mixture) is unowned now and released here.
	for(var/datum/pipeline/line_member in line_members)
		line_member.bind_network_air(src, network_air)
	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		normal_member.bind_network_air(src, network_air)
	for(var/datum/gas_mixture/member_air in old_gases)
		if(member_air != network_air && !QDELETED(member_air) && !owner_of(member_air))
			spent(member_air)
	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		normal_member.attach_external_network_air(src)
	mark_topology_dirty()

/datum/pipe_network/proc/attach_external_air(atom/movable/owner, datum/gas_mixture/external_air)
	if(!owner || !external_air || external_air == air || external_air_volumes?[owner])
		return FALSE
	var/base_volume = volume()
	if(!air)
		rel_set(src, nameof(air), new /datum/gas_mixture(1))
	var/external_volume = external_air.return_volume()
	air.merge(external_air)
	air.set_volume(max(base_volume + external_volume, 1))
	if(!external_air_volumes)
		external_air_volumes = list()
	external_air_volumes[owner] = external_volume // ALLOW(ownership): reservoir -> volume numbers, drained by detach_external_air() in lifecycle_unbind(); the reservoir owns its own air
	owner.set_port_network_air(air)
	if(!QDELETED(external_air) && !owner_of(external_air))
		consumed(external_air, src)
	gas_touched(air)
	return TRUE

/datum/pipe_network/proc/detach_external_air(atom/movable/owner, mark_after = TRUE)
	if(!owner || !external_air_volumes?[owner] || !air)
		return FALSE
	var/external_volume = external_air_volumes[owner]
	var/current_volume = volume()
	var/datum/gas_mixture/detached = air.remove_ratio(min(external_volume / max(current_volume, 1), 1))
	detached.set_volume(max(external_volume, 1))
	air.set_volume(max(current_volume - external_volume, 1))
	external_air_volumes.Remove(owner)
	if(!length(external_air_volumes))
		external_air_volumes = null
	owner.set_port_network_air(detached)
	if(mark_after)
		gas_touched(air)
	return TRUE

/// Topology and engineered-material roster changes need one bounded network pass.
/datum/pipe_network/proc/mark_topology_dirty()
	update = TRUE
	revision++
	START_PROCESSING_PIPENET(src)

/// A real leak owns recurring work without re-running engineered roster scans.
/datum/pipe_network/proc/mark_leak_dirty()
	revision++
	START_PROCESSING_PIPENET(src)

/// Compatibility no-op. Connected ports already share the same authoritative
/// arena handle, so there is nothing to reconcile.
/datum/pipe_network/proc/reconcile_air()
	return
