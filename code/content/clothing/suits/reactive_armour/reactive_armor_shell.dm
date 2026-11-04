/obj/item/clothing/suit/armor/reactive_armor_shell
	name = "reactive armor shell"
	desc = "An experimental suit of armor, awaiting installation of an anomaly core."
	icon_state = "reactiveoff"
	w_class = ITEMSIZE_COST_LARGE
	resistance_flags = FIRE_PROOF | UNACIDABLE

CAPABILITIES(/obj/item/clothing/suit/armor/reactive_armor_shell)
	op("reactive_shell_insert_core", item(/obj/item/assembly/signaler/anomaly), label("Insert anomaly core"), then(PROC_REF(reactive_shell_insert_core)))

/// Old attackby: install an anomaly core.
/obj/item/clothing/suit/armor/reactive_armor_shell/proc/reactive_shell_insert_core(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/static/list/anomaly_armour_types = list(
		/obj/effect/anomaly/grav = /obj/item/clothing/suit/armor/reactive/repulse,
		/obj/effect/anomaly/flux = /obj/item/clothing/suit/armor/reactive/tesla,
		/obj/effect/anomaly/bluespace = /obj/item/clothing/suit/armor/reactive/teleport,
		//obj/effect/anomaly/bioscrambler = /obj/item/clothing/suit/armor/reactive/bioscrambling,
		/obj/effect/anomaly/hallucination = /obj/item/clothing/suit/armor/reactive/hallucinating,
		/obj/effect/anomaly/dimensional = /obj/item/clothing/suit/armor/reactive/barricade,
		/obj/effect/anomaly/pyro = /obj/item/clothing/suit/armor/reactive/fire,
		/obj/effect/anomaly/weather = /obj/item/clothing/suit/armor/reactive/weather
	)

	if(istype(I, /obj/item/assembly/signaler/anomaly))
		var/obj/item/assembly/signaler/anomaly/anomaly = I
		var/armour_path = is_path_in_list(anomaly.anomaly_type, anomaly_armour_types, TRUE)
		if(!armour_path)
			armour_path = /obj/item/clothing/suit/armor/reactive/stealth
		var/anomaly_name = "[anomaly]"
		if(!consume(anomaly, user))
			return TRUE
		to_chat(user, span_notice("You insert [anomaly_name] into the chest plate, and the armour gently hums to life."))
		replace_with(src, armour_path)
		return TRUE
	return OP_DECLINE
