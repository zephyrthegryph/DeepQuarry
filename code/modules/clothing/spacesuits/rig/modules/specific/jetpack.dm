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

/obj/item/rig_module/maneuvering_jets/engage()
	if(!..())
		return 0
	jets.toggle_rockets_effect(holder?.wearer())
	return 1

/obj/item/rig_module/maneuvering_jets/activate()

	if(active)
		return 0

	active = 1

	om_after(src, 1, PROC_REF(refresh_suit_overlay))

	if(!jets.on)
		jets.jetpack_toggle_effect(holder?.wearer())
	return 1

/obj/item/rig_module/maneuvering_jets/deactivate()
	if(!..())
		return 0
	if(jets.on)
		jets.jetpack_toggle_effect(holder?.wearer())
	return 1

DECLARE_DEFAULT_CHILD(/obj/item/rig_module/maneuvering_jets, "jets", /obj/item/tank/jetpack/rig)


/obj/item/rig_module/maneuvering_jets/installed()
	..()
	jets.holder_handle = om_handle(holder)
	jets.ion_trail.set_up(holder)

/obj/item/rig_module/maneuvering_jets/removed()
	..()
	jets.holder_handle = null
	jets.ion_trail.set_up(jets)
