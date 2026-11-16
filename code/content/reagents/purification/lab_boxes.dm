// The chemistry lab's loose stock, boxed: the supplies closet and the chemical closet hold these instead of a heap of single items
// (the closets' starts_with in code/content/structures/crates_lockers/closets/secure/medical.dm). Each box holds what its starts_with lists inside its own
// capacity (INVENTORY_BOX_SPACE, 14 units: small things cost 2, tiny things 1); dq_chem_lab_boxes_fit_their_contents proves it.

/// Funnels and the filters that go in them.
/obj/item/storage/box/chem_funnels
	name = "box of funnels and filters"
	desc = "Two funnels and a stack of paper and charcoal filters for them."
	icon_state = "box"
	starts_with = list(
		/obj/item/chem_funnel = 2,
		/obj/item/chem_filter/paper = 4,
		/obj/item/chem_filter/charcoal = 4)

/// The electrode pairs for electrolysis on a hot plate.
/obj/item/storage/box/chem_electrodes
	name = "box of electrodes"
	desc = "Graphite electrode pairs on spring clips, for running a current through a beaker."
	icon_state = "box"
	starts_with = list(/obj/item/chem_electrode = 3)

/// The catalyst and liner sheets. A sheet stack is a normal-sized item, so this box takes normal items and has the room for the ten it starts with (40 units); sheets of a kind merge as they are put in.
/obj/item/storage/box/chem_catalysts
	name = "box of catalyst sheets"
	desc = "Tungsten sheets for catalysts and phoron glass sheets for liners."
	icon_state = "box"
	max_storage_space = ITEMSIZE_COST_NORMAL * 10
	starts_with = list(
		/obj/item/stack/material/tungsten = 6,
		/obj/item/stack/material/glass/phoronglass = 4)

CAPABILITIES(/obj/item/storage/box/chem_catalysts)
	configure(storage(max_size = ITEMSIZE_NORMAL))

/// Large beakers for the bigger batches.
/obj/item/storage/box/chem_large_beakers
	name = "box of large beakers"
	desc = "A box of large beakers."
	icon_state = "beaker"
	starts_with = list(/obj/item/reagent_containers/glass/beaker/large = 4)

/// Boron-11 and the foaming and fermenting agents the process chemicals use.
/obj/item/storage/box/chem_process_stock
	name = "box of process stock"
	desc = "Bottles of boron-11, enzyme and yeast: the stock the process chemicals are made from."
	icon_state = "beaker"
	starts_with = list(
		/obj/item/reagent_containers/glass/bottle/boron11 = 2,
		/obj/item/reagent_containers/food/condiment/enzyme = 2,
		/obj/item/reagent_containers/food/condiment/yeast = 2)

/// The emergency bottles and the droppers.
/obj/item/storage/box/chem_bench_bottles
	name = "box of bench bottles"
	desc = "Bottles of inaprovaline and antitoxin, and droppers to measure them out."
	icon_state = "beaker"
	starts_with = list(
		/obj/item/reagent_containers/glass/bottle/inaprovaline = 2,
		/obj/item/reagent_containers/glass/bottle/antitoxin = 2,
		/obj/item/reagent_containers/dropper = 2)
