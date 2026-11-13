// Reagent purity: what a reagent volume carries besides the reagent (code/domains/world_model/reagents/contaminants.dm).
//
// A reagent in a holder may carry a sparse `contaminants` list (contaminant id -> fraction of that reagent's volume, 0..1; null when pure).
// Purity is computed from it (1 - the fractions' sum), never stored; the grade is the band the purity falls in.

/// Grades, worst to best (a recipe asks for a minimum: `needs_grade = list(REAGENT_ID_X = GRADE_PHARMA)`).
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
/// A contaminant fraction below this is dropped (the list stays sparse).
#define CONTAMINANT_EPSILON 0.0001

// Contaminant ids (the registry rows, contaminant_defs()).
#define CONTAMINANT_HEAVY_METAL "heavy_metal"
#define CONTAMINANT_SULFUR "sulfur"
#define CONTAMINANT_ORGANIC_RESIDUE "organic_residue"
#define CONTAMINANT_SALTS "salts"
#define CONTAMINANT_ACID_RESIDUE "acid_residue"
#define CONTAMINANT_BASE_RESIDUE "base_residue"
#define CONTAMINANT_OILY_RESIDUE "oily_residue"
#define CONTAMINANT_INERT_FILLER "inert_filler"
#define CONTAMINANT_BIOLOGICAL "biological"
#define CONTAMINANT_REACTIVE "reactive"

// Roles: what a contaminant does to the patient.
#define CONTAMINANT_ROLE_TOXIC "toxic"           // slow organ damage per unit
#define CONTAMINANT_ROLE_INERT "inert"           // only dilutes (the reagent's potency is its purity)
#define CONTAMINANT_ROLE_REACTIVE "reactive"     // a chance of a minor burn
#define CONTAMINANT_ROLE_BIOLOGICAL "biological" // toxin and a mild fever

/// A purity band is rolled this far inside its edges, so a rolled source never sits on a boundary.
#define CONTAMINANT_ROLL_MARGIN 0.02
