// E3, stats: the gate fixtures of doc/rewrite/final_api.html section 19 "E3, stats" (code/modules/unit_tests/dq_e3_stats_tests.dm).
//
// /obj/e3_rules carries one stat of each combine rule, and a FORMULA that reads one of them. /obj/e3_machine is the gated-contribution case
// (operable from broken, draw from on) and a status. /obj/e3_apc and /obj/e3_load are the fan-out of the spike: one channel var, 50 readers.
// /obj/e3_wire contributes to the stat of the entity its relation names.

/// Every rule once, so a table-driven test reads each one's base value, tie-break and override.
/obj/e3_rules
	name = "e3 rules"
	var/e3_seed = 1

STAT(/obj/e3_rules, e3_all, ALL)
STAT(/obj/e3_rules, e3_any, ANY)
STAT(/obj/e3_rules, e3_sum, SUM)
STAT(/obj/e3_rules, e3_product, PRODUCT)
STAT(/obj/e3_rules, e3_max, MAX)
STAT(/obj/e3_rules, e3_min, MIN)
STAT(/obj/e3_rules, e3_top, TOP)
STAT(/obj/e3_rules, e3_set, SET)
STAT(/obj/e3_rules, e3_mask_and, MASK_AND, base = 15)
STAT(/obj/e3_rules, e3_mask_or, MASK_OR)
STAT(/obj/e3_rules, e3_keyed, SUM_PER_KEY)
STAT(/obj/e3_rules, e3_formula, FORMULA, formula = PROC_REF(compute_formula), reads = list("e3_seed", "e3_sum"))

TRACKED(/obj/e3_rules, e3_seed)

/obj/e3_rules/proc/compute_formula(datum/act/A)
	return e3_seed * 2 + e3_sum

/// A machine whose stats come from its own state: operable is not broken, draw is 2 while idle and 10 more while on, can_run reads operable.
/obj/e3_machine
	name = "e3 machine"
	var/broken = FALSE
	var/e3_on = FALSE

STAT(/obj/e3_machine, e3_operable, ALL)
STAT(/obj/e3_machine, e3_draw, SUM)
STAT(/obj/e3_machine, e3_can_run, ALL)
STAT(/obj/e3_machine, e3_stun, MAX, base = 0, units = LIFE_CYCLE, reapply = REAPPLY_MAX)

TRACKED(/obj/e3_machine, broken)
TRACKED(/obj/e3_machine, e3_on)

CAPABILITIES(/obj/e3_machine)
	contributes(STAT_E3_OPERABLE, cond_not(nameof(broken)))
	contributes(STAT_E3_DRAW, 2)
	when(nameof(e3_on), contributes(STAT_E3_DRAW, 10))
	contributes(STAT_E3_CAN_RUN, STAT_E3_OPERABLE)
	immune_to(STATUS_E3_STUN, when = nameof(broken))

/// An immune subtype: always.
/obj/e3_machine/stoic
	name = "e3 stoic machine"

CAPABILITIES(/obj/e3_machine/stoic)
	immune_to(STATUS_E3_STUN)

/// A thing that is only a source of holds (a datum or an object, both work).
/obj/e3_source
	name = "e3 source"

/// The fan-out of the spike: an APC channel read by its loads through a relation.
/obj/e3_apc
	name = "e3 apc"
	var/channel_on = TRUE
	var/list/loads

TRACKED(/obj/e3_apc, channel_on)

CAPABILITIES(/obj/e3_apc)
	ref_many(nameof(loads), /obj/e3_load)

/obj/e3_load
	name = "e3 load"
	var/obj/e3_apc/apc

STAT(/obj/e3_load, e3_powered, ALL)

CAPABILITIES(/obj/e3_load)
	ref_one(nameof(apc), /obj/e3_apc)
	contributes(STAT_E3_POWERED, PROC_REF(apc_channel), reads = list("apc.channel_on"))

/obj/e3_load/proc/apc_channel(datum/act/A)
	return apc ? apc.channel_on : TRUE

/// Contributes to the stat of what its relation names (a single-valued edge: inline).
/obj/e3_wire
	name = "e3 wire"
	var/obj/e3_machine/plugged
	var/live = TRUE

TRACKED(/obj/e3_wire, live)

CAPABILITIES(/obj/e3_wire)
	ref_one(nameof(plugged), /obj/e3_machine)
	when(nameof(live), contributes_to(nameof(plugged), STAT_E3_DRAW, 7))

/// A real machine, for the base stats declared on /obj/machinery.
/obj/machinery/e3_probe
	name = "e3 probe"
