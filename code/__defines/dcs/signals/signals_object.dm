// Object signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

// /obj signals
///from base of obj/deconstruct(): (disassembled)
#define COMSIG_OBJ_DECONSTRUCT "obj_deconstruct"


// /obj/machinery signals

///from /obj/machinery/atom_break(damage_flag): (damage_flag)
#define COMSIG_MACHINERY_BROKEN "machinery_broken"
///from base power_change() when power is lost
#define COMSIG_MACHINERY_POWER_LOST "machinery_power_lost"
///from base power_change() when power is restored
#define COMSIG_MACHINERY_POWER_RESTORED "machinery_power_restored"
///from /obj/machinery/rnd/destructive_analyzer/proc/destroy_item(gain_research_points = FALSE): Runs when the destructive scanner scans a group of objects. (list/scanned_atoms)
#define COMSIG_MACHINERY_DESTRUCTIVE_SCAN "machinery_destructive_scan"
///from /obj/machinery/doppler_array/proc/sense_explosion(): Runs when an explosion is detected. (turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
#define COMSIG_MACHINERY_EXPLOSION_DETECTED "machinery_explosion_detected"
///from /obj/machinery/computer/telescience/proc/doteleport(mob/user): (list/atom/movable/teleported_things, turf/target_turf, sending )
#define COMSIG_TELESCI_TELEPORT "telesci_teleport"
// COMSIG_MACHINERY_START_PROCESSING_AIR / STOP_PROCESSING_AIR removed
// alongside SSair.atmos_machinery; the only "raisers" were the SSair procs that
// are themselves gone. No subscribers existed.


// /obj/machinery/computer/teleporter

// /obj/machinery/power/supermatter_crystal


// /obj/machinery/cryo_cell signals


// /obj/machinery/atmospherics/components/binary/valve signals


// /obj access signals


// /obj/machinery/door/airlock signals

//from /obj/machinery/door/airlock/open(): (forced)
//from /obj/machinery/door/airlock/close(): (forced)

// /obj/item signals

///from base of obj/item/equipped(): (mob/equipper, slot)
#define COMSIG_ITEM_EQUIPPED "item_equip"
/// A mob has just equipped an item. Called on [/mob] from base of [/obj/item/equipped()]: (/obj/item/equipped_item, slot)
#define COMSIG_MOB_EQUIPPED_ITEM "mob_equipped_item"
/// A mob has just unequipped an item.
#define COMSIG_MOB_UNEQUIPPED_ITEM "mob_unequipped_item"
///from base of obj/item/dropped(): (mob/user)
#define COMSIG_ITEM_DROPPED "item_drop"
///from base of obj/item/pickup(): (/mob/taker)
#define COMSIG_ITEM_PICKUP "item_pickup"

/**
 * From base of datum/strippable_item/get_alternate_actions(): (atom/owner, mob/user, list/alt_actions)
 * As a side note, make sure the strippable item datum (the slot) in question doesn't have too many alternate actions already,
 * as only up to three are supported at a time (as of september 2025), though, so far only the jumpsuit slot uses all three slots.
 *
 * Also make sure to code the alt action and add it to the StripMenu.tsx interface
 */


// /obj signals for economy

// /obj/item signals for economy
///called when an item is sold by the exports subsystem
#define COMSIG_ITEM_EXPORTED "item_sold"
	/// Stops the export from adding the export information to the report, so you can handle it manually.
	#define COMPONENT_STOP_EXPORT_REPORT (1<<0)


// /obj/item/clothing signals

///from [/mob/living/carbon/human/Move]: ()
#define COMSIG_SHOES_STEP_ACTION "shoes_step_action"

// /obj/item/implant signals
	//#define COMPONENT_STOP_IMPLANTING (1<<0) //The name makes sense for both
	#define COMPONENT_DELETE_NEW_IMPLANT (1<<1)
	#define COMPONENT_DELETE_OLD_IMPLANT (1<<2)


	//This uses all return values of COMSIG_IMPLANT_OTHER

// /obj/item/pda signals


// /obj/item/radio signals


// /obj/item/pen signals


// /obj/item/gun signals


// Jetpack things
// Please kill me

//called in /obj/item/tank/jetpack/proc/turn_on() : ()
//called in /obj/item/tank/jetpack/proc/turn_off() : ()

//called in /obj/item/organ/cyberimp/chest/thrusters/proc/toggle() : ()
//called in /obj/item/organ/cyberimp/chest/thrusters/proc/toggle() : ()

// /obj/item/camera signals


// /obj/item/grenade signals


// /obj/projectile signals (sent to the firer)

// FROM [/obj/item/proc/set_embed] sent when an item's embedding properties are changed : ()


// /obj/vehicle/sealed/car/vim signals


// /obj/vehicle/sealed/mecha signals


///from base of /obj/item/attack(): (mob/living, mob/living, list/modifiers, list/attack_modifiers)
#define COMSIG_ITEM_ATTACK "item_attack"
///from base of obj/item/attack_self(): (/mob)
#define COMSIG_ITEM_ATTACK_SELF "item_attack_self"
//from base of obj/item/attack_self_secondary(): (/mob)
///from base of obj/item/pre_attack(): (atom/target, mob/user, list/modifiers, list/attack_modifiers)
#define COMSIG_ITEM_PRE_ATTACK "item_pre_attack"


/*
 * The following four signals are separate from the above two because buttons and pressure plates don't set the holder of the inserted assembly.
 * This causes subtle behavioral differences that future handlers for these signals may need to account for,
 * even if none of the currently implemented handlers do.
 */


//Non TG signals:
///from /proc/techweb_item_point_check(obj/item/I): Runs when assessing an item's techweb point value.
#define COMSIG_TECHWEB_POINT_CHECK "techweb_point_check"
///from /proc/techweb_item_point_check(obj/item/I): Runs when assessing an item's techweb point type.
#define COMSIG_TECHWEB_TYPE_CHECK "techweb_type_check"
