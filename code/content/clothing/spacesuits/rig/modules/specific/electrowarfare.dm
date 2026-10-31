/obj/item/rig_module/electrowarfare_suite

	name = "electrowarfare module"
	desc = "A bewilderingly complex bundle of fiber optics and chips."
	icon_state = "ewar"
	toggleable = 1
	usable = 0

	activate_string = "Enable Countermeasures"
	deactivate_string = "Disable Countermeasures"

	interface_name = "electrowarfare system"
	interface_desc = "An active counter-electronic warfare suite that disrupts AI tracking."

/obj/item/rig_module/electrowarfare_suite/activate(skip_engage = 0, mob/user)

	if(!..())
		return

	// This is not the best way to handle this, but I don't want it to mess with ling camo
	var/mob/living/M = holder.wearer()
	sparse_set(M, digitalcamo, sparse_get_or(M, digitalcamo, 0) + 1)

/obj/item/rig_module/electrowarfare_suite/deactivate(forced = FALSE, mob/user)

	if(!..())
		return

	var/mob/living/M = holder.wearer()
	sparse_set(M, digitalcamo, max(0,(sparse_get_or(M, digitalcamo, 0)-1)))
