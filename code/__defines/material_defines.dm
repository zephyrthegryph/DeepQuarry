// Hoisted material defines.
//
// MATCLASS_* are used as default values on upstream /datum/material
// subtypes (e.g. material_class = MATCLASS_METAL in code/modules/
// materials/materials/_materials.dm), so they need to be visible at
// parse time before those upstream files are reached. This file is
// included early in deepquarry.dme alongside quarry_defines.dm; the
// rest of the property system (datum classes, ranges, helpers) lives
// in code/modules/materials/material_properties.dm and
// only references these defines.

#define MATCLASS_METAL   "metal"
#define MATCLASS_CRYSTAL "crystal"
#define MATCLASS_ORGANIC "organic"
#define MATCLASS_CERAMIC "ceramic"
