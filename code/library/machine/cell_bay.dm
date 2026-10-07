// A power-cell bay: content-typed entries over the engine's physical spaces and one-item var slots.

// ---- cell bay ----

CAPABILITY_TYPE(cell_bay, CAP_CELL_BAY, /datum/capability/lib/cell_bay, key = slot_var, slot_var = null, at = null, accepts = /obj/item/cell, starts = null, starts_args = null, fits = null)

/// A power cell slot over a holder var (`slot_var`, nameof(cell)), in space `at` when given: cell_bay.<var>.insert (a cell in hand goes in, when
/// it `fits`: size_is(ITEMSIZE_NORMAL)) and cell_bay.<var>.take (an empty hand takes it out). Both are placed at(at), so the path decides: a
/// closed door sets them aside for whatever else the click means, and refuses with its reason when nothing else does. The cell shows through
/// an open cover (a look layer), examine says what it holds, and cell_charge_percent() reads its charge through the bay. `starts` (any starts =
/// form of section 6, with starts_args) fills the bay when the holder initializes.
/datum/capability/lib/cell_bay
	holder_hooks = HOLDER_HOOK_INIT

MSG_DEF_SELF(cell_bay/missing, "The power cell is missing.")

/datum/capability/lib/cell_bay/entries()
	var/list/entries = list()
	var/list/at_space = list()
	var/visible = slot_var
	if(!isnull(at))
		entries += entry_make(ENTRY_SPACE_SLOT, null, list("var" = slot_var, "space" = at))
		at_space += global.at(at)
		// every space a cell bay sits in today is behind a cover: the cell shows while the cover is open and on
		visible = cond_all(slot_var, COVER_OPEN, cond_not(COVER_REMOVED))
	entries += op("insert", item(accepts), put_in(slot_var), at_space, fits ? needs(fits) : null)
	entries += op("take", hand(), ungated(), when(slot_var), take_out(slot_var), at_space)
	entries += look_layer(LOOK_CELL, when = visible)
	entries += examine_line(CAP_PROC(examine_cell), reads = list(slot_var))
	return entries

/// The charge meter (or the missing cell, when the bay can be seen into).
/datum/capability/lib/cell_bay/proc/examine_cell(datum/act/A)
	var/obj/item/cell/C = A.holder.vars[slot_var]
	if(!istype(C))
		var/atom/holder = A.holder
		return (!isnull(at) && istype(holder) && isnull(holder.space_reason(at, AUTH_PHYSICAL))) ? "The power cell is missing." : null
	return "The charge meter reads [round(C.percent())]%."

/// The bay starts with a thing when its holder initializes: any starts = form (starts_make(): a type, nameof(var) of a holder var holding one,
/// pick_one(), when(cond, T), PROC_REF(x)) with starts_args. A var a mapper already filled keeps what it holds.
/datum/capability/lib/cell_bay/on_holder_init(datum/act/eval/A)
	var/atom/holder = A.holder
	if(isnull(starts) || !istype(holder) || !isnull(holder.vars[slot_var]))
		return
	for(var/atom/movable/thing in starts_make(holder, starts, starts_args, holder))
		if(isnull(holder.vars[slot_var]))
			varslot_set(holder, slot_var, thing)
		else
			qdel(thing) // ALLOW(lifecycle): a one-item bay keeps the first thing a list-valued starts made; the rest were never placed

/datum/capability/lib/cell_bay/output_reads(hook)
	return list(slot_var)

/// The charge of A's cell bay in percent: 0 with no cell (never null).
/proc/cell_charge_percent(atom/A)
	READS_FROM()
	var/datum/type_table/T = table_of(A)
	for(var/key in T.caps)
		var/datum/capability/lib/cell_bay/bay = T.caps[key]
		if(istype(bay) && bay.cap_id == CAP_CELL_BAY)
			var/obj/item/cell/cell = A.vars[bay.slot_var]
			return istype(cell) ? cell.percent() : 0
	return 0
