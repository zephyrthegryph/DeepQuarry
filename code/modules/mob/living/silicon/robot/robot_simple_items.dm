// Robot toolbelts, such as screwdrivers and the like. All contained in one neat little package.
// The code for actually 'how these use the item inside of them instead of the item itself' can be found in code\modules\mob\living\silicon\robot\inventory.dm (yes, click code, gross, I know.)
/*
 * Engineering Tools
 */

/obj/item/robotic_multibelt
	name = "Robotic multitool"
	desc = "An integrated toolbelt that holds various tools."
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_engiborg"
	w_class = ITEMSIZE_HUGE

	var/obj/item/selected_item = null

	var/list/cyborg_integrated_tools = list( // ALLOW(instance_list): d: edited in place per instance (10 writers)
		/obj/item/tool/screwdriver/cyborg = null,
		/obj/item/tool/wrench/cyborg = null,
		/obj/item/tool/crowbar/cyborg = null,
		/obj/item/tool/wirecutters/cyborg = null,
		/obj/item/multitool/cyborg = null,
		/obj/item/weldingtool/electric/mounted/cyborg = null,
		)

	/// The carried tools' names (text), in menu order; tools are looked up with integrated_tool_named().
	var/list/integrated_tools_by_name

	var/list/integrated_tool_images

CAPABILITIES(/obj/item/robotic_multibelt)
	owns_many(nameof(cyborg_integrated_tools))

/// The selected tool: one of cyborg_integrated_tools, which owns it.
/obj/item/robotic_multibelt/relations()
	. = ..()
	. += rel_one(nameof(selected_item))

/obj/item/robotic_multibelt/item_ctrl_click(mob/user)
	if(selected_item)
		selected_item.attack_self(user)
	return

/obj/item/robotic_multibelt/examine(mob/user)
	. = ..()
	if(selected_item)
		. += span_notice("\The [src] is currently set to \the [selected_item].")
		. += selected_item.examine(user)

/obj/item/robotic_multibelt/proc/get_module()
	var/obj/item/robot_module/module
	if(isrobot(loc)) //We're in a robot (in hands)
		var/mob/living/silicon/robot/our_robot = loc
		module = our_robot.module
	else if(istype(loc, /obj/item/robot_module)) //We're inside the module itself (in inventory)
		module = loc
	else //Admin spawned us outside of a module.
		CRASH("Robotic Multibelt is not in a robot or module. This should not happen.")
	return module

//'Alterate Tools' means we do special tool handling in Init
/obj/item/robotic_multibelt/Initialize(mapload, custom_handling = FALSE)
	. = ..()
	generate_tools()

/obj/item/robotic_multibelt/proc/generate_tools()
	integrated_tools_by_name = list()

	integrated_tool_images = list()

	for(var/path in cyborg_integrated_tools)
		if(ispath(path)) //Some things like the materials printer makes its own tools and it won't be a path.
			if(!cyborg_integrated_tools[path])
				rel_add(src, nameof(cyborg_integrated_tools), new path(src), path)
		var/obj/item/I = integrated_tool_at(path)
		I.canremove = FALSE

	for(var/tool in cyborg_integrated_tools)
		var/obj/item/real_tool = integrated_tool_at(tool)
		integrated_tools_by_name |= real_tool.name
		var/image/tool_image = image(icon = real_tool.icon, icon_state = real_tool.icon_state)
		tool_image.color = real_tool.color
		integrated_tool_images[real_tool.name] = tool_image

/// The tool under `key` in cyborg_integrated_tools: the value put under a type path, or the
/// member itself (a made-in-place tool such as a material stack is its own key).
/obj/item/robotic_multibelt/proc/integrated_tool_at(key)
	var/obj/item/tool = cyborg_integrated_tools[key]
	if(!tool && isitem(key))
		tool = key
	return tool

/// The carried tool called `tool_name`, or null.
/obj/item/robotic_multibelt/proc/integrated_tool_named(tool_name)
	for(var/key in cyborg_integrated_tools)
		var/obj/item/tool = integrated_tool_at(key)
		if(tool?.name == tool_name)
			return tool
	return null

// The selection and the by-name index point into cyborg_integrated_tools.

DECLARE_INTERACTIONS(/obj/item/robotic_multibelt, INTERACT_USE(null, PROC_REF(interaction_self), REQ_FIELD("cyborg_integrated_tools", "your multibelt is empty")))

/// Old attack_self.
/obj/item/robotic_multibelt/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()

	for(var/Iname in integrated_tools_by_name)
		options[Iname] = integrated_tool_images[Iname]

	// A single tool is picked at once (autopick_single_option).
	open_request(src, /datum/prompt/choice, PROC_REF(tool_chosen), answerer = user, radial = TRUE, choices = options, anchor = src, radius = 40, require_near = TRUE, autopick_single_option = TRUE, timeout = 0)
	return TRUE

/// Tool radial answer.
/obj/item/robotic_multibelt/proc/tool_chosen(datum/act/request/A)
	if(!A.answer)
		return
	cut_overlays()
	assume_selected_item(integrated_tool_named(A.answer.value))

/obj/item/robotic_multibelt/proc/assume_selected_item(obj/item/chosen_item)
	if(!chosen_item)
		return
	icon = chosen_item.icon
	icon_state = chosen_item.icon_state
	color = chosen_item.color
	rel_set(src, nameof(selected_item), chosen_item)

/obj/item/robotic_multibelt/dropped(mob/user, equipping, slot)
	..()
	//We go back to our initial values.
	original_state()

/obj/item/robotic_multibelt/proc/original_state(mob/user)
	rel_clear(src, nameof(selected_item))
	icon = initial(icon)
	icon_state = initial(icon_state)

/obj/item/tool/screwdriver/cyborg
	name = "powered screwdriver"
	desc = "An electrical screwdriver, designed to be both precise and quick."
	usesound = SFX_ITEMS_DRILL_USE_2
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_engiborg_screwdriver"
	random_color = FALSE
	toolspeed = 0.5

/obj/item/tool/crowbar/cyborg
	name = "hydraulic crowbar"
	desc = "A hydraulic prying tool, compact but powerful. Designed to replace crowbars in industrial synthetics."
	usesound = SFX_ITEMS_JAWS_PRY
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_engiborg_crowbar"
	force = 10
	toolspeed = 0.5

/obj/item/tool/crowbar/cyborg/jaws
	name = "puppy jaws"
	desc = "The jaws of a small dog. Still strong enough to pry things."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "smalljaws_textless"
	hitsound = SFX_WEAPONS_BITE
	attack_verb = list("nibbled", "bit", "gnawed", "chomped", "nommed")
	force = 15

/obj/item/weldingtool/electric/mounted/cyborg
	name = "integrated electric welding tool"
	desc = "An advanced welder designed to be used in robotic systems."
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "indwelder_cyborg"
	usesound = SFX_ITEMS_WELDER2
	toolspeed = 0.5
	welding = FALSE
	no_passive_burn = TRUE

/obj/item/weldingtool/electric/mounted/cyborg/look_parts(datum/look/look)
	..()
	if(isrobotmultibelt(loc))
		var/obj/item/robotic_multibelt/our_belt = loc
		our_belt.cut_overlays()
		if(welding)
			our_belt.add_overlay("indwelder_cyborg-on")

/obj/item/tool/wirecutters/cyborg
	name = "wirecutters"
	desc = "This cuts wires. With science."
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_engiborg_cutters"
	usesound = SFX_ITEMS_JAWS_CUT
	random_color = FALSE
	toolspeed = 0.5

/obj/item/tool/wrench/cyborg
	name = "automatic wrench"
	desc = "An advanced robotic wrench. Can be found in industrial synthetic shells."
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_engiborg_wrench"
	usesound = SFX_ITEMS_DRILL_USE_2
	toolspeed = 0.5

/obj/item/multitool/cyborg
	name = "multitool"
	desc = "Optimised and stripped-down version of a regular multitool."
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_engiborg_multitool"
	toolspeed = 0.5

/obj/item/multitool/cyborg/draw(datum/look/look)
	..()
	look.state("toolkit_engiborg_multitool")

/obj/item/multitool/ai_detector/cyborg/get_mechanics_info(list/additional_information)
	return ..(list("This changes colors (and makes sounds that only you can hear if in your active modules) during various events.<br>\
	BLUE: You are outside of camera range.<br>\
	GREEN: You are inside of camera range.<br>\
	RED: You are currently being watched by the AI.<br>\
	FLASHING RED AND ORANGE: You are currently being TRACKED by the AI.<br>\
	FLASHING ORANGE AND BLUE: The AI has attempted to track you but has failed to do so due to being outside camera range.") + additional_information)

/obj/item/multitool/ai_detector/cyborg
	name = "AI detector multitool"
	toolspeed = 0.5
	desc = "Allows you to see if you are being watched by the AI or within network range. Also works as a normal multitool."

/obj/item/stack/cable_coil/cyborg
	name = "cable coil synthesizer"
	desc = "A device that makes cable."
	gender = NEUTER
	uses_charge = 1
	charge_costs = list(1)

/// A synthesiser keeps its cable construction for the cable it lays, but is not
/// made of recyclable material itself (it would dupe materials in a recycler).
/obj/item/stack/cable_coil/cyborg/material_totals()
	return list()

CAPABILITIES(/obj/item/stack/cable_coil/cyborg)
	without("ui_open")
	op("cyborg_coil_self", in_hand(), label("Change colour"), then(PROC_REF(cyborg_coil_self)))

/// Old attack_self.
/obj/item/stack/cable_coil/cyborg/proc/cyborg_coil_self(datum/act/op/A)
	var/mob/user = A.actor
	set_colour(user)

/obj/item/stack/cable_coil/cyborg/proc/set_colour(mob/user)
	set name = "Change Colour"
	set category = VERB_CAT_OBJECT

	open_request(src, /datum/prompt/choice, PROC_REF(cable_colour_chosen), answerer = user, ask_flags = ASK_CARRIED | ASK_CAPABLE, title = "Cable Colour", question = "Pick new colour.", choices = GLOB.possible_cable_coil_colours, timeout = 0)

/obj/item/stack/cable_coil/cyborg/proc/cable_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	set_cable_color(A.answer.value, A.request.answerer)
	if(isrobotmultibelt(loc))
		var/obj/item/robotic_multibelt/our_belt = loc
		var/image/cable_image = our_belt.integrated_tool_images[name]
		cable_image.color = color
		if(our_belt.icon == icon)
			our_belt.color = color

/*
 * Surgical Tools
 */

/obj/item/robotic_multibelt/medical
	name = "Robotic surgical multitool"
	desc = "An integrated surgical toolbelt."
	icon_state = "toolkit_engiborg"

	cyborg_integrated_tools = list(
		/obj/item/surgical/retractor/cyborg = null,
		/obj/item/surgical/hemostat/cyborg = null,
		/obj/item/surgical/cautery/cyborg = null,
		/obj/item/surgical/surgicaldrill/cyborg = null,
		/obj/item/surgical/scalpel/cyborg = null,
		/obj/item/surgical/circular_saw/cyborg = null,
		/obj/item/surgical/bonegel/cyborg = null,
		/obj/item/surgical/FixOVein/cyborg = null,
		/obj/item/surgical/bonesetter/cyborg = null,
		/obj/item/surgical/bioregen/cyborg = null,
		/obj/item/autopsy_scanner = null
		)

/obj/item/surgical/retractor/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_retractor"
	toolspeed = 0.5

/obj/item/surgical/hemostat/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_hemostat"
	toolspeed = 0.5

/obj/item/surgical/cautery/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_cautery"
	toolspeed = 0.5

/obj/item/surgical/surgicaldrill/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_drill"
	toolspeed = 0.5

/obj/item/surgical/scalpel/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_scalpel"
	toolspeed = 0.5

/obj/item/surgical/circular_saw/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_saw"
	toolspeed = 0.5

/obj/item/surgical/bonegel/cyborg
	toolspeed = 0.5

/obj/item/surgical/FixOVein/cyborg
	toolspeed = 0.5

/obj/item/surgical/bonesetter/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "toolkit_medborg_bonesetter"
	toolspeed = 0.5

/obj/item/surgical/bioregen/cyborg
	icon_state = "cyborg_bioregen"
	toolspeed = 0.5

//Service multibelt!
/obj/item/robotic_multibelt/service
	name = "Service multitool"
	desc = "An integrated service toolbelt."
	icon_state = "toolkit_medborg"

	cyborg_integrated_tools = list(
		/obj/item/material/minihoe/cyborg  = null,
		/obj/item/material/knife/machete/hatchet/cyborg  = null,
		/obj/item/analyzer/plant_analyzer/cyborg  = null,
		/obj/item/material/knife/cyborg  = null,
		/obj/item/robot_harvester = null,
		/obj/item/material/kitchen/rollingpin/cyborg  = null,
		/obj/item/tool/wirecutters/cyborg = null,
		/obj/item/multitool/cyborg = null,
		/obj/item/reagent_containers/spray = null
		)

//Botanical multibelt!
/obj/item/robotic_multibelt/botanical
	name = "Botanical multitool"
	desc = "An integrated botanical toolbelt."
	icon_state = "toolkit_engiborg"

	cyborg_integrated_tools = list(
		/obj/item/material/minihoe/cyborg  = null,
		/obj/item/material/knife/machete/hatchet/cyborg  = null,
		/obj/item/analyzer/plant_analyzer/cyborg = null,
		/obj/item/robot_harvester = null,
		/obj/item/tool/wirecutters/cyborg = null,
		/obj/item/multitool/cyborg = null,
		/obj/item/reagent_containers/spray = null
		)

/obj/item/material/minihoe/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "sili_cultivator"
	applies_material_colour = FALSE

/obj/item/material/knife/machete/hatchet/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "sili_hatchet"
	applies_material_colour = FALSE

/obj/item/analyzer/plant_analyzer/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "sili_secateur"

/obj/item/material/knife/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "sili_knife"
	applies_material_colour = FALSE

/obj/item/material/kitchen/rollingpin/cyborg
	icon = 'icons/obj/tools_robot.dmi'
	icon_state = "sili_rolling_pin"
	applies_material_colour = FALSE

/obj/item/robotic_multibelt/syndicate
	name = "Syndicate Robotic multitool"
	desc = "An integrated toolbelt that holds various tools. This one comes with a multitool-hacktool."
	cyborg_integrated_tools = list(
		/obj/item/tool/screwdriver/cyborg = null,
		/obj/item/tool/wrench/cyborg = null,
		/obj/item/tool/crowbar/cyborg = null,
		/obj/item/tool/wirecutters/cyborg = null,
		/obj/item/multitool/hacktool = null,
		/obj/item/weldingtool/electric/mounted/cyborg = null,
		)

//Admin proc to add new materials to their fabricator
/mob/living/silicon/robot/proc/add_new_material(mat_to_add) //Allows us to add a new material to the borg's synth and then make their multibelt refresh.
	if(!module)
		return

	if(!mat_to_add)
		return

	var/datum/matter_synth/synth_path = ispath(mat_to_add) ? mat_to_add : GLOB.material_synth_list[mat_to_add]

	if(!can_install_synth(synth_path))
		return

	var/amount
	switch(mat_to_add)
		if(/datum/matter_synth/metal)
			amount = 40000
		if(/datum/matter_synth/plasteel)
			amount = 20000
		if(/datum/matter_synth/glass)
			amount = 40000
		if(/datum/matter_synth/wood)
			amount = 40000
		if(/datum/matter_synth/plastic)
			amount = 40000
		if(/datum/matter_synth/wire)
			amount = 50
		if(/datum/matter_synth/cloth)
			amount = 40000

	if(!amount)
		return

	rel_add(module, nameof(module.synths), new synth_path(amount))
	update_material_multibelts()

/mob/living/silicon/robot/proc/update_material_multibelts()
	for(var/obj/item/robotic_multibelt/materials/mat_belt in contents_of(module)) //If it's stowed in our inventory
		mat_belt.generate_tools()
	for(var/obj/item/robotic_multibelt/materials/mat_belt in contents) //If it's in our handstory
		mat_belt.generate_tools()

/mob/living/silicon/robot/proc/can_install_synth(datum/matter_synth/type_to_check)
	if(!ispath(type_to_check, /datum/matter_synth))
		return FALSE
	for(var/datum/matter_synth/synth in module.synths)
		if(istype(synth, type_to_check))
			return FALSE
	return TRUE

/mob/living/silicon/robot/proc/remove_material(mat_to_remove)
	if(!module)
		return

	if(!mat_to_remove)
		return

	var/datum/matter_synth/synth_path = ispath(mat_to_remove) ? mat_to_remove : GLOB.material_synth_list[mat_to_remove]

	for(var/datum/matter_synth/synth in module.synths)
		if(istype(synth, synth_path))
			own_remove(module, nameof(module.synths), synth)
	update_material_multibelts()

//The Material Dispenser Multibelt
//This thing is uh...Bulky. And took a lot of effort to get to work.

/obj/item/robotic_multibelt/materials
	name = "Robotic Material Dispenser"
	desc = "An integrated material dispenser! Click once to select your material. Use Ctrl + Click to open the menu for the selected material."
	icon_state = "toolkit_material"

	cyborg_integrated_tools = list()

/obj/item/robotic_multibelt/materials/generate_tools()
	var/obj/item/robot_module/module = get_module()
	if(!module || !module.synths || !LAZYLEN(module.synths)) //We have a synths list and it has contents within it!
		return

	var/datum/matter_synth/has_steel //Steel synth. For generating Rglass
	var/datum/matter_synth/has_glass //Glass synth. For generating Rglass
	for(var/datum/matter_synth/our_synth in module.synths)
		if(our_synth.name == METAL_SYNTH)
			has_steel = our_synth
			continue
		if(our_synth.name == GLASS_SYNTH)
			has_glass = our_synth
			continue

	var/list/possible_synths = list()
	for(var/datum/matter_synth/our_synth in module.synths)
		switch(our_synth.name)
			if(METAL_SYNTH)
				if(has_glass)
					possible_synths[/obj/item/stack/material/cyborg/glass/reinforced] = list(our_synth, has_glass)
				possible_synths += list(/obj/item/stack/material/cyborg/steel = list(our_synth))
				possible_synths += list(/obj/item/stack/tile/floor/cyborg = list(our_synth))
				possible_synths += list(/obj/item/stack/rods/cyborg = list(our_synth))
				possible_synths += list(/obj/item/stack/tile/roofing/cyborg = list(our_synth))
			if(PLASTEEL_SYNTH)
				possible_synths += list(/obj/item/stack/material/cyborg/plasteel = list(our_synth))
			if(GLASS_SYNTH)
				if(has_steel)
					possible_synths[/obj/item/stack/material/cyborg/glass/reinforced] = list(our_synth, has_steel)
				possible_synths += list(/obj/item/stack/material/cyborg/glass = list(our_synth))
			if(WOOD_SYNTH)
				possible_synths += list(/obj/item/stack/tile/wood/cyborg = list(our_synth))
				possible_synths += list(/obj/item/stack/material/cyborg/wood = list(our_synth))
			if(PLASTIC_SYNTH)
				possible_synths += list(/obj/item/stack/material/cyborg/plastic = list(our_synth))
			if(WIRE_SYNTH)
				possible_synths += list(/obj/item/stack/cable_coil/cyborg = list(our_synth))
			if(CLOTH_SYNTH)
				possible_synths += list(/obj/item/stack/sandbags/cyborg = list(our_synth))

	for(var/obj/item/stack/our_item in cyborg_integrated_tools)
		if(is_type_in_list(our_item, possible_synths))
			possible_synths -= our_item.type
		else
			integrated_tools_by_name -= our_item.name
			integrated_tool_images -= our_item.name
			own_remove(src, nameof(cyborg_integrated_tools), our_item)

	for(var/stack_to_add in possible_synths)
		var/obj/item/stack/current_stack = new stack_to_add(src)
		for(var/datum/matter_synth/linked_synth as anything in possible_synths[stack_to_add])
			rel_add(current_stack, nameof(current_stack.synths), linked_synth)
		rel_add(src, nameof(cyborg_integrated_tools), current_stack)

	. = ..()


///Allows the material fabricator to pick up materials if they hit an appropriate stack.
/obj/item/robotic_multibelt/materials/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(istype(target, /obj/item/stack)) //We are targeting a stack.
		if(!selected_item)
			to_chat(user, span_warning("You need to select a material first!"))
			return
		var/obj/item/stack/target_stack = target
		if(istype(selected_item, /obj/item/stack))
			target_stack.attackby(selected_item, user)

/*
 * Grippers
 */

//Simple borg hand.
//Limited use.
//If you want to add more items to the gripper, add them to the global define list for that gripper.
/obj/item/gripper
	name = "magnetic gripper"
	desc = "A simple grasping tool specialized in construction and engineering work."
	icon = 'icons/obj/device.dmi'
	icon_state = "gripper"

	flags = NOBLUDGEON

	//Has a list of items that it can hold.

	// The item it is wrapping is GRIPPER_HELD(src) (the gripper_holding relation). Use get_wrapped_item when possible.

	var/total_pockets = 5 //How many total inventory slots we want to have in the gripper

	// ALLOW(instance_list): d: gripper pockets are created in Initialize and always present
	var/list/pockets = list() //List of the pockets we have. This is used to store the items inside of the gripper.

	var/obj/item/current_pocket = null //What pocket (or item!) we currently have selected


	var/list/photo_images

	/// If we're currently using the gripper on something.
	var/gripper_in_use = FALSE
	/// If we're currently in the radial menu. (Blocks pickup attempts)
	var/in_radial_menu = FALSE

	var/mob/living/silicon/robot/our_robot

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	///Var for attack_self chain
	var/special_handling = FALSE

/// A gripper is a provider (doc/rewrite/final_api.html 16.8): selected, it handles things for its cyborg within arm's reach, and what it carries is the
/// held item of the cyborg's ops (/mob/living/silicon/robot/held_for_ops()), so it puts a cell into an APC through the APC's own insert op and takes
/// one out through its take op (into a free pocket: carry()). What it may hold is its CONSTRAINT_HOLD.
CAPABILITIES(/obj/item/gripper)
	provides(AFF_MANIPULATE | AFF_HOLD_SMALL, reach = 1)
	owns_many(nameof(pockets))

/// The selected pocket (one of `pockets`) or item.
/obj/item/gripper/relations()
	. = ..()
	. += rel_one(nameof(current_pocket))
	. += rel_one(nameof(our_robot))

/obj/item/storage/internal/gripper
	max_storage_space = ITEMSIZE_COST_HUGE


CAPABILITIES(/obj/item/storage/internal/gripper)
	configure(storage(max_size = ITEMSIZE_HUGE))

/obj/item/gripper/Initialize(mapload)
	. = ..()

	if(total_pockets)
		for(var/i = 1, i <= total_pockets, i++)
			var/obj/new_pocket = new /obj/item/storage/internal/gripper(src)
			new_pocket.name = "Pocket [i]"
			rel_add(src, nameof(pockets), new_pocket)
	rel_set(src, nameof(current_pocket), peek(pockets))
	if(isrobot(loc.loc)) //We're in the module.
		rel_set(src, nameof(our_robot), loc.loc)
	else if(isrobot(loc)) //We spawned in the robot's module slots...Weird, but whatever.
		rel_set(src, nameof(our_robot), loc)
	else //We were in neither. Let's qdel ourselves.
		return INITIALIZE_HINT_QDEL
	observe(our_robot, /datum/notice/do_after_began, src, then(PROC_REF(begin_using)))
	observe(our_robot, /datum/notice/do_after_ended, src, then(PROC_REF(end_using)))

// The selected pocket is one of `pockets`, and the robot owns the gripper.

/obj/item/gripper/examine(mob/user)
	. = ..()
	var/obj/item/wrapped = get_wrapped_item()
	if(wrapped)
		. += span_notice("\The [src] is holding \the [wrapped].")
		. += wrapped.examine(user)

/obj/item/gripper/item_ctrl_click(mob/user)
	var/obj/item/wrapped = get_wrapped_item()
	if(wrapped && !is_in_use(user, FALSE))
		wrapped.attack_self(user)

/// Old click_alt.
/obj/item/gripper/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(!is_in_use(user, FALSE))
		drop_item(user)
	return TRUE

EXTEND_INTERACTIONS(/obj/item/gripper, INTERACT_VERB("Drop Item", PROC_REF(gripper_verb_drop), REQ_IN_INVENTORY))

/// Old Drop Item verb: Release an item from your magnetic gripper.
/obj/item/gripper/proc/gripper_verb_drop(mob/user, obj/item/held, datum/interaction/interaction)
	drop_item(src.loc)

//Different types of grippers!

/obj/item/gripper/engineering
	name = "Engineering Gripper"
	desc = "An integrated Engineering Gripper."
	icon_state = "gripper-omni"

/obj/item/gripper/drone
	name = "Drone Gripper"
	desc = "An integrated Drone Gripper."
	icon_state = "gripper-old"

/obj/item/gripper/omni
	name = "omni gripper"
	desc = "A strange grasping tool that can hold anything a human can, but still maintains the limitations of application its more limited cousins have."
	icon_state = "gripper-omni"

// VEEEEERY limited version for mining borgs. Basically only for swapping cells and upgrading the drills.
/obj/item/gripper/miner
	name = "drill maintenance gripper"
	desc = "A simple grasping tool for the maintenance of heavy drilling machines."
	icon_state = "gripper-mining"

/obj/item/gripper/security
	name = "security gripper"
	desc = "A simple grasping tool for corporate security work."
	icon_state = "gripper-sec"

/obj/item/gripper/paperwork
	name = "paperwork gripper"
	desc = "A simple grasping tool for clerical work."

/obj/item/gripper/medical
	name = "medical gripper"
	desc = "A simple grasping tool for medical work."
	icon_state = "gripper-flesh"

/obj/item/gripper/research //A general usage gripper, used for toxins/robotics/xenobio/etc
	name = "scientific gripper"
	icon_state = "gripper-sci"
	desc = "A simple grasping tool suited to assist in a wide array of research applications."

/obj/item/gripper/circuit
	name = "circuit assembly gripper"
	icon_state = "gripper-circ"
	desc = "A complex grasping tool used for working with circuitry."

/obj/item/gripper/service //Used to handle food, drinks, seeds, and cards.
	name = "service gripper"
	icon_state = "gripper-sheet"
	desc = "A simple grasping tool used to perform tasks in the service sector, such as handling food, drinks, and seeds. It can also hold cards and fake casino chips for hosting card games."

/obj/item/gripper/gravekeeper	//Used for handling grave things, flowers, etc.
	name = "grave gripper"
	icon_state = "gripper-old"
	desc = "A specialized grasping tool used in the preparation and maintenance of graves."

/obj/item/gripper/scene
	name = "misc gripper"
	desc = "A simple grasping tool that can hold a variety of 'general' objects..."

/obj/item/gripper/no_use/organ
	name = "organ gripper"
	icon_state = "gripper-flesh"
	desc = "A specialized grasping tool used to preserve and manipulate organic material."

/obj/item/gripper/no_use/organ/Entered(atom/movable/AM)
	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 1
		for(var/obj/item/organ/organ in O)
			organ.preserved = 1
	..()

/obj/item/gripper/no_use/organ/Exited(atom/movable/AM)
	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 0
		for(var/obj/item/organ/organ in O)
			organ.preserved = 0
	..()

/obj/item/gripper/no_use/organ/robotics
	name = "robotics organ gripper"
	icon_state = "gripper-flesh"
	desc = "A specialized grasping tool used in robotics work."

/obj/item/gripper/no_use/mech
	name = "exosuit gripper"
	icon_state = "gripper-mech"
	desc = "A large, heavy-duty grasping tool used in construction of mechs."

	special_handling = TRUE

/obj/item/gripper/no_use //Used when you want to hold and put items in other things, but not able to 'use' the item


/obj/item/gripper/no_use/loader //This is used to disallow building with metal.
	name = "sheet loader"
	desc = "A specialized loading device, designed to pick up and insert sheets of materials inside machines."
	icon_state = "gripper-sheet"

/obj/item/gripper/syndicate
	name = "syndicate gripper"
	desc = "A simple grasping tool for off-the-books syndicate work."
	icon_state = "gripper-sec"

/*
 * Misc tools
 */
/obj/item/reagent_containers/glass/bucket/cyborg
	var/mob/living/silicon/robot/R
	var/last_robot_loc

/obj/item/reagent_containers/glass/bucket/cyborg/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(R), loc.loc)
	observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(check_loc)))

/obj/item/reagent_containers/glass/bucket/cyborg/proc/check_loc(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/movable_attempted_move/event = A
	var/atom/old_loc = event.old_loc
	if(old_loc == R || old_loc == R.module)
		last_robot_loc = old_loc
	if(!istype(loc, /obj/machinery) && loc != R && loc != R.module)
		if(last_robot_loc)
			forceMove(last_robot_loc)
			last_robot_loc = null
		else
			forceMove(R)
		if(loc == R)
			hud_layerise()

// What each gripper can pick up: its hold constraint (P3), checked through
// dq_constraint_refusal() like any other holder.

TYPE_TABLE(/obj/item/gripper, hold_spec, list(HOLD_ONLY(list(BASIC_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/engineering, hold_spec, list(HOLD_ONLY(list(BASIC_GRIPPER, CIRCUIT_GRIPPER, SHEET_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/drone, hold_spec, list(HOLD_ONLY(list(BASIC_GRIPPER, SHEET_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/omni, hold_spec, list(HOLD_ONLY(list(OMNI_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/miner, hold_spec, list(HOLD_ONLY(list(MINER_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/security, hold_spec, list(HOLD_ONLY(list(SECURITY_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/paperwork, hold_spec, list(HOLD_ONLY(list(PAPERWORK_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/medical, hold_spec, list(HOLD_ONLY(list(BASIC_GRIPPER, ORGAN_GRIPPER, MEDICAL_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/research, hold_spec, list(HOLD_ONLY(list(BASIC_GRIPPER, CIRCUIT_GRIPPER, SHEET_GRIPPER, EXOSUIT_GRIPPER, ROBOTICS_ORGAN_GRIPPER, RESEARCH_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/circuit, hold_spec, list(HOLD_ONLY(list(CIRCUIT_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/service, hold_spec, list(HOLD_ONLY(list(SERVICE_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/gravekeeper, hold_spec, list(HOLD_ONLY(list(GRAVEYARD_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/scene, hold_spec, list(HOLD_ONLY(list(SCENE_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/no_use/organ, hold_spec, list(HOLD_ONLY(list(ORGAN_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/no_use/organ/robotics, hold_spec, list(HOLD_ONLY(list(ROBOTICS_ORGAN_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/no_use/mech, hold_spec, list(HOLD_ONLY(list(EXOSUIT_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/no_use/loader, hold_spec, list(HOLD_ONLY(list(SHEET_GRIPPER))))

TYPE_TABLE(/obj/item/gripper/syndicate, hold_spec, list(HOLD_ONLY(list(BASIC_GRIPPER, SECURITY_GRIPPER, MINER_GRIPPER, PAPERWORK_GRIPPER, MEDICAL_GRIPPER, RESEARCH_GRIPPER, CIRCUIT_GRIPPER, SERVICE_GRIPPER, GRAVEYARD_GRIPPER, ORGAN_GRIPPER, ROBOTICS_ORGAN_GRIPPER, EXOSUIT_GRIPPER, SHEET_GRIPPER))))

