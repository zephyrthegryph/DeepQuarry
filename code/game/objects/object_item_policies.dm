STATIC_ENTRY(throwing_config)
/proc/throwing_config(spin = null)
	return entry_make(ENTRY_THROWING_CONFIG, null, list("spin" = spin))
/datum/type_trait/throwing_config
	var/spin = TRUE
/datum/type_trait/throwing_config/copy_values(datum/type_trait/throwing_config/into)
	into.spin = spin
/datum/entry_engine/type_trait/throwing_config
	kind = ENTRY_THROWING_CONFIG
	trait_type = /datum/type_trait/throwing_config
	publish_key = THROWING_CONFIG_KEY
	base_type = /atom/movable
	var_names = list("does_spin" = "spin")
READS_AS(/proc/throwing_config_of, THROWING_CONFIG_KEY)
/proc/throwing_config_of(atom/movable/holder) as /datum/type_trait/throwing_config
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_THROWING_CONFIG)
/proc/throwing_config_of_type(type) as /datum/type_trait/throwing_config
	READS_FROM()
	return type_trait_of_type(type, ENTRY_THROWING_CONFIG)
/atom/movable/proc/set_does_spin(value)
	return set_trait(src, ENTRY_THROWING_CONFIG, "spin", value)

STATIC_ENTRY(item_placement)
/proc/item_placement(center_x = null, center_y = null)
	return entry_make(ENTRY_ITEM_PLACEMENT, null, list("center_x" = center_x, "center_y" = center_y))
/datum/type_trait/item_placement
	var/center_x = 16
	var/center_y = 16
/datum/type_trait/item_placement/copy_values(datum/type_trait/item_placement/into)
	into.center_x = center_x
	into.center_y = center_y
/datum/entry_engine/type_trait/item_placement
	kind = ENTRY_ITEM_PLACEMENT
	trait_type = /datum/type_trait/item_placement
	publish_key = ITEM_PLACEMENT_KEY
	base_type = /obj/item
	var_names = list("center_of_mass_x" = "center_x", "center_of_mass_y" = "center_y")
READS_AS(/proc/placement_of, ITEM_PLACEMENT_KEY)
/proc/placement_of(obj/item/holder) as /datum/type_trait/item_placement
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_PLACEMENT)
/proc/placement_of_type(type) as /datum/type_trait/item_placement
	READS_FROM()
	return type_trait_of_type(type, ENTRY_ITEM_PLACEMENT)
/obj/item/proc/set_center_of_mass_x(value)
	return set_trait(src, ENTRY_ITEM_PLACEMENT, "center_x", value)
/obj/item/proc/set_center_of_mass_y(value)
	return set_trait(src, ENTRY_ITEM_PLACEMENT, "center_y", value)

STATIC_ENTRY(object_communication)
/proc/object_communication(hears = null, speaks = null, shown = null)
	return entry_make(ENTRY_OBJECT_COMMUNICATION, null, list("hears" = hears, "speaks" = speaks, "shown" = shown))
/datum/type_trait/object_communication
	var/hears = null
	var/speaks = 0
	var/shown = TRUE
/datum/type_trait/object_communication/copy_values(datum/type_trait/object_communication/into)
	into.hears = hears
	into.speaks = speaks
	into.shown = shown
/datum/entry_engine/type_trait/object_communication
	kind = ENTRY_OBJECT_COMMUNICATION
	trait_type = /datum/type_trait/object_communication
	publish_key = OBJECT_COMMUNICATION_KEY
	base_type = /obj
	var_names = list("show_messages" = "hears", "can_speak" = "speaks", "show_examine" = "shown")
READS_AS(/proc/communication_of, OBJECT_COMMUNICATION_KEY)
/proc/communication_of(obj/holder) as /datum/type_trait/object_communication
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_OBJECT_COMMUNICATION)
/proc/communication_of_type(type) as /datum/type_trait/object_communication
	READS_FROM()
	return type_trait_of_type(type, ENTRY_OBJECT_COMMUNICATION)
/obj/proc/set_show_messages(value)
	return set_trait(src, ENTRY_OBJECT_COMMUNICATION, "hears", value)
/obj/proc/set_can_speak(value)
	return set_trait(src, ENTRY_OBJECT_COMMUNICATION, "speaks", value)
/obj/proc/set_show_examine(value)
	return set_trait(src, ENTRY_OBJECT_COMMUNICATION, "shown", value)

STATIC_ENTRY(object_transfer)
/proc/object_transfer(redgate = null)
	return entry_make(ENTRY_OBJECT_TRANSFER, null, list("redgate" = redgate))
/datum/type_trait/object_transfer
	var/redgate = TRUE
/datum/type_trait/object_transfer/copy_values(datum/type_trait/object_transfer/into)
	into.redgate = redgate
/datum/entry_engine/type_trait/object_transfer
	kind = ENTRY_OBJECT_TRANSFER
	trait_type = /datum/type_trait/object_transfer
	publish_key = OBJECT_TRANSFER_KEY
	base_type = /obj
	var_names = list("redgate_allowed" = "redgate")
READS_AS(/proc/transfer_policy_of, OBJECT_TRANSFER_KEY)
/proc/transfer_policy_of(obj/holder) as /datum/type_trait/object_transfer
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_OBJECT_TRANSFER)
/proc/transfer_policy_of_type(type) as /datum/type_trait/object_transfer
	READS_FROM()
	return type_trait_of_type(type, ENTRY_OBJECT_TRANSFER)
/obj/proc/set_redgate_allowed(value)
	return set_trait(src, ENTRY_OBJECT_TRANSFER, "redgate", value)

STATIC_ENTRY(item_admission)
/proc/item_admission(trash = null)
	return entry_make(ENTRY_ITEM_ADMISSION, null, list("trash" = trash))
/datum/type_trait/item_admission
	var/trash = TRUE
/datum/type_trait/item_admission/copy_values(datum/type_trait/item_admission/into)
	into.trash = trash
/datum/entry_engine/type_trait/item_admission
	kind = ENTRY_ITEM_ADMISSION
	trait_type = /datum/type_trait/item_admission
	publish_key = ITEM_ADMISSION_KEY
	base_type = /obj/item
	var_names = list("trash_eatable" = "trash")
READS_AS(/proc/item_admission_of, ITEM_ADMISSION_KEY)
/proc/item_admission_of(obj/item/holder) as /datum/type_trait/item_admission
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_ADMISSION)
/proc/item_admission_of_type(type) as /datum/type_trait/item_admission
	READS_FROM()
	return type_trait_of_type(type, ENTRY_ITEM_ADMISSION)
/obj/item/proc/set_trash_eatable(value)
	return set_trait(src, ENTRY_ITEM_ADMISSION, "trash", value)

