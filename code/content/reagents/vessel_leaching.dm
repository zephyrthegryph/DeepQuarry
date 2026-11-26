// Vessel leaching: a reagent vessel is made of something, and harsh or hot contents take a little of it up. There are no liners to buy: the acid-proof vessel is one
// made entirely of borosilicate glass, which gives nothing up.
//
// The vessel's material is what the vessel is built of where the contents touch it (the wetted surface of a printed beaker, the plain material of a bucket, glass for a
// bottle). What it leaches is the contaminant the material's trace vocabulary names (code/content/materials/engineering/material_traces.dm): a metal the heavy-metal
// contaminant, a plastic the plasticiser, ordinary glass a silicate filler and an alkali residue, wood an organic residue. The leached trace is a reagent like any
// other: it counts against the mixture's purity and shows in a scanner's composition.
//
// It happens once per reaction step settled in the vessel (xform_settle_reagents) and once per second on a hot plate (heat_step), scaled by how harsh the contents are
// (the share that is strong acid or base, a process chemical, an oxidiser) and how far over the hot point they are, and by the material's own resistance. Mild contents
// at room temperature leach nothing. Every leach is logged under GLOB.chem_trace.

/// Material id -> the contaminants it leaches (an even share of the amount each). A material that is not here leaches nothing: borosilicate glass, ceramic, graphite.
GLOBAL_LIST_INIT(vessel_leach_contaminants, build_vessel_leach_contaminants())

/proc/build_vessel_leach_contaminants()
	var/list/table = list()
	for(var/metal in list(MAT_IRON, MAT_STEEL, MAT_STEELHULL, MAT_SILVER, MAT_GOLD, MAT_URANIUM, MAT_TITANIUM, MAT_PLASTEEL, MAT_PLASTEELHULL, MAT_DURASTEEL, MAT_DURASTEELHULL, \
			MAT_TITANIUMHULL, MAT_LEAD, MAT_COPPER, MAT_ALUMINIUM, MAT_BRONZE, MAT_PLATINUM, MAT_OSMIUM, MAT_TIN, MAT_NICKEL, MAT_CHROMIUM, MAT_TUNGSTEN))
		table[metal] = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	for(var/polymer in list(MAT_PLASTIC, MAT_RUBBER, MAT_NYLON, MAT_HARD_PLASTIC))
		table[polymer] = list(REAGENT_ID_CONTAMINANT_PLASTICISER)
	for(var/glass in list(MAT_GLASS, MAT_RGLASS))
		table[glass] = list(REAGENT_ID_CONTAMINANT_INERT_FILLER, REAGENT_ID_CONTAMINANT_BASE_RESIDUE)
	for(var/timber in list(MAT_WOOD, MAT_SIFWOOD, MAT_HARDWOOD, MAT_BIRCHWOOD, MAT_PINEWOOD, MAT_OAKWOOD, MAT_ACACIAWOOD, MAT_REDWOOD))
		table[timber] = list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE)
	return table

/// How harsh a reagent is: 0 for a mild one, 1 for a strong acid, a process chemical or an oxidiser, 2 for a strong base (a mineral one: a hydroxide or a carbonate).
/proc/chem_harshness(datum/reagent/R)
	if(istype(R, /datum/reagent/contaminant))
		return 0
	var/datum/chem_structure/S = GLOB.chem_structures[R.id]
	if(S && (CHEM_TAG_BASIC in S.tags) && (CHEM_TAG_IONIC in S.tags))
		return 2
	if(R.material_corrosivity > 0 || length(chem_agents_of(R.id)))
		return 1
	if(S && (CHEM_TAG_IONIC in S.tags) && ((CHEM_TAG_ACIDIC in S.tags) || (CHEM_TAG_OXIDISER in S.tags)))
		return 1
	return 0

/// The share of the contents (0 to 1) that is harsh, and the share of it that is a strong base, as list(harsh, base).
/datum/reagents/proc/harsh_shares()
	var/harsh = 0
	var/base = 0
	if(total_volume <= 0)
		return list(0, 0)
	for(var/datum/reagent/R as anything in reagent_list)
		var/kind = chem_harshness(R)
		if(kind)
			harsh += R.volume
			if(kind == 2)
				base += R.volume
	return list(harsh / total_volume, base / total_volume)

/// What this vessel is made of where its contents touch it: the wetted surface of a built vessel, else its plain material, else the most of what a printed one cost, else what its type is by default.
/obj/item/reagent_containers/proc/vessel_material() as /datum/material
	var/datum/material/wetted = construction_liner_material()
	if(wetted)
		return wetted
	var/datum/material/plain = material_for_role(MATERIAL_ROLE_BULK) || primary_construction_material()
	if(plain)
		return plain
	// A printed vessel records what it cost as a mix (the lathe's split_materials_uniformly()), not as a blueprint: it is made of the most of it.
	var/list/totals = material_totals()
	var/dominant
	for(var/material_id in totals)
		if(!dominant || totals[material_id] > totals[dominant])
			dominant = material_id
	if(istype(dominant, /datum/material))
		return dominant
	if(dominant)
		return get_material_by_name(dominant)
	var/default_material = vessel_default_material()
	return default_material ? get_material_by_name(default_material) : null

/// The material a vessel with no blueprint of its own is made of (a material id), or null for one that holds nothing apart from its contents.
/obj/item/reagent_containers/proc/vessel_default_material()
	return null

/obj/item/reagent_containers/glass/vessel_default_material()
	return MAT_GLASS

/obj/item/reagent_containers/glass/rag/vessel_default_material()
	return null

/// Each reaction step settled in the vessel is one step of leaching.
/obj/item/reagent_containers/xform_steps_settled(steps)
	vessel_leach(steps)

/// What the vessel leaches at the contents' temperature and harshness, as contaminant id -> units for `steps` reaction steps or seconds. Empty when it leaches nothing.
/obj/item/reagent_containers/proc/vessel_leach_amounts(steps)
	. = list()
	var/datum/reagents/holder = reagents
	if(!holder || holder.total_volume <= 0 || steps <= 0)
		return
	var/datum/material/vessel = vessel_material()
	var/list/leaches = vessel ? GLOB.vessel_leach_contaminants[vessel.name] : null
	if(!length(leaches))
		return
	var/list/shares = holder.harsh_shares()
	var/harsh = shares[1]
	var/base = shares[2]
	var/temperature = get_temperature()
	var/harsh_term = harsh >= VESSEL_HARSH_FLOOR ? harsh : 0
	var/hot_point = VESSEL_HOT_POINT
	if(vessel.name == MAT_GLASS || vessel.name == MAT_RGLASS)
		// Ordinary glass stands up to acid; it gives up a trace only when very hot or in a strong base.
		hot_point = VESSEL_GLASS_HOT_POINT
		harsh_term = base >= VESSEL_HARSH_FLOOR ? base : 0
	var/hot_term = 0
	if(temperature > hot_point)
		hot_term = clamp((temperature - hot_point) / VESSEL_HOT_SPAN, 0.25, VESSEL_HOT_MAX) // the first degree over the point already counts
	var/strength = harsh_term + hot_term
	if(strength <= 0)
		return
	var/susceptibility = clamp((100 - vessel.corrosion_resistance) / 100, 0.1, 1)
	// A trace is always at least a trace: a resistant material still gives up the least amount a holder keeps.
	var/amount = max(VESSEL_LEACH_UNIT * susceptibility * strength * steps / length(leaches), VESSEL_LEACH_MINIMUM)
	for(var/contaminant in leaches)
		.[contaminant] = amount

/// The vessel gives up its trace into the contents for `steps` reaction steps or seconds. No reaction is run for what it adds: the caller settles the holder.
/obj/item/reagent_containers/proc/vessel_leach(steps)
	var/list/amounts = vessel_leach_amounts(steps)
	if(!length(amounts))
		return
	var/datum/material/vessel = vessel_material()
	for(var/contaminant in amounts)
		reagents.add_reagent(contaminant, amounts[contaminant], safety = 1)
		if(GLOB.chem_trace)
			log_world("CHEM: vessel [src] ([vessel.name]) leached [round(amounts[contaminant], 0.0001)]u [contaminant] into [reagents.get_reagents()] at [round(get_temperature() - T0C, 0.1)] C")

/// What the vessel says it is made of, and what it gives up, for its examine.
/obj/item/reagent_containers/proc/vessel_description()
	var/datum/material/vessel = vessel_material()
	if(!vessel)
		return null
	var/list/leaches = GLOB.vessel_leach_contaminants[vessel.name]
	if(!length(leaches))
		return "It is made of [vessel.display_name]: nothing leaches from it, however harsh or hot its contents."
	var/list/names = list()
	for(var/contaminant in leaches)
		names += contaminant_def(contaminant)?.name || contaminant
	return "It is made of [vessel.display_name]: harsh or hot contents take up a trace of [english_list(names)] from it."
