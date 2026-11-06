// runs_on_cell(draw =, ...): a machine that runs on a power cell in a slot (doc/rewrite/final_api.html, section 11 "The library"; the cell slot itself is
// cell_bay() or owns_one()). The capability owns the drain: while `when` holds (and the machine is operable) every `interval` it takes `draw` watts' worth
// of charge from the cell, and it keeps ONE tracked state var, `powered_var`, that says whether the cell can feed another step. That var is written only
// when it crosses (the cell is put in or taken out, a step finds the cell short, a charged cell is put in), never once per step, so a look or a
// condition that reads it is redrawn on the crossing and not on every drain.
//
//   runs_on_cell(draw = nameof(use), when = nameof(on), powered_var = nameof(cell_powered), on_lost = PROC_REF(power_lost))
//
// - `draw`: watts, a number or nameof(var) of a holder var; a step takes draw * CELLRATE.
// - `when`: the state the drain runs under (a holder var or stat); the drain also needs STAT_OPERABLE. Null: it runs whenever the machine is operable.
// - `cell_var`: the holder var that holds the cell (default nameof(cell)). `powered_var`: the holder's bool var the capability writes (default
//   "cell_powered"); the holder declares it (`var/cell_powered = FALSE`), and reads it like any tracked var.
// - `on_lost`: a holder proc x() run when the state crosses to unpowered (what a machine does when its cell cannot feed it: switch off, say). Nothing is
//   run when it crosses back: a machine that went off for want of charge stays off until something switches it on.
// - `after_draw`: a holder proc x(obj/item/cell/C) run after a step took its charge (an aesthetic that follows the drain: a light's flicker).
// cell_can_feed(holder) says whether the cell can feed a step now, read from the cell itself; cell_run_step(holder) is the step the timer runs.

CAPABILITY_TYPE(runs_on_cell, CAP_RUNS_ON_CELL, /datum/capability/lib/runs_on_cell, key = NONE, draw = 0, cell_var = "cell", powered_var = "cell_powered", when = null, interval = MACHINE_SERVICE_INTERVAL, on_lost = null, after_draw = null)

/datum/capability/lib/runs_on_cell
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/runs_on_cell/entries()
	return list(
		every(interval, then(CAP_PROC(run_step)), when = when ? all_of(when, STAT_OPERABLE) : STAT_OPERABLE),
		on_change(cell_var, ANY, then(CAP_PROC(cell_changed))))

/// The holder's cell is read once its starting contents exist.
/datum/capability/lib/runs_on_cell/on_holder_init(datum/act/eval/A)
	settle(A.holder, can_feed(A.holder))

/// Watts' worth of charge one step takes.
/datum/capability/lib/runs_on_cell/proc/step_amount(datum/holder)
	var/watts = istext(draw) ? holder.vars[draw] : draw
	return watts * CELLRATE

/// TRUE when the holder's cell holds enough to feed one step.
/datum/capability/lib/runs_on_cell/proc/can_feed(datum/holder)
	var/obj/item/cell/C = holder.vars[cell_var]
	return istype(C) && C.charge >= step_amount(holder)

/// Writes the powered state when it differs, and runs on_lost on a crossing to unpowered.
/datum/capability/lib/runs_on_cell/proc/settle(datum/holder, powered)
	powered = !!powered
	if(!!holder.vars[powered_var] == powered)
		return
	op_write_key(holder, powered_var, powered)
	log_world("RUNS_ON_CELL: [holder.type] [powered ? "has" : "lost"] cell power")
	if(!powered && on_lost)
		call(holder, on_lost)()

/// The cell was put in or taken out: the state follows it.
/datum/capability/lib/runs_on_cell/proc/cell_changed(datum/act/A)
	settle(A.holder, can_feed(A.holder))

/// The timer's step.
/datum/capability/lib/runs_on_cell/proc/run_step(datum/act/timer/A)
	feed_step(A.holder)

/// One step: a cell that cannot feed it crosses the state to unpowered; otherwise the step takes its charge.
/datum/capability/lib/runs_on_cell/proc/feed_step(datum/holder)
	if(!can_feed(holder))
		settle(holder, FALSE)
		return
	var/obj/item/cell/C = holder.vars[cell_var]
	C.use(step_amount(holder))
	settle(holder, TRUE)
	if(after_draw)
		call(holder, after_draw)(C)

/// TRUE when `holder`'s cell can feed one step of its runs_on_cell() draw (read from the cell; no cell, or a short one, is FALSE).
/proc/cell_can_feed(datum/holder)
	READS_FROM()
	var/datum/capability/lib/runs_on_cell/C = cap_of(holder, CAP_RUNS_ON_CELL)
	return !!C?.can_feed(holder)

/// Runs one step of `holder`'s cell drain now (the timer's own step).
/proc/cell_run_step(datum/holder)
	var/datum/capability/lib/runs_on_cell/C = cap_of(holder, CAP_RUNS_ON_CELL)
	C?.feed_step(holder)
