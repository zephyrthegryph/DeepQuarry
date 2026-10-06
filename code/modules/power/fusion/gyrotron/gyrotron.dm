// The gyrotron: an emitter suited for heating a fusion core's field (doc/rewrite/final_api.html section 16). It fires every `rate` seconds at a
// beam power its console sets (set_beam_power()), takes a part replacer, and a multitool sets the ident tag its console finds it by.

/obj/machinery/power/emitter/gyrotron
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "gyrotron"
	icon = 'icons/obj/machines/power/fusion.dmi'
	desc = "It is a heavy duty industrial gyrotron suited for powering fusion reactors."
	icon_state = "emitter-off"
	req_access = list(ACCESS_ENGINE)
	use_power = USE_POWER_IDLE
	active_power_usage = 50000

	circuit = /obj/item/circuitboard/gyrotron

	var/id_tag
	var/rate = 3
	var/mega_energy = 1

/obj/machinery/power/emitter/gyrotron/anchored
	anchored = TRUE
	state = FLOOR_WELD_WELDED

TRACKED(/obj/machinery/power/emitter/gyrotron, id_tag)

CAPABILITIES(/obj/machinery/power/emitter/gyrotron)
	registry(REGISTRY_GYROTRONS, key = nameof(id_tag))
	part_replacement()
	op("set_ident", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0), when(cond_not(nameof(anomalous))),
		asks(/datum/prompt/text, fields = list("title" = "Gyrotron", "question" = "Enter a new ident tag.", "default" = nameof(id_tag), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(ident_entered)))

/obj/machinery/power/emitter/gyrotron/Initialize(mapload)
	default_apply_parts()
	return ..()

/obj/machinery/power/emitter/gyrotron/proc/ident_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	var/new_ident = answer?.value
	if(!new_ident || !A.actor?.Adjacent(src))
		return OP_REFUSED
	set_id_tag(new_ident)
	return OP_OK

/obj/machinery/power/emitter/gyrotron/proc/set_beam_power(new_power)
	mega_energy = new_power
	update_active_power_usage(mega_energy * initial(active_power_usage))

/obj/machinery/power/emitter/gyrotron/get_rand_burst_delay()
	return rate * 10

/obj/machinery/power/emitter/gyrotron/get_burst_delay()
	return rate * 10

/obj/machinery/power/emitter/gyrotron/get_emitter_beam()
	var/obj/item/projectile/beam/emitter/E = ..()
	E.damage = mega_energy * 50
	return E

/obj/machinery/power/emitter/gyrotron/emitter_look(datum/look/look)
	look.state((active && power_region && avail(active_power_usage)) ? "emitter-on" : "emitter-off")
