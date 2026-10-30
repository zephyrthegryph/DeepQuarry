#define DISEASE_LIMIT		3
#define VIRUS_SYMPTOM_LIMIT	6

//Visibility Flags
#define HIDDEN_SCANNER	(1<<0)
#define HIDDEN_PANDEMIC	(1<<1)

//Disease Flags
#define CURABLE				(1<<0)
#define CAN_CARRY			(1<<1)
#define CAN_RESIST			(1<<2)
#define CAN_NOT_POPULATE	(1<<3)

//Spread Flags
#define DISEASE_SPREAD_SPECIAL			(1<<0)
#define DISEASE_SPREAD_NON_CONTAGIOUS	(1<<1)
#define DISEASE_SPREAD_BLOOD			(1<<2)
#define DISEASE_SPREAD_FLUIDS			(1<<3)
#define DISEASE_SPREAD_CONTACT			(1<<4)
#define DISEASE_SPREAD_AIRBORNE			(1<<5)
#define DISEASE_SPREAD_FALTERED			(1<<6)

//Severity Defines
#define DISEASE_BENEFICIAL	"Beneficial"
#define DISEASE_POSITIVE	"Positive"
#define DISEASE_NONTHREAT	"No threat"
#define DISEASE_MINOR		"Minor"
#define DISEASE_MEDIUM		"Medium"
#define DISEASE_HARMFUL		"Harmful"
#define DISEASE_DANGEROUS 	"Dangerous"
#define DISEASE_BIOHAZARD	"BIOHAZARD"
#define DISEASE_PANDEMIC	"PANDEMIC"

//Various Virus Flags
#define NEEDS_ALL_CURES			0x1		/// If a virus requires EVERY cure in the cure list to become cured.
#define SPREAD_DEAD				0x2		/// If a virus spreads to the dead and proceesses in them.
#define INFECT_SYNTHETICS		0x4		/// If a synthetic can be infected with the virus.
#define HAS_TIMER				0x8		/// If the cure timer is currently active.
#define PROCESSING				0x10	/// If stage_act has been called and we are now processing.
#define CARRIER					0x20	/// If we are a carrier for the virus but we will not be affected by it.
#define BYPASSES_IMMUNITY 		0x40	/// If this virus bypasses immunity.
#define DISCOVERED				0x80	/// If applied, this virus will show up on medical HUDs. Automatically set when it reaches mid-stage.
#define DORMANT					0x100	/// If applied, the virus is dormant and will not act or spread.
#define FALTERED				0x200	/// If applied, the virus is faltered and will only spread by intentional injection.
#define IMMUTABLE				0x400 	/// If applied, the virus will not mutate in any kind of way.

// Contagion (disease) afflictions: code/modules/medical/contagion.
/// Host immune response at which a curable contagion is cleared.
#define CONTAGION_IMMUNITY_CLEAR 100
/// Host immune response at which a contagion stops advancing and regresses.
#define CONTAGION_IMMUNITY_CONTROL 50
/// Immunity per tick at full natural regeneration (rest, nutrition): ~55 min to clear awake, half that asleep.
#define CONTAGION_IMMUNE_BASE 0.06
/// Immunity per tick at a standard dose of an antimicrobial (spaceacillin).
#define CONTAGION_IMMUNE_ANTIMICROBIAL 0.15
/// Extra immunity per tick while the host lies down (bed rest).
#define CONTAGION_IMMUNE_BEDREST 0.04

// Transmission routes (/datum/affliction_trigger/contagion/expose()).
/// Breathed in: internals and breath-proof hosts are safe; a mask filters.
#define CONTAGION_ROUTE_AIRBORNE "airborne"
/// Skin contact on a body zone: the clothing covering it filters.
#define CONTAGION_ROUTE_CONTACT "contact"
/// Straight into the blood or gut (injection, ingestion): nothing filters.
#define CONTAGION_ROUTE_BLOOD "blood"

#define EXTRAPOLATOR_RESULT_DISEASES		"extrapolator_result_disease"
#define EXTRAPOLATOR_RESULT_ACT_PRIORITY	"extrapolator_result_action_priority"
#define EXTRAPOLATOR_ACT_PRIORITY_SPECIAL	"extrapolator_action_priority_special"
#define EXTRAPOLATOR_ACT_PRIORITY_ISOLATE	"extrapolator_action_priority_isolate"
#define EXTRAPOLATOR_ACT_ADD_DISEASES(target_list, diseases)\
	do {\
		var/_D = ##diseases;\
		if ((islist(_D) && length(_D)) || istype(_D, /datum/affliction/contagion)) {	\
			LAZYORASSOCLIST(##target_list, EXTRAPOLATOR_RESULT_DISEASES, _D);\
		}\
	} while(0)
#define EXTRAPOLATOR_ACT_CHECK(target_list, wanted_action_priority) (##target_list[EXTRAPOLATOR_RESULT_ACT_PRIORITY] == ##wanted_action_priority)
#define EXTRAPOLATOR_ACT_SET(target_list, wanted_action_priority) (##target_list[EXTRAPOLATOR_RESULT_ACT_PRIORITY] = ##wanted_action_priority)
