// Steady-state op cost: twenty crew on the station act every few ticks for minutes of mixed play (melee, an item used on a crewmate and on the
// floor, a light switched in hand, a right-click menu, an examine, a scalpel on a crewmate (surgery), a wrench on a girder (construction)), each act through the path a player's input takes (op_resolve_click(),
// interaction_menu_data()). Reports the op system's milliseconds per tick and per act; a --profile run dumps the window's proc profile.
//   tools/build/build.sh bench --scenario=op_steady [--arg=seconds=300] [--profile]

/datum/benchmark/op_steady
	id = "op_steady"
	description = "Twenty crew in mixed play for minutes: the op system's cost per tick"

/datum/benchmark/op_steady/Run()
	wait_for_assets()
	var/list/turf/simulated/floor/floors = active_play_station_floors()
	if(length(floors) < 50)
		fail("too few open station floors ([length(floors)])")
	var/list/mob/living/carbon/human/crew = list()
	for(var/i in 1 to param("crew", 20))
		var/mob/living/carbon/human/H = new(pick(floors))
		H.mind_initialize()
		crew += H
		CHECK_TICK
	// pairs share a tile; each holds a toolbox and carries a light
	var/list/obj/item/flashlight/lights = list()
	var/list/obj/item/surgical/scalpel/scalpels = list()
	var/list/obj/item/tool/wrench/wrenches = list()
	var/list/obj/structure/girder/girders = list()
	for(var/i in 1 to length(crew) step 2)
		var/mob/living/carbon/human/A = crew[i]
		var/mob/living/carbon/human/B = crew[min(i + 1, length(crew))]
		B.forceMove(get_turf(A))
	for(var/mob/living/carbon/human/H as anything in crew)
		H.put_in_hands(new /obj/item/storage/toolbox/mechanical(H.loc))
		lights += new /obj/item/flashlight(H.loc)
		scalpels += new /obj/item/surgical/scalpel(H.loc)
		wrenches += new /obj/item/tool/wrench(H.loc)
		girders += new /obj/structure/girder(H.loc)
	wait_seconds(3)
	var/list/kinds = list("melee", "item_on_mob", "item_on_floor", "toggle", "menu", "examine", "surgery", "construction")
	var/list/kind_ms = list()
	var/list/kind_n = list()
	var/op_ms = 0
	var/ticks = 0
	var/stop_at = world.time + param("seconds", 300) SECONDS
	// each crew member acts once every act_every ticks, staggered (one act a tick each is past what a person clicks, and stretches the run)
	var/act_every = max(1, param("act_every", 5))
	begin_window()
	while(world.time < stop_at)
		for(var/i in 1 to length(crew))
			var/mob/living/carbon/human/A = crew[i]
			var/mob/living/carbon/human/B = crew[(i % 2) ? min(i + 1, length(crew)) : i - 1]
			if(QDELETED(A) || QDELETED(B) || A == B || (ticks + i) % act_every)
				continue
			var/kind = kinds[(round((ticks + i) / act_every) % length(kinds)) + 1]
			var/obj/item/T = A.get_active_hand()
			// surgery and construction hold their own tool for the act: the toolbox goes down and comes back outside the timed span
			var/obj/item/swap = null
			if(kind == "surgery" || kind == "construction")
				swap = kind == "surgery" ? scalpels[i] : wrenches[i]
				if(T)
					A.drop_from_inventory(T, A.loc)
				if(swap.loc != A.loc && swap.loc != A)
					swap.forceMove(A.loc)
				A.put_in_hands(swap)
				T = A.get_active_hand()
			var/obj/structure/girder/G = girders[i]
			if(kind == "construction" && (QDELETED(G) || G.loc != A.loc))
				G = new /obj/structure/girder(A.loc)
				girders[i] = G
			STATE_SET(A, cooldowns, next_click, 0)
			var/stamp = TICK_USAGE_REAL
			switch(kind)
				if("melee")
					A.set_use_stance(I_HURT)
					op_resolve_click(A, B, T, GESTURE_CLICK, ORIGIN_CLICK, TRUE, TRUE)
				if("item_on_mob")
					A.set_use_stance(I_HELP)
					op_resolve_click(A, B, T, GESTURE_CLICK, ORIGIN_CLICK, TRUE, TRUE)
				if("item_on_floor")
					op_resolve_click(A, get_turf(A), T, GESTURE_CLICK, ORIGIN_CLICK, TRUE, TRUE)
				if("toggle")
					var/obj/item/flashlight/F = lights[i]
					if(F.loc != A.loc)
						F.forceMove(A.loc)
					op_resolve_click(A, F, F, GESTURE_SELF, ORIGIN_CLICK, TRUE, TRUE)
				if("menu")
					interaction_menu_data(A, B)
				if("examine")
					op_resolve_click(A, B, T, GESTURE_SHIFT, ORIGIN_CLICK, TRUE, TRUE)
				if("surgery")
					A.set_use_stance(I_HELP)
					op_resolve_click(A, B, T, GESTURE_CLICK, ORIGIN_CLICK, TRUE, TRUE)
				if("construction")
					op_resolve_click(A, G, T, GESTURE_CLICK, ORIGIN_CLICK, TRUE, TRUE)
			var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
			op_ms += ms
			kind_ms[kind] += ms
			kind_n[kind]++
			if(swap)
				if(swap.loc == A)
					A.drop_from_inventory(swap, A.loc)
			// a toolbox that left the hand (set down, dropped) is taken back, so the next acts are the same kinds
			if(!A.get_active_hand())
				var/obj/item/storage/toolbox/mechanical/box = locate() in A.loc
				if(box)
					A.put_in_hands(box)
		ticks++
		stoplag()
	end_window("op_steady")
	metric("op_steady_ms_per_tick", ticks ? op_ms / ticks : 0, "ms")
	count_metric("op_steady_ticks", ticks, "ticks", "none")
	for(var/kind in kind_ms)
		metric("op_steady_[kind]_us", kind_n[kind] ? kind_ms[kind] * 1000 / kind_n[kind] : 0, "us")
	for(var/mob/living/carbon/human/H as anything in crew)
		qdel(H)
		CHECK_TICK
