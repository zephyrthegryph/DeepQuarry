// /datum/apc_icon_renderer
//
// Pure rendering helper for the APC.  Given the APC's current state it
// computes the correct icon_state, overlays, and lighting, then applies
// them.  All logic that touches the visual representation of an APC lives
// here so that apc.dm can be free of scattered update_icon / check_updates
// concerns.
//
// Usage:
//   renderer.apply(apc)   — call whenever visible state may have changed.
//   renderer.apply_light_only(apc)   — cheap path when only light changes.
//
// apply() is idempotent: it records a bitfield of last-applied state and
// returns early if nothing changed.

/datum/apc_icon_renderer
	/// Bitfield of the last icon_state conditions applied.
	var/last_update_state   = -1
	/// Bitfield of the last overlay conditions applied.
	var/last_update_overlay = -1

// apply() — compute new state, diff against last, and apply only what
// changed.  Returns a bitmask:
//   1 — icon_state was updated
//   2 — overlays were updated
//   0 — nothing changed
/datum/apc_icon_renderer/proc/apply(obj/machinery/power/apc/apc)
	var/new_state   = _compute_state(apc)
	var/new_overlay = _compute_overlay(apc, new_state)

	var/result = 0
	if(last_update_state != new_state)
		result |= 1
		last_update_state = new_state
	if(last_update_overlay != new_overlay)
		result |= 2
		last_update_overlay = new_overlay

	if(!result)
		return 0

	if(result & 1)
		_apply_icon_state(apc, new_state)
	if(result & 2)
		_apply_overlays(apc, new_state, new_overlay)
	if(result & 3)
		_apply_light(apc, new_state)

	return result

/// Force a full re-apply regardless of cached state.
/datum/apc_icon_renderer/proc/force_apply(obj/machinery/power/apc/apc)
	last_update_state   = -1
	last_update_overlay = -1
	apply(apc)

// _compute_state() — derive the UPDATE_* bitfield from current APC state.
/datum/apc_icon_renderer/proc/_compute_state(obj/machinery/power/apc/apc)
	var/s = 0
	if(apc.cell)       s |= UPDATE_CELL_IN
	if(apc.stat & BROKEN) s |= UPDATE_BROKE
	if(apc.stat & MAINT)  s |= UPDATE_MAINT
	if(apc.opened == 1)   s |= UPDATE_OPENED1
	else if(apc.opened == 2) s |= UPDATE_OPENED2
	else if(apc.wiresexposed) s |= UPDATE_WIREEXP
	else if(apc.emagged || apc.hacker || apc.failure_timer)
		s |= UPDATE_BLUESCREEN
	if(s <= UPDATE_CELL_IN)
		s |= UPDATE_ALLGOOD
	return s

// _compute_overlay() — derive the APC_UPOVERLAY_* bitfield from current APC state.
// Mirrors the original check_updates() logic precisely:
//   * APC_UPOVERLAY_OPERATING is set regardless of UPDATE_ALLGOOD.
//   * Locked/charging/channel overlays only apply when UPDATE_ALLGOOD is set.
/datum/apc_icon_renderer/proc/_compute_overlay(obj/machinery/power/apc/apc, state)
	var/o = 0

	// OPERATING flag is set outside the ALLGOOD guard in the original code.
	if(apc.operating)
		o |= APC_UPOVERLAY_OPERATING

	if(!(state & UPDATE_ALLGOOD))
		return o

	if(apc.locked)         o |= APC_UPOVERLAY_LOCKED

	// Charging indicator.
	switch(apc.charging)
		if(0) o |= APC_UPOVERLAY_CHARGEING0
		if(1) o |= APC_UPOVERLAY_CHARGEING1
		if(2) o |= APC_UPOVERLAY_CHARGEING2

	// Equipment indicator — mirrors the original if/else chain in check_updates().
	if(!apc.equipment)
		o |= APC_UPOVERLAY_EQUIPMENT0
	else if(apc.equipment == 1)
		o |= APC_UPOVERLAY_EQUIPMENT1
	else if(apc.equipment == 2)
		o |= APC_UPOVERLAY_EQUIPMENT2

	// Lighting indicator.
	if(!apc.lighting)
		o |= APC_UPOVERLAY_LIGHTING0
	else if(apc.lighting == 1)
		o |= APC_UPOVERLAY_LIGHTING1
	else if(apc.lighting == 2)
		o |= APC_UPOVERLAY_LIGHTING2

	// Environ indicator.
	if(!apc.environ)
		o |= APC_UPOVERLAY_ENVIRON0
	else if(apc.environ == 1)
		o |= APC_UPOVERLAY_ENVIRON1
	else if(apc.environ == 2)
		o |= APC_UPOVERLAY_ENVIRON2

	return o

// _apply_icon_state() — set icon_state based on UPDATE_* flags.
/datum/apc_icon_renderer/proc/_apply_icon_state(obj/machinery/power/apc/apc, state)
	if(state & UPDATE_ALLGOOD)
		apc.icon_state = "apc0"
		return

	if(state & (UPDATE_OPENED1 | UPDATE_OPENED2))
		var/basestate = "apc[(apc.cell ? "2" : "1")]"
		if(state & UPDATE_OPENED1)
			if(state & (UPDATE_MAINT | UPDATE_BROKE))
				apc.icon_state = "apcmaint"
			else
				apc.icon_state = basestate
		else
			apc.icon_state = "[basestate]-nocover"
		return

	if(state & UPDATE_BROKE)
		apc.icon_state = "apc-b"
		return
	if(state & UPDATE_WIREEXP)
		apc.icon_state = "apcewires"
		return
	if(state & UPDATE_BLUESCREEN)
		apc.icon_state = "apcemag"
		return

// _apply_overlays() — rebuild overlays based on UPDATE_* and APC state.
/datum/apc_icon_renderer/proc/_apply_overlays(obj/machinery/power/apc/apc, state, overlay_flags)
	apc.cut_overlays()
	if(!(state & UPDATE_ALLGOOD))
		return
	if(apc.stat & (BROKEN | MAINT))
		return

	var/list/new_overlays = list()
	new_overlays += mutable_appearance(apc.icon, "apcox-[apc.locked]")
	new_overlays += emissive_appearance(apc.icon, "apcox-[apc.locked]")
	new_overlays += mutable_appearance(apc.icon, "apco3-[apc.charging]")
	new_overlays += emissive_appearance(apc.icon, "apco3-[apc.charging]")
	if(apc.operating)
		new_overlays += mutable_appearance(apc.icon, "apco0-[apc.equipment]")
		new_overlays += emissive_appearance(apc.icon, "apco0-[apc.equipment]")
		new_overlays += mutable_appearance(apc.icon, "apco1-[apc.lighting]")
		new_overlays += emissive_appearance(apc.icon, "apco1-[apc.lighting]")
		new_overlays += mutable_appearance(apc.icon, "apco2-[apc.environ]")
		new_overlays += emissive_appearance(apc.icon, "apco2-[apc.environ]")
	apc.add_overlay(new_overlays)

// _apply_light() — set the APC's dynamic light based on state.
/datum/apc_icon_renderer/proc/_apply_light(obj/machinery/power/apc/apc, state)
	if(state & UPDATE_BLUESCREEN)
		apc.set_light(l_range = 2, l_power = 0.25, l_color = "#0000FF")
		return
	if((state & UPDATE_ALLGOOD) && !(apc.stat & (BROKEN | MAINT)))
		var/color
		switch(apc.charging)
			if(0) color = "#F86060"
			if(1) color = "#A8B0F8"
			if(2) color = "#82FF4C"
		apc.set_light(l_range = 2, l_power = 0.25, l_color = color)
		return
	apc.set_light(0)
