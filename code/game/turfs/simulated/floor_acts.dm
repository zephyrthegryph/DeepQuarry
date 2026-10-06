// Floors use integrity (damage.md §5, D-turf): the tile's condition is its
// integrity. Below `integrity_failure` the tile breaks (break_tile()); at zero
// the tile is torn up to plating, and plating torn up again opens to the base
// turf. `broken`/`burnt` stay as the icon state of that condition only.
/turf/simulated/floor
	uses_integrity = TRUE
	max_integrity = FLOOR_INTEGRITY
	integrity_failure = FLOOR_INTEGRITY_FAILURE

/// Floors take blast on their own ladder so a heavy blast still breaches the
/// deck: the epicentre opens it to the base turf outright, the rest is a
/// blast packet on the tile's integrity.
/turf/simulated/floor/receive_explosion(severity)
	if(resistance_flags & BOMB_PROOF)
		return 0
	if(react_to_entry(DAMAGE_ENTRY_EXPLOSION, severity)) // the ladder below is not a DAMAGE_ENTRY_EXPLOSION packet
		return 0
	switch(round(severity))
		if(1)
			ChangeTurf(get_base_turf_by_area(src))
			return max_integrity
		if(2)
			// A breach keeps the old odds (40% lattice, 40% open deck); the
			// rest of the ring is a blast packet on the tile.
			if(prob(40))
				if(prob(33))
					new /obj/item/stack/material/steel(src)
				ReplaceWithLattice()
				return max_integrity
			if(prob(66))
				ChangeTurf(get_base_turf_by_area(src))
				return max_integrity
			hotspot_expose(1000, CELL_VOLUME)
			return deal_damage(DAMAGE_BLAST, rand(FLOOR_INTEGRITY * 0.5, FLOOR_INTEGRITY * 1.5), flags = DAMAGE_PACKET_SILENT)
		if(3)
			if(prob(50))
				hotspot_expose(1000, CELL_VOLUME)
			return deal_damage(DAMAGE_BLAST, rand(0, FLOOR_INTEGRITY * 0.75), flags = DAMAGE_PACKET_SILENT)
	return 0

/// Rounds that stop on a floor and blobs spreading over it leave the deck
/// alone, as before integrity: only blasts and flame wear a floor down.
/turf/simulated/floor/projectile_damage(obj/item/projectile/P, def_zone)
	return 0

CAPABILITIES(/turf/simulated/floor)
	extend(/datum/act/hit/blob, instead())
	param(nameof(floortype_at_make), pos = 1)

/// The tile breaks as its condition crosses the failure fraction.
/turf/simulated/floor/on_update_integrity(old_value, new_value)
	. = ..()
	var/failure_amount = integrity_failure * max_integrity
	if(old_value > failure_amount && new_value <= failure_amount && new_value > 0)
		break_tile()

/turf/simulated/floor/atom_destruction(damage_flag)
	. = ..()
	if(is_plating())
		if(prob(33))
			new /obj/item/stack/material/steel(src)
		if(prob(50))
			ReplaceWithLattice()
		else
			ChangeTurf(get_base_turf_by_area(src))
		return
	if(prob(33))
		new /obj/item/stack/material/steel(src)
	// The torn-up tile leaves damaged plating with a fresh condition.
	break_tile_to_plating()
	update_integrity(max_integrity * integrity_failure)

/// Restore the tile's condition (new flooring, welded dents).
/turf/simulated/floor/proc/restore_floor_integrity()
	if(uses_integrity)
		repair_damage(max_integrity)

/// Flame contact on a simulated turf: its declared heat damage (floor tiles
/// scorch and lift, walls melt). The one turf fire_act.
/turf/simulated/fire_act(exposed_temperature, exposed_volume)
	burn(exposed_temperature)

/// Heat damage from flame contact at `exposed_temperature`; none by default.
/turf/simulated/proc/burn(exposed_temperature)
	return

/turf/simulated/floor/burn(exposed_temperature)

	var/temp_destroy = get_damage_temperature()
	if(!burnt && prob(5))
		burn_tile(exposed_temperature)
	else if(temp_destroy && exposed_temperature >= (temp_destroy + 100) && prob(1) && !is_plating())
		// The flame tears the tile up through its integrity (to plating).
		deal_damage(DAMAGE_THERMAL, get_integrity(), flags = DAMAGE_PACKET_SILENT | DAMAGE_PACKET_UNARMORED)
		burn_tile(exposed_temperature)
		feed_lingering_fire(0.35) // Lingering fire, feeding fires
	return

//should be a little bit lower than the temperature required to destroy the material
/turf/simulated/floor/proc/get_damage_temperature()
	return flooring ? flooring.damage_temperature : null
