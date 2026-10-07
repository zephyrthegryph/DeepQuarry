/datum/seed_pile
	var/name
	var/amount
	var/tmp/datum/seed/seed_type_static	// Keeps track of what our seed is
	// ALLOW(instance_list): d: a seed pile holds seeds
	var/list/obj/item/seeds/seeds = list() // Tracks actual objects contained in the pile
	var/ID

CAPABILITIES(/datum/seed_pile)
	owns_one(nameof(seed_type_static), on_destroy = ON_DESTROY_PRIVATE_COPY)

// The seed objects sit in the storage machine's contents; the pile only indexes them.
/datum/seed_pile/ownership()
	. = ..()
	. += owns(nameof(seeds), policy = OWN_SPILL)

/datum/seed_pile/New(obj/item/seeds/O, ID)
	name = O.name
	amount = 1
	// The pile's own reference seed: the registered line, or a private snapshot of a packet's private copy.
	var/datum/seed/S = O.seed()
	proto_set(src, nameof(seed_type_static), (!S || is_registered(S)) ? S : S.copy_line())
	rel_add(src, nameof(seeds), O)
	src.ID = ID

/datum/seed_pile/proc/matches(obj/item/seeds/O)
	if (O.seed() == seed_type())
		return 1
	return 0

/obj/machinery/seed_storage
	name = "Seed storage"
	desc = "It stores, sorts, and dispenses seeds."
	icon = 'icons/obj/vending.dmi'
	icon_state = "seeds"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 100

	var/seeds_initialized = 0 // Map-placed ones break if seeds are loaded right at the start of the round, so we do it on the first interaction
	var/list/datum/seed_pile/piles = list() // ALLOW(instance_list): d: seed piles are filled at init and are the machine's stock
	var/list/datum/seed_pile/piles_contra //Hacked.
	var/list/starting_seeds
	var/list/contraband_seeds //Seeds we only show if we've been hacked.
	var/list/scanner // What properties we can view
	var/smart = 0 //Used for hacking. Overrides the scanner.
	var/hacked = 0
	var/lockdown = 0

/// Shocks its users like an airlock: the shock wire cut (until mended) or pulsed (30 s); live only while operable (shock_live()).
STAT(/obj/machinery/seed_storage, electrified, TOP, base = 0)

CAPABILITIES(/obj/machinery/seed_storage)
	started_work(step = PROC_REF(work_step))
	owns_many(nameof(piles), /datum/seed_pile)
	owns_many(nameof(piles_contra), /datum/seed_pile)
	interface("SeedStorage")
	extend("ui_open", priority(OP_PRIORITY_DEFAULT - 3))
	op("vend", ui_act("vend", arg("id", num())), then(PROC_REF(ui_act_vend)))
	op("purge", ui_act("purge", arg("id", num())), then(PROC_REF(ui_act_purge)))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Seed Storage", count = 4, randomize = TRUE, tools = FALSE, status_lines = PROC_REF(wire_lights))
	shock_wire(stat = STAT_ELECTRIFIED)
	on_wire(WIRE_SEED_SMART, cut = PROC_REF(smart_wire_cut), pulse = PROC_REF(smart_wire_pulsed))
	on_wire(WIRE_CONTRABAND, cut = PROC_REF(contraband_wire_cut), pulse = PROC_REF(contraband_wire_pulsed))
	on_wire(WIRE_SEED_LOCKDOWN, cut = PROC_REF(lockdown_wire_cut), pulse = PROC_REF(lockdown_wire_pulsed))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("insert_seeds", item(/obj/item/seeds), priority(OP_PRIORITY_DEFAULT - 1), label("Insert seeds"), needs(req(PROC_REF(not_locked_down_holds), because = PROC_REF(not_locked_down_refusal))), then(PROC_REF(interaction_insert_seeds)))
	op("insert_bag", item(/obj/item/storage/bag/plants), priority(OP_PRIORITY_DEFAULT - 1), label("Empty seed bag"), needs(req(PROC_REF(not_locked_down_holds), because = PROC_REF(not_locked_down_refusal))), then(PROC_REF(interaction_insert_bag)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 2), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("use_wire_tools", any_of_tools(TOOL_WIRECUTTER, TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Wires"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)), then(PROC_REF(wire_tool_used)))

/obj/machinery/seed_storage/proc/wire_lights()
	return list(
		"The orange light is [shock_live(src) ? "off." : "on."]",
		"The red light is [smart ? "off." : "blinking."]",
		"The green light is [(hacked || emagged()) ? "on." : "off."]",
		"The keypad lock light is [lockdown ? "deployed." : "retracted."]")

/// The smart wire cut turns smart mode off (mending does not turn it back on).
/obj/machinery/seed_storage/proc/smart_wire_cut(datum/act/A)
	smart = FALSE

/obj/machinery/seed_storage/proc/smart_wire_pulsed(datum/act/A)
	smart = !smart

/obj/machinery/seed_storage/proc/contraband_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	hacked = !N.mended

/obj/machinery/seed_storage/proc/contraband_wire_pulsed(datum/act/A)
	hacked = !hacked

/// The lockdown wire mended locks the keypad down and clears the access; cut, the access is back as built.
/obj/machinery/seed_storage/proc/lockdown_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		lockdown = TRUE
		req_access = list()
		req_one_access = list()
	else
		req_access = initial(req_access)
		req_one_access = initial(req_one_access)

/obj/machinery/seed_storage/proc/lockdown_wire_pulsed(datum/act/A)
	lockdown = !lockdown

// ALLOW(init/INSTANCE_STATE): rolls its contraband seed batch
/obj/machinery/seed_storage/Initialize(mapload)
	. = ..()
	if(!length(contraband_seeds))
		contraband_seeds = pick( 	/// Some form of ambrosia in all lists.
			prob(30);list( /// General produce
				/obj/item/seeds/ambrosiavulgarisseed = 3,
				/obj/item/seeds/greengrapeseed = 3,
				/obj/item/seeds/icepepperseed = 2,
				/obj/item/seeds/kudzuseed = 1
			),
			prob(30);list( ///Mushroom batch
				/obj/item/seeds/ambrosiavulgarisseed = 1,
				/obj/item/seeds/glowberryseed = 2,
				/obj/item/seeds/libertymycelium = 1,
				/obj/item/seeds/reishimycelium = 2,
				/obj/item/seeds/sporemycelium = 1
			),
			prob(15);list( /// Survivalist
				/obj/item/seeds/ambrosiadeusseed = 2,
				/obj/item/seeds/redtowermycelium = 2,
				/obj/item/seeds/vale = 2,
				/obj/item/seeds/siflettuce = 2
			),
			prob(20);list( /// Cold plants
				/obj/item/seeds/ambrosiavulgarisseed = 2,
				/obj/item/seeds/thaadra = 2,
				/obj/item/seeds/icepepperseed = 2,
				/obj/item/seeds/siflettuce = 1
			),
			prob(10);list( ///Poison party
				/obj/item/seeds/ambrosiavulgarisseed = 3,
				/obj/item/seeds/surik = 1,
				/obj/item/seeds/telriis = 1,
				/obj/item/seeds/nettleseed = 2,
				/obj/item/seeds/poisonberryseed = 1
			),
			prob(5);list( /// Extra poison party!
				/obj/item/seeds/ambrosiainfernusseed = 1,
				/obj/item/seeds/amauri = 1,
				/obj/item/seeds/surik = 1,
				/obj/item/seeds/deathberryseed = 1 /// Very ow.
			)
		)

/// Seed storage has no timed work of its own (its shock is a timed hold).
/obj/machinery/seed_storage/proc/work_step(datum/act/timer/A)
	return PROCESS_KILL

/obj/machinery/seed_storage/random // This is mostly for testing, but I guess admins could spawn it
	name = "Random seed storage"
	scanner = list("stats", "produce", "soil", "temperature", "light", "pressure")
	starting_seeds = list(/obj/item/seeds/random = 50)

/obj/machinery/seed_storage/garden
	name = "Garden seed storage"
	scanner = list("stats")
	starting_seeds = list(
		/obj/item/seeds/appleseed = 3,
		/obj/item/seeds/bananaseed = 3,
		/obj/item/seeds/berryseed = 3,
		/obj/item/seeds/cabbageseed = 3,
		/obj/item/seeds/carrotseed = 3,
		/obj/item/seeds/celery = 3,
		/obj/item/seeds/chantermycelium = 3,
		/obj/item/seeds/cherryseed = 3,
		/obj/item/seeds/chiliseed = 3,
		/obj/item/seeds/cocoapodseed = 3,
		/obj/item/seeds/cornseed = 3,
		/obj/item/seeds/durian = 3,
		/obj/item/seeds/eggplantseed = 3,
		/obj/item/seeds/grapeseed = 3,
		/obj/item/seeds/grassseed = 3,
		/obj/item/seeds/replicapod = 3,
		/obj/item/seeds/lavenderseed = 3,
		/obj/item/seeds/lemonseed = 3,
		/obj/item/seeds/lettuce = 3,
		/obj/item/seeds/limeseed = 3,
		/obj/item/seeds/mtearseed = 2,
		/obj/item/seeds/orangeseed = 3,
		/obj/item/seeds/onionseed = 3,
		/obj/item/seeds/peanutseed = 3,
		/obj/item/seeds/plumpmycelium = 3,
		/obj/item/seeds/poppyseed = 3,
		/obj/item/seeds/potatoseed = 3,
		/obj/item/seeds/pumpkinseed = 3,
		/obj/item/seeds/rhubarb = 3,
		/obj/item/seeds/riceseed = 3,
		/obj/item/seeds/rose = 3,
		/obj/item/seeds/soyaseed = 3,
		/obj/item/seeds/pineapple = 3,
		/obj/item/seeds/sugarcaneseed = 3,
		/obj/item/seeds/sunflowerseed = 3,
		/obj/item/seeds/shandseed = 2,
		/obj/item/seeds/tobaccoseed = 3,
		/obj/item/seeds/tomatoseed = 3,
		/obj/item/seeds/towermycelium = 3,
		/obj/item/seeds/vanilla = 3,
		/obj/item/seeds/wabback = 2,
		/obj/item/seeds/watermelonseed = 3,
		/obj/item/seeds/wheatseed = 3,
		/obj/item/seeds/whitebeetseed = 3,
		/obj/item/seeds/wurmwoad = 3
		)

/obj/machinery/seed_storage/xenobotany
	name = "Xenobotany seed storage"
	scanner = list("stats", "produce", "soil", "temperature", "light", "pressure")
	smart = 1
	starting_seeds = list(
		/obj/item/seeds/ambrosiavulgarisseed = 3,
		/obj/item/seeds/appleseed = 3,
		/obj/item/seeds/amanitamycelium = 2,
		/obj/item/seeds/bananaseed = 3,
		/obj/item/seeds/berryseed = 3,
		/obj/item/seeds/cabbageseed = 3,
		/obj/item/seeds/carrotseed = 3,
		/obj/item/seeds/celery = 3,
		/obj/item/seeds/chantermycelium = 3,
		/obj/item/seeds/cherryseed = 3,
		/obj/item/seeds/chiliseed = 3,
		/obj/item/seeds/cocoapodseed = 3,
		/obj/item/seeds/cornseed = 3,
		/obj/item/seeds/durian = 3,
		/obj/item/seeds/replicapod = 3,
		/obj/item/seeds/eggplantseed = 3,
		/obj/item/seeds/glowshroom = 2,
		/obj/item/seeds/grapeseed = 3,
		/obj/item/seeds/grassseed = 3,
		/obj/item/seeds/lavenderseed = 3,
		/obj/item/seeds/lemonseed = 3,
		/obj/item/seeds/lettuce = 3,
		/obj/item/seeds/libertymycelium = 2,
		/obj/item/seeds/limeseed = 3,
		/obj/item/seeds/mtearseed = 2,
		/obj/item/seeds/nettleseed = 2,
		/obj/item/seeds/orangeseed = 3,
		/obj/item/seeds/peanutseed = 3,
		/obj/item/seeds/plastiseed = 3,
		/obj/item/seeds/plumpmycelium = 3,
		/obj/item/seeds/poppyseed = 3,
		/obj/item/seeds/potatoseed = 3,
		/obj/item/seeds/pumpkinseed = 3,
		/obj/item/seeds/reishimycelium = 2,
		/obj/item/seeds/rhubarb = 3,
		/obj/item/seeds/riceseed = 3,
		/obj/item/seeds/rose = 3,
		/obj/item/seeds/soyaseed = 3,
		/obj/item/seeds/pineapple = 3,
		/obj/item/seeds/sugarcaneseed = 3,
		/obj/item/seeds/sunflowerseed = 3,
		/obj/item/seeds/shandseed = 2,
		/obj/item/seeds/tobaccoseed = 3,
		/obj/item/seeds/tomatoseed = 3,
		/obj/item/seeds/towermycelium = 3,
		/obj/item/seeds/vanilla = 3,
		/obj/item/seeds/wabback = 2,
		/obj/item/seeds/watermelonseed = 3,
		/obj/item/seeds/wheatseed = 3,
		/obj/item/seeds/whitebeetseed = 3,
		/obj/item/seeds/wurmwoad = 3
		)

/obj/machinery/seed_storage/proc/not_locked_down(mob/actor, atom/target, obj/item/held)
	return !lockdown // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu

/// Requirement (was REQ_* not_locked_down): the legacy check answers TRUE to pass.
/obj/machinery/seed_storage/proc/not_locked_down_holds(datum/act/op/A)
	var/answer = not_locked_down(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why not_locked_down_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/seed_storage/proc/not_locked_down_refusal(datum/act/op/A)
	var/answer = not_locked_down(A.actor, src, A.held)
	return istext(answer) ? answer : "it's locked down"

/obj/machinery/seed_storage/proc/interaction_insert_seeds(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/seeds/O = A.held
	add(O)
	act_message(user, src, MSG_SELF(span_filter_notice("You put %I% into %T%.")), MSG_OTHERS(span_filter_notice("%U% puts \the [O.name] into %T%.")), item = O)
	return TRUE

/obj/machinery/seed_storage/proc/interaction_insert_bag(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/storage/P = A.held
	var/loaded = 0
	for(var/obj/item/seeds/G in contents_of(P))
		++loaded
		add(G)
	if (loaded)
		act_message(user, src, MSG_SELF(span_filter_notice("You put the seeds from \the [P.name] into %T%.")), \
			MSG_OTHERS(span_filter_notice("%U% puts the seeds from \the [P.name] into %T%.")))
	else
		to_chat(user, span_notice("There are no seeds in \the [P.name]."))
	return TRUE

/obj/machinery/seed_storage/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return TRUE

	if(shock_live(src))
		if(shock(user, 100))
			return TRUE

	if(panel_open)
		wires_open(src, user)
	if(lockdown)
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/seed_storage/ui_prepare(mob/user, datum/tgui/ui)
	if(!seeds_initialized)
		for(var/typepath in starting_seeds)
			var/amount = LAZYACCESS(starting_seeds, typepath)
			if(isnull(amount)) amount = 1

			for(var/i = 1 to amount)
				var/O = new typepath
				add(O)
		for(var/typepath in contraband_seeds)
			var/amount = LAZYACCESS(contraband_seeds, typepath)
			if(isnull(amount)) amount = 1

			for (var/i = 1 to amount)
				var/O = new typepath
				add(O, 1)
		seeds_initialized = 1

	return TRUE

/// /obj/machinery/seed_storage's window data.
/obj/machinery/seed_storage/ui_data(datum/act/eval/A)
	var/list/data = list()

	if(smart)
		scanner = list("stats", "produce", "soil", "temperature", "light", "pressure")
	else
		scanner = initial(scanner)

	data["scanner"] = (scanner || list())

	var/list/piles_to_check = piles
	if(hacked || emagged())
		piles_to_check = piles + piles_contra

	var/list/seeds = list()
	for(var/datum/seed_pile/S in piles_to_check)
		var/datum/seed/seed = S.seed_type()
		if(!seed)
			continue
		var/list/seedinfo = list(
			"name" = seed.seed_name,
			"uid" = seed.uid,
			"amount" = S.amount,
			"id" = S.ID,
		)

		seedinfo["traits"] = list()
		if("stats" in scanner)
			seedinfo["traits"]["Endurance"] = seed.get_trait(TRAIT_ENDURANCE)
			seedinfo["traits"]["Yield"] = seed.get_trait(TRAIT_YIELD)
			seedinfo["traits"]["Production"] = seed.get_trait(TRAIT_PRODUCTION)
			seedinfo["traits"]["Potency"] = seed.get_trait(TRAIT_POTENCY)
			seedinfo["traits"]["Repeat Harvest"] = seed.get_trait(TRAIT_HARVEST_REPEAT)
		if("temperature" in scanner)
			seedinfo["traits"]["Ideal Heat"] = seed.get_trait(TRAIT_IDEAL_HEAT)
		if("light" in scanner)
			seedinfo["traits"]["Ideal Light"] = seed.get_trait(TRAIT_IDEAL_LIGHT)
		if("soil" in scanner)
			if(seed.get_trait(TRAIT_REQUIRES_NUTRIENTS))
				if(seed.get_trait(TRAIT_NUTRIENT_CONSUMPTION) < 0.05)
					seedinfo["traits"]["Nutrient Consumption"] = "Low"
				else if(seed.get_trait(TRAIT_NUTRIENT_CONSUMPTION) > 0.2)
					seedinfo["traits"]["Nutrient Consumption"] = "High"
				else
					seedinfo["traits"]["Nutrient Consumption"] = "Norm"
			else
				seedinfo["traits"]["Nutrient Consumption"] = "No"
			if(seed.get_trait(TRAIT_REQUIRES_WATER))
				if(seed.get_trait(TRAIT_WATER_CONSUMPTION) < 1)
					seedinfo["traits"]["Water Consumption"] = "Low"
				else if(seed.get_trait(TRAIT_WATER_CONSUMPTION) > 5)
					seedinfo["traits"]["Water Consumption"] = "High"
				else
					seedinfo["traits"]["Water Consumption"] = "Norm"
			else
				seedinfo["traits"]["Water Consumption"] = "No"

		seedinfo["traits"]["notes"] = ""
		switch(seed.get_trait(TRAIT_CARNIVOROUS))
			if(1)
				seedinfo["traits"]["notes"] += "CARN "
			if(2)
				seedinfo["traits"]["notes"] += "FASTCARN"
		switch(seed.get_trait(TRAIT_SPREAD))
			if(1)
				seedinfo["traits"]["notes"] += "VINE "
			if(2)
				seedinfo["traits"]["notes"] += "FASTVINE"
		if ("pressure" in scanner)
			if(seed.get_trait(TRAIT_LOWKPA_TOLERANCE) < 20)
				seedinfo["traits"]["notes"] += "LP "
			if(seed.get_trait(TRAIT_HIGHKPA_TOLERANCE) > 220)
				seedinfo["traits"]["notes"] += "HP "
		if ("temperature" in scanner)
			if(seed.get_trait(TRAIT_HEAT_TOLERANCE) > 30)
				seedinfo["traits"]["notes"] += "TEMRES "
			else if(seed.get_trait(TRAIT_HEAT_TOLERANCE) < 10)
				seedinfo["traits"]["notes"] += "TEMSEN "
		if ("light" in scanner)
			if(seed.get_trait(TRAIT_LIGHT_TOLERANCE) > 10)
				seedinfo["traits"]["notes"] += "LIGRES "
			else if(seed.get_trait(TRAIT_LIGHT_TOLERANCE) < 3)
				seedinfo["traits"]["notes"] += "LIGSEN "
		if(seed.get_trait(TRAIT_TOXINS_TOLERANCE) < 3)
			seedinfo["traits"]["notes"] += "TOXSEN "
		else if(seed.get_trait(TRAIT_TOXINS_TOLERANCE) > 6)
			seedinfo["traits"]["notes"] += "TOXRES "
		if(seed.get_trait(TRAIT_PEST_TOLERANCE) < 3)
			seedinfo["traits"]["notes"] += "PESTSEN "
		else if(seed.get_trait(TRAIT_PEST_TOLERANCE) > 6)
			seedinfo["traits"]["notes"] += "PESTRES "
		if(seed.get_trait(TRAIT_WEED_TOLERANCE) < 3)
			seedinfo["traits"]["notes"] += "WEEDSEN "
		else if(seed.get_trait(TRAIT_WEED_TOLERANCE) > 6)
			seedinfo["traits"]["notes"] += "WEEDRES "
		if(seed.get_trait(TRAIT_PARASITE))
			seedinfo["traits"]["notes"] += "PAR "
		if ("temperature" in scanner)
			if(seed.get_trait(TRAIT_ALTER_TEMP) > 0)
				seedinfo["traits"]["notes"] += "TEMP+ "
			if(seed.get_trait(TRAIT_ALTER_TEMP) < 0)
				seedinfo["traits"]["notes"] += "TEMP- "
		if(seed.get_trait(TRAIT_BIOLUM))
			seedinfo["traits"]["notes"] += "LUM "

		seeds.Add(list(seedinfo))

	data["seeds"] = seeds

	return data

/// The pile the UI's id names, among those this storage shows.
/obj/machinery/seed_storage/proc/pile_by_id(id)
	var/list/piles_to_check = piles
	if(hacked || emagged())
		piles_to_check = piles + piles_contra
	for(var/datum/seed_pile/N in piles_to_check)
		if(N.ID == id)
			return N
	return null

/obj/machinery/seed_storage/proc/ui_act_vend(datum/act/op/A, id)
	var/datum/seed_pile/N = pile_by_id(id)
	if(!N)
		return
	var/obj/O = pick(N.seeds)
	if(O)
		--N.amount
		own_take_member(N, nameof(/datum/seed_pile::seeds), O)
		if(N.amount <= 0 || N.seeds.len <= 0)
			own_take_member(src, nameof(/obj/machinery/seed_storage::piles), N)
			own_take_member(src, nameof(/obj/machinery/seed_storage::piles_contra), N)
			spent(N)
		O.forceMove(src.loc)
	else
		own_take_member(src, nameof(/obj/machinery/seed_storage::piles), N)
		own_take_member(src, nameof(/obj/machinery/seed_storage::piles_contra), N)
		spent(N)
	return TRUE

/obj/machinery/seed_storage/proc/ui_act_purge(datum/act/op/A, id)
	var/datum/seed_pile/N = pile_by_id(id)
	if(!N)
		return
	for(var/obj/O in N.seeds)
		spent(O)
	own_take_member(src, nameof(/obj/machinery/seed_storage::piles), N)
	own_take_member(src, nameof(/obj/machinery/seed_storage::piles_contra), N)
	spent(N)
	return TRUE

/obj/machinery/seed_storage/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, TRUE)
	set_anchored(!anchored)
	to_chat(user, span_filter_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))
	return OP_OK

/obj/machinery/seed_storage/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	set_panel_open(!panel_open)
	to_chat(user, span_filter_notice("You [panel_open ? "open" : "close"] the maintenance panel."))
	playsound(src, tool.usesound, 50, TRUE)
	cut_overlays()
	if(panel_open)
		add_overlay("[initial(icon_state)]-panel")
	return OP_OK

/// The wirecutters or a multitool behind the open panel: the wires.
/obj/machinery/seed_storage/proc/wire_tool_used(datum/act/op/A)
	wires_open(src, A.actor)
	return OP_OK

DECLARE_EMAG(/obj/machinery/seed_storage, PROC_REF(on_emag), null, null)
/obj/machinery/seed_storage/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	set_emagged(1)
	if(lockdown)
		to_chat(user, span_notice("\The [src]'s control panel thunks, as its cover retracts."))
		lockdown = 0
	if(LAZYLEN(req_access) || LAZYLEN(req_one_access))
		req_access = list()
		req_one_access = list()
		to_chat(user, span_warning("\The [src]'s access mechanism shorts out."))
		fx_sparks(src, 3, FALSE)
		visible_message(span_warning("\The [src]'s panel sparks!"))
	return 1

/obj/machinery/seed_storage/proc/add(obj/item/seeds/O as obj, contraband = 0)
	if (istype(O.loc, /mob))
		var/mob/user = O.loc
		user.remove_from_mob(O)
	else if(istype(O.loc,/obj/item/storage))
		var/obj/item/storage/S = O.loc
		S.remove_from_storage(O, src)

	O.forceMove(src)
	var/newID = 0

	if(contraband)
		if(piles.len)
			var/datum/seed_pile/final_pile = piles[piles.len]
			newID = final_pile.ID + 1
		for (var/datum/seed_pile/N in piles_contra)
			if (N.matches(O))
				++N.amount
				rel_add(N, nameof(N.seeds), (O))
				return
			else if(N.ID >= newID)
				newID = N.ID + 1
		rel_add(src, nameof(piles_contra), new /datum/seed_pile(O, newID))
		return

	for (var/datum/seed_pile/N in piles)
		if (N.matches(O))
			++N.amount
			rel_add(N, nameof(N.seeds), (O))
			return
		else if(N.ID >= newID)
			newID = N.ID + 1

	rel_add(src, nameof(piles), new /datum/seed_pile(O, newID))

	return


// seeds: teaseed
/obj/machinery/seed_storage/garden
	starting_seeds = list(
		/obj/item/seeds/appleseed = 3,
		/obj/item/seeds/bananaseed = 3,
		/obj/item/seeds/berryseed = 3,
		/obj/item/seeds/cabbageseed = 3,
		/obj/item/seeds/carrotseed = 3,
		/obj/item/seeds/celery = 3,
		/obj/item/seeds/chantermycelium = 3,
		/obj/item/seeds/cherryseed = 3,
		/obj/item/seeds/chiliseed = 3,
		/obj/item/seeds/cocoapodseed = 3,
		/obj/item/seeds/cornseed = 3,
		/obj/item/seeds/durian = 3,
		/obj/item/seeds/eggplantseed = 3,
		/obj/item/seeds/grapeseed = 3,
		/obj/item/seeds/grassseed = 3,
		/obj/item/seeds/replicapod = 3,
		/obj/item/seeds/lavenderseed = 3,
		/obj/item/seeds/lemonseed = 3,
		/obj/item/seeds/lettuce = 3,
		/obj/item/seeds/limeseed = 3,
		/obj/item/seeds/mtearseed = 2,
		/obj/item/seeds/mustardseed = 3,
		/obj/item/seeds/orangeseed = 3,
		/obj/item/seeds/onionseed = 3,
		/obj/item/seeds/peanutseed = 3,
		/obj/item/seeds/peppercornseed = 2,
		/obj/item/seeds/plumpmycelium = 3,
		/obj/item/seeds/poppyseed = 3,
		/obj/item/seeds/potatoseed = 3,
		/obj/item/seeds/pumpkinseed = 3,
		/obj/item/seeds/rhubarb = 3,
		/obj/item/seeds/riceseed = 3,
		/obj/item/seeds/rose = 3,
		/obj/item/seeds/soyaseed = 3,
		/obj/item/seeds/pineapple = 3,
		/obj/item/seeds/sugarcaneseed = 3,
		/obj/item/seeds/sunflowerseed = 3,
		/obj/item/seeds/shandseed = 2,
		/obj/item/seeds/teaseed = 3,
		/obj/item/seeds/tobaccoseed = 3,
		/obj/item/seeds/tomatoseed = 3,
		/obj/item/seeds/towermycelium = 3,
		/obj/item/seeds/vanilla = 3,
		/obj/item/seeds/wabback = 2,
		/obj/item/seeds/watermelonseed = 3,
		/obj/item/seeds/wheatseed = 3,
		/obj/item/seeds/whitebeetseed = 3,
		/obj/item/seeds/wurmwoad = 3,
		/obj/item/seeds/shrinkshroom = 3,
		/obj/item/seeds/megashroom = 3)

// adds pitcherseed
/obj/machinery/seed_storage/xenobotany
	name = "Xenobotany seed storage"
	scanner = list("stats", "produce", "soil", "temperature", "light")
	starting_seeds = list(
		/obj/item/seeds/ambrosiavulgarisseed = 3,
		/obj/item/seeds/appleseed = 3,
		/obj/item/seeds/amanitamycelium = 2,
		/obj/item/seeds/bananaseed = 3,
		/obj/item/seeds/berryseed = 3,
		/obj/item/seeds/cabbageseed = 3,
		/obj/item/seeds/carrotseed = 3,
		/obj/item/seeds/celery = 3,
		/obj/item/seeds/chantermycelium = 3,
		/obj/item/seeds/cherryseed = 3,
		/obj/item/seeds/chiliseed = 3,
		/obj/item/seeds/cocoapodseed = 3,
		/obj/item/seeds/cornseed = 3,
		/obj/item/seeds/durian = 3,
		/obj/item/seeds/replicapod = 3,
		/obj/item/seeds/eggplantseed = 3,
		/obj/item/seeds/glowshroom = 2,
		/obj/item/seeds/grapeseed = 3,
		/obj/item/seeds/grassseed = 3,
		/obj/item/seeds/lavenderseed = 3,
		/obj/item/seeds/lemonseed = 3,
		/obj/item/seeds/lettuce = 3,
		/obj/item/seeds/libertymycelium = 2,
		/obj/item/seeds/limeseed = 3,
		/obj/item/seeds/mtearseed = 2,
		/obj/item/seeds/mustardseed = 3,
		/obj/item/seeds/nettleseed = 2,
		/obj/item/seeds/orangeseed = 3,
		/obj/item/seeds/peanutseed = 3,
		/obj/item/seeds/peppercornseed = 2,
		/obj/item/seeds/plastiseed = 3,
		/obj/item/seeds/plumpmycelium = 3,
		/obj/item/seeds/poppyseed = 3,
		/obj/item/seeds/potatoseed = 3,
		/obj/item/seeds/pumpkinseed = 3,
		/obj/item/seeds/reishimycelium = 2,
		/obj/item/seeds/rhubarb = 3,
		/obj/item/seeds/riceseed = 3,
		/obj/item/seeds/rose = 3,
		/obj/item/seeds/soyaseed = 3,
		/obj/item/seeds/pineapple = 3,
		/obj/item/seeds/sugarcaneseed = 3,
		/obj/item/seeds/sunflowerseed = 3,
		/obj/item/seeds/shandseed = 2,
		/obj/item/seeds/teaseed = 3,
		/obj/item/seeds/tobaccoseed = 3,
		/obj/item/seeds/tomatoseed = 3,
		/obj/item/seeds/towermycelium = 3,
		/obj/item/seeds/vanilla = 3,
		/obj/item/seeds/wabback = 2,
		/obj/item/seeds/watermelonseed = 3,
		/obj/item/seeds/wheatseed = 3,
		/obj/item/seeds/whitebeetseed = 3,
		/obj/item/seeds/wurmwoad = 3,
		/obj/item/seeds/shrinkshroom = 3,
		/obj/item/seeds/megashroom = 3,
		/obj/item/seeds/lustflower = 2,
		/obj/item/seeds/pitcherseed = 3)

/// The pile's seed (PROTO): a registered line, or its own snapshot.
/datum/seed_pile/proc/seed_type() as /datum/seed
	return seed_type_static
