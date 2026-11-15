// Group clashes (the machinery: code/domains/world_model/reagents/blocks/agents.dm; doc/rewrite/proposals/chemistry_redesign.md section 6).
//
// Two finished chemicals that meet react by the groups they carry, on contact, with no catalyst and no temperature (unless the clash names one). They run in a
// loose container and in the stomach (`ingested`: swallowed doses mix there) and never in the bloodstream or on the skin. The building blocks, the intermediates
// and the process chemicals do not clash among themselves (they are made and mixed on purpose: an acid and an amine meant to be condensed are not a salt in
// the beaker): `GLOB.chem_building_blocks`.
//
//   acid group + amine        a salt (contaminant salts): both tied up (an amino acid and what is made of one are their own salt: no clash)
//   thiol + metal centre      the thiol takes the metal: organic residue and heavy metal
//   nitro + amine             nitrosamine
//   oxidiser + thiol/hydroxyl oxidised, usually ruined: organic residue
//   halide + amine, warm      an unintended joined molecule: organic residue and hydrochloric acid
//   phosphate + calcium/iron  drops out as a solid: salts
//   nitro + reducer           runs hot: reactive impurity
// Also on contact: the dry agent drinks water, the scavenger resin takes a contaminant and leaves inert filler.

/// The calcium and iron sources a phosphate drops out against.
GLOBAL_LIST_INIT(chem_phosphate_precipitants, list(REAGENT_ID_CALCIUM, REAGENT_ID_IRON, REAGENT_ID_CALCIUMCARBONATE, REAGENT_ID_IRONSALINE))

/// What reduces a nitro compound (the reducers that run it hot).
GLOBAL_LIST_INIT(chem_nitro_reducers, list(REAGENT_ID_HYDROGEN, REAGENT_ID_HYDRIDE, REAGENT_ID_LITHIUM, REAGENT_ID_SODIUM, REAGENT_ID_POTASSIUM))

/// Every clash the declarations make, for the generator: the ids of the finished chemicals are those with a structure that is not a building block.
/proc/chem_clash_rows(datum/chem_gen/G)
	. = list()
	var/list/members = list()
	for(var/id in G.ids)
		if(chem_is_contaminant_id(G, id) || (id in GLOB.chem_building_blocks))
			continue
		var/datum/chem_structure/S = G.structures[id]
		if(S.is_organic())
			members += id
	for(var/a in members)
		var/datum/chem_structure/A = G.structures[a]
		for(var/b in members)
			if(a == b)
				continue
			var/datum/chem_structure/B = G.structures[b]
			if(A.has_group(CHEM_GROUP_CARBOXYL) && B.has_group(CHEM_GROUP_AMINE) && !A.has_core(CHEM_CORE_AMINO) && !B.has_core(CHEM_CORE_AMINO) && !chem_clash_is_join(A, B)) // an amino acid is its own salt: the daxons do not salt each other out
				. += chem_clash(a, b, list(REAGENT_ID_CONTAMINANT_SALTS = 2), null, "an acid group and an amine make a salt: both are tied up")
			if(A.has_group(CHEM_GROUP_THIOL) && B.has_group(CHEM_GROUP_METAL_CENTRE))
				. += chem_clash(a, b, list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1, REAGENT_ID_CONTAMINANT_HEAVY_METAL = 1), null, "the thiol takes the metal")
			if(A.has_group(CHEM_GROUP_NITRO) && B.has_group(CHEM_GROUP_AMINE))
				. += chem_clash(a, b, list(REAGENT_ID_CONTAMINANT_NITROSAMINE = 1, REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1), null, "a nitro compound and an amine make nitrosamine")
			if(A.has_group(CHEM_GROUP_NITRO) && (B.has_group(CHEM_GROUP_THIOL) || B.has_group(CHEM_GROUP_HYDROXYL)) && !B.has_group(CHEM_GROUP_NITRO))
				. += chem_clash(a, b, list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 2), null, "an oxidiser takes a thiol or a hydroxyl: usually ruined")
			if(A.has_group(CHEM_GROUP_HALIDE) && B.has_group(CHEM_GROUP_AMINE))
				. += chem_clash(a, b, list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 1, REAGENT_ID_HYDROCHLORIC = 1), chem_band_of(REACTION_TEMP_WARM), "a halide and an amine, warm, join into something nobody meant")
		if(A.has_group(CHEM_GROUP_PHOSPHATE))
			for(var/metal in GLOB.chem_phosphate_precipitants)
				. += chem_clash(a, metal, list(REAGENT_ID_CONTAMINANT_SALTS = 2), null, "a phosphate with calcium or iron drops out as a solid")
		if(A.has_group(CHEM_GROUP_NITRO))
			for(var/reducer in GLOB.chem_nitro_reducers)
				. += chem_clash(a, reducer, list(REAGENT_ID_CONTAMINANT_REACTIVE = 2), null, "a nitro compound and a reducer run hot")
	. += chem_clash(REAGENT_ID_DRYAGENT, REAGENT_ID_WATER, list(REAGENT_ID_CONTAMINANT_SALTS = 1), null, "the dry agent drinks the water")
	for(var/contaminant_id in G.ids)
		if(!chem_is_contaminant_id(G, contaminant_id) || contaminant_id == REAGENT_ID_CONTAMINANT_INERT_FILLER || contaminant_id == REAGENT_ID_CONTAMINANT_SALTS)
			continue
		. += chem_clash(REAGENT_ID_SCAVENGERRESIN, contaminant_id, list(REAGENT_ID_CONTAMINANT_INERT_FILLER = 1), null, "the resin takes the contaminant")

/// Do these two condense into a chemical that exists (an amide of the acid group and the amine)? Then they are a recipe, not a clash.
/proc/chem_clash_is_join(datum/chem_structure/acid, datum/chem_structure/amine)
	var/list/groups = acid.groups.Copy()
	groups -= CHEM_GROUP_CARBOXYL
	var/list/partner_groups = amine.groups.Copy()
	partner_groups -= CHEM_GROUP_AMINE
	groups += partner_groups
	var/list/joined_links = acid.links + amine.links
	joined_links += CHEM_LINK_AMIDE
	return !!chem_structure_match(chem_structure_make(acid.cores + amine.cores, groups, joined_links, amine.cation, null))
