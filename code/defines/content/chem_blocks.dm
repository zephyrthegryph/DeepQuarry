// Chemical block structures and processes (code/domains/world_model/reagents/blocks/, the declarations: code/content/reagents/blocks/).
//
// A chemistry reagent is built of blocks: one or more cores, groups hung on them, links joining two parts, or (an inorganic) a cation and an anion. Its formula,
// class and tags are derived from that structure and nothing else. A process changes a structure, and the reaction it makes is generated at boot from the
// structures that exist.

// ---- cores ----
#define CHEM_CORE_SHORT_CHAIN "short_chain"
#define CHEM_CORE_LONG_CHAIN "long_chain"
#define CHEM_CORE_RING "ring"
#define CHEM_CORE_DOUBLE_RING "double_ring"
#define CHEM_CORE_SUGAR_RING "sugar_ring"
#define CHEM_CORE_AMINO "amino"
#define CHEM_CORE_STEROID "steroid"
#define CHEM_CORE_NITROGEN_RING "nitrogen_ring"
#define CHEM_CORE_SILOXANE "siloxane"
#define CHEM_CORE_PHORON_LATTICE "phoron_lattice"
// The exotic cores: what a creature, a slime or an expedition gives. They cannot be built on the station and no process turns one into another (code/content/reagents/blocks/structures.dm).
#define CHEM_CORE_FIRE "fire"
#define CHEM_CORE_DEATH "death"
#define CHEM_CORE_LIFE "life"
#define CHEM_CORE_VENOM "venom"
#define CHEM_CORE_SLIME "slime"
#define CHEM_CORE_VOLT "volt"
#define CHEM_CORE_RELIC "relic"
#define CHEM_CORE_VOID "void"

// ---- groups ----
#define CHEM_GROUP_HYDROXYL "hydroxyl"
#define CHEM_GROUP_CARBONYL "carbonyl"
#define CHEM_GROUP_CARBOXYL "carboxyl"
#define CHEM_GROUP_AMINE "amine"
#define CHEM_GROUP_NITRO "nitro"
#define CHEM_GROUP_HALIDE "halide"
#define CHEM_GROUP_THIOL "thiol"
#define CHEM_GROUP_PHOSPHATE "phosphate"
#define CHEM_GROUP_METAL_CENTRE "metal_centre"
/// A nitrile: a carbon and a nitrogen hung on a core (the tenth group: the cyanide arm of substitution and the glues need it).
#define CHEM_GROUP_CYANIDE "cyanide"

// ---- links (join two parts) ----
#define CHEM_LINK_ESTER "ester"
#define CHEM_LINK_AMIDE "amide"

// ---- ions (an inorganic is a cation and an anion) ----
#define CHEM_ION_HYDROGEN "hydrogen"
#define CHEM_ION_SODIUM "sodium"
#define CHEM_ION_POTASSIUM "potassium"
#define CHEM_ION_AMMONIUM "ammonium"
#define CHEM_ION_CALCIUM "calcium"
#define CHEM_ION_HEAVY_METAL "heavy_metal"
#define CHEM_ION_HYDROXIDE "hydroxide"
#define CHEM_ION_CHLORIDE "chloride"
#define CHEM_ION_SULFATE "sulfate"
#define CHEM_ION_NITRATE "nitrate"
#define CHEM_ION_CARBONATE "carbonate"
#define CHEM_ION_PEROXIDE "peroxide"
#define CHEM_ION_SILICATE "silicate"
#define CHEM_ION_HYPOCHLORITE "hypochlorite"
#define CHEM_ION_PHOSPHATE "phosphate"
#define CHEM_ION_CYANIDE "cyanide"
#define CHEM_ION_HYDRIDE "hydride"
#define CHEM_ION_LITHIUM "lithium"
#define CHEM_ION_IRON "iron"
#define CHEM_ION_COPPER "copper"

// ---- tags (what a structure is, for filters and the book) ----
#define CHEM_TAG_ORGANIC "organic"
#define CHEM_TAG_IONIC "ionic"
#define CHEM_TAG_POLAR "polar"
#define CHEM_TAG_NONPOLAR "nonpolar"
#define CHEM_TAG_ACIDIC "acidic"
#define CHEM_TAG_BASIC "basic"
#define CHEM_TAG_METALLIC "metallic"
#define CHEM_TAG_SULFUROUS "sulfurous"
#define CHEM_TAG_HALOGENATED "halogenated"
#define CHEM_TAG_NITROGENOUS "nitrogenous"
#define CHEM_TAG_OXIDISER "oxidiser"
#define CHEM_TAG_BIOLOGICAL "biological"
#define CHEM_TAG_SOLID "solid"

// ---- processes ----
#define CHEM_PROCESS_OXIDISE "oxidise"
#define CHEM_PROCESS_REDUCE "reduce"
#define CHEM_PROCESS_HALOGENATE "halogenate"
#define CHEM_PROCESS_NITRATE "nitrate"
#define CHEM_PROCESS_SUBSTITUTE "substitute"
#define CHEM_PROCESS_PHOSPHORYLATE "phosphorylate"
#define CHEM_PROCESS_DECARBOXYLATE "decarboxylate"
#define CHEM_PROCESS_CONDENSE "condense"
#define CHEM_PROCESS_HYDROLYSE "hydrolyse"
#define CHEM_PROCESS_FERMENT "ferment"
#define CHEM_PROCESS_CRACK "crack"
#define CHEM_PROCESS_NEUTRALISE "neutralise"
#define CHEM_PROCESS_DISPLACE "displace"
#define CHEM_PROCESS_ELECTROLYSE "electrolyse"
#define CHEM_PROCESS_POLYMERISE "polymerise"
/// Not a process a mixture is made to do: the reaction between two chemicals on contact, by the groups they carry (code/content/reagents/blocks/clashes.dm).
#define CHEM_PROCESS_CLASH "clash"

// ---- catalyst kinds: what a process runs on ----
/// Nothing but heat and the added reagent.
#define CHEM_CATALYST_NONE "none"
/// An acid dissolved in the mixture (sulphuric acid): spent into acid residue.
#define CHEM_CATALYST_ACID "dissolved_acid"
/// A base dissolved in the mixture (lye): spent into base residue.
#define CHEM_CATALYST_BASE "dissolved_base"
/// A sheet of a catalytic metal lying in the container: its catalytic activity sets the temperature reduction and the selectivity.
#define CHEM_CATALYST_SOLID_METAL "solid_metal"
/// A sheet of a porous catalytic material (a solid acid) lying in the container.
#define CHEM_CATALYST_SOLID_ACID "solid_acid"
/// A sheet of a heat-resistant catalytic metal (tungsten): it does everything a solid metal does and also runs the high-temperature crack and reduce that melt or sinter any other.
#define CHEM_CATALYST_SOLID_REFRACTORY "solid_refractory"
/// A catalytic metal whose heat resistance (its card stat) is at least this is refractory.
#define CHEM_REFRACTORY_HEAT 90
/// An enzyme in the mixture: works at gentle heat, leaves biological residue.
#define CHEM_CATALYST_ENZYME "enzyme"
/// A process chemical poured in (hydride, a strong oxidiser, ...): it is the process, consumed; less selective, leaves its own residue (agents.dm).
#define CHEM_CATALYST_AGENT "agent"
/// A reaction on contact (a clash): no catalyst, no band; in a container and in the stomach, never in the bloodstream.
#define CHEM_CATALYST_CONTACT "contact"

/// A solid catalyst whose material holds this much reagent (its sorbent trait, sorbed_volume()) is a solid acid; any other catalytic sheet is a metal.
#define CHEM_SOLID_ACID_POROSITY 8
/// Kelvin a solid catalyst of activity 100 lowers the working band of a process by.
#define CHEM_SOLID_REDUCTION_PER_POINT 0.5
/// A solid catalyst with less effective activity than this does nothing.
#define CHEM_SOLID_MIN_ACTIVITY 5
/// Kelvin a dissolved acid or base lowers the working band of a process by.
#define CHEM_DISSOLVED_REDUCTION 35
/// Units of a dissolved catalyst (or an enzyme) spent into residue per unit of product made.
#define CHEM_CATALYST_RESIDUE_RATE 0.04
/// How hard sulfur and heavy metals poison a metal catalyst: the share of the mixture they make, times this, is the share of the activity lost.
#define CHEM_POISON_SCALE 20
/// An enzyme stops working when heavy metals make this share of the mixture.
#define CHEM_ENZYME_POISON_SHARE 0.004
/// The share of a step's product that is clean, by what ran it (an uncatalysed step, a dissolved catalyst, an enzyme; a solid catalyst's is its activity).
#define CHEM_SELECTIVITY_NONE 0.8
#define CHEM_SELECTIVITY_DISSOLVED 0.9
#define CHEM_SELECTIVITY_ENZYME 0.97
/// Units of organic residue made per unit of product that was not selective.
#define CHEM_RESIDUE_PER_LOST 0.5

/// Peroxide in a container this hot (K) detonates, at this many units at least; each unit is this much of an explosion (an amount of 2 or less is a pop).
#define PEROXIDE_DETONATION_TEMP (T0C + 70)
#define PEROXIDE_MIN_UNITS 0.05
#define PEROXIDE_BLAST_PER_UNIT 4

/// Where a generated rule's order starts: after every declared rule, so a declared recipe wins a shared reactant.
#define CHEM_ROUTE_ORDER_BASE 1000000

/// Units of an exotic-core chemical a step spends for each unit of product (the yields of the exotic trees are small: a step wastes a third of its core).
#define CHEM_EXOTIC_TAKE 1.5

/// A structure with its groups at most this many (a process does not hang a fifth group on a core).
#define CHEM_GROUPS_MAX 4

/// The tiers of the chemistry (doc/rewrite/proposals/chemistry_redesign.md section 8), for the book.
#define CHEM_TIER_STAPLE 1
#define CHEM_TIER_STANDARD 2
#define CHEM_TIER_ADVANCED 3
#define CHEM_TIER_EXOTIC 4
