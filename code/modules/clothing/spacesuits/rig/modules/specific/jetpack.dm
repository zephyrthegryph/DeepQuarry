/obj/item/rig_module/maneuvering_jets

	name = "hardsuit maneuvering jets"
	desc = "A compact gas thruster system for a hardsuit."
	icon_state = "thrusters"
	usable = 1
	toggleable = 1
	selectable = 0
	disruptive = 0

	suit_overlay_active = "maneuvering_active"
	suit_overlay_inactive = null //"maneuvering_inactive"

	engage_string = "Toggle Stabilizers"
	activate_string = "Activate Thrusters"
	deactivate_string = "Deactivate Thrusters"

	interface_name = "maneuvering jets"
	interface_desc = "An inbuilt EVA maneuvering system that runs off the rig air supply."

	var/obj/item/tank/jetpack/rig/jets

/obj/item/rig_module/maneuvering_jets/engage(atom/target, notify_ai, mob/user)
	if(!..())
		return 0
	jets.toggle_rockets_effect(holder?.wearer())
	return 1

/obj/item/rig_module/maneuvering_jets/activate(skip_engage = 0, mob/user)

	if(active)
		return 0

	active = 1

	after(src, 1, PROC_REF(refresh_suit_overlay))

	if(!jets.on)
		jets.jetpack_toggle_effect(holder?.wearer())
	return 1

/obj/item/rig_module/maneuvering_jets/deactivate(forced = FALSE, mob/user)
	if(!..())
		return 0
	if(jets.on)
		jets.jetpack_toggle_effect(holder?.wearer())
	return 1

DECLARE_DEFAULT_CHILD(/obj/item/rig_module/maneuvering_jets, "jets", /obj/item/tank/jetpack/rig)


/obj/item/rig_module/maneuvering_jets/installed()
	..()
	rel_set(jets, nameof(jets.holder), holder)
	jets.ion_trail.set_up(holder)

/obj/item/rig_module/maneuvering_jets/removed()
	..()
	rel_clear(jets, nameof(jets.holder))
	jets.ion_trail.set_up(jets)
