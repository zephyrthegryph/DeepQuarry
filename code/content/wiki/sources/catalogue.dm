// The wiki's catalogue: one article per thing the station makes or orders (cat/<type>), one per research node (research/node/<id>) and one per
// supply pack (cargo/pack/<type>), read from the techweb designs, the research nodes and the supply packs. Built once with the index; each
// body on first read.
//
// Where a thing is filed is data:
//   1. a design made for exactly one department's lathes (departmental_flags) is filed in that department;
//   2. otherwise the longest matching type prefix in GLOB.wiki_catalogue_departments;
//   3. otherwise "Uncategorised", which the window sorts last.
// Its group inside the department is the first production category of its design, else the prefix row's group, else "General".

/// Type prefix -> "Department/Group". Longest prefix wins.
GLOBAL_LIST_INIT(wiki_catalogue_departments, list(
	/obj/item/reagent_containers/glass = "Research/Chemistry glassware",
	/obj/item/reagent_containers/syringe = "Medical/Injectors",
	/obj/item/reagent_containers/hypospray = "Medical/Injectors",
	/obj/item/reagent_containers/pill = "Medical/Pills and patches",
	/obj/item/reagent_containers/food = "Civilian/Food and drink",
	/obj/item/reagent_containers = "Civilian/Containers",
	/obj/item/chem_funnel = "Research/Chemistry glassware",
	/obj/item/chem_filter = "Research/Chemistry glassware",
	/obj/machinery/chem_hot_plate = "Research/Chemistry machines",
	/obj/machinery/chem_condenser = "Research/Chemistry machines",
	/obj/machinery/chem_ice_machine = "Research/Chemistry machines",
	/obj/machinery/chem_master = "Research/Chemistry machines",
	/obj/machinery/chemical_dispenser = "Research/Chemistry machines",
	/obj/item/surgical = "Medical/Surgical tools",
	/obj/item/healthanalyzer = "Medical/Diagnostics",
	/obj/item/stack/medical = "Medical/Field treatment",
	/obj/item/bodybag = "Medical/Field treatment",
	/obj/item/organ = "Medical/Organs and prosthetics",
	/obj/item/robot_parts = "Research/Robotics",
	/obj/item/mecha_parts = "Research/Exosuits",
	/obj/mecha = "Research/Exosuits",
	/obj/item/stock_parts = "Research/Machine parts",
	/obj/item/circuitboard = "Engineering/Circuit boards",
	/obj/item/integrated_circuit = "Research/Integrated circuits",
	/obj/item/implant = "Medical/Implants",
	/obj/item/implanter = "Medical/Implants",
	/obj/item/gun = "Security/Weapons",
	/obj/item/melee = "Security/Weapons",
	/obj/item/ammo_magazine = "Security/Ammunition",
	/obj/item/ammo_casing = "Security/Ammunition",
	/obj/item/handcuffs = "Security/Restraints",
	/obj/item/clothing/suit/armor = "Security/Armour",
	/obj/item/clothing/head/helmet = "Security/Armour",
	/obj/item/clothing = "Civilian/Clothing",
	/obj/item/stack/cable_coil = "Engineering/Power",
	/obj/item/cell = "Engineering/Power",
	/obj/machinery/power = "Engineering/Power",
	/obj/item/pipe = "Engineering/Atmospherics",
	/obj/machinery/atmospherics = "Engineering/Atmospherics",
	/obj/item/tank = "Engineering/Atmospherics",
	/obj/item/analyzer = "Engineering/Atmospherics",
	/obj/item/tool = "Engineering/Tools",
	/obj/item/weldingtool = "Engineering/Tools",
	/obj/item/multitool = "Engineering/Tools",
	/obj/item/t_scanner = "Engineering/Tools",
	/obj/item/rcd = "Engineering/Tools",
	/obj/item/stack/material = "Engineering/Materials",
	/obj/item/stack/tile = "Engineering/Construction",
	/obj/item/stack/rods = "Engineering/Construction",
	/obj/item/frame = "Engineering/Construction",
	/obj/item/pickaxe = "Cargo/Mining",
	/obj/item/mining_scanner = "Cargo/Mining",
	/obj/item/ore = "Cargo/Mining",
	/obj/item/seeds = "Civilian/Botany",
	/obj/item/material/minihoe = "Civilian/Botany",
	/obj/item/robotanalyzer = "Research/Robotics",
	/obj/item/modular_computer = "Command/Computers",
	/obj/item/computer_hardware = "Command/Computers",
	/obj/item/radio = "Command/Communications",
	/obj/item/paper = "Command/Paperwork",
	/obj/item/storage = "Civilian/Storage",
	/obj/item/toy = "Civilian/Recreation",
	/obj/item/flashlight = "Engineering/Tools",
	/obj/machinery = "Engineering/Machines",
	/obj/structure = "Engineering/Construction",
))

/// departmental_flags bit -> department.
GLOBAL_LIST_INIT(wiki_department_by_flag, list(
	"[DEPARTMENT_BITFLAG_SECURITY]" = "Security",
	"[DEPARTMENT_BITFLAG_SERVICE]" = "Civilian",
	"[DEPARTMENT_BITFLAG_CARGO]" = "Cargo",
	"[DEPARTMENT_BITFLAG_ENGINEERING]" = "Engineering",
	"[DEPARTMENT_BITFLAG_SCIENCE]" = "Research",
	"[DEPARTMENT_BITFLAG_MEDICAL]" = "Medical",
))

/proc/wiki_cat_id(path)
	return "cat/[replacetext("[path]", "/obj/", "")]"

/proc/wiki_node_id(node_id)
	return "research/node/[node_id]"

/proc/wiki_pack_id(datum/supply_pack/P)
	return "cargo/pack/[replacetext("[P.type]", "/datum/supply_pack/", "")]"

/// The "Department/Group" a type is filed under by its prefix, or null.
/proc/wiki_catalogue_prefix_section(path)
	var/best
	var/best_len = 0
	for(var/prefix in GLOB.wiki_catalogue_departments)
		if(!ispath(path, prefix))
			continue
		var/prefix_len = length("[prefix]")
		if(prefix_len > best_len)
			best = GLOB.wiki_catalogue_departments[prefix]
			best_len = prefix_len
	return best

/// Where a catalogue entry is filed: "Department/Catalogue/Group", or "Uncategorised/<group>".
/proc/wiki_catalogue_path(path, datum/design_techweb/design)
	var/department
	var/group
	if(design && design.departmental_flags != ALL)
		var/found
		for(var/flag in GLOB.wiki_department_by_flag)
			if(design.departmental_flags & text2num(flag))
				if(found)
					found = null
					break
				found = GLOB.wiki_department_by_flag[flag]
		department = found
	var/section = wiki_catalogue_prefix_section(path)
	if(section)
		var/list/parts = splittext(section, "/")
		department = department || parts[1]
		group = parts[2]
	if(design && length(design.category))
		group = trim(replacetext("[design.category[1]]", "/", " ")) || group
	if(!department)
		return "Uncategorised/[group || "General"]"
	return "[department]/Catalogue/[group || "General"]"

/// path -> list(designs) and path -> list(packs), built once.
GLOBAL_TABLE(wiki_catalogue_sources_table, GLOBAL_PROC_REF(build_wiki_catalogue_sources))

/proc/build_wiki_catalogue_sources()
	var/list/designs_by_path = list()
	var/list/packs_by_path = list()
	var/list/designs = research_techweb_designs()
	for(var/design_id in designs)
		var/datum/design_techweb/D = designs[design_id]
		var/path = D?.build_path ? saved_type_path(D.build_path) : null
		if(!ispath(path, /obj))
			continue
		LAZYADD(designs_by_path[path], D)
	var/list/packs = supply_supply_pack()
	for(var/pack_name in packs)
		var/datum/supply_pack/P = packs[pack_name]
		if(!P?.name || P.contraband)
			continue
		for(var/path in P.contains)
			if(ispath(path, /obj))
				LAZYOR(packs_by_path[path], P)
	return list("designs" = designs_by_path, "packs" = packs_by_path)

/proc/wiki_source_catalogue(list/index)
	var/list/sources = GLOBAL_TABLE_GET(wiki_catalogue_sources_table)
	var/list/paths = list()
	for(var/path in sources["designs"])
		paths[path] = TRUE
	for(var/path in sources["packs"])
		paths[path] = TRUE
	for(var/path in paths)
		var/obj/O = path
		var/list/designs = sources["designs"][path]
		var/datum/design_techweb/first = length(designs) ? designs[1] : null
		var/name = initial(O.name) || first?.name
		if(!name)
			continue
		wiki_set_sprite(wiki_add(index, wiki_cat_id(path), capitalize(name), wiki_catalogue_path(path, first), null, null, GLOBAL_PROC_REF(wiki_catalogue_body), path), path)
	var/list/nodes = research_techweb_nodes()
	for(var/node_id in nodes)
		var/datum/techweb_node/N = nodes[node_id]
		if(!N || !N.show_on_wiki || N.hidden)
			continue
		wiki_add(index, wiki_node_id(node_id), N.display_name, "Research/Research nodes/[N.category || "Other"]", null, null, GLOBAL_PROC_REF(wiki_node_body), node_id)
	var/list/packs = supply_supply_pack()
	for(var/pack_name in packs)
		var/datum/supply_pack/P = packs[pack_name]
		if(!P?.name || P.contraband)
			continue
		wiki_add(index, wiki_pack_id(P), P.name, "Cargo/Supply packs/[P.group || "Other"]", null, null, GLOBAL_PROC_REF(wiki_pack_body), pack_name)

/// The description a catalogued thing gives of itself: its design's, else the type's own.
/proc/wiki_catalogue_description(path)
	var/list/designs = GLOBAL_TABLE_GET(wiki_catalogue_sources_table)["designs"][path]
	for(var/datum/design_techweb/D as anything in designs)
		var/text = D.get_description()
		if(text)
			return text
	var/obj/O = path
	return initial(O.desc)

/// A design's machines, by build_type.
/proc/wiki_design_machines(datum/design_techweb/D)
	. = list()
	if(D.build_type & AUTOLATHE)
		. += "an autolathe"
	if(D.build_type & PROTOLATHE)
		. += "a protolathe"
	if(D.build_type & IMPRINTER)
		. += "a circuit imprinter"
	if(D.build_type & MECHFAB)
		. += "an exosuit fabricator"
	if(D.build_type & PROSFAB)
		. += "a prosthetics fabricator"

/// A material cost table as text: "2000 steel, 500 glass".
/proc/wiki_material_text(list/materials)
	var/list/parts = list()
	for(var/key in materials)
		var/name = "[key]"
		if(ispath(key, /datum/material))
			var/datum/material/M = key
			name = initial(M.name) || name
		parts += "[materials[key]] [name]"
	return english_list(parts)

/proc/wiki_catalogue_body(path)
	var/list/sources = GLOBAL_TABLE_GET(wiki_catalogue_sources_table)
	var/list/blocks = list(wiki_p(wiki_catalogue_description(path) || "No description is recorded for it."))
	var/list/facts = list(list("Filed under", replacetext(wiki_catalogue_path(path, null), "/", " / ")))
	blocks += list(wiki_kv(facts))
	var/list/made = list()
	var/list/nodes = list()
	var/list/recycle = list()
	for(var/datum/design_techweb/D as anything in sources["designs"][path])
		var/list/machines = wiki_design_machines(D)
		made += "[length(machines) ? "Printed in [english_list(machines, and_text = " or ")]" : "Made"] from [wiki_material_text(D.materials) || "nothing listed"], in [D.construction_time / 10] seconds."
		for(var/node_id in D.unlocked_by)
			if(wiki_title(wiki_node_id(node_id)))
				nodes[wiki_node_id(node_id)] = TRUE
		if(length(D.materials))
			recycle |= wiki_material_text(D.materials)
	if(length(made))
		blocks += list(wiki_h("How it is made"), wiki_ul(made))
	if(length(nodes))
		var/list/links = list()
		for(var/id in nodes)
			links += list(wiki_link(id, wiki_title(id)))
		blocks += list(wiki_links("Unlocked by", links))
	var/list/packs = list()
	for(var/datum/supply_pack/P as anything in sources["packs"][path])
		packs += list(wiki_link(wiki_pack_id(P), P.name, "[P.cost] points"))
	if(length(packs))
		blocks += list(wiki_h("Ordering it"), wiki_links("Supply packs", packs))
	if(!length(made) && !length(packs))
		blocks += list(wiki_note("Not printed or ordered: found where the station keeps it."))
	if(ispath(path, /obj/item/circuitboard))
		var/obj/item/circuitboard/B = path
		var/built = initial(B.build_path)
		if(built)
			var/obj/machine = built
			blocks += list(wiki_h("Builds"), wiki_p(wiki_title(wiki_cat_id(built)) ? wiki_ref(wiki_cat_id(built), initial(machine.name)) : "[initial(machine.name)]: fit the board in a machine frame with the parts it asks for, then screw it shut."))
	if(length(recycle))
		blocks += list(wiki_h("Recycling"), wiki_p("Fed to an autolathe or a recycler it gives back up to what it was made of: [english_list(recycle)]."))
	if(ispath(path, /obj/item/stack))
		blocks += list(wiki_note("A stack: use it in hand to see what it builds. Stacks of the same kind merge."))
	return blocks

/proc/wiki_node_body(node_id)
	var/datum/techweb_node/N = research_techweb_nodes()[node_id]
	var/list/blocks = list(wiki_p(N.description || "A research node."))
	var/list/facts = list(list("Category", N.category))
	var/total = 0
	for(var/point_type in N.research_costs)
		total += N.research_costs[point_type]
	if(total)
		facts += list(list("Cost", "[total] research points"))
	if(N.starting_node)
		facts += list(list("Known", "From the start of the shift"))
	blocks += list(wiki_kv(facts))
	var/list/prereqs = list()
	for(var/id in N.prereq_ids)
		if(wiki_title(wiki_node_id(id)))
			prereqs += list(wiki_link(wiki_node_id(id), wiki_title(wiki_node_id(id))))
	if(length(prereqs))
		blocks += list(wiki_links("Needs", prereqs))
	var/list/unlocks = list()
	for(var/id in N.unlock_ids)
		if(wiki_title(wiki_node_id(id)))
			unlocks += list(wiki_link(wiki_node_id(id), wiki_title(wiki_node_id(id))))
	if(length(unlocks))
		blocks += list(wiki_links("Leads to", unlocks))
	var/list/designs = list()
	for(var/design_id in N.design_ids)
		var/datum/design_techweb/D = research_techweb_designs()[design_id]
		var/path = D?.build_path ? saved_type_path(D.build_path) : null
		if(path && wiki_title(wiki_cat_id(path)))
			designs += list(wiki_link(wiki_cat_id(path), D.name))
		else if(D)
			designs += list(wiki_link(null, D.name))
	if(length(designs))
		blocks += list(wiki_h("Designs"), wiki_links("Unlocks", designs))
	return blocks

/proc/wiki_pack_body(pack_name)
	var/datum/supply_pack/P = supply_supply_pack()[pack_name]
	var/list/blocks = list(wiki_p(P.desc || "A supply crate."))
	var/list/facts = list(list("Cost", "[P.cost] points"), list("Group", P.group))
	if(P.access)
		facts += list(list("Locked", "Opens with the right access"))
	if(P.num_contained)
		facts += list(list("Contents", "[P.num_contained] picked at random from the list below"))
	blocks += list(wiki_kv(facts))
	var/list/items = list()
	var/list/counts = list()
	for(var/path in P.contains)
		counts[path] = (counts[path] || 0) + max(1, isnum(P.contains[path]) ? P.contains[path] : 1)
	for(var/path in counts)
		var/obj/O = path
		var/id = wiki_cat_id(path)
		items += list(wiki_link(wiki_title(id) ? id : null, capitalize(initial(O.name) || "[path]"), counts[path] > 1 ? "x[counts[path]]" : null, null, path))
	if(length(items))
		blocks += list(wiki_links("Contains", items))
	blocks += list(wiki_note("Order it at a supply console; see [wiki_ref("guide/cargo/ordering", "ordering supplies")]."))
	return blocks
