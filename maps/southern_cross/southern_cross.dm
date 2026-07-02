// You probably don't want to tick this file yet.

#if !defined(USING_MAP_DATUM)

	#include "southern_cross_areas.dm"
	#include "southern_cross_defines.dm"
	#include "southern_cross_jobs.dm"
	#include "southern_cross_elevator.dm"
	#include "southern_cross_events.dm"
	#include "southern_cross_overrides.dm"
	#include "southern_cross_presets.dm"
	#include "southern_cross_shuttles.dm"

	#include "shuttles/crew_shuttles.dm"
	#include "shuttles/heist.dm"
	#include "shuttles/merc.dm"
	#include "shuttles/ninja.dm"
	#include "shuttles/ert.dm"

	#include "loadout/loadout_accessories.dm"
	#include "loadout/loadout_head.dm"
	#include "loadout/loadout_suit.dm"
	#include "loadout/loadout_uniform.dm"

	#include "datums/supplypacks/munitions.dm"
	#include "items/encryptionkey_sc.dm"
	#include "items/headset_sc.dm"
	#include "items/clothing/sc_suit.dm"
	#include "items/clothing/sc_under.dm"
	#include "items/clothing/sc_accessory.dm"
	#include "job/outfits.dm"
	#include "structures/closets/engineering.dm"
	#include "structures/closets/medical.dm"
	#include "structures/closets/misc.dm"
	#include "structures/closets/research.dm"
	#include "structures/closets/security.dm"
	#include "turfs/outdoors.dm"
	#include "overmap/sectors.dm"

	// Station-only trim (2026-07-01). Load order sets z-levels:
	//   -1 = station decks (z1,2,3), -6 = CentCom (z4), -7 = Transit (z5).
	// Removed: -2 (empty), -3 Plains, -4 Mountains, -5 misc/derelict, -8 Wilderness.
	#include "southern_cross-1.dmm"
	#include "southern_cross-6.dmm"
	#include "southern_cross-7.dmm"

	#define USING_MAP_DATUM /datum/map/southern_cross

	// todo: map.dmm-s here

#elif !defined(MAP_OVERRIDE)

	#warn A map has already been included, ignoring Southern Cross

#endif