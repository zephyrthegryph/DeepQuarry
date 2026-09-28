/// The plant world service (fold wave F1; was SSplants): seed and gene data. It has no periodic work
/// of its own: spreading plants grow on their own lane (PERIODIC_PLANTS, 7.5 s), started by
/// add_plant(), and the growing set is the REGISTRY_GROWING_PLANTS registry. GLOB.planet_service.Initialize()
/// calls initialize(), where SSplants used to initialize.
GLOBAL_DATUM_INIT(plant_service, /datum/world_service/plants, new)

REF_STATIC(/datum/world_service/plants, list("seeds", "plant_gene_datums"))

/datum/world_service/plants
	name = "Plants"
	var/list/product_descs = list()					// Stores generated fruit descs. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/seeds = list()							// All seed data stored here. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/gene_tag_masks = list()				// Gene obfuscation for delicious trial and error goodness. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/plant_icon_cache = list()				// Stores images of growth, fruits and seeds. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/plant_sprites = list()					// List of all growth sprites plus number of growth stages. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/accessible_plant_sprites = list()		// List of all plant sprites allowed to appear in random generation. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/plant_product_sprites = list()			// List of all harvested product sprites. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/accessible_product_sprites = list()	// List of all product sprites allowed to appear in random generation. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/gene_masked_list = list()				// Stored gene masked list, rather than recreating it when needed. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)
	var/list/plant_gene_datums = list()				// Stored datum versions of the gene masked list. // ALLOW(instance_list): d: world service singleton (one instance in GLOB, was a subsystem)

/datum/world_service/plants/stat_line()
	return "P:[REGISTRY_COUNT(REGISTRY_GROWING_PLANTS)]|S:[length(seeds)]"

/datum/world_service/plants/initialize()
	if(initialized)
		return
	setup()
	initialized = TRUE
	log_world("Plant service initialized: [length(seeds)] seeds, [length(gene_tag_masks)] gene masks.")

// Predefined/roundstart varieties use a string key to make it
// easier to grab the new variety when mutating. Post-roundstart
// and mutant varieties use their uid converted to a string instead.
// Looks like shit but it's sort of necessary.
/datum/world_service/plants/proc/setup()
	// Build the icon lists.
	for(var/icostate in icon_states_fast('icons/obj/hydroponics_growing.dmi'))
		var/split = findtext(icostate,"-")
		if(!split)
			// invalid icon_state
			continue

		var/ikey = copytext(icostate,(split+1))
		if(ikey == "dead")
			// don't count dead icons
			continue
		ikey = text2num(ikey)
		var/base = copytext(icostate,1,split)

		if(!(plant_sprites[base]) || (plant_sprites[base]<ikey))
			plant_sprites[base] = ikey
			if(!(base in GLOB.forbidden_plant_growth_sprites))
				accessible_plant_sprites[base] = ikey

	for(var/icostate in icon_states_fast('icons/obj/hydroponics_products.dmi'))
		var/split = findtext(icostate,"-")
		var/base = copytext(icostate,1,split)
		if(split)
			plant_product_sprites |= base
			if(!(base in GLOB.forbidden_plant_product_sprites))
				accessible_product_sprites |= base

	// Populate the global seed datum list.
	for(var/type in subtypesof(/datum/seed))
		var/datum/seed/S = new type
		seeds[S.name] = S
		S.uid = "[length(seeds)]"
		S.roundstart = 1

	// Make sure any seed packets that were mapped in are updated
	// correctly (since the seed datums did not exist a tick ago).
	for(var/obj/item/seeds/S in REGISTRY_MEMBERS(REGISTRY_SEED_PACKS))
		S.update_seed()

	//Might as well mask the gene types while we're at it.
	var/list/gene_datums = GLOB.decls_repository.get_decls_of_subtype(/datum/decl/plantgene)
	var/list/used_masks = list()
	var/list/plant_traits = ALL_GENES
	while(plant_traits && length(plant_traits))
		var/gene_tag = pick(plant_traits)
		var/gene_mask = "[uppertext(num2hex(rand(0,255), 2))]"

		while(gene_mask in used_masks)
			gene_mask = "[uppertext(num2hex(rand(0,255), 2))]"

		var/datum/decl/plantgene/G

		for(var/D in gene_datums)
			var/datum/decl/plantgene/P = gene_datums[D]
			if(gene_tag == P.gene_tag)
				G = P
				gene_datums -= D
		used_masks += gene_mask
		plant_traits -= gene_tag
		gene_tag_masks[gene_tag] = gene_mask
		plant_gene_datums[gene_mask] = G
		gene_masked_list.Add(list(list("tag" = gene_tag, "mask" = gene_mask)))

// Proc for creating a random seed type.
/datum/world_service/plants/proc/create_random_seed(survive_on_station)
	var/datum/seed/seed = new()
	seed.randomize()
	seed.uid = length(seeds) + 1
	seed.name = "[seed.uid]"
	seeds[seed.name] = seed

	if(survive_on_station)
		if(seed.consume_gasses)
			seed.consume_gasses[GAS_PHORON] = null
			seed.consume_gasses[GAS_CH4] = null
			seed.consume_gasses[GAS_CO2] = null
		if(seed.chems && !isnull(seed.chems[REAGENT_ID_PACID]))
			seed.chems[REAGENT_ID_PACID] = null // Eating through the hull will make these plants completely inviable, albeit very dangerous.
			seed.chems -= null // Setting to null does not actually remove the entry, which is weird.
		seed.set_trait(TRAIT_IDEAL_HEAT,293)
		seed.set_trait(TRAIT_HEAT_TOLERANCE,20)
		seed.set_trait(TRAIT_IDEAL_LIGHT,8)
		seed.set_trait(TRAIT_LIGHT_TOLERANCE,5)
		seed.set_trait(TRAIT_LOWKPA_TOLERANCE,25)
		seed.set_trait(TRAIT_HIGHKPA_TOLERANCE,200)
	return seed

/datum/world_service/plants/proc/add_plant(obj/effect/plant/plant)
	if(!QDELETED(plant))
		registry_join(REGISTRY_GROWING_PLANTS, plant)
		om_task_periodic(plant, PERIODIC_PLANTS)

/datum/world_service/plants/proc/remove_plant(obj/effect/plant/plant)
	registry_leave(REGISTRY_GROWING_PLANTS, plant)
	om_task_periodic_stop(plant)


// Debug for testing seed genes.
ADMIN_VERB(show_plant_genes, R_DEBUG, "Show Plant Genes", "Prints the round's plant gene masks.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	if(!GLOB.plant_service.initialized)
		to_chat(user, "Gene masks not set.")
		return

	for(var/mask in GLOB.plant_service.gene_tag_masks)
		to_chat(user, "[mask]: [GLOB.plant_service.gene_tag_masks[mask]]")

