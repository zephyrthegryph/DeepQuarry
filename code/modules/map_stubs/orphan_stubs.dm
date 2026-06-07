// Minimal area declarations for areas that are referenced by live feature
// definitions but whose physical maps are not currently included in the build.
//
// These are intentional, valid (empty) area types — NOT broken orphans. They
// exist so the feature definitions below compile; the areas only become real
// in-game if/when a map that uses them is added:
//   - Dorm holodeck programs + projection areas  (computer/HolodeckControl/holodorm)
//   - Surface turbolift shaft areas              (the surface turbolift)
//   - Maglev tram shock area                     (/turf/simulated/floor/maglev)
//
// Everything else previously stubbed here was resolved during the hard-fork
// cleanup: item stubs were rescued/implemented in the live tree, and references
// to areas of fully-removed maps were deleted from the code that listed them.

// Dorm holodeck programs
/area/holodeck/holodorm/source_off
/area/holodeck/holodorm/source_basic
/area/holodeck/holodorm/source_seating
/area/holodeck/holodorm/source_beach
/area/holodeck/holodorm/source_desert
/area/holodeck/holodorm/source_snow
/area/holodeck/holodorm/source_garden
/area/holodeck/holodorm/source_space
/area/holodeck/holodorm/source_boxing

// Dorm holodeck projection areas
/area/crew_quarters/sleep/Dorm_1/holo
/area/crew_quarters/sleep/Dorm_3/holo
/area/crew_quarters/sleep/Dorm_5/holo
/area/crew_quarters/sleep/Dorm_7/holo

// Surface turbolift shaft areas
/area/turbolift/t_surface/level1
/area/turbolift/t_surface/level2
/area/turbolift/t_surface/level3
/area/turbolift/tether/transit
/area/turbolift/t_station/level1

// Maglev tram shock area
/area/tether/surfacebase/tram
