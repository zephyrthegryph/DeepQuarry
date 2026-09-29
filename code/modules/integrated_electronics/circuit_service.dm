// The circuit world service (fold wave F3; was SScircuit): the integrated circuit component and
// assembly tables and the fabricator recipe list. It has no periodic work, so it is a lazy service,
// built on first use through circuit_service().
GLOBAL_DATUM_INIT(circuit_service, /datum/world_service/circuit, new)

/// The circuit service, initialized on first use.
/proc/circuit_service() as /datum/world_service/circuit
	RETURN_TYPE(/datum/world_service/circuit)
	return LAZY_SERVICE(circuit_service)

/datum/world_service/circuit
	name = "Circuit"

	var/list/all_components = list()								// Associative list of [component_name]:[component_path] pairs
	var/list/cached_components = list()								// Associative list of [component_path]:[component] pairs
	var/list/all_assemblies = list()								// Associative list of [assembly_name]:[assembly_path] pairs
	var/list/cached_assemblies = list()								// Associative list of [assembly_path]:[assembly] pairs
	var/list/all_circuits = list()									// Associative list of [circuit_name]:[circuit_path] pairs
	var/list/circuit_fabricator_recipe_list = list()				// Associative list of [category_name]:[list_of_circuit_paths] pairs

/datum/world_service/circuit/initialize()
	initialized = TRUE
	circuits_init()
	log_world("Circuit service initialized: [length(all_components)] components, [length(all_assemblies)] assemblies.")

/datum/world_service/circuit/stat_line()
	return "Components: [length(all_components)] | Assemblies: [length(all_assemblies)]"

/datum/world_service/circuit/proc/circuits_init()
	//Cached lists for free performance
	for(var/obj/item/integrated_circuit/IC as anything in typesof(/obj/item/integrated_circuit))
		var/path = IC
		all_components[initial(IC.name)] = path // Populating the component lists
		own_put(src, "cached_components", path, new path)

		if(!(initial(IC.spawn_flags) & (IC_SPAWN_DEFAULT | IC_SPAWN_RESEARCH)))
			continue

		var/category = initial(IC.category_text)
		if(!circuit_fabricator_recipe_list[category])
			circuit_fabricator_recipe_list[category] = list()
		var/list/category_list = circuit_fabricator_recipe_list[category]
		category_list += IC // Populating the fabricator categories

	for(var/obj/item/electronic_assembly/A as anything in typesof(/obj/item/electronic_assembly))
		var/path = A
		all_assemblies[initial(A.name)] = path
		own_put(src, "cached_assemblies", path, new path)


	circuit_fabricator_recipe_list["Assemblies"] = list(
		/obj/item/electronic_assembly/default,
		/obj/item/electronic_assembly/calc,
		/obj/item/electronic_assembly/clam,
		/obj/item/electronic_assembly/simple,
		/obj/item/electronic_assembly/hook,
		/obj/item/electronic_assembly/pda,
		/obj/item/electronic_assembly/tiny/default,
		/obj/item/electronic_assembly/tiny/cylinder,
		/obj/item/electronic_assembly/tiny/scanner,
		/obj/item/electronic_assembly/tiny/hook,
		/obj/item/electronic_assembly/tiny/box,
		/obj/item/electronic_assembly/medium/default,
		/obj/item/electronic_assembly/medium/box,
		/obj/item/electronic_assembly/medium/clam,
		/obj/item/electronic_assembly/medium/medical,
		/obj/item/electronic_assembly/medium/gun,
		/obj/item/electronic_assembly/medium/radio,
		/obj/item/electronic_assembly/large/default,
		/obj/item/electronic_assembly/large/scope,
		/obj/item/electronic_assembly/large/terminal,
		/obj/item/electronic_assembly/large/arm,
		/obj/item/electronic_assembly/large/tall,
		/obj/item/electronic_assembly/large/industrial,
		/obj/item/electronic_assembly/drone/default,
		/obj/item/electronic_assembly/drone/arms,
		/obj/item/electronic_assembly/drone/secbot,
		/obj/item/electronic_assembly/drone/medbot,
		/obj/item/electronic_assembly/drone/genbot,
		/obj/item/electronic_assembly/drone/android,
		/obj/item/electronic_assembly/wallmount/tiny,
		/obj/item/electronic_assembly/wallmount/light,
		/obj/item/electronic_assembly/wallmount,
		/obj/item/electronic_assembly/wallmount/heavy,
		/obj/item/implant/integrated_circuit,
		/obj/item/clothing/under/circuitry,
		/obj/item/clothing/gloves/circuitry,
		/obj/item/clothing/glasses/circuitry,
		/obj/item/clothing/shoes/circuitry,
		/obj/item/clothing/head/circuitry,
		/obj/item/clothing/ears/circuitry,
		/obj/item/clothing/suit/circuitry,
		/obj/item/electronic_assembly/circuit_bug
		)

	circuit_fabricator_recipe_list["Tools"] = list(
		/obj/item/integrated_electronics/wirer,
		/obj/item/integrated_electronics/debugger,
		/obj/item/integrated_electronics/detailer
		)

// Prototype instances the service spawned once, keyed by path.
