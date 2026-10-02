/obj/machinery/gadget
	var/obj/item/cell/battery
	var/obj/machinery/other/partner
	var/power = 0
	var/list/cache = list()

/obj/machinery/other
	var/zap = 0
	var/zing = 1
	var/watched_rel
	var/plain_rel

REL_ONE(/obj/machinery/gadget, partner_rel, WATCH_ALWAYS)
REL_MANY(/obj/machinery/gadget, plain_rel2, 0)
TRACKED_BRIDGED(/obj/machinery/other, zing)

/obj/machinery/gadget/proc/watch_setup()
	rel(nameof(foo_rel), src, watch = TRUE)
	rel(nameof(src.bar_rel), src, 0)

/obj/machinery/gadget/tgui_data(mob/user)
	. = ..()
	.["a"] = partner.zap
	.["b"] = src.power
	.["c"] = battery.charge
	.["d"] = partner_rel.zap
	.["d2"] = foo_rel.zap
	.["d3"] = bar_rel.zap
	.["e"] = reagents.total_volume
	.["f"] = SSair.times
	.["g"] = MAX_THING.x
	.["h"] = GLOB.some_list.len
	.["i"] = GLOB.thing_list.entries
	.["j"] = partner.battery.zap2
	.["k"] = src.partner.zap
	.["l"] = user.client.view
	.["m"] = get_area(src).power_equip
	.["n"] = partner?.zap
	.["o"] = partner.verbs_len()
	.["p"] = initial(partner.zap)
	.["q"] = "[partner.zing]"
	.["q2"] = "[partner.plain_rel]"
	.["r"] = "partner.zing in text"
	// partner.zap in a comment
	/* partner.zap in a block comment */
	var/obj/machinery/gadget/G = src
	.["s"] = G.power
	var/obj/machinery/other/O = partner
	.["t"] = O.zap
	var/datum/capability/thing/C = cap_of(src, 1)
	.["u"] = C.cadence
	var/datum/x/D = cap_data?[1]
	.["v"] = D.pours
	var/datum/x/R2 = reagents
	.["w"] = R2.total_volume
	var/datum/x/E = C.thing
	.["x"] = E.y
	.["y"] = world.time + usr.x + callee.y + state.z + data.k + ui.u + entry.e + held.h + config.c
	.["z"] = partner.zap // ALLOW(sys_dx_untracked_read): fixture keeps this one
	// ALLOW(sys_dx_untracked_read): fixture keeps the next one
	.["z2"] = partner.zap
	.["z3"] = a.b.c.d
	.["z4"] = src.a.b
	.["z5"] = partner.type + partner.parent_type
	.["z6"] = partner . zap
	.["z7"] = partner ?. zap

/obj/machinery/gadget/capabilities()
	. = ..()
	. += cap_hand("X", PROC_REF(do_x), needs = PROC_REF(check_it))
	. += cap_hand("Y", PROC_REF(do_y), needs = TYPE_PROC_REF(/obj/machinery/gadget, check_that))
	. += cap_hand("Z", PROC_REF(do_z), needs = GLOBAL_PROC_REF(not_a_needs))

/obj/machinery/gadget/proc/check_it(mob/user)
	return partner.zap > 0 && power

/obj/machinery/gadget/proc/check_that(mob/user)
	return partner.zing || partner.zap

/obj/machinery/gadget/proc/not_a_needs()
	return partner.zap

/datum/capability/gizmo/draw(atom/holder, datum/look/look)
	look.overlay("a", when = holder.power)
	look.overlay("b", when = holder.partner.zap)
	look.overlay("c", when = cadence)
	look.overlay("d", when = other.var)
	look.overlay("e", when = look.thing)

/datum/capability/gizmo/examine(atom/holder, mob/user)
	return "[holder.power] [partner.zap]"

/datum/capability/gizmo/hidden_verbs(atom/holder)
	return list(holder.a, holder.b.c, peer.d)

/datum/capability/gizmo/helper(atom/holder)
	return partner.zap

/datum/capability/gizmo/tgui_data(atom/holder)
	return partner.zap

/datum/capability/gizmo/gate(atom/holder, mob/user, datum/interaction/entry)
	var/datum/x/S = holder.cap_data[1]
	var/datum/y/T = holder.cap_data?[2]
	return S.q + T.r + holder.cap_data.z

/obj/machinery/gadget/draw(mob/user)
	return partner.zap

/obj/machinery/gadget/draw(datum/look/L)
	return partner.zap

/obj/machinery/gadget/draw(mob/looker)
	return partner.zap

/obj/machinery/gadget/draw(look)
	return partner.zap

/obj/item/thing/should_run()
	return partner.zap

/mob/living/hidden_verbs()
	return list(a.b)

/obj/machinery/gadget/tgui_data(
		mob/user, ui)
	return peer.stat

/obj/machinery/gadget/proc/other_proc()
	return partner.zap
