/obj/item/rig_module/datajack

	name = "datajack module"
	desc = "A simple induction datalink module."
	icon_state = "datajack"
	toggleable = 1
	activates_on_touch = 1
	usable = 0

	activate_string = "Enable Datajack"
	deactivate_string = "Disable Datajack"

	interface_name = "contact datajack"
	interface_desc = "An induction-powered high-throughput datalink suitable for hacking encrypted networks."
	var/list/stored_research

/obj/item/rig_module/datajack/Initialize(mapload)
	. = ..()
	stored_research = list()

/obj/item/rig_module/datajack/engage(atom/target)

	if(!..())
		return 0

	if(target)
		var/mob/living/carbon/human/H = holder.wearer
		if(!accepts_item(target,H))
			return 0
	return 1

/obj/item/rig_module/datajack/accepts_item(obj/item/input_device, mob/living/user)

	// I fucking hate R&D code. This typecheck spam would be totally unnecessary in a sane setup. Sanity? This is BYOND.
	// else if(istype(input_device,/obj/machinery))
	// 	var/datum/research/incoming_files
	// 	if(istype(input_device,/obj/machinery/computer/rdconsole) ||
	// 		istype(input_device,/obj/machinery/r_n_d/server) ||
	// 		istype(input_device,/obj/machinery/mecha_part_fabricator))

	// 		incoming_files = input_device:files

	return 0

/obj/item/rig_module/datajack/proc/load_data(incoming_data)

	if(islist(incoming_data))
		for(var/entry in incoming_data)
			load_data(entry)
		return 1

	return 0
