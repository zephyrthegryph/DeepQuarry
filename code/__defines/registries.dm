// Registries (roadmap L3, doc/rewrite/state.md section 7).
//
// A registry is the set of live instances of some kind: every PDA, every APC,
// every camera. It replaces the ad-hoc `GLOB.x += src` / `GLOB.x -= src` lists.
//
// Membership is declared on the type, never written by hand:
//
//     REGISTRY_MEMBERSHIP(/obj/item/pda, REGISTRY_PDAS)
//
// /atom/on_materialize() joins every registry the type declares, and
// /atom/on_dematerialize() leaves them. Destroy() always dematerializes, so a
// deleted object can never be left behind in a registry.
//
// Reading: REGISTRY_MEMBERS(id) is the live member list, in join order. Treat
// it as read-only; copy it before doing anything that could delete members.
// A keyed registry also answers REGISTRY_KEYED(id, key).
//
// New registries: add an id here and a REGISTRY_DECLARE() line in
// code/datums/registries.dm. tools/ci/registry_lint.py refuses new ad-hoc
// global lists of instances.

/// The live member list of a registry, in join order. Read-only.
#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
/// Members of a keyed registry filed under KEY (a list, possibly null).
#define REGISTRY_KEYED(ID, KEY) registry_keyed(ID, KEY)
/// A copy of the member list, safe to change or to walk while deleting.
#define REGISTRY_COPY(ID) (list() + GLOB.registry_members[ID])
/// How many live members a registry has.
#define REGISTRY_COUNT(ID) length(GLOB.registry_members[ID])

/// Declares a registry: `/datum/registry/NAME` with `id = ID`.
#define REGISTRY_DECLARE(NAME, ID) /datum/registry/##NAME { id = ID }

/// Declares that PATH (and its subtypes) belong to registry ID while materialized.
/// A type may use this once per registry; each use adds one id.
#define REGISTRY_MEMBERSHIP(PATH, ID) ##PATH/declare_registries(list/ids) { ..(); ids += ID; }

// Registry ids. Keep them sorted.
#define REGISTRY_AI_CORES_DEACTIVATED "all_deactivated_AI_cores"
#define REGISTRY_ALARM_CONSOLES "allConsoles"
#define REGISTRY_APCS "apcs"
#define REGISTRY_AUTORESLEEVERS "active_autoresleevers"
#define REGISTRY_BEACONS "all_beacons"
#define REGISTRY_BEAM_POINTS "all_beam_points"
#define REGISTRY_BLOB_CORES "blob_cores"
#define REGISTRY_BLOB_NODES "blob_nodes"
#define REGISTRY_BLOBS "all_blobs"
#define REGISTRY_BODYCAMERA_SCREENS "bodycamera_screens"
#define REGISTRY_BRIG_CLOSETS "all_brig_closets"
#define REGISTRY_BUILDMODE_HOLDERS "active_buildmode_holders"
#define REGISTRY_BUMP_TELEPORTERS "bump_teleporters"
#define REGISTRY_CABLES "cable_list"
#define REGISTRY_CAMERAS "cameras"
#define REGISTRY_CASTERS "allCasters"
#define REGISTRY_CATALOGUERS "all_cataloguers"
#define REGISTRY_CHEM_IMPLANTS "all_chem_implants"
#define REGISTRY_COMMUNICATORS "all_communicators"
#define REGISTRY_CREMATORIUMS "all_crematoriums"
#define REGISTRY_DARKPORTAL_HUBS "all_darkportal_hubs"
#define REGISTRY_DARKPORTAL_MINIONS "all_darkportal_minions"
#define REGISTRY_DEBUGGING_EFFECTS "all_debugging_effects"
#define REGISTRY_DOCKING_CODE_PAPERS "papers_dockingcode"
#define REGISTRY_DRONE_FABRICATORS "all_drone_fabricators"
#define REGISTRY_ENGINE_SETUP_MARKERS "all_engine_setup_markers"
#define REGISTRY_ENTERTAINMENT_SCREENS "entertainment_screens"
#define REGISTRY_ENV_MESSAGES "env_messages"
#define REGISTRY_EVENT_COLLECTOR_BLOCKERS "event_collector_blockers"
#define REGISTRY_EVENT_COLLECTORS "event_collectors"
#define REGISTRY_EXTRACTION_BEACONS "total_extraction_beacons"
#define REGISTRY_FAXES "allfaxes"
#define REGISTRY_FUEL_INJECTORS "fuel_injectors"
#define REGISTRY_FUSION_CORES "fusion_cores"
#define REGISTRY_GEIGER_COUNTERS "geiger_counters"
#define REGISTRY_GPS "GPS_list"
#define REGISTRY_GYROTRONS "gyrotrons"
#define REGISTRY_HOLOPOSTERS "holoposters"
#define REGISTRY_JANITORIAL_CARTS "all_janitorial_carts"
#define REGISTRY_LANDMARKS "landmarks_list"
#define REGISTRY_MACHINES "machines"
#define REGISTRY_MECHAS "mechas_list"
#define REGISTRY_MESSAGE_SERVERS "message_servers"
#define REGISTRY_METEORS "meteor_list"
#define REGISTRY_MICRO_TUNNELS "micro_tunnels"
#define REGISTRY_MOP_BUCKETS "all_mopbuckets"
#define REGISTRY_MOPS "all_mops"
#define REGISTRY_NANITE_TURFS "nanite_turfs"
#define REGISTRY_NARSIE "narsie_list"
#define REGISTRY_NAVBEACONS "navbeacons"
#define REGISTRY_NUKE_DISKS "nuke_disks"
#define REGISTRY_OVERMAP_VISITABLES "visitable_overmap_object_instances"
#define REGISTRY_PAI_CARDS "all_pai_cards"
#define REGISTRY_PDAS "PDAs"
#define REGISTRY_POINTDEFENSE_CONTROLLERS "pointdefense_controllers"
#define REGISTRY_POINTDEFENSE_TURRETS "pointdefense_turrets"
#define REGISTRY_PORTAL_MASTERS "all_portal_masters"
#define REGISTRY_PORTALS "all_portals"
#define REGISTRY_RAD_COLLECTORS "rad_collectors"
#define REGISTRY_RUNES "rune_list"
#define REGISTRY_SEED_PACKS "all_seed_packs"
#define REGISTRY_SHUTOFF_VALVES "shutoff_valves"
#define REGISTRY_SIMPLE_PORTALS "simple_portals"
#define REGISTRY_SINGULARITIES "all_singularities"
#define REGISTRY_SMES "smeses"
#define REGISTRY_TELE_BEACONS_PREMADE "premade_tele_beacons"
#define REGISTRY_TELE_LANDMARKS "tele_landmarks"
#define REGISTRY_TELECOMMS "telecomms_list"
#define REGISTRY_TRACKING_IMPLANTS "all_tracking_implants"
#define REGISTRY_TRANSACTION_DEVICES "transaction_devices"
#define REGISTRY_TURBINES "all_turbines"
#define REGISTRY_TURBOLIFT_HOLDERS "turbolifts"
