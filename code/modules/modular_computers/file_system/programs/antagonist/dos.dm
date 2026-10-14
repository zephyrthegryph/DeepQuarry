/datum/computer_file/program/ntnet_dos
	filename = "ntn_dos"
	filedesc = "DoS Traffic Generator"
	program_icon_state = "hostile"
	program_key_state = "security_key"
	program_menu_icon = "arrow-4-diag"
	extended_desc = "This advanced script can perform denial of service attacks against NTNet quantum relays. The system administrator will probably notice this. Multiple devices can run this program together against same relay for increased effect"
	size = 20
	requires_ntnet = TRUE
	available_on_ntnet = FALSE
	available_on_syndinet = TRUE

	var/tmp/obj/machinery/ntnet_relay/target
	var/dos_speed = 0
	var/error = ""
	var/executed = 0

/datum/computer_file/program/ntnet_dos/process_tick()
	dos_speed = 0
	switch(ntnet_status)
		if(1)
			dos_speed = NTNETSPEED_LOWSIGNAL * NTNETSPEED_DOS_AMPLIFICATION
		if(2)
			dos_speed = NTNETSPEED_HIGHSIGNAL * NTNETSPEED_DOS_AMPLIFICATION
		if(3)
			dos_speed = NTNETSPEED_ETHERNET * NTNETSPEED_DOS_AMPLIFICATION
	if(target() && executed)
		target().dos_overload += dos_speed
		if(!target().operable())
			rel_remove(target(), nameof(/obj/machinery/ntnet_relay::dos_sources), src)
			rel_clear(src, nameof(target))
			error = "Connection to destination relay lost."

/datum/computer_file/program/ntnet_dos/kill_program(forced)
	if(target())
		rel_remove(target(), nameof(/obj/machinery/ntnet_relay::dos_sources), src)
		rel_clear(src, nameof(target))
	executed = 0

	..(forced)

CAPABILITIES(/datum/computer_file/program/ntnet_dos)
	interface("NtosNetDos")
	op("PRG_target_relay", ui_act("PRG_target_relay", arg("targid", num())), then(PROC_REF(ui_act_prg_target_relay)))
	op("PRG_reset", ui_act("PRG_reset"), then(PROC_REF(ui_act_prg_reset)))
	op("PRG_execute", ui_act("PRG_execute"), then(PROC_REF(ui_act_prg_execute)))

/datum/computer_file/program/ntnet_dos/ui_data(datum/act/eval/A)
	if(!GLOB.ntnet_global)
		return

	var/list/data = get_header_data()
	data["error"] = error

	if(target() && executed)
		data["target"] = TRUE
		data["speed"] = dos_speed

		data["overload"] = target().dos_overload
		data["capacity"] = target().dos_capacity
	else
		data["target"] = FALSE
		data["relays"] = list()
		for(var/obj/machinery/ntnet_relay/R in GLOB.ntnet_global.relays)
			data["relays"] += list(list("id" = R.uid))
		data["focus"] = target() ? target().uid : null

	return data

/datum/computer_file/program/ntnet_dos/proc/ui_act_prg_target_relay(datum/act/op/A, targid)
	for(var/obj/machinery/ntnet_relay/R in GLOB.ntnet_global.relays)
		if(R.uid == targid)
			rel_set(src, nameof(src.target), R)
			break
	return TRUE

/datum/computer_file/program/ntnet_dos/proc/ui_act_prg_reset(datum/act/op/A)
	if(target())
		rel_remove(target(), nameof(/obj/machinery/ntnet_relay::dos_sources), src)
		rel_clear(src, nameof(src.target))
	executed = FALSE
	error = ""
	return TRUE

/datum/computer_file/program/ntnet_dos/proc/ui_act_prg_execute(datum/act/op/A)
	if(target())
		executed = TRUE
		rel_add(target(), nameof(/obj/machinery/ntnet_relay::dos_sources), src)
		if(GLOB.ntnet_global.intrusion_detection_enabled)
			var/obj/item/computer_hardware/network_card/network_card = computer().network_card
			GLOB.ntnet_global.add_log("IDS WARNING - Excess traffic flood targeting relay [target().uid] detected from device: [network_card.get_network_tag()]")
			GLOB.ntnet_global.intrusion_detection_alarm = TRUE
	return TRUE

/// The target this refers to (a relation view: null once that is deleted).
/datum/computer_file/program/ntnet_dos/proc/target() as /obj/machinery/ntnet_relay
	return target
