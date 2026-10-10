// Video camera circuits.
// Separated from input/output files to start improving organization.

/obj/item/integrated_circuit/output/video_camera
	name = "video output circuit"
	desc = "A tiny camera module that captures a 7x7 view around the assembly and broadcasts it on a private channel."
	extended_desc = "This circuit creates a camera feed from the assembly's location. Pair it with a camera input circuit \
		by holding the input circuit and clicking on this circuit before installing either into assemblies. \
		Draws power continuously while active."
	icon_state = "video_camera"
	complexity = 6
	inputs = list(
		"camera name" = IC_PINTYPE_STRING,
		"active" = IC_PINTYPE_BOOLEAN
	)
	inputs_default = list(
		"1" = "IC Camera",
		"2" = TRUE
	)
	outputs = list()
	activators = list()
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_idle = 50
	category_text = "Output"

	var/obj/machinery/camera/intcircuit/camera
	var/camera_network_id
	var/see_dark = FALSE

CAPABILITIES(/obj/item/integrated_circuit/output/video_camera)
	owns_one(nameof(camera), /obj/machinery/camera/intcircuit, starts = PROC_REF(make_camera))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

// ALLOW(init/INSTANCE_STATE): gets its own camera network id and the camera that uses it
/obj/item/integrated_circuit/output/video_camera/Initialize(mapload)
	. = ..()
	update_camera_name()

/// The starting camera (owns_one(starts =)) on its own network.
/obj/item/integrated_circuit/output/video_camera/proc/make_camera(current)
	camera_network_id = "ic_cam_[sequential_id(/obj/item/integrated_circuit/output/video_camera)]"
	return new /obj/machinery/camera/intcircuit(src, camera_network_id, see_dark)


/obj/item/integrated_circuit/output/video_camera/on_data_written()
	update_camera_name()
	update_camera_status()

/obj/item/integrated_circuit/output/video_camera/proc/update_camera_name()
	if(!camera)
		return
	var/new_name = get_pin_data(IC_INPUT, 1)
	if(!new_name || !istext(new_name))
		new_name = "IC Camera"
	camera.c_tag = new_name
	camera.name = new_name

/obj/item/integrated_circuit/output/video_camera/proc/update_camera_status()
	if(!camera)
		return
	var/should_be_active = get_pin_data(IC_INPUT, 2)
	if(should_be_active && assembly()?.battery?.charge)
		if(!camera.status)
			camera.set_status(TRUE)
		power_draw_idle = initial(power_draw_idle)
	else
		if(camera.status)
			camera.set_status(FALSE)
		power_draw_idle = 0

/obj/item/integrated_circuit/output/video_camera/power_fail()
	if(camera?.status)
		camera.set_status(FALSE)
	power_draw_idle = 0

/// Old attackby.
/obj/item/integrated_circuit/output/video_camera/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/integrated_circuit/input/video_camera_input))
		var/obj/item/integrated_circuit/input/video_camera_input/input = W
		if(src in input.paired_cameras)
			rel_remove(input, nameof(input.paired_cameras), src)
			to_chat(user, span_notice("You unpair \the [input] from \the [src]."))
		else
			rel_add(input, nameof(input.paired_cameras), src)
			to_chat(user, span_notice("You pair \the [input] with \the [src]. The input circuit will now receive this camera's feed."))
		return OP_PASS
	return OP_DECLINE

/obj/item/integrated_circuit/output/video_camera/examine(mob/user)
	. = ..()
	. += span_notice("Camera network ID: [camera_network_id]")
	if(camera?.status)
		. += span_notice("The camera is currently <b>active</b>.")
	else
		. += span_warning("The camera is currently <b>inactive</b>.")

// Darkvision output camera

/obj/item/integrated_circuit/output/video_camera/advanced
	name = "advanced video output circuit"
	desc = "A high-end camera module with enhanced optics that can see in complete darkness."
	extended_desc = "Functions identically to the standard camera output circuit, but includes darkvision. \
		Draws twice as much power."
	complexity = 8
	power_draw_idle = 100
	see_dark = TRUE
	spawn_flags = IC_SPAWN_RESEARCH

/obj/machinery/camera/intcircuit
	name = "IC camera"
	network = list()
	use_power = USE_POWER_OFF
	status = TRUE
	invuln = TRUE
	anchored = FALSE
	on_open_network = FALSE

	var/see_dark = FALSE

CAPABILITIES(/obj/machinery/camera/intcircuit)
	param(nameof(network_id), pos = 1)
	param(nameof(see_dark), pos = 2)

/// The network a circuit camera is made on (its constructor param).
/obj/machinery/camera/intcircuit/var/network_id

// ALLOW(init/INSTANCE_STATE): a circuit camera is numbered and joins the camera net
/obj/machinery/camera/intcircuit/Initialize(mapload)
	if(network_id)
		network = list(network_id)
	// Skip the parent Initialize's assembly creation and network checks
	c_tag = "IC Camera #[rand(1000, 9999)]"
	name = c_tag
	GLOB.cameranet.addCamera(src)
	return ..()

/// Phase 2: leaves the camera net.
/obj/machinery/camera/intcircuit/lifecycle_dematerialize()
	. = ..()
	GLOB.cameranet.removeCamera(src)

/obj/machinery/camera/intcircuit/update_coverage(network_change = 0)
	GLOB.cameranet.updateVisibility(src, 0)

/obj/machinery/camera/intcircuit/can_use()
	// Ensures circuit is in a powered assembly to work.
	var/obj/item/integrated_circuit/output/video_camera/parent = loc
	if(istype(parent) && parent.assembly()?.battery?.charge)
		return TRUE
	return FALSE

/obj/machinery/camera/intcircuit/isXRay()
	return see_dark

// Input Circuit

/obj/item/integrated_circuit/input/video_camera_input
	name = "video input circuit"
	desc = "A circuit that receives and displays video feeds from paired video output circuits."
	extended_desc = "Pair this circuit with camera output circuits by holding this circuit and clicking on them. \
		When used in an assembly, selecting this circuit from the interaction menu will open a camera viewing console \
		showing all paired camera feeds. Draws a small amount of power while active."
	icon_state = "video_camera"
	complexity = 5
	can_be_asked_input = TRUE
	inputs = list()
	outputs = list()
	activators = list()
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	category_text = "Input"

	var/list/obj/item/integrated_circuit/output/video_camera/paired_cameras
	var/datum/tgui_module/camera/intcircuit/camera_module

CAPABILITIES(/obj/item/integrated_circuit/input/video_camera_input)
	owns_one(nameof(camera_module), /datum/tgui_module/camera/intcircuit, starts = /datum/tgui_module/camera/intcircuit)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))


/obj/item/integrated_circuit/input/video_camera_input/ask_for_input(mob/user)
	if(!length(paired_cameras))
		to_chat(user, span_warning("No cameras are paired to this circuit! Hold this circuit and click on camera output circuits to pair them."))
		return
	// Check if any cameras are actually available
	var/any_available = FALSE
	for(var/obj/item/integrated_circuit/output/video_camera/cam_circuit in paired_cameras)
		if(cam_circuit.assembly() && cam_circuit.camera?.can_use())
			any_available = TRUE
			break
	if(!any_available)
		to_chat(user, span_warning("None of the paired cameras are currently active or powered."))
		return
	// Update the modules camera list and open UI
	camera_module.update_camera_list()
	camera_module.tgui_interact(user)

/obj/item/integrated_circuit/input/video_camera_input/examine(mob/user)
	. = ..()
	. += span_notice("Paired cameras: [length(paired_cameras)]")
	for(var/obj/item/integrated_circuit/output/video_camera/cam in paired_cameras)
		var/status_text = cam.camera?.can_use() ? "ACTIVE" : "INACTIVE"
		. += span_notice(" - [cam.camera?.c_tag || "Unknown"] ([status_text])")

/// Old attackby.
/obj/item/integrated_circuit/input/video_camera_input/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/integrated_circuit/output/video_camera))
		W.attackby(src, user)
		return OP_PASS
	return OP_DECLINE

/obj/item/integrated_circuit/input/video_camera_input/power_fail()
	// Close any open UIs
	SStgui.close_uis(camera_module)

// TGUI Module for input circuit.

/datum/tgui_module/camera/intcircuit
	name = "IC Camera Feed"
	tgui_id = "ICCameraConsole"
	access_based = FALSE

	var/tmp/obj/item/integrated_circuit/input/video_camera_input/owner_circuit

/datum/tgui_module/camera/intcircuit/New(host)
	rel_set(src, nameof(owner_circuit), host)
	// Pass an empty network list - we override get_available_cameras
	..(host, list("intcircuit_dummy"))
	access_based = FALSE

/datum/tgui_module/camera/intcircuit/tgui_host(mob/user)
	if(owner_circuit()?.assembly())
		return owner_circuit().assembly()
	return owner_circuit()

/datum/tgui_module/camera/intcircuit/get_available_cameras(mob/user)
	var/list/D = list()
	if(!owner_circuit())
		return D
	for(var/obj/item/integrated_circuit/output/video_camera/cam_circuit in owner_circuit().paired_cameras)
		if(!cam_circuit.assembly()) // Skip circuits not in assemblies
			continue
		var/obj/machinery/camera/intcircuit/C = cam_circuit.camera
		if(C && C.c_tag)
			D["[ckey(C.c_tag)]"] = C
	return D

/datum/tgui_module/camera/intcircuit/proc/update_camera_list()
	return

/// Switching cameras forgets the last turf first, then the module switches as usual.
/datum/tgui_module/camera/intcircuit/ui_act_switch_camera(datum/act/op/A, name)
	rel_clear(src, nameof(last_camera_turf))
	return ..()

/// The owner_circuit this refers to (a relation view: null once that is deleted).
/datum/tgui_module/camera/intcircuit/proc/owner_circuit() as /obj/item/integrated_circuit/input/video_camera_input
	return owner_circuit
