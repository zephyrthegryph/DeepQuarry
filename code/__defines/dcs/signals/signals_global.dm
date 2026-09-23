// Global signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

// global signals
// These are signals which can be listened to by any component on any parent
// start global signals with "!", this used to be necessary but now it's just a formatting choice


/// sent after world.maxx and/or world.maxy are expanded: (has_exapnded_world_maxx, has_expanded_world_maxy)
#define COMSIG_GLOB_EXPANDED_WORLD_BOUNDS "!expanded_world_bounds"
/// called after a successful var edit somewhere in the world: (list/args)
#define COMSIG_GLOB_VAR_EDIT "!var_edit"
/// called after an explosion happened : (epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
#define COMSIG_GLOB_EXPLOSION "!explosion"
/// Called from base of /mob/Initialise : (mob)
#define COMSIG_GLOB_MOB_CREATED "!mob_created"
/// mob died somewhere : (mob/living, gibbed)
#define COMSIG_GLOB_MOB_DEATH "!mob_death"
/// called by datum/cinematic/play() : (datum/cinematic/new_cinematic)
#define COMSIG_GLOB_PLAY_CINEMATIC "!play_cinematic"
	#define COMPONENT_GLOB_BLOCK_CINEMATIC (1<<0)
/// ingame button pressed (/obj/machinery/button/button)
#define COMSIG_GLOB_BUTTON_PRESSED "!button_pressed"
/// called post /obj/item initialize (obj/item/created_item)
#define COMSIG_GLOB_ATOM_AFTER_POST_INIT "!atom_after_post_init"


// NON TG SPECIFIC SIGNALS:

// Shuttle Comsigs
/// Supply shuttle selling, before all items are sold, called by /datum/controller/subsystem/supply/proc/sell() : (/list/area/supply_shuttle_areas)
#define COMSIG_GLOB_SUPPLY_SHUTTLE_DEPART "!sell_supply_shuttle"
/// Supply shuttle selling, for each item sold, called by /datum/controller/subsystem/supply/proc/sell() : (atom/movable/sold_item, sold_successfully, datum/exported_crate/export_data, area/shuttle_subarea)
#define COMSIG_GLOB_SUPPLY_SHUTTLE_SELL_ITEM "!supply_shuttle_sell_item"
/// Mind inserted into body: (mob/new_owner, /datum/mind/assigned_mind)
#define COMSIG_GLOB_RESLEEVED_MIND "!resleeved_mind_into_body"

/// /datum/controller/subsystem/ticker/proc/setup() : ()
#define COMSIG_GLOB_ROUND_START "!round_start"
/// /datum/controller/subsystem/ticker/proc/post_game_tick() : ()
#define COMSIG_GLOB_ROUND_END "!round_end"

//NON TG Signals:
/// borg created: (mob/living/silicon/robot/new_robot)
#define COMSIG_GLOB_BORGIFY "!borgify_mob"
/// brain removed from body, called by /obj/item/organ/internal/brain/proc/transfer_identity() : (mob/living/carbon/brain/brainmob)
#define COMSIG_GLOB_BRAIN_REMOVED "!brain_removed_from_mob"
/// ID card modified: (obj/item/card/id/modified_card)
#define COMSIG_GLOB_REASSIGN_EMPLOYEE_IDCARD "!modified_employee_idcard"
/// ID card terminated: (obj/item/card/id/terminated_card)
#define COMSIG_GLOB_TERMINATE_EMPLOYEE_IDCARD "!modified_terminated_idcard"
/// payment account status changed /obj/machinery/account_database/tgui_act() : (datum/money_account/account)
#define COMSIG_GLOB_PAYMENT_ACCOUNT_STATUS "!payment_account_change_status"
/// payment account status changed /obj/machinery/account_database/tgui_act() : (datum/money_account/account)
#define COMSIG_GLOB_PAYMENT_ACCOUNT_REVOKE "!payment_account_revoke_payroll"

// base /datum/decl/emote/proc/do_emote() : (mob/user, extra_params)
#define COMSIG_GLOB_EMOTE_PERFORMED "!emote_performed"
// base /proc/say_dead_direct() : (message)
#define COMSIG_GLOB_DEAD_SAY "!dead_say"
// base /turf/wash() : ()
#define COMSIG_GLOB_WASHED_FLOOR "!washed_floor"
// base /obj/machinery/artifact_harvester/proc/harvest() : (obj/item/anobattery/inserted_battery, mob/user)
#define COMSIG_GLOB_HARVEST_ARTIFACT "!harvest_artifact"
// upon harvesting a slime's extract : (obj/item/slime_extract/newly_made_core)
#define COMSIG_GLOB_HARVEST_SLIME_CORE "!harvest_slime_core"
// base /datum/recipe/proc/make_food() : (obj/container, list/results)
#define COMSIG_GLOB_FOOD_PREPARED "!recipe_food_completed"
// base /datum/construction/proc/spawn_result() : (/obj/mecha/result_mech)
#define COMSIG_GLOB_MECH_CONSTRUCTED "!mecha_constructed"
// when trashpiles are successfully searched : (mob/living/user, list/searched_by)
#define COMSIG_GLOB_TRASHPILE_SEARCHED "!trash_pile_searched"
// upon forensics swap or sample kit forensics collection : (atom/target, mob/user)
#define COMSIG_GLOB_FORENSICS_COLLECTED "!performed_forensics_collection"

// base /obj/item/autopsy_scanner/do_surgery() : (mob/user, mob/target)
#define COMSIG_GLOB_AUTOPSY_PERFORMED "!performed_autopsy"
