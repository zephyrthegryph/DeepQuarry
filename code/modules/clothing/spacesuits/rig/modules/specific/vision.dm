/*
 * Contains
 * /obj/item/rig_module/vision
 * /obj/item/rig_module/vision/multi
 * /obj/item/rig_module/vision/meson
 * /obj/item/rig_module/vision/thermal
 * /obj/item/rig_module/vision/nvg
 * /obj/item/rig_module/vision/medhud
 * /obj/item/rig_module/vision/sechud
 */

/datum/rig_vision
	var/mode
	var/obj/item/clothing/glasses/glasses

CAPABILITIES(/datum/rig_vision)
	owns_one(nameof(glasses), /obj/item/clothing/glasses)

/datum/rig_vision/nvg
	mode = "night vision"

/datum/rig_vision/nvg/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/night)

/datum/rig_vision/thermal
	mode = "thermal scanner"

/datum/rig_vision/thermal/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/thermal)

/datum/rig_vision/meson
	mode = "meson scanner"

/datum/rig_vision/meson/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/meson)

/datum/rig_vision/graviton
	mode = "graviton scanner"

/datum/rig_vision/graviton/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/graviton)

/datum/rig_vision/sechud
	mode = "security HUD"

/datum/rig_vision/sechud/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/hud/security)

/datum/rig_vision/medhud
	mode = "medical HUD"

/datum/rig_vision/medhud/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/hud/health)

/datum/rig_vision/material
	mode = "material scanner"

/datum/rig_vision/material/New()
	rel_set(src, nameof(glasses), new /obj/item/clothing/glasses/material)

/obj/item/rig_module/vision

	name = "hardsuit visor"
	desc = "A layered, translucent visor system for a hardsuit."
	icon_state = "optics"

	interface_name = "optical scanners"
	interface_desc = "An integrated multi-mode vision system."

	usable = TRUE
	toggleable = TRUE
	disruptive = FALSE
	module_cooldown = 0

	engage_string = "Cycle Visor Mode"
	activate_string = "Enable Visor"
	deactivate_string = "Disable Visor"

	var/datum/rig_vision/vision
	var/list/vision_modes = list( // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
		/datum/rig_vision/nvg,
		/datum/rig_vision/thermal,
		/datum/rig_vision/meson
		)

	var/vision_index

CAPABILITIES(/obj/item/rig_module/vision)
	owns_many(nameof(vision_modes))

/obj/item/rig_module/vision/multi

	name = "hardsuit optical package"
	desc = "A complete visor system of optical scanners and vision modes."
	icon_state = "fulloptics"

	interface_name = "multi optical visor"
	interface_desc = "An integrated multi-mode vision system."

	vision_modes = list(/datum/rig_vision/graviton,
						/datum/rig_vision/nvg,
						/datum/rig_vision/thermal,
						/datum/rig_vision/sechud,
						/datum/rig_vision/medhud)

/obj/item/rig_module/vision/meson

	name = "hardsuit meson scanner"
	desc = "A layered, translucent visor system for a hardsuit."
	icon_state = "meson"

	usable = FALSE

	interface_name = "meson scanner"
	interface_desc = "An integrated meson scanner."

	vision_modes = list(/datum/rig_vision/meson)

/obj/item/rig_module/vision/material

	name = "hardsuit material scanner"
	desc = "A layered, translucent visor system for a hardsuit."
	icon_state = "meson"

	usable = FALSE

	interface_name = "material scanner"
	interface_desc = "An integrated material scanner."

	vision_modes = list(/datum/rig_vision/material)

/obj/item/rig_module/vision/graviton

	name = "hardsuit graviton visor"
	desc = "A layered, translucent visor system for a hardsuit."
	icon_state = "optics"

	usable = FALSE

	interface_name = "graviton visor"
	interface_desc = "An integrated graviton scanner."

	vision_modes = list(/datum/rig_vision/graviton)

/obj/item/rig_module/vision/mining

	name = "hardsuit mining scanners"
	desc = "A layered, translucent visor system for a hardsuit."
	icon_state = "optics"

	usable = FALSE

	interface_name = "mining scanners"
	interface_desc = "An integrated mining scanner array."

	vision_modes = list(/datum/rig_vision/material,
						/datum/rig_vision/meson)

/obj/item/rig_module/vision/thermal

	name = "hardsuit thermal scanner"
	desc = "A layered, translucent visor system for a hardsuit."
	icon_state = "thermal"

	usable = FALSE

	interface_name = "thermal scanner"
	interface_desc = "An integrated thermal scanner."

	vision_modes = list(/datum/rig_vision/thermal)

/obj/item/rig_module/vision/nvg

	name = "hardsuit night vision interface"
	desc = "A multi input night vision system for a hardsuit."
	icon_state = "night"

	usable = FALSE

	interface_name = "night vision interface"
	interface_desc = "An integrated night vision system."

	vision_modes = list(/datum/rig_vision/nvg)

/obj/item/rig_module/vision/sechud

	name = "hardsuit security hud"
	desc = "A simple tactical information system for a hardsuit."
	icon_state = "securityhud"

	usable = FALSE

	interface_name = "security HUD"
	interface_desc = "An integrated security heads up display."

	vision_modes = list(/datum/rig_vision/sechud)

/obj/item/rig_module/vision/medhud

	name = "hardsuit medical hud"
	desc = "A simple medical status indicator for a hardsuit."
	icon_state = "healthhud"

	usable = FALSE

	interface_name = "medical HUD"
	interface_desc = "An integrated medical heads up display."

	vision_modes = list(/datum/rig_vision/medhud)

// There should only ever be one vision module installed in a suit.
/obj/item/rig_module/vision/installed()
	..()
	rel_set(holder, nameof(holder.visor), src)


/obj/item/rig_module/vision/engage(atom/target, notify_ai, mob/user)

	if(!..() || !vision_modes)
		return FALSE

	// Don't cycle if this engage() is being called by activate().
	if(!active)
		to_chat(holder.wearer(), span_blue("You activate your visual sensors."))
		return TRUE

	if(vision_modes.len > 1)
		vision_index++
		if(vision_index > vision_modes.len)
			vision_index = 1
		rel_set(src, nameof(vision), vision_modes[vision_index])

		to_chat(holder.wearer(), span_blue("You cycle your sensors to <b>[vision.mode]</b> mode."))
	else
		to_chat(holder.wearer(), span_blue("Your sensors only have one mode."))
	return TRUE

/obj/item/rig_module/vision/activate(skip_engage = 0, mob/user)
	if((. = ..()) && holder.wearer())
		holder.wearer().recalculate_vis()

/obj/item/rig_module/vision/deactivate(forced = FALSE, mob/user)
	if((. = ..()) && holder.wearer())
		holder.wearer().recalculate_vis()

/obj/item/rig_module/vision/Initialize(mapload)
	. = ..()

	if(!vision_modes)
		return

	vision_index = 1
	// vision_modes starts as a list of types; it becomes the module's owned instances.
	var/list/mode_types = vision_modes.Copy()
	rel_clear(src, nameof(vision_modes)) // the type list holds no children yet: this only empties it
	for(var/vision_mode in mode_types)
		var/datum/rig_vision/vision_datum = rel_add(src, nameof(vision_modes), new vision_mode)
		if(!vision)
			rel_set(src, nameof(vision), vision_datum)


// vision_modes holds the module's own /datum/rig_vision instances once processed; vision points at one of them.
