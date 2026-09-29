/datum/pipe_network
	/// Compatibility read view: list(air) while the network has air, else null. Derived from
	/// the owned `air` by sync_gases(); written nowhere else.
	var/list/gases
	/// The sole gas inventory for every fixed port and pipeline in this network. Owned: the
	/// member ports' air1/air2/... and pipelines' air are PROTO views naming it (atmos_air_set()).
	var/datum/gas_mixture/air
	var/volume = 0	//caches the total volume for atmos machines to use in gas calculations

	/// Membership rosters: two-sided with each member's network_memberships.
	var/list/obj/machinery/atmospherics/normal_members
	var/list/datum/pipeline/line_members

	var/list/leaks = list() // ALLOW(instance_list): atmos area (M1a/S1): listed in memory_lists_audit.md, not edited here
	/// Runtime reservoirs connected through portable connectors: owner -> volume.
	var/list/external_air_volumes

	/// TRUE while this network needs one reconciliation pass.
	var/update = TRUE
	/// Monotonic mutation generation used by sleeping dependants and diagnostics.
	var/revision = 1
	/// Region wrapper retained by the Rust topology owner. Legacy component code
	/// may request deletion, but only the Rust commit may actually retire it.
	var/rust_authoritative = FALSE


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
	var/network_volume = volume
	for(var/datum/pipeline/line_member in old_line_members)
		line_member.detach_network_air(src, air, network_volume)
	for(var/obj/machinery/atmospherics/normal_member in old_normal_members)
		normal_member.detach_network_air(src, air, network_volume)
	// The rosters and each line's `network` view are relations (cleared in phase 4); a
	// member's reassign_network() is the domain consequence (its network1/2 slot).
	rel_clear(src, "leaks")
	external_air_volumes = null
	for(var/obj/machinery/atmospherics/normal_member in old_normal_members)
		normal_member.reassign_network(src, null)
	own_clear(src, "air", OWN_DELETE)
	sync_gases()
	volume = 0

/// Keeps the compatibility `gases` view equal to list(air).
/datum/pipe_network/proc/sync_gases()
	gases = air ? list(air) : null // ALLOW(ownership): a derived read-only copy of the owned `air`, rewritten whenever air changes

/datum/pipe_network/proc/add_normal_member(obj/machinery/atmospherics/member)
	if(!member || QDELETED(member))
		return FALSE
	rel_add(src, "normal_members", member)
	return TRUE

/datum/pipe_network/proc/add_line_member(datum/pipeline/member)
	if(!member || QDELETED(member))
		return FALSE
	rel_add(src, "line_members", member)
	return TRUE

/// One reconciliation pass for a dirty network, run by SSair's pipenet phase (SSair.dm
/// process_pipenets()) only while the network is queued (mark_dirty()/mark_leak_dirty()): engineered
/// pipe materials and the batched leak exchange (vg_batch_mingle_hook). Gas flow itself is Rust.
/// Returns PROCESS_KILL once settled, which dequeues it.
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
				rel_remove(src, "leaks", leak)
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
		return PROCESS_KILL

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

	if(!air)
		own_set(src, "air", new /datum/gas_mixture(max(volume, 1)))
		sync_gases()
	if(giver.air)
		air.merge(giver.air)
	volume += giver.volume
	air.set_volume(max(volume, 1))

	for(var/obj/machinery/atmospherics/pipe/giver_leak as anything in giver_leaks)
		rel_add(src, "leaks", giver_leak)

	for(var/obj/machinery/atmospherics/normal_member in giver_normal_members)
		normal_member.bind_network_air(giver, air)
		rel_remove(giver, "normal_members", normal_member)
		rel_add(src, "normal_members", normal_member)
		normal_member.reassign_network(giver, src)

	for(var/datum/pipeline/line_member in giver_line_members)
		line_member.bind_network_air(giver, air)
		rel_remove(giver, "line_members", line_member)
		rel_add(src, "line_members", line_member)
		rel_set(line_member, "network", src)

	if(length(giver_external))
		if(!external_air_volumes)
			external_air_volumes = list()
		for(var/atom/movable/owner as anything in giver_external)
			external_air_volumes[owner] = giver_external[owner] // ALLOW(ownership): reservoir -> volume numbers, drained by detach_external_air() in lifecycle_unbind(); the reservoir owns its own air
			owner.set_port_network_air(air)

	// The receiving network now owns every transferred member.  Leaving the
	// donor's lists populated retained a second copy of the whole pipenet forever.
	STOP_PROCESSING_PIPENET(giver)
	rel_clear(giver, "leaks")
	giver.external_air_volumes = null
	own_clear(giver, "air", OWN_DELETE)
	giver.sync_gases()
	giver.volume = 0
	qdel(giver)
	sync_gases()
	mark_topology_dirty()
	return 1

/datum/pipe_network/proc/update_network_gases()
	// Topology construction begins with one temporary mixture per pipeline/device
	// port. Pool them once, bind every port to one authoritative mixture, and
	// delete the obsolete handles. Routine processing never redistributes gas.
	var/list/old_gases = list()
	volume = 0

	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		var/result = normal_member.return_network_air(src)
		if(result)
			for(var/datum/gas_mixture/member_air in result)
				old_gases |= member_air

	for(var/datum/pipeline/line_member in line_members)
		old_gases |= line_member.air

	for(var/datum/gas_mixture/member_air in old_gases)
		volume += member_air.return_volume()

	var/datum/gas_mixture/network_air = new(max(volume, 1))
	for(var/datum/gas_mixture/member_air in old_gases)
		network_air.merge(member_air)
	network_air.set_volume(max(volume, 1))
	// A previous authoritative mixture is among old_gases (merged above): detach it so
	// own_set() doesn't dispose of it while members still name it; it goes below.
	if(air)
		own_take(src, "air")
	own_set(src, "air", network_air)
	sync_gases()
	// Binding deletes each port's private mixture (atmos_air_set()); what is left over
	// (the previous network mixture) is unowned now and released here.
	for(var/datum/pipeline/line_member in line_members)
		line_member.bind_network_air(src, network_air)
	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		normal_member.bind_network_air(src, network_air)
	for(var/datum/gas_mixture/member_air in old_gases)
		if(member_air != network_air && !QDELETED(member_air) && !owner_of(member_air))
			qdel(member_air)
	for(var/obj/machinery/atmospherics/normal_member in normal_members)
		normal_member.attach_external_network_air(src)
	mark_topology_dirty()

/datum/pipe_network/proc/attach_external_air(atom/movable/owner, datum/gas_mixture/external_air)
	if(!owner || !external_air || external_air == air || external_air_volumes?[owner])
		return FALSE
	if(!air)
		own_set(src, "air", new /datum/gas_mixture(1))
		sync_gases()
	var/external_volume = external_air.return_volume()
	air.merge(external_air)
	volume += external_volume
	air.set_volume(max(volume, 1))
	if(!external_air_volumes)
		external_air_volumes = list()
	external_air_volumes[owner] = external_volume // ALLOW(ownership): reservoir -> volume numbers, drained by detach_external_air() in lifecycle_unbind(); the reservoir owns its own air
	owner.set_port_network_air(air)
	if(!QDELETED(external_air) && !owner_of(external_air))
		qdel(external_air)
	sync_gases()
	mark_dirty()
	return TRUE

/datum/pipe_network/proc/detach_external_air(atom/movable/owner, mark_after = TRUE)
	if(!owner || !external_air_volumes?[owner] || !air)
		return FALSE
	var/external_volume = external_air_volumes[owner]
	var/datum/gas_mixture/detached = air.remove_ratio(min(external_volume / max(volume, 1), 1))
	detached.set_volume(max(external_volume, 1))
	volume = max(volume - external_volume, 0)
	air.set_volume(max(volume, 1))
	external_air_volumes.Remove(owner)
	if(!length(external_air_volumes))
		external_air_volumes = null
	owner.set_port_network_air(detached)
	if(mark_after)
		mark_dirty()
	return TRUE

/// Records a gas-state mutation. The Rust mixture revision is authoritative;
/// this revision exists for exact DM-side subscribers and does not enroll the
/// whole pipenet for a topology/material scan.
/datum/pipe_network/proc/mark_dirty()
	revision++

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

// Rosters: two-sided with each member's network_memberships (ownership.md §4.1).
REL_PAIR_LIST(/datum/pipe_network, normal_members, network_memberships)
REL_PAIR_LIST(/datum/pipe_network, line_members, network_memberships)

