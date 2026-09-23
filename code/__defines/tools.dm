// Tool types, if you add new ones please add them to /obj/item/debug/omnitool in code/game/objects/items/debug_items.dm
#define TOOL_CROWBAR "crowbar"
#define TOOL_MULTITOOL "multitool"
#define TOOL_SCREWDRIVER "screwdriver"
#define TOOL_WIRECUTTER "wirecutter"
#define TOOL_WRENCH "wrench"
#define TOOL_WELDER "welder"
#define TOOL_CABLE_COIL "cablecoil"
#define TOOL_ANALYZER "analyzer"
#define TOOL_MINING "mining"
#define TOOL_SHOVEL "shovel"
#define TOOL_RETRACTOR "retractor"
#define TOOL_HEMOSTAT "hemostat"
#define TOOL_CAUTERY "cautery"
#define TOOL_DRILL "drill"
#define TOOL_SCALPEL "scalpel"
#define TOOL_SAW "saw"
#define TOOL_BONESET "bonesetter"
#define TOOL_KNIFE "knife"
#define TOOL_BLOODFILTER "bloodfilter"
#define TOOL_ROLLINGPIN "rollingpin"

/**
 * A helper for checking if an item interaction should be skipped.
 * This is only used explicitly because some interactions may not want to ever be skipped.
 */
#define SHOULD_SKIP_INTERACTION(target, item, user) (HAS_TRAIT(target, TRAIT_COMBAT_MODE_SKIP_INTERACTION) && IS_HARMING(user))

/// Return when an item interaction is successful.
/// This cancels the rest of the chain entirely and indicates success.
#define ITEM_INTERACT_SUCCESS (1<<0) // Same as TRUE, as most tool (legacy) tool acts return TRUE on success
/// Return to prevent the rest of the attack chain from being executed / preventing the item user from thwacking the target.
/// Similar to [ITEM_INTERACT_SUCCESS], but does not necessarily indicate success.
#define ITEM_INTERACT_BLOCKING (1<<1)
	/// Only for people who get confused by the naming scheme
	#define ITEM_INTERACT_FAILURE ITEM_INTERACT_BLOCKING
/// Return to skip the rest of the interaction chain, going straight to attack.
#define ITEM_INTERACT_SKIP_TO_ATTACK (1<<2)

/// Any result which consumes the click and therefore suppresses afterattack().
#define ITEM_INTERACT_CONSUMED(result) ((result) & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING))

// Declarative /obj/machinery maintenance capabilities.
#define MACHINE_MAINT_PANEL (1<<0)
#define MACHINE_MAINT_FRAME (1<<1)
#define MACHINE_MAINT_WRENCH (1<<2)
#define MACHINE_MAINT_WELDER_REPAIR (1<<3)
#define MACHINE_MAINT_STANDARD (MACHINE_MAINT_PANEL | MACHINE_MAINT_FRAME)
#define MACHINE_MAINT_STANDARD_MOVABLE (MACHINE_MAINT_STANDARD | MACHINE_MAINT_WRENCH)
