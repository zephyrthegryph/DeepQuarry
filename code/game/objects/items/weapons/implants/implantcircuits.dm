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
	IC.implant_handle = om_handle(src)

DECLARE_DEFAULT_CHILD(/obj/item/implant/integrated_circuit, "IC", /obj/item/electronic_assembly/implant)

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

/obj/item/implant/integrated_circuit/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	IC.emp_act(severity, recursive)

/obj/item/implant/integrated_circuit/examine(mob/user)
	. = ..()
	. += IC.examine(user)

/// Old attackby.
/obj/item/implant/integrated_circuit/proc/integrated_circuit_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/integrated_electronics) || istype(O, /obj/item/integrated_circuit) || istype(O, /obj/item/cell/device))
		IC.attackby(O, user)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/implant/integrated_circuit/crowbar_act(mob/user, obj/item/tool)
	return IC.crowbar_act(user, tool)

/obj/item/implant/integrated_circuit/screwdriver_act(mob/user, obj/item/tool)
	return IC.screwdriver_act(user, tool)

EXTEND_INTERACTIONS(/obj/item/implant/integrated_circuit, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(integrated_circuit_interaction_item)), \
)

/// Old attack_self.
/obj/item/implant/integrated_circuit/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	IC.attack_self(user)
	return TRUE
