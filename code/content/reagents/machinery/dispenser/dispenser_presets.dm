/obj/machinery/chemical_dispenser/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hydrogen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lithium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/carbon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/nitrogen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/oxygen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/fluorine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/aluminum),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/silicon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/phosphorus),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sulfur),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/chlorine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/potassium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/iron),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/copper),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mercury),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/radium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ethanol),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sacid),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tungsten),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/calcium)
		)

/obj/machinery/chemical_dispenser/ert
	name = "medicine dispenser"
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/inaprov),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ryetalyn),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/paracetamol),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tramadol),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/oxycodone),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sterilizine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/leporazine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/kelotane),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dermaline),
			/obj/item/reagent_containers/chem_disp_cartridge/dexalin,
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dexalin_p),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tricord),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dylovene),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/synaptizine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hyronalin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/arithrazine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/alkysine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/imidazoline),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/peridaxon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/bicaridine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hyperzine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/rezadone),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/spaceacillin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ethylredox),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sleeptox),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/chloral),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cryoxadone),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/clonexadone)
		)

/obj/machinery/chemical_dispenser/bar_soft
	name = "soft drink dispenser"
	desc = "A soda machine."
	icon_state = "soda_dispenser"
	ui_title = "Soda Dispenser"
	accept_drinking = 1
	import_job = JOB_BARTENDER

/obj/machinery/chemical_dispenser/bar_soft/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ice),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/coffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cream),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/icetea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cola),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/smw),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dr_gibb),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/spaceup),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tonic),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodawater),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon_lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/watermelon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/grapesoda),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/pineapple)
		)

/obj/machinery/chemical_dispenser/bar_alc
	name = "booze dispenser"
	desc = "A beer machine. Like a soda machine, but more fun!"
	icon_state = "booze_dispenser"
	ui_title = "Booze Dispenser"
	accept_drinking = 1
	import_job = JOB_BARTENDER

/obj/machinery/chemical_dispenser/bar_alc/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon_lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sodawater),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tonic),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/beer),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/kahlua),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/whiskey),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/redwine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/whitewine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/vodka),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/gin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/rum),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tequila),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/vermouth),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cognac),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cider),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ale),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mead),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/bitters)
		)

/obj/machinery/chemical_dispenser/bar_coffee
	name = "coffee dispenser"
	desc = "Driving crack dealers out of employment since 2280."
	icon_state = "coffee_dispenser"
	ui_title = "Coffee Dispenser"
	accept_drinking = 1
	import_job = JOB_BARTENDER

/obj/machinery/chemical_dispenser/bar_coffee/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/coffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/drip_coffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cafe_latte),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/soy_latte),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hot_coco),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/milk),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/cream),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/milk_foam),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ice),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mint),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/orange),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lemon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/lime),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/berry),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/greentea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/decaf),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/chaitea),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/decafchai)
		)

/obj/machinery/chemical_dispenser/bar_syrup
	name = "syrup dispenser"
	desc = "Allow your customers to test your patience to the extremes."
	icon_state = "syrup_dispenser"
	ui_title = "Syrup Dispenser"
	accept_drinking = 1

/obj/machinery/chemical_dispenser/bar_syrup/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_pumpkin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_caramel),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_scaramel),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_irish),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_almond),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_cinnamon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_pistachio),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_vanilla),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_toffee),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_cherry),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/grenadine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_butterscotch),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_chocolate),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_wchocolate),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_strawberry),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_coconut),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_ginger),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_gingerbread),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_peppermint),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/syrup_birthday)
		)


/obj/machinery/chemical_dispenser/xenoflora
	name = "xenoflora chem dispenser"
	ui_title = "Xenoflora Chemical Dispenser"
	dispense_reagents = list(
		REAGENT_ID_WATER, REAGENT_ID_SUGAR, REAGENT_ID_ETHANOL, REAGENT_ID_RADIUM, REAGENT_ID_AMMONIA, REAGENT_ID_DIETHYLAMINE, REAGENT_ID_PLANTBGONE, REAGENT_ID_MUTAGEN, REAGENT_ID_CALCIUM
		)
	import_job = JOB_XENOBOTANIST

/obj/machinery/chemical_dispenser/xenoflora/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sugar),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ethanol),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/radium),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ammonia),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/diethylamine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/plantbgone),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/mutagen),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/calcium)
		)

/obj/machinery/chemical_dispenser/biochemistry
	name = "bioproduct dispenser"
	ui_title = "Bioproduct Dispenser"
	dispense_reagents = list(
		REAGENT_ID_NUTRIMENT, REAGENT_ID_PROTEIN, REAGENT_ID_MILK
		)
	import_job = null

/obj/machinery/chemical_dispenser/biochemistry/full
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/nutriment),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/protein),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/milk)
		)

/obj/machinery/chemical_dispenser/ert/specialops
	import_job = null

/obj/machinery/chemical_dispenser/ert/specialops
	spawn_cartridges = list(
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/inaprov),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dylovene),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ryetalyn),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/tramadol),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/oxycodone),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/sterilizine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/leporazine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/kelotane),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dermaline),
			/obj/item/reagent_containers/chem_disp_cartridge/dexalin,
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/dexalin_p),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/synaptizine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hyronalin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/arithrazine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/alkysine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/imidazoline),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/peridaxon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/bicaridine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hyperzine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/rezadone),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/spaceacillin),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/ethylredox),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/carthatoline),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/corophizine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/myelamine),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/osteodaxon),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/biomass),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/iron),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/nutriment),
			VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/protein)
		)

/obj/machinery/chemical_dispenser/ert/specialops/abductor
	name = "chemical dispenser"
	icon_state = "dispenser_2way"
	desc = "A mysterious machine which can fabricate many chemicals."
	import_job = null
