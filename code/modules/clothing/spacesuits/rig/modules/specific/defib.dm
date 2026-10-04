/obj/item/rig_module/device/defib
	name = "mounted defib"
	desc = "A rig mounted defib unit. Has expanded functionality to function on both organics and FBP's."
	icon_state = "flash"
	interface_name = "mounted defib"
	interface_desc = "Toggle to swap between FBP and Organic compatibility."
	device_type = /obj/item/shockpaddles/standalone/rig
	usable = 1
	engage_string = "Toggle Mode"

/obj/item/shockpaddles/standalone/rig
	name = "mounted defib"
	desc = "Rig mounted defib. How are you seeing this? Stop that."
	wielded = 1

/obj/item/shockpaddles/standalone/rig/Initialize(mapload)
	emp_protection_flags |= EMP_PROTECT_SELF
	. = ..()

/obj/item/shockpaddles/standalone/rig/checked_use(charge_amt)
	return 1

CAPABILITIES(/obj/item/shockpaddles/standalone/rig)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/shockpaddles/standalone/rig/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	use_on_synthetic = !use_on_synthetic
	to_chat(user, span_notice("You switch the [src] to [use_on_synthetic ? "FBP" : "organic"] compatibility."))
	return TRUE
