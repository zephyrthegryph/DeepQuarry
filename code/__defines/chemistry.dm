#define DEFAULT_HUNGER_FACTOR 0.05 // Factor of how fast mob nutrition decreases

#define REM 0.2 // Means 'Reagent Effect Multiplier'. This is how many units of reagent are consumed per tick

#define CHEM_TOUCH 1
#define CHEM_INGEST 2
#define CHEM_BLOOD 3
#define CHEM_VORE 4 // vore belly interactions

/// Bit for a species reagent tag (IS_*) in a reagent's immune_species_* masks (P2-S13).
#define SPECIES_TAG_BIT(tag) (1 << (tag))

#define MINIMUM_CHEMICAL_VOLUME 0.01

#define SOLID 1
#define LIQUID 2
#define GAS 3

#define REAGENTS_OVERDOSE 30

#define CHEM_SYNTH_ENERGY 500 // How much energy does it take to synthesize 1 unit of chemical, in Joules.

// Some on_mob_life() procs check for alien races.
#define IS_DIONA   1
#define IS_VOX     2
#define IS_SKRELL  3
#define IS_UNATHI  4
#define IS_TAJARA  5
#define IS_XENOS   6
#define IS_TESHARI 7
#define IS_SLIME   8
#define IS_ZADDAT  9
#define IS_ZORREN  10


#define REAGENTS_PER_SHEET 20
#define REAGENTS_PER_ROD 10
#define REAGENTS_PER_ORE 20
#define REAGENTS_PER_LOG 40
#define REAGENTS_PER_HULL 40

// BF_ANTIMICROBIAL levels
#define ANTIBIO_NORM	1
#define ANTIBIO_OD		2
#define ANTIBIO_SUPER	3

#define MAX_PILL_SPRITE 24 //max icon state of the pill sprites
#define MAX_BOTTLE_SPRITE 4 //max icon state of the pill sprites
#define MAX_PATCH_SPRITE 4 // max icon state of the patch sprites,
#define MAX_MULTI_AMOUNT 20 // Max number of pills/patches that can be made at once
#define MAX_UNITS_PER_PILL 60 // Max amount of units in a pill
#define MAX_UNITS_PER_PATCH 60 // Max amount of units in a patch
#define MAX_UNITS_PER_BOTTLE 60 // Max amount of units in a bottle (it's volume)
#define MAX_CUSTOM_NAME_LEN 64 // Max length of a custom pill/condiment/whatever


// More for our custom races
#define IS_CHIMERA 12
#define IS_SHADEKIN 13
#define IS_ALRAUNE 14
#define IS_LLEILL 15
#define IS_GREY 16

/// Species masks for reagent effects that several reagents share (SPECIES_TAG_BIT sets).
/// Species that draw nourishment from nutriment/protein in the blood.
#define REAGENT_BLOOD_FED_SPECIES (SPECIES_TAG_BIT(IS_SLIME) | SPECIES_TAG_BIT(IS_CHIMERA))
/// Species unharmed by prion-laden brain matter.
#define REAGENT_PRION_IMMUNE_SPECIES (SPECIES_TAG_BIT(IS_CHIMERA) | SPECIES_TAG_BIT(IS_SLIME) | SPECIES_TAG_BIT(IS_DIONA) | SPECIES_TAG_BIT(IS_SHADEKIN))

// Injection routes for /mob/living/proc/can_inject() (P2-S9): every injector
// asks the same question and names how it delivers.
/// A needle (syringe, syringe gun dart): pierces flesh, not plating.
#define INJECT_METHOD_NEEDLE 1
/// A jet or pressure injector (hypospray, autoinjector): also works through a
/// prosthetic's fluid port, but still stopped by thick hide and thick material.
#define INJECT_METHOD_HYPO 2

// ---- One Life cycle of a metabolism holder (/datum/reagents/metabolism/proc/metabolize(); vg_chem::metabolism) ----
/// /datum/reagents/metabolism/proc/cycle_taken(): what one reagent takes up this cycle.
#define CHEM_TAKEN_REMOVED 1
#define CHEM_TAKEN_DOSE 2
#define CHEM_TAKEN_MAX_DOSE 3
#define CHEM_TAKEN_OVERDOSING 4
#define CHEM_TAKEN_OVERDOSE_INJURY 5
/// The share of an ingested uptake the gut absorbs.
#define CHEM_TAKEN_ABSORBED 6
/// /datum/reagents/metabolism/proc/cycle_body(): the body's share of the rates.
#define CHEM_BODY_REMOVED 1
#define CHEM_BODY_INGEST_REMOVED 2
#define CHEM_BODY_INGEST_ABSORBED 3
