/obj/item/implant/integrated_circuit
	name = "electronic implant"
	desc = "It's a case, for building very tiny electronics with."
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_implant"
	var/obj/item/electronic_assembly/implant/IC = null

/obj/item/implant/integrated_circuit/islegal()
	return TRUE

/obj/item/implant/integrated_circuit/Initialize(mapload)
	. = ..()
	rel_set(IC, nameof(IC.implant), src)

CAPABILITIES(/obj/item/implant/integrated_circuit)
	owns_one(nameof(IC), starts = /obj/item/electronic_assembly/implant)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(circuit_implant_emp))))
	op("use", in_hand(), label("Use"), then(PROC_REF(circuit_use)))
	op("add_electronics", item(/obj/item/integrated_electronics), passes(), label("Add"), then(PROC_REF(circuit_attacked)))
	op("add_circuit", item(/obj/item/integrated_circuit), passes(), label("Add"), then(PROC_REF(circuit_attacked)))
	op("add_cell", item(/obj/item/cell/device), passes(), label("Add"), then(PROC_REF(circuit_attacked)))

/obj/item/implant/integrated_circuit/get_data()
	var/dat = {"
	<b>Implant Specifications:</b><BR>
	<b>Name:</b> Modular Implant<BR>
	<b>Life:</b> 3 years.<BR>
	<b>Important Notes: EMP can cause malfunctions in the internal electronics of this implant.</B><BR>
	<HR>
	<b>Implant Details:</b><BR>
	<b>Function:</b> Contains no innate functions until other components are added.<BR>
	<b>Special Features:</b>
	<i>Modular Circuitry</i>- Can be loaded with specific modular circuitry in order to fulfill a wide possibility of functions.<BR>
	<b>Integrity:</b> Implant is not shielded from electromagnetic interference, otherwise it is independent of subject's status."}
	return dat

/// The pulse reaches the assembly inside.
/obj/item/implant/integrated_circuit/proc/circuit_implant_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	IC.emp_act(packet.severity)
	return HOOK_DECLINE

/obj/item/implant/integrated_circuit/examine(mob/user)
	. = ..()
	. += IC.examine(user)

/// A circuit, an assembly part or a device cell is offered to the assembly inside; the click goes on.
/obj/item/implant/integrated_circuit/proc/circuit_attacked(datum/act/op/A)
	IC.attackby(A.held, A.actor)
	return OP_OK

/obj/item/implant/integrated_circuit/crowbar_act(mob/user, obj/item/tool)
	return IC.crowbar_act(user, tool)

/obj/item/implant/integrated_circuit/screwdriver_act(mob/user, obj/item/tool)
	return IC.screwdriver_act(user, tool)

/// Using the implant uses the assembly.
/obj/item/implant/integrated_circuit/proc/circuit_use(datum/act/op/A)
	IC.attack_self(A.actor)
	return OP_OK
