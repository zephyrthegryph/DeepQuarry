
/obj/cap_fixture/meter
	var/obj/item/cell/cell
	var/level = 1
	var/emp_disabled = FALSE

/obj/item/cell
	var/charge = 0
	var/maxcharge = 100
	var/rigged = FALSE
	var/sealed = FALSE
	var/label_text
TRACKED(/obj/item/cell, charge)
SETTER(/obj/item/cell, sealed)

/obj/item/cell/proc/set_label_text(value)
	label_text = value

/obj/cap_fixture/meter/draw(datum/look/look)
	..()
	look.gauge("charge", cell.charge / 100)
	look.overlay("rigged", when = cell.rigged)
	look.overlay("sealed", when = cell.sealed)
	look.overlay("label", when = cell.label_text)
	look.state(level ? "on" : "off")

/obj/cap_fixture/meter/should_run()
	return cell?.maxcharge > 0 && src.level

/obj/cap_fixture/meter/proc/has_cell(mob/user)
	return cell.rigged

/obj/cap_fixture/meter/proc/can_pour(mob/user, obj/item/held)
	var/datum/capability/meter/C = cap_of(src, /datum/capability/meter)
	var/datum/meter_data/D = cap_data?[C.key]
	var/datum/meter_data/E = src.cap_data?[C.key]
	if(E.pours)
		return FALSE
	if(held.force || C.max_pours <= D.pours)
		return FALSE
	var/datum/reagents/R = reagents
	var/datum/construction_ladder/built = ladder_for(src)
	var/datum/ladder_stage/stage = built.stage_named("x")
	for(var/datum/capability/K as anything in caps_all(src))
		if(K.cadence && stage.icon && R.total_volume && initial(cell.charge))
			return TRUE
	return reagents?.total_volume > 0

/obj/cap_fixture/meter/capabilities()
	. = ..()
	. += cap_slot(nameof(cell), /obj/item/cell, needs = PROC_REF(has_cell))
	. += cap_hand("Pour", PROC_REF(pour), needs = PROC_REF(can_pour))
	. += cap_gauge(level = level)
	. += cap_lock(access = src.req_access)
	. += cap_panel(name = "panel")
	var/list/extra = list()
	. += extra

/datum/capability/meter/draw(atom/holder, datum/look/look)
	var/obj/cap_fixture/meter/M = holder
	var/obj/item/cell/C = M.cell
	look.overlay("x", when = holder.level)
	look.overlay("y", when = M.level)
	look.overlay("z", when = "[holder.cell.charge]")
	look.overlay("w", when = C.rigged)

/datum/capability/meter/gate(atom/holder, mob/user, datum/interaction/entry)
	var/datum/interaction/capability/E = entry
	if(user.stat || entry.behind || E.cap)
		return "no"

/datum/capability/meter/ui_data(atom/holder, mob/user, list/data)
	var/list/rows = list()
	rows += "x"
	data["rows"] = rows
	for(var/i = 1, i <= 3, i++)
		rows[i] = i
	holder.last_ui = world.time
	last_holder = holder
	changed(holder)
	holder.verbs.Remove(/obj/proc/x)
	look_like(value = 1)
	rows.Cut(1, 2)
	holder.set_dir(NORTH)

/obj/cap_fixture/meter/tgui_data(mob/user)
	. = ..()
	.["level"] = level
	. += list("x" = 1)
	level++
	src.cell.set_charge(5)
	if(level == 2)
		return

/obj/cap_fixture/meter/proc/zap()
	timed_set(src, nameof(emp_disabled), TRUE, for_time = 10 SECONDS)
	emp_disabled = FALSE

/obj/cap_fixture/meter/proc/set_emp_disabled(value)
	emp_disabled = value

/obj/cap_fixture/meter/proc/other(obj/cap_fixture/meter/M)
	M.emp_disabled = TRUE
	var/emp_disabled = 3
	emp_disabled = 4
