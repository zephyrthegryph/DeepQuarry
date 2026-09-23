// Propagation paths (doc/rewrite/containment.md §3.2, roadmap C2).
//
// When heat, damage, gas or radiation reaches a holder, one function per
// effect decides what reaches each thing inside and how much. Nothing else
// writes its own "does heat reach the pockets" code.
//
//   dq_path_step(holder, child, effect, kind, penetration)
//       share (0..1) of `effect` crossing from `holder` to a direct child
//   dq_path_share(child, from, effect, kind, penetration)
//       product of the steps from `from` down to `child`, however deep
//   holder.propagate_damage(packet)   receive_damage() calls this (damage)
//   holder.propagate_fire(T, volume)  /obj/fire_act() calls this (heat)
//   heat_adapter.dm                   the one coupling to the heat domain (M4)
//
// One step, for a child in slot S of holder H:
//   1. S's own transmission for the effect (slot_def vars, data only);
//   2. if S is inside H's shell (internal or sealed), H's attenuation:
//      insulation (PROP_INSULATION) for heat, armour for damage and radiation;
//   3. if S is layered, every thing in H's layers further out, outermost
//      first, attenuates the same way: a suit covers a jumpsuit.
// Gas passes unless S is sealed. Living things take heat and damage only
// through slots that set reaches_mobs.

/// Default share of each damage kind (DAMAGE_* order) passing into a slot
/// with `exposure`, before armour. Conservative: the holder's shell takes
/// blunt and cutting blows; heat and radiation have their own paths; EMPs and
/// explosions already reach contents through their own recursion.
/proc/dq_path_default_damage(exposure)
	var/static/list/external = list(
		0, // blunt
		0, // sharp
		0, // pierce
		0, // thermal: the heat path
		0, // cold: the heat path
		0, // shock
		0, // corrosive
		0, // toxic
		0, // radiation: the radiation path
		0, // ionic: emp_act recursion
		0, // blast: ex_act recursion
		0, // pain
	)
	// External contents are outside the shell: equipment zones (C3, D2)
	// decide what a hit on the holder does to them, not this path.
	var/static/list/internal = list(
		0,    // blunt
		0,    // sharp
		0.5,  // pierce: a stab or a round can go through
		0,    // thermal
		0,    // cold
		0,    // shock
		0.25, // corrosive: acid seeps in
		0,    // toxic
		0,    // radiation
		0,    // ionic
		0,    // blast
		0,    // pain
	)
	var/static/list/sealed = list(
		0,    // blunt
		0,    // sharp
		0.5,  // pierce
		0,    // thermal
		0,    // cold
		0,    // shock
		0,    // corrosive: the seal keeps it out
		0,    // toxic
		0,    // radiation
		0,    // ionic
		0,    // blast
		0,    // pain
	)
	switch(exposure)
		if(SLOT_EXPOSURE_EXTERNAL)
			return external
		if(SLOT_EXPOSURE_SEALED)
			return sealed
	return internal

/// Damage kinds that land on one thing (a blow, a stab, a round). The rest
/// (acid, blast, ...) spread over everything in the slot.
/proc/dq_path_point_kind(kind)
	return kind == DAMAGE_BLUNT || kind == DAMAGE_SHARP || kind == DAMAGE_PIERCE

/// Fraction of heat `A` keeps from what it covers, 0..1 (P1 PROP_INSULATION).
/proc/dq_path_insulation(atom/A)
	return clamp(PROPERTY(A, PROP_INSULATION) || 0, 0, 1)

/// Fraction of a hit of armour key `key` that `A` stops, 0..1. Items read
/// their armour list; nothing else has armour until D2 interns it.
/proc/dq_path_armor(atom/A, key, penetration = 0)
	if(!key || !isitem(A))
		return 0
	var/obj/item/I = A
	var/armor = I.armor?[key]
	if(!armor)
		return 0
	armor = clamp(PENETRATE_ARMOUR(armor, penetration), 0, 100)
	return armor / 100

/// What `A`, covering something, lets through of `effect`, 0..1.
/proc/dq_path_attenuation(atom/A, effect, kind, penetration = 0)
	switch(effect)
		if(PATH_EFFECT_HEAT)
			return 1 - dq_path_insulation(A)
		if(PATH_EFFECT_DAMAGE)
			return 1 - dq_path_armor(A, damage_kind_armor_key(kind), penetration)
		if(PATH_EFFECT_RADIATION)
			return 1 - dq_path_armor(A, damage_kind_armor_key(DAMAGE_RADIATION), penetration)
	return 1

/// The things in `holder`'s layers further out than slot `def`, outermost
/// layer first. Empty for an unlayered slot.
/proc/dq_path_outer_layers(atom/holder, datum/slot_def/def)
	. = list()
	if(def.layer == SLOT_LAYER_NONE)
		return
	var/datum/ledger/L = holder.ledger
	if(!L)
		return
	var/list/outer = list()
	for(var/datum/slot_def/other as anything in L.defs)
		if(other.layer > def.layer)
			outer += other
	sortTim(outer, GLOBAL_PROC_REF(cmp_slot_def_layer_dsc))
	for(var/datum/slot_def/other as anything in outer)
		var/list/things = L.slots[other.id]
		if(length(things))
			. += things

/proc/cmp_slot_def_layer_dsc(datum/slot_def/a, datum/slot_def/b)
	return b.layer - a.layer

/// The slot definition `child` is in on `holder`, or null.
/proc/dq_path_slot_of(atom/holder, atom/movable/child)
	if(!holder || child?.loc != holder || !dq_slot_defs_for(holder))
		return null
	var/datum/ledger/L = dq_ledger(holder)
	var/list/entry = L?.entries[child]
	if(!entry)
		return null
	return L.def_by_id(entry[LEDGER_E_SLOT])

/// Share (0..1) of `effect` (PATH_EFFECT_*) that crosses from `holder` to
/// `child`, a direct child. `kind` is the DAMAGE_* kind for damage.
/// Holders without slots pass nothing: legacy holders keep their own code
/// until their track migrates them.
/proc/dq_path_step(atom/holder, atom/movable/child, effect, kind = 0, penetration = 0)
	var/datum/slot_def/def = dq_path_slot_of(holder, child)
	if(!def)
		return 0
	if(effect == PATH_EFFECT_GAS)
		return def.passes_gas() ? 1 : 0
	if(!def.reaches_mobs && isliving(child) && effect != PATH_EFFECT_RADIATION)
		return 0
	var/share
	switch(effect)
		if(PATH_EFFECT_HEAT)
			share = def.heat_transmission
		if(PATH_EFFECT_DAMAGE)
			share = def.damage_share(kind)
		if(PATH_EFFECT_RADIATION)
			share = def.radiation_transmission
		else
			CRASH("unknown path effect [effect]")
	if(share <= 0)
		return 0
	if(def.is_inside())
		share *= dq_path_attenuation(holder, effect, kind, penetration)
	for(var/atom/cover as anything in dq_path_outer_layers(holder, def))
		if(share < PATH_MIN_SHARE)
			return 0
		share *= dq_path_attenuation(cover, effect, kind, penetration)
	return share < PATH_MIN_SHARE ? 0 : share

/// Share (0..1) of `effect` reaching `child` from `from`, which holds it
/// directly or through nested holders. 0 if `child` isn't inside `from`.
/proc/dq_path_share(atom/movable/child, atom/from, effect, kind = 0, penetration = 0)
	. = 1
	var/atom/movable/current = child
	while(current && current != from)
		var/atom/holder = current.loc
		if(!holder || isturf(holder))
			return 0
		. *= dq_path_step(holder, current, effect, kind, penetration)
		if(!.)
			return 0
		current = holder

// ---- Damage (D1's receive_damage calls this) ----

/// Passes each thing in this holder's slots its share of `packet`, per the
/// path rules. Each share is a packet of its own, delivered through the
/// child's receive_damage(), so nested holders pass it on in turn.
/atom/proc/propagate_damage(datum/damage_packet/packet)
	if(!length(contents) || !dq_slot_defs_for(src))
		return 0
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return 0
	. = 0
	var/list/incoming = packet.amounts
	for(var/datum/slot_def/def as anything in L.defs)
		var/list/things = L.slots[def.id]
		if(!length(things))
			continue
		things = things.Copy()
		// One target per point kind per slot; spread kinds reach everyone.
		var/list/point_targets = list()
		for(var/kind in 1 to DAMAGE_KIND_COUNT)
			if(incoming[kind] > 0 && dq_path_point_kind(kind) && def.damage_share(kind) > 0)
				point_targets["[kind]"] = pick(things)
		for(var/atom/movable/child as anything in things)
			if(QDELETED(child) || child.loc != src)
				continue
			var/datum/damage_packet/share_packet
			for(var/kind in 1 to DAMAGE_KIND_COUNT)
				var/amount = incoming[kind]
				if(amount <= 0)
					continue
				if(dq_path_point_kind(kind) && point_targets["[kind]"] != child)
					continue
				var/share = dq_path_step(src, child, PATH_EFFECT_DAMAGE, kind, packet.penetration)
				if(share <= 0)
					continue
				if(!share_packet)
					share_packet = damage_packet(packet.source, packet.attacker, packet.weapon, null, packet.flags | DAMAGE_PACKET_SILENT, packet.penetration, packet.direction, packet.armor_flag)
				share_packet.add(kind, amount * share)
			if(!share_packet)
				continue
			. += child.receive_damage(share_packet)
			share_packet.release()
		if(QDELETED(src))
			return

// ---- Heat (fire exposure today; heat_adapter.dm for the heat domain) ----

/// Exposes each thing in this holder's slots to its share of a fire of
/// `exposed_temperature`: what crosses the path raises it above the interior's
/// ambient temperature. Returns how many things were exposed.
/atom/proc/propagate_fire(exposed_temperature, exposed_volume)
	if(!length(contents) || !dq_slot_defs_for(src))
		return 0
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return 0
	var/ambient = dq_heat_path_ambient(src)
	if(exposed_temperature <= ambient)
		return 0
	. = 0
	for(var/atom/movable/child as anything in L.ordered())
		if(QDELETED(child) || child.loc != src)
			continue
		var/share = dq_path_step(src, child, PATH_EFFECT_HEAT)
		if(share <= 0)
			continue
		child.fire_act(ambient + (exposed_temperature - ambient) * share, exposed_volume)
		.++
		if(QDELETED(src))
			return
