#define WIRE		"wire"
#define WIRING		"wiring"
#define UNWIRE		"unwire"
#define UNWIRING	"unwiring"


/obj/item/integrated_electronics/wirer
	name = "circuit wirer"
	desc = "It's a small wiring tool, with a wire roll, electric soldering iron, wire cutter, and more in one package. \
	The wires used are generally useful for small electronics, such as circuitboards and breadboards, as opposed to larger wires \
	used for power or data transmission."
	icon = 'icons/obj/integrated_electronics/electronic_tools.dmi'
	icon_state = "wirer-wire"
	item_state = "wirer"
	w_class = ITEMSIZE_SMALL
	var/datum/integrated_io/selected_io = null
	var/mode = WIRE

TRACKED(/obj/item/integrated_electronics/wirer, mode)

/// The look (the draw sweep: from its template).
/obj/item/integrated_electronics/wirer/draw(datum/look/look)
	..()
	look.state("wirer-[mode]")

/obj/item/integrated_electronics/wirer/proc/wire(datum/integrated_io/io, mob/user)
	if(!io.holder().assembly())
		to_chat(user, span_warning("\The [io.holder()] needs to be secured inside an assembly first."))
		return
	if(mode == WIRE)
		rel_set(src, nameof(selected_io), io)
		to_chat(user, span_notice("You attach a data wire to \the [selected_io.holder()]'s [selected_io.name] data channel."))
		set_mode(WIRING)
	else if(mode == WIRING)
		if(io == selected_io)
			to_chat(user, span_warning("Wiring \the [selected_io.holder()]'s [selected_io.name] into itself is rather pointless."))
			return
		if(io.io_type != selected_io.io_type)
			to_chat(user, span_warning("Those two types of channels are incompatible. The first is a [selected_io.io_type], \
			while the second is a [io.io_type]."))
			return
		if(io.holder().assembly() && io.holder().assembly() != selected_io.holder().assembly())
			to_chat(user, span_warning("Both \the [io.holder()] and \the [selected_io.holder()] need to be inside the same assembly."))
			return
		rel_add(selected_io, nameof(selected_io.linked), io)
		rel_add(io, nameof(io.linked), selected_io)

		to_chat(user, span_notice("You connect \the [selected_io.holder()]'s [selected_io.name] to \the [io.holder()]'s [io.name]."))
		set_mode(WIRE)
		selected_io.holder().interact(user) // This is to update the UI.
		rel_clear(src, nameof(selected_io))

	else if(mode == UNWIRE)
		rel_set(src, nameof(selected_io), io)
		if(!LAZYLEN(io.linked))
			to_chat(user, span_warning("There is nothing connected to \the [selected_io] data channel."))
			rel_clear(src, nameof(selected_io))
			return
		to_chat(user, span_notice("You prepare to detach a data wire from \the [selected_io.holder()]'s [selected_io.name] data channel."))
		set_mode(UNWIRING)
		return

	else if(mode == UNWIRING)
		if(io == selected_io)
			to_chat(user, span_warning("You can't wire a pin into each other, so unwiring \the [selected_io.holder()] from \
			the same pin is rather moot."))
			return
		if(selected_io in io.linked)
			rel_remove(io, nameof(io.linked), selected_io)
			rel_remove(selected_io, nameof(selected_io.linked), io)
			to_chat(user, span_notice("You disconnect \the [selected_io.holder()]'s [selected_io.name] from \
			\the [io.holder()]'s [io.name]."))
			selected_io.holder().interact(user) // This is to update the UI.
			rel_clear(src, nameof(selected_io))
			set_mode(UNWIRE)
		else
			to_chat(user, span_warning("\The [selected_io.holder()]'s [selected_io.name] and \the [io.holder()]'s \
			[io.name] are not connected."))
			return
	return

CAPABILITIES(/obj/item/integrated_electronics/wirer)
	op("mode", in_hand(), label("Switch wiring mode"), then(PROC_REF(wiring_mode_changed)))

/obj/item/integrated_electronics/wirer/proc/wiring_mode_changed(datum/act/op/A)
	var/mob/user = A.actor
	switch(mode)
		if(WIRE)
			set_mode(UNWIRE)
		if(WIRING)
			if(selected_io)
				to_chat(user, span_notice("You decide not to wire the data channel."))
			rel_clear(src, nameof(selected_io))
			set_mode(WIRE)
		if(UNWIRE)
			set_mode(WIRE)
		if(UNWIRING)
			if(selected_io)
				to_chat(user, span_notice("You decide not to disconnect the data channel."))
			rel_clear(src, nameof(selected_io))
			set_mode(UNWIRE)
	to_chat(user, span_notice("You set \the [src] to [mode]."))
	return OP_OK

#undef WIRE
#undef WIRING
#undef UNWIRE
#undef UNWIRING

/obj/item/integrated_electronics/debugger
	name = "circuit debugger"
	desc = "This small tool allows one working with custom machinery to directly set data to a specific pin, useful for writing \
	settings to specific circuits, or for debugging purposes. It can also pulse activation pins."
	icon = 'icons/obj/integrated_electronics/electronic_tools.dmi'
	icon_state = "debugger"
	w_class = ITEMSIZE_SMALL
	var/data_to_write = null
	var/accepting_refs = 0

CAPABILITIES(/obj/item/integrated_electronics/debugger)
	op("debugger_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/integrated_electronics/debugger/proc/interaction_self(datum/act/op/A)
	var/datum/circuit_memory_review/review = new
	review.start(A.actor, src, A.held, FALSE)
	return OP_OK

/obj/item/integrated_electronics/debugger/proc/memory_type_selected(datum/circuit_memory_review/review)
	var/mob/user = review.user_value()
	switch(review.type_name)
		if("string", "number")
			stop_memory_ref_scan()
			review.open_value()
			return
		if("ref")
			accepting_refs = 1
			to_chat(user, span_notice("You turn \the [src]'s ref scanner on. Slide it across \
				an object for a ref of that object to save it in memory."))
		if("null")
			data_to_write = null
			to_chat(user, span_notice("You set \the [src]'s memory to absolutely nothing."))
	review.retire()

/obj/item/integrated_electronics/debugger/proc/stop_memory_ref_scan()
	accepting_refs = 0

/obj/item/integrated_electronics/debugger/proc/memory_value_selected(datum/circuit_memory_review/review, new_data)
	var/mob/user = review.user_value()
	stop_memory_ref_scan()
	switch(review.type_name)
		if("string")
			new_data = sanitizeSafe(new_data, MAX_MESSAGE_LEN, 0, 0)
			if(istext(new_data))
				data_to_write = new_data
				to_chat(user, span_notice("You set \the [src]'s memory to \"[new_data]\"."))
		if("number")
			if(isnum(new_data))
				data_to_write = new_data
				to_chat(user, span_notice("You set \the [src]'s memory to [new_data]."))

/obj/item/integrated_electronics/debugger/afterattack(atom/target, mob/living/user, proximity)
	if(accepting_refs && proximity)
		data_to_write = ic_ref(target)
		act_message(user, src, others = span_notice("%U% slides %T% over \the [target]."))
		to_chat(user, span_notice("You set \the [src]'s memory to a reference to [target.name] \[Ref\]. The ref scanner is \
		now off."))
		accepting_refs = 0

/obj/item/integrated_electronics/debugger/proc/write_data(datum/integrated_io/io, mob/user)
	if(io.io_type == DATA_CHANNEL)
		io.write_data_to_pin(data_to_write)
		var/data_to_show = data_to_write
		if(ic_is_ref(data_to_write))
			var/w = data_to_write
			var/atom/A = ic_ref_resolve(w)
			data_to_show = A.name
		to_chat(user, span_notice("You write '[data_to_write ? data_to_show : "NULL"]' to the '[io]' pin of \the [io.holder()]."))
	else if(io.io_type == PULSE_CHANNEL)
		io.holder().check_then_do_work(ignore_power = TRUE)
		to_chat(user, span_notice("You pulse \the [io.holder()]'s [io]."))

	io.holder().interact(user) // This is to update the UI.




/obj/item/multitool
	var/accepting_refs
	var/tmp/datum/integrated_io/selected_io
	var/mode = 0

/obj/item/multitool/draw(datum/look/look)
	..()
	look_parts(look)

/// What this chain's providers drew: each type's own part of the look, a subtype replacing or extending it (..()).
/obj/item/multitool/proc/look_parts(datum/look/look)
	if(selected_io())
		if(buffer() || connecting() || connectable())
			look.state("multitool_tracking")
		else
			look.state("multitool_red")
	else
		if(buffer() || connecting() || connectable())
			look.state("multitool_tracking_fail")
		else if(accepting_refs)
			look.state("multitool_ref_scan")
		else if(ref_wiring)
			look.state("multitool_no_camera")
		else
			look.state(initial(icon_state)) // idle: the type's own sprite (a hacktool keeps its disguise)

/obj/item/multitool/proc/wire(datum/integrated_io/io, mob/user)
	if(!io.holder().assembly())
		to_chat(user, span_warning("\The [io.holder()] needs to be secured inside an assembly first."))
		return

	if(selected_io())
		if(io == selected_io())
			to_chat(user, span_warning("Wiring \the [selected_io().holder()]'s [selected_io().name] into itself is rather pointless."))
			return
		if(io.io_type != selected_io().io_type)
			to_chat(user, span_warning("Those two types of channels are incompatible. The first is a [selected_io().io_type], \
			while the second is a [io.io_type]."))
			return
		if(io.holder().assembly() && io.holder().assembly() != selected_io().holder().assembly())
			to_chat(user, span_warning("Both \the [io.holder()] and \the [selected_io().holder()] need to be inside the same assembly."))
			return
		var/datum/integrated_io/selected = selected_io()
		rel_add(selected, nameof(selected.linked), io)
		rel_add(io, nameof(io.linked), selected)

		to_chat(user, span_notice("You connect \the [selected_io().holder()]'s [selected_io().name] to \the [io.holder()]'s [io.name]."))
		selected_io().holder().interact(user) // This is to update the UI.
		rel_clear(src, nameof(selected_io))

	else
		rel_set(src, nameof(selected_io), io)
		to_chat(user, span_notice("You link \the multitool to \the [selected_io().holder()]'s [selected_io().name] data channel."))



/obj/item/multitool/proc/unwire(datum/integrated_io/io1, datum/integrated_io/io2, mob/user)
	if(!LAZYLEN(io1.linked) || !LAZYLEN(io2.linked))
		to_chat(user, span_warning("There is nothing connected to the data channel."))
		return

	if(!(io1 in io2.linked) || !(io2 in io1.linked) )
		to_chat(user, span_warning("These data pins aren't connected!"))
		return
	else
		rel_remove(io1, nameof(io1.linked), io2)
		rel_remove(io2, nameof(io2.linked), io1)
		to_chat(user, span_notice("You clip the data connection between the [io1.holder().displayed_name]'s \
		[io1.name] and the [io2.holder().displayed_name]'s [io2.name]."))
		io1.holder().interact(user) // This is to update the UI.

/obj/item/multitool/afterattack(atom/target, mob/living/user, proximity)
	if(proximity && engineering_reading && istype(target, /obj/machinery/photocopier))
		var/obj/machinery/photocopier/copier = target
		copier.print_engineering_reading(src, user)
		return
	if(accepting_refs && toolmode == MULTITOOL_MODE_INTCIRCUITS && proximity)
		ref_wiring = ic_ref(target)
		act_message(user, src, others = span_notice("%U% slides %T% over \the [target]."))
		to_chat(user, span_notice("You set \the [src]'s memory to a reference to [target.name] \[Ref\]. The ref scanner is \
		now off."))
		accepting_refs = 0

/obj/item/storage/bag/circuits
	name = "circuit kit"
	desc = "This kit's essential for any circuitry projects."
	icon = 'icons/obj/integrated_electronics/electronic_misc.dmi'
	icon_state = "circuit_kit"
	w_class = ITEMSIZE_NORMAL
	display_contents_with_number = 0

CAPABILITIES(/obj/item/storage/bag/circuits)
	configure(storage(accepts = list(
		/obj/item/integrated_circuit,
		/obj/item/storage/bag/circuits/mini,
		/obj/item/electronic_assembly,
		/obj/item/integrated_electronics,
		/obj/item/tool/crowbar,
		/obj/item/tool/screwdriver,
		/obj/item/multitool,
		/obj/item/integrated_electronics/wirer,
		/obj/item/integrated_electronics/debugger,
		/obj/item/integrated_electronics/detailer)))

//Emp'ing this one bag causes a recursion loop of over 700 emp_act's,
//Which is enough to trigger byond's recursion level protection

CAPABILITIES(/obj/item/storage/bag/circuits/basic)
	after_init(0, then(PROC_REF(stock_kit)))

/obj/item/storage/bag/circuits/basic/proc/stock_kit(datum/act/timer/A)
	emp_protection_flags |= EMP_PROTECT_SELF
	new /obj/item/storage/bag/circuits/mini/arithmetic(src)
	new /obj/item/storage/bag/circuits/mini/trig(src)
	new /obj/item/storage/bag/circuits/mini/input(src)
	new /obj/item/storage/bag/circuits/mini/output(src)
	new /obj/item/storage/bag/circuits/mini/memory(src)
	new /obj/item/storage/bag/circuits/mini/logic(src)
	new /obj/item/storage/bag/circuits/mini/time(src)
	new /obj/item/storage/bag/circuits/mini/reagents(src)
	new /obj/item/storage/bag/circuits/mini/transfer(src)
	new /obj/item/storage/bag/circuits/mini/converter(src)
	new /obj/item/storage/bag/circuits/mini/power(src)
	new /obj/item/electronic_assembly(src)
	new /obj/item/assembly/electronic_assembly(src)
	new /obj/item/assembly/electronic_assembly(src)
	new /obj/item/multitool(src)
	new /obj/item/tool/screwdriver(src)
	new /obj/item/tool/crowbar(src)
	new /obj/item/integrated_electronics/wirer(src)
	new /obj/item/integrated_electronics/debugger(src)
	new /obj/item/integrated_electronics/detailer(src)
	make_exact_fit()

CAPABILITIES(/obj/item/storage/bag/circuits/all)
	after_init(0, then(PROC_REF(stock_kit)))

/obj/item/storage/bag/circuits/all/proc/stock_kit(datum/act/timer/A)
	new /obj/item/storage/bag/circuits/mini/arithmetic/all(src)
	new /obj/item/storage/bag/circuits/mini/trig/all(src)
	new /obj/item/storage/bag/circuits/mini/input/all(src)
	new /obj/item/storage/bag/circuits/mini/output/all(src)
	new /obj/item/storage/bag/circuits/mini/memory/all(src)
	new /obj/item/storage/bag/circuits/mini/logic/all(src)
	new /obj/item/storage/bag/circuits/mini/smart/all(src)
	new /obj/item/storage/bag/circuits/mini/manipulation/all(src)
	new /obj/item/storage/bag/circuits/mini/time/all(src)
	new /obj/item/storage/bag/circuits/mini/reagents/all(src)
	new /obj/item/storage/bag/circuits/mini/transfer/all(src)
	new /obj/item/storage/bag/circuits/mini/converter/all(src)
	new /obj/item/storage/bag/circuits/mini/power/all(src)

	new /obj/item/electronic_assembly(src)
	new /obj/item/electronic_assembly/medium(src)
	new /obj/item/electronic_assembly/large(src)
	new /obj/item/electronic_assembly/drone(src)
	new /obj/item/integrated_electronics/wirer(src)
	new /obj/item/integrated_electronics/debugger(src)
	new /obj/item/integrated_electronics/detailer(src)
	new /obj/item/tool/crowbar(src)
	make_exact_fit()

/obj/item/storage/bag/circuits/mini
	name = "circuit box"
	desc = "Used to partition categories of circuits, for a neater workspace."
	w_class = ITEMSIZE_SMALL
	display_contents_with_number = 1
	var/spawn_flags_to_use = IC_SPAWN_DEFAULT
	/// The circuit types this box stocks, four of each spawnable one (a shared constant list).
	var/list/circuit_kinds

CAPABILITIES(/obj/item/storage/bag/circuits/mini)
	configure(storage(accepts = list(/obj/item/integrated_circuit)))
	after_init(0, then(PROC_REF(fill_circuits)))

/obj/item/storage/bag/circuits/mini/proc/fill_circuits(datum/act/timer/A)
	for(var/kind in circuit_kinds)
		for(var/obj/item/integrated_circuit/IC in GLOB.all_integrated_circuits)
			if(!istype(IC, kind))
				continue
			if(IC.spawn_flags & spawn_flags_to_use)
				for(var/i = 1 to 4)
					new IC.type(src)
	make_exact_fit()

/obj/item/storage/bag/circuits/mini/arithmetic
	circuit_kinds = list(/obj/item/integrated_circuit/arithmetic)
	name = "arithmetic circuit box"
	desc = "Warning: Contains math."
	icon_state = "box_arithmetic"

/obj/item/storage/bag/circuits/mini/arithmetic/all // Don't believe this will ever be needed.
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/trig
	circuit_kinds = list(/obj/item/integrated_circuit/trig)
	name = "trig circuit box"
	desc = "Danger: Contains more math."
	icon_state = "box_trig"

/obj/item/storage/bag/circuits/mini/trig/all // Ditto
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/input
	circuit_kinds = list(/obj/item/integrated_circuit/input)
	name = "input circuit box"
	desc = "Tell these circuits everything you know."
	icon_state = "box_input"

/obj/item/storage/bag/circuits/mini/input/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/output
	circuit_kinds = list(/obj/item/integrated_circuit/output)
	name = "output circuit box"
	desc = "Circuits to interface with the world beyond itself."
	icon_state = "box_output"

/obj/item/storage/bag/circuits/mini/output/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/memory
	circuit_kinds = list(/obj/item/integrated_circuit/memory)
	name = "memory circuit box"
	desc = "Machines can be quite forgetful without these."
	icon_state = "box_memory"

/obj/item/storage/bag/circuits/mini/memory/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/logic
	circuit_kinds = list(/obj/item/integrated_circuit/logic)
	name = "logic circuit box"
	desc = "May or may not be Turing complete."
	icon_state = "box_logic"

/obj/item/storage/bag/circuits/mini/logic/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/time
	circuit_kinds = list(/obj/item/integrated_circuit/time)
	name = "time circuit box"
	desc = "No time machine parts, sadly."
	icon_state = "box_time"

/obj/item/storage/bag/circuits/mini/time/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/reagents
	circuit_kinds = list(/obj/item/integrated_circuit/reagent)
	name = "reagent circuit box"
	desc = "Unlike most electronics, these circuits are supposed to come in contact with liquids."
	icon_state = "box_reagents"

/obj/item/storage/bag/circuits/mini/reagents/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/transfer
	circuit_kinds = list(/obj/item/integrated_circuit/transfer)
	name = "transfer circuit box"
	desc = "Useful for moving data representing something arbitrary to another arbitrary virtual place."
	icon_state = "box_transfer"

/obj/item/storage/bag/circuits/mini/transfer/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/converter
	circuit_kinds = list(/obj/item/integrated_circuit/converter)
	name = "converter circuit box"
	desc = "Transform one piece of data to another type of data with these."
	icon_state = "box_converter"

/obj/item/storage/bag/circuits/mini/converter/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH


/obj/item/storage/bag/circuits/mini/smart
	circuit_kinds = list(/obj/item/integrated_circuit/smart)
	name = "smart box"
	desc = "Sentience not included."
	icon_state = "box_ai"

/obj/item/storage/bag/circuits/mini/smart/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH


/obj/item/storage/bag/circuits/mini/manipulation
	circuit_kinds = list(/obj/item/integrated_circuit/manipulation)
	name = "manipulation box"
	desc = "Make your machines actually useful with these."
	icon_state = "box_manipulation"

/obj/item/storage/bag/circuits/mini/manipulation/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH



/obj/item/storage/bag/circuits/mini/power
	circuit_kinds = list(/obj/item/integrated_circuit/passive/power, /obj/item/integrated_circuit/power)
	name = "power circuit box"
	desc = "Electronics generally require electricity."
	icon_state = "box_power"

/obj/item/storage/bag/circuits/mini/power/all
	spawn_flags_to_use = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH


/// The selected_io this refers to (a relation view: null once that is deleted).
/obj/item/multitool/proc/selected_io() as /datum/integrated_io
	return selected_io

#define CIRCUIT_MEMORY_ACCESS_DENIED "circuit memory access denied"
#define CIRCUIT_MEMORY_UNSUPPORTED_ACTOR "circuit memory unsupported actor"

/// Nonspatial state for a debugger or constant-chip type/value question chain.
/datum/circuit_memory_review
	var/mob/actor
	var/obj/item/source_item
	var/obj/item/original_held
	var/held_expected = FALSE
	var/original_client_ckey
	var/constant_chip = FALSE
	var/type_name

CAPABILITIES(/datum/circuit_memory_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(source_item), /obj/item)
	ref_one(nameof(original_held), /obj/item)

/datum/prompt/choice/circuit_memory_type
	timeout = 0

/datum/prompt/choice/circuit_memory_type/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/circuit_memory_review/review = owner
	return review.prompt_refusal()

/datum/prompt/text/circuit_memory_text
	timeout = 0

/datum/prompt/text/circuit_memory_text/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/circuit_memory_review/review = owner
	return review.prompt_refusal()

/datum/prompt/number/circuit_memory_number
	timeout = 0

/datum/prompt/number/circuit_memory_number/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/circuit_memory_number/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/circuit_memory_review/review = owner
	return review.prompt_refusal()

/datum/circuit_memory_review/proc/retire()
	spent(src)

/datum/circuit_memory_review/proc/user_value()
	return original_client_ckey ? GLOB.directory[original_client_ckey] : actor

/datum/circuit_memory_review/proc/why_not()
	if(QDELETED(actor) || QDELETED(source_item))
		return "gone"
	if(constant_chip ? !istype(source_item, /obj/item/integrated_circuit/memory/constant) : !istype(source_item, /obj/item/integrated_electronics/debugger))
		return "gone"
	if(held_expected && QDELETED(original_held))
		return "gone"
	if(original_client_ckey && !user_value())
		return "gone"

/// The read-only branches of CanUseTopic; its access-denied message is delivered after refusal.
/datum/circuit_memory_review/proc/prompt_refusal()
	. = why_not()
	if(.)
		return
	var/mob/user = user_value()
	if(!ismob(user))
		return CIRCUIT_MEMORY_UNSUPPORTED_ACTOR
	if(!user.CanUseObjTopic(source_item))
		return CIRCUIT_MEMORY_ACCESS_DENIED
	if(source_item.tgui_status(user, GLOB.tgui_physical_state) != STATUS_INTERACTIVE)
		return "can't use it"

/datum/circuit_memory_review/proc/start(mob/user, obj/item/source_item, obj/item/held, constant_chip)
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		retire()
		return
	rel_set(src, nameof(actor), user)
	rel_set(src, nameof(src.source_item), source_item)
	held_expected = !isnull(held)
	rel_set(src, nameof(original_held), held)
	src.constant_chip = constant_chip
	if(why_not())
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(start_step))
	if(!result.ok)
		stack_trace("[type] start_step: [result.error]")
		retire()

/datum/circuit_memory_review/proc/start_step()
	open_request(src, /datum/prompt/choice/circuit_memory_type, PROC_REF(type_entered), answerer = actor, question = "Please choose a type to use.", title = "[source_item] type setting", choices = list("string", "number", "ref", "null"))

/datum/circuit_memory_review/proc/run_step(step, datum/act/request/A)
	var/obj/item/refreshed_item = source_item
	var/refresh = !why_not() && (A.answer || (A.request.outcome == REQ_CANCELLED && !isnull(A.request.value)))
	if(!A.answer || why_not())
		if(!why_not() && A.request.outcome == REQ_CANCELLED && !isnull(A.request.value))
			if(A.request.last_error == CIRCUIT_MEMORY_ACCESS_DENIED)
				var/mob/user = actor
				to_chat(user, span_danger("[icon2html(source_item, user.client)]Access Denied!"))
			else if(A.request.last_error == CIRCUIT_MEMORY_UNSUPPORTED_ACTOR)
				stack_trace("Circuit memory configuration requires a mob for CanUseObjTopic; original client argument [original_client_ckey] cannot use the topic.")
		retire()
		if(refresh && !QDELETED(refreshed_item))
			SStgui.update_uis(refreshed_item)
		return
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("Circuit memory step [step]: [result.error]")
		retire()
	if(refresh && !QDELETED(refreshed_item))
		SStgui.update_uis(refreshed_item)

/datum/circuit_memory_review/proc/type_entered(datum/act/request/A)
	run_step(PROC_REF(type_step), A)

/datum/circuit_memory_review/proc/type_step(datum/act/request/A)
	type_name = A.answer.value
	if(istype(source_item, /obj/item/integrated_circuit/memory/constant))
		var/obj/item/integrated_circuit/memory/constant/chip = source_item
		chip.memory_type_selected(src)
	else if(istype(source_item, /obj/item/integrated_electronics/debugger))
		var/obj/item/integrated_electronics/debugger/debugger = source_item
		debugger.memory_type_selected(src)

/datum/circuit_memory_review/proc/open_value()
	if(type_name == "string")
		open_request(src, /datum/prompt/text/circuit_memory_text, PROC_REF(value_entered), answerer = actor, question = "Now type in a string.", title = "[source_item] string writing", max_len = constant_chip ? MAX_NAME_LEN : MAX_MESSAGE_LEN, name_text = constant_chip, encode = FALSE, multiline = FALSE)
	else
		open_request(src, /datum/prompt/number/circuit_memory_number, PROC_REF(value_entered), answerer = actor, question = "Now type in a number.", title = "[source_item] number writing", default = 0, min_value = constant_chip ? 0 : -INFINITY, max_value = INFINITY, step = constant_chip ? 1 : null)

/datum/circuit_memory_review/proc/value_entered(datum/act/request/A)
	run_step(PROC_REF(value_step), A)

/datum/circuit_memory_review/proc/value_step(datum/act/request/A)
	if(istype(source_item, /obj/item/integrated_circuit/memory/constant))
		var/obj/item/integrated_circuit/memory/constant/chip = source_item
		chip.memory_value_selected(src, A.answer.value)
	else if(istype(source_item, /obj/item/integrated_electronics/debugger))
		var/obj/item/integrated_electronics/debugger/debugger = source_item
		debugger.memory_value_selected(src, A.answer.value)
	retire()

#undef CIRCUIT_MEMORY_ACCESS_DENIED
#undef CIRCUIT_MEMORY_UNSUPPORTED_ACTOR
