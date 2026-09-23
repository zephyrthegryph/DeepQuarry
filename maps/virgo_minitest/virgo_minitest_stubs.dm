// Compile stubs for the virgo_minitest unit-test map.
//
// virgo_minitest was ported from the CHOMPStation2 archive and still places a few
// content types that were removed during the hard fork. Since this map only exists
// to give the unit-test suite a small, clean station to boot on (CITESTING), these
// types just need to exist — they don't need behaviour. Real map content is gone.
//
// Kept in the map dir (not code/modules/map_stubs) so they compile ONLY with the
// test map, not the live Southern Cross build.

// Away-gateway variant. /obj/machinery/gateway is itself a stub (map_stubs.dm).
// The map instance sets `calibrated`, so carry the var to satisfy the map reader.
/obj/machinery/gateway/centeraway
	var/calibrated = TRUE

// Loot landmark placed on the away sectors. Inert on the test map.
/obj/effect/landmark/loot_spawn
