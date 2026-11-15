// Mixture purity: the share of a holder that is contaminant (code/domains/world_model/reagents/contaminants.dm).
//
// A contaminant is a reagent (/datum/reagent/contaminant, code/content/reagents/reagents/content/contaminants.dm) with a volume of its own. A holder's purity
// is 1 minus the contaminant volume over its total volume, computed, never stored; its grade is the band the purity falls in.

/// Grades, worst to best (a recipe asks for a minimum of the holder: `needs_grade = GRADE_PHARMA`).
#define GRADE_CRUDE 1
#define GRADE_STANDARD 2
#define GRADE_PHARMA 3
#define GRADE_REAGENT 4

/// Lowest purity of each grade (a purity under PURITY_STANDARD is Crude).
#define PURITY_STANDARD 0.6
#define PURITY_PHARMA 0.9
#define PURITY_REAGENT 0.99

/// Slack when a computed purity is compared with a band edge (a purity of exactly 0.9 is Pharma despite float rounding).
#define PURITY_EPSILON 0.0001

// The contaminant reagents (names and ids).
#define REAGENT_CONTAMINANT_HEAVY_METAL "Heavy metals"
#define REAGENT_ID_CONTAMINANT_HEAVY_METAL "contaminant_heavy_metal"
#define REAGENT_CONTAMINANT_SULFUR "Sulfur compounds"
#define REAGENT_ID_CONTAMINANT_SULFUR "contaminant_sulfur"
#define REAGENT_CONTAMINANT_ORGANIC_RESIDUE "Organic residue"
#define REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE "contaminant_organic_residue"
#define REAGENT_CONTAMINANT_SALTS "Salts"
#define REAGENT_ID_CONTAMINANT_SALTS "contaminant_salts"
#define REAGENT_CONTAMINANT_ACID_RESIDUE "Acid residue"
#define REAGENT_ID_CONTAMINANT_ACID_RESIDUE "contaminant_acid_residue"
#define REAGENT_CONTAMINANT_BASE_RESIDUE "Base residue"
#define REAGENT_ID_CONTAMINANT_BASE_RESIDUE "contaminant_base_residue"
#define REAGENT_CONTAMINANT_OILY_RESIDUE "Oily residue"
#define REAGENT_ID_CONTAMINANT_OILY_RESIDUE "contaminant_oily_residue"
#define REAGENT_CONTAMINANT_INERT_FILLER "Inert filler"
#define REAGENT_ID_CONTAMINANT_INERT_FILLER "contaminant_inert_filler"
#define REAGENT_CONTAMINANT_BIOLOGICAL "Endotoxin"
#define REAGENT_ID_CONTAMINANT_BIOLOGICAL "contaminant_biological"
#define REAGENT_CONTAMINANT_REACTIVE "Reactive impurity"
#define REAGENT_ID_CONTAMINANT_REACTIVE "contaminant_reactive"

// Roles: what a contaminant does to the patient.
#define CONTAMINANT_ROLE_TOXIC "toxic"           // slow organ damage per unit
#define CONTAMINANT_ROLE_INERT "inert"           // only takes up volume: dilutes whatever it is mixed with
#define CONTAMINANT_ROLE_REACTIVE "reactive"     // a chance of a minor burn
#define CONTAMINANT_ROLE_BIOLOGICAL "biological" // toxin and a mild fever

/// A purity band is rolled this far inside its edges, so a rolled source never sits on a boundary.
#define CONTAMINANT_ROLL_MARGIN 0.02
