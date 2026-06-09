// /datum/apc_power_distributor
//
// Encapsulates channel state-machine logic, cell-charging mathematics,
// and load-tracking for an APC.  The APC itself delegates all of those
// concerns here and remains a thin shell that owns interaction, icons,
// and the terminal lifecycle.
//
// Design invariants
//   * This datum holds NO direct references to atoms other than the
//     owning APC back-ref.  All area/terminal/cell access goes through apc.
//   * tick() is the only proc that mutates channel state.
//   * autoset() is a pure function (no side-effects).

// ADIST_CHANGED_CHANNELS and ADIST_CHANGED_CHARGING are defined in code/__defines/apc.dm.

/datum/apc_power_distributor
	/// Back-reference to the owning APC — set once in New(), never changed.
	var/obj/machinery/power/apc/apc = null

	/// Channel states — mirrors vars on the APC for external readers.
	var/lighting  = POWERCHAN_ON_AUTO
	var/equipment = POWERCHAN_ON_AUTO
	var/environ   = POWERCHAN_ON_AUTO

	/// Cell-charge bookkeeping.
	var/charging    = 0  ///< 0 = not charging, 1 = charging, 2 = full
	var/chargemode  = 1  ///< 1 = auto-charge enabled, 0 = disabled
	var/chargecount = 0  ///< consecutive ticks above charge threshold

	/// Long-term power trend (+= surplus ticks, -= deficit ticks).
	/// Positive = sustained surplus, negative = sustained deficit.
	var/longtermpower = 10

	/// Per-tick load samples, refreshed each process() call.
	var/lastused_light    = 0
	var/lastused_equip    = 0
	var/lastused_environ  = 0
	var/lastused_charging = 0
	var/lastused_total    = 0

	/// External-power status for TGUI / icon rendering.
	var/main_status = APC_EXTERNAL_POWER_NOTCONNECTED

	/// Shedding tier currently active (prevents repeated alarm triggers).
	var/autoflag = 0

/datum/apc_power_distributor/New(obj/machinery/power/apc/owner)
	apc = owner

/datum/apc_power_distributor/Destroy()
	apc = null
	return ..()

/// reset() — restore default state.  Called by APC.reboot().
/datum/apc_power_distributor/proc/reset()
	lighting  = POWERCHAN_ON_AUTO
	equipment = POWERCHAN_ON_AUTO
	environ   = POWERCHAN_ON_AUTO
	charging    = 0
	chargemode  = 1
	chargecount = 0
	autoflag    = 0
	longtermpower = 10
	lastused_light    = 0
	lastused_equip    = 0
	lastused_environ  = 0
	lastused_charging = 0
	lastused_total    = 0
	main_status = APC_EXTERNAL_POWER_NOTCONNECTED

/// set_channel() — update a single channel from a TGUI action.
/// chan: "eqp" | "lgt" | "env"
/// val: raw numeric value from TGUI params (text or number)
/datum/apc_power_distributor/proc/set_channel(chan, val)
	var/sanitised = setsubsystem(text2num(val))
	switch(chan)
		if("eqp") equipment = sanitised
		if("lgt") lighting  = sanitised
		if("env") environ   = sanitised

/// setsubsystem() — maps a UI-requested value to a valid POWERCHAN_* constant.
/// Pure function: no side-effects.
/datum/apc_power_distributor/proc/setsubsystem(val)
	if(apc.cell && apc.cell.charge > 0)
		return (val == 1) ? POWERCHAN_OFF : val
	else if(val == POWERCHAN_ON_AUTO)
		return POWERCHAN_OFF_AUTO
	else
		return POWERCHAN_OFF

/// autoset() — pure state-machine transition helper.
/// cur_state : current POWERCHAN_* value
/// on        : 0 = force off, 1 = allow on, 2 = auto-off
/// Returns the new POWERCHAN_* value (may be unchanged).
/datum/apc_power_distributor/proc/autoset(cur_state, on)
	switch(cur_state)
		if(POWERCHAN_OFF_AUTO)
			if(on == 1)
				return POWERCHAN_ON_AUTO
		if(POWERCHAN_ON)
			if(on == 0)
				return POWERCHAN_OFF
		if(POWERCHAN_ON_AUTO)
			if(on == 0 || on == 2)
				return POWERCHAN_OFF_AUTO
	return cur_state

/// attempt_charging() — TRUE if the APC should trickle-charge the cell this tick.
/datum/apc_power_distributor/proc/attempt_charging()
	return (chargemode && charging == 1 && apc.operating)

/// tick() — the main per-tick logic.
/// Called from APC.process() after broken/failure-timer early-exits.
/// Returns a ADIST_CHANGED_* bitfield indicating what changed so the APC
/// can decide whether to queue an icon update.
/datum/apc_power_distributor/proc/tick()
	var/area/A = apc.area

	// Sample area load from the last tick.
	lastused_light   = A.usage(LIGHT, lighting  >= POWERCHAN_ON)
	lastused_equip   = A.usage(EQUIP, equipment >= POWERCHAN_ON)
	lastused_environ = A.usage(ENVIRON, environ >= POWERCHAN_ON)
	A.clear_usage()
	lastused_total = lastused_light + lastused_equip + lastused_environ

	// Snapshot pre-tick channel states for change detection.
	var/last_lt = lighting
	var/last_eq = equipment
	var/last_en = environ
	var/last_ch = charging

	var/excess = apc.surplus()

	// Update external-power status.
	if(!apc.avail())
		main_status = APC_EXTERNAL_POWER_NOTCONNECTED
	else if(excess < 0)
		main_status = APC_EXTERNAL_POWER_NOENERGY
	else
		main_status = APC_EXTERNAL_POWER_GOOD

	if(apc.cell && !apc.shorted && !apc.grid_check)
		_process_with_cell(excess)
	else
		_process_no_cell()

	// Build and return change bitfield.
	var/changed = 0
	if(last_lt != lighting || last_eq != equipment || last_en != environ)
		changed |= ADIST_CHANGED_CHANNELS
	if(last_ch != charging)
		changed |= ADIST_CHANGED_CHARGING
	return changed

/// _process_with_cell() — normal operating path (cell present).
/datum/apc_power_distributor/proc/_process_with_cell(excess)
	var/obj/item/cell/C = apc.cell

	// Draw from cell to cover last tick's load (capped to cell charge).
	var/cellused = min(C.charge, CELLRATE * lastused_total)
	C.use(cellused)

	if(excess > lastused_total)
		// Grid has plenty — reimburse the cell for what was drawn.
		var/draw = apc.draw_power(cellused / CELLRATE)
		C.give(draw * CELLRATE)
	else
		if((C.charge / CELLRATE + excess) >= lastused_total)
			// Cell + grid covers this tick's demand.
			var/draw = apc.draw_power(excess)
			C.charge = min(C.maxcharge, C.charge + CELLRATE * draw)
			charging = 0
		else
			// Not enough combined power — shed all auto-channels.
			charging  = 0
			chargecount = 0
			equipment = autoset(equipment, 0)
			lighting  = autoset(lighting,  0)
			environ   = autoset(environ,   0)
			autoflag  = 0

	// Apply load-shedding policy based on cell percent + trend.
	_update_channels()

	// Trickle-charge pass.
	lastused_charging = 0
	if(attempt_charging())
		if(excess > 0)
			var/ch = min(excess * CELLRATE, C.maxcharge * apc.chargelevel)
			ch = apc.draw_power(ch / CELLRATE)
			C.give(ch * CELLRATE)
			lastused_charging = ch
			lastused_total    += ch  // sensors need this to not report APC charging as "Other"
		else
			charging  = 0
			chargecount = 0

	// Mark full if capped.
	if(C.charge >= C.maxcharge)
		C.charge = C.maxcharge
		charging = 2

	// Advance chargecount; start charging once sustained surplus detected.
	if(chargemode)
		if(!charging)
			if(excess > C.maxcharge * apc.chargelevel)
				chargecount++
			else
				chargecount = 0
			if(chargecount >= 10)
				chargecount = 0
				charging = 1
	else
		charging    = 0
		chargecount = 0

/// _process_no_cell() — no cell installed; shed all loads and trigger alarm.
/datum/apc_power_distributor/proc/_process_no_cell()
	charging    = 0
	chargecount = 0
	equipment = autoset(equipment, 0)
	lighting  = autoset(lighting,  0)
	environ   = autoset(environ,   0)
	GLOB.power_alarm.triggerAlarm(apc.loc, apc, hidden = apc.alarms_hidden)
	autoflag = 0

/// _update_channels() — apply shedding tiers based on cell level + long-term trend.
/datum/apc_power_distributor/proc/_update_channels()
	if(charging && longtermpower < 10)
		longtermpower += 1
	else if(longtermpower > -10)
		longtermpower -= 2

	var/cpct = apc.cell.percent()

	if((cpct > 30) || longtermpower > 0)
		if(autoflag != 3)
			equipment = autoset(equipment, 1)
			lighting  = autoset(lighting,  1)
			environ   = autoset(environ,   1)
			autoflag  = 3
			GLOB.power_alarm.clearAlarm(apc.loc, apc)

	else if((cpct <= 30) && (cpct > 15) && longtermpower < 0)
		if(autoflag != 2)
			equipment = autoset(equipment, 2)
			lighting  = autoset(lighting,  1)
			environ   = autoset(environ,   1)
			GLOB.power_alarm.triggerAlarm(apc.loc, apc, hidden = apc.alarms_hidden)
			autoflag = 2

	else if(cpct <= 15)
		if((autoflag > 1 && longtermpower < 0) || (autoflag > 1 && longtermpower >= 0))
			equipment = autoset(equipment, 2)
			lighting  = autoset(lighting,  2)
			environ   = autoset(environ,   1)
			GLOB.power_alarm.triggerAlarm(apc.loc, apc, hidden = apc.alarms_hidden)
			autoflag = 1

	else
		if(autoflag != 0)
			equipment = autoset(equipment, 0)
			lighting  = autoset(lighting,  0)
			environ   = autoset(environ,   0)
			GLOB.power_alarm.triggerAlarm(apc.loc, apc, hidden = apc.alarms_hidden)
			autoflag = 0

// ADIST_CHANGED_* defines live in code/__defines/apc.dm and are not undef'd here.
