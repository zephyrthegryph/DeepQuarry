// The bicaridine chain with the closet's traced bottles and the dispenser's cartridges on the hot plate: salicylic acid and nitric acid with a splash of sulphuric acid
// make nitrosalicylic acid, hydrogen reduces it. The chain is traced under GLOB.chem_trace so a stray product (space cleaner) names its route in the log.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A dispenser cartridge holding `amount` units of stock of `reagent_id` with its source's traces, as the dispenser's own recharge adds it.
/datum/unit_test/proc/dq_bic_cartridge(reagent_id, amount)
	var/obj/item/reagent_containers/chem_disp_cartridge/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge, test_floor())
	C.reagents.clear_reagents()
	C.add_stock(reagent_id, amount)
	return C

/// Runs the bicaridine chain for a round seed. Returns the beaker after step 2 and logs the amounts after each step.
/datum/unit_test/proc/dq_bic_run_chain(seed, boil_leftover = TRUE)
	rolls_fix_seed(seed)
	var/obj/item/reagent_containers/glass/bottle/precursor/salicylic_acid/sal = allocate(/obj/item/reagent_containers/glass/bottle/precursor/salicylic_acid, test_floor())
	var/obj/item/reagent_containers/glass/bottle/precursor/nitric_acid/nitric = allocate(/obj/item/reagent_containers/glass/bottle/precursor/nitric_acid, test_floor())
	var/obj/item/reagent_containers/chem_disp_cartridge/sacid = dq_bic_cartridge(REAGENT_ID_SACID, 50)
	var/obj/item/reagent_containers/chem_disp_cartridge/hydrogen = dq_bic_cartridge(REAGENT_ID_HYDROGEN, 200)
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, test_floor())
	P.set_anchored(TRUE)
	P.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	move_into(P, nameof(P.held_container), B)
	sal.reagents.trans_to_holder(B.reagents, 25)
	nitric.reagents.trans_to_holder(B.reagents, 28)
	sacid.dispense_to_holder(B.reagents, 2)
	P.switch_element(null, TRUE)
	P.set_dial(T0C + 60)
	for(var/second in 1 to 120)
		P.heat_step(1)
	log_world("CHEM TEST seed [seed] after step 1 ([round(B.get_temperature() - T0C)] C): [B.reagents.get_reagents()]")
	if(boil_leftover)
		// The book's way of clearing the leftover nitric acid: hold the beaker above its boiling point (83 C) until it has gone off.
		P.set_dial(T0C + 95)
		for(var/second in 1 to 90)
			P.heat_step(1)
		log_world("CHEM TEST seed [seed] after boiling the leftover off ([round(B.get_temperature() - T0C)] C): [B.reagents.get_reagents()]")
	P.switch_element(null, FALSE)
	B.inherit_heat(T0C + 20) // taken off the plate to cool: the hydrogen goes in at room temperature
	hydrogen.dispense_to_holder(B.reagents, 90)
	P.switch_element(null, TRUE)
	log_world("CHEM TEST seed [seed] after hydrogen at room temperature: [B.reagents.get_reagents()]")
	P.set_dial(T0C + 95)
	for(var/second in 1 to 240)
		P.heat_step(1)
	log_world("CHEM TEST seed [seed] after step 2 ([round(B.get_temperature() - T0C)] C): [B.reagents.get_reagents()]")
	return B

/// The documented chain in a normal lab beaker on the real plate, hydrogen dosed at room temperature and the beaker then heated: it makes bicaridine, and no
/// nitrogen, ammonia or space cleaner appears in it (no trace pool carries nitrogen: the pools are contaminants only).
/datum/unit_test/dq_chem_bicaridine_chain_traced_bottles

/datum/unit_test/dq_chem_bicaridine_chain_traced_bottles/Run()
	var/old_trace = GLOB.chem_trace
	var/old_seed = GLOB.round_seed
	GLOB.chem_trace = TRUE
	for(var/seed in list(4401, 4402, 4403, 4404, 4405))
		var/obj/item/reagent_containers/glass/beaker/B = dq_bic_run_chain(seed)
		var/datum/reagents/R = B.reagents
		TEST_ASSERT_EQUAL(R.get_reagent_amount(REAGENT_ID_CLEANER), 0, "seed [seed]: no space cleaner ([R.get_reagents()])")
		TEST_ASSERT_EQUAL(R.get_reagent_amount(REAGENT_ID_AMMONIA), 0, "seed [seed]: no ammonia ([R.get_reagents()])")
		TEST_ASSERT_EQUAL(R.get_reagent_amount(REAGENT_ID_NITROGEN), 0, "seed [seed]: no nitrogen ([R.get_reagents()])")
		TEST_ASSERT(R.get_reagent_amount(REAGENT_ID_BICARIDINE) > 8, "seed [seed]: the hydrogen reduced the nitrosalicylic acid to bicaridine, it did not boil away ([R.get_reagents()])")
		TEST_ASSERT(R.get_reagent_amount(REAGENT_ID_NITRICACID) < 0.01, "seed [seed]: the leftover nitric acid was boiled off ([R.get_reagents()])")
	rolls_fix_seed(old_seed)
	GLOB.chem_trace = old_trace

/// Leftover nitric acid with sulphuric acid in the beaker nitrates the finished bicaridine to residue: the designed interference, so boiling the leftover off first pays.
/datum/unit_test/dq_chem_bicaridine_leftover_nitric_taxes_the_product

/datum/unit_test/dq_chem_bicaridine_leftover_nitric_taxes_the_product/Run()
	var/obj/item/reagent_containers/glass/beaker/clean = dq_bic_run_chain(4401, TRUE)
	var/obj/item/reagent_containers/glass/beaker/dirty = dq_bic_run_chain(4401, FALSE)
	var/clean_amount = clean.reagents.get_reagent_amount(REAGENT_ID_BICARIDINE)
	var/dirty_amount = dirty.reagents.get_reagent_amount(REAGENT_ID_BICARIDINE)
	TEST_ASSERT(clean_amount > dirty_amount, "boiling the nitric acid off first leaves more bicaridine ([clean_amount]u against [dirty_amount]u with it left in)")

/// A dissolved gas dosed into a warming beaker is still there when the beaker reaches the band that uses it.
/datum/unit_test/dq_chem_dissolved_gas_stays_while_the_beaker_warms

/datum/unit_test/dq_chem_dissolved_gas_stays_while_the_beaker_warms/Run()
	var/obj/item/reagent_containers/glass/beaker/B = dq_blk_beaker(60)
	B.reagents.add_reagent(REAGENT_ID_HYDROGEN, 30, safety = 1)
	B.reagents.boil_step(10)
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_HYDROGEN) > 29, "ten seconds at 60 C leave the hydrogen ([B.reagents.get_reagent_amount(REAGENT_ID_HYDROGEN)]u of 30u)")

#endif
