// Global signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

// global signals
// These are signals which can be listened to by any component on any parent
// start global signals with "!", this used to be necessary but now it's just a formatting choice


/// called after an explosion happened : (epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
#define COMSIG_GLOB_EXPLOSION "!explosion"
/// Called from base of /mob/Initialise : (mob)
#define COMSIG_GLOB_MOB_CREATED "!mob_created"
/// mob died somewhere : (mob/living, gibbed)
#define COMSIG_GLOB_MOB_DEATH "!mob_death"
/// called by datum/cinematic/play() : (datum/cinematic/new_cinematic)
#define COMSIG_GLOB_PLAY_CINEMATIC "!play_cinematic"
	#define COMPONENT_GLOB_BLOCK_CINEMATIC (1<<0)


// NON TG SPECIFIC SIGNALS:

// Shuttle Comsigs
/// Supply shuttle selling, before all items are sold, called by /datum/controller/subsystem/supply/proc/sell() : (/list/area/supply_shuttle_areas)
#define COMSIG_GLOB_SUPPLY_SHUTTLE_DEPART "!sell_supply_shuttle"


//NON TG Signals:
/// brain removed from body, called by /obj/item/organ/internal/brain/proc/transfer_identity() : (mob/living/carbon/brain/brainmob)
#define COMSIG_GLOB_BRAIN_REMOVED "!brain_removed_from_mob"
/// payment account status changed /obj/machinery/account_database/tgui_act() : (datum/money_account/account)
#define COMSIG_GLOB_PAYMENT_ACCOUNT_STATUS "!payment_account_change_status"

// base /datum/decl/emote/proc/do_emote() : (mob/user, extra_params)
// base /proc/say_dead_direct() : (message)
// base /turf/wash() : ()
// base /obj/machinery/artifact_harvester/proc/harvest() : (obj/item/anobattery/inserted_battery, mob/user)
// upon harvesting a slime's extract : (obj/item/slime_extract/newly_made_core)
// base /datum/recipe/proc/make_food() : (obj/container, list/results)
// base /datum/construction/proc/spawn_result() : (/obj/mecha/result_mech)
// when trashpiles are successfully searched : (mob/living/user, list/searched_by)
// upon forensics swap or sample kit forensics collection : (atom/target, mob/user)

// base /obj/item/autopsy_scanner/do_surgery() : (mob/user, mob/target)
#define COMSIG_GLOB_AUTOPSY_PERFORMED "!performed_autopsy"
