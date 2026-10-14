/obj/item/integrated_circuit/memory
	name = "memory chip"
	desc = "This tiny chip can store one piece of data."
	icon_state = "memory1"
	complexity = 1
	inputs = list()
	outputs = list()
	activators = list("set" = IC_PINTYPE_PULSE_IN, "on set" = IC_PINTYPE_PULSE_OUT)
	category_text = "Memory"
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 1
	var/number_of_pins = 1

/obj/item/integrated_circuit/memory/Initialize(mapload)
	for(var/i = 1 to number_of_pins)
		inputs["input [i]"] = IC_PINTYPE_ANY // This is just a string since pins don't get built until ..() is called.
		outputs["output [i]"] = IC_PINTYPE_ANY
	. = ..()
	complexity = number_of_pins

/obj/item/integrated_circuit/memory/examine(mob/user)
	. = ..()
	var/i
	for(i = 1, i <= outputs.len, i++)
		var/datum/integrated_io/O = outputs[i]
		var/data = "nothing"
		if(ic_is_ref(O.data))
			var/datum/d = O.data_as_type(/datum)
			if(d)
				data = "[d]"
		else if(!isnull(O.data))
			data = O.data
		. += "\The [src] has [data] saved to address [i]."

/obj/item/integrated_circuit/memory/do_work()
	for(var/i = 1 to inputs.len)
		var/datum/integrated_io/I = inputs[i]
		var/datum/integrated_io/O = outputs[i]
		O.data = I.data
		O.push_data()
	activate_pin(2)

/obj/item/integrated_circuit/memory/tiny
	name = "small memory circuit"
	desc = "This circuit can store two pieces of data."
	icon_state = "memory2"
	power_draw_per_use = 2
	number_of_pins = 2

/obj/item/integrated_circuit/memory/medium
	name = "medium memory circuit"
	desc = "This circuit can store four pieces of data."
	icon_state = "memory4"
	power_draw_per_use = 2
	number_of_pins = 4

/obj/item/integrated_circuit/memory/large
	name = "large memory circuit"
	desc = "This big circuit can hold eight pieces of data."
	icon_state = "memory8"
	power_draw_per_use = 4
	number_of_pins = 8

/obj/item/integrated_circuit/memory/huge
	name = "large memory stick"
	desc = "This stick of memory can hold up up to sixteen pieces of data."
	icon_state = "memory16"
	w_class = ITEMSIZE_NORMAL
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 8
	number_of_pins = 16

/obj/item/integrated_circuit/memory/constant
	name = "constant chip"
	desc = "This tiny chip can store one piece of data, which cannot be overwritten without disassembly."
	complexity = 1
	inputs = list()
	outputs = list("output pin" = IC_PINTYPE_ANY)
	activators = list("push data" = IC_PINTYPE_PULSE_IN)
	var/accepting_refs = 0
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH

/obj/item/integrated_circuit/memory/constant/do_work()
	var/datum/integrated_io/O = outputs[1]
	O.push_data()

CAPABILITIES(/obj/item/integrated_circuit/memory/constant)
	op("constant_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/integrated_circuit/memory/constant/proc/interaction_self(datum/act/op/A)
	var/datum/circuit_memory_review/review = new
	review.start(A.actor, src, A.held, TRUE)
	return OP_OK

/obj/item/integrated_circuit/memory/constant/proc/memory_type_selected(datum/circuit_memory_review/review)
	var/mob/user = review.user_value()
	var/datum/integrated_io/O = outputs[1]
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
			O.data = null
			to_chat(user, span_notice("You set \the [src]'s memory to absolutely nothing."))
	review.retire()

/obj/item/integrated_circuit/memory/constant/proc/stop_memory_ref_scan()
	accepting_refs = 0

/obj/item/integrated_circuit/memory/constant/proc/memory_value_selected(datum/circuit_memory_review/review, new_data)
	var/mob/user = review.user_value()
	var/datum/integrated_io/O = outputs[1]
	stop_memory_ref_scan()
	switch(review.type_name)
		if("string")
			new_data = sanitizeSafe(new_data, MAX_NAME_LEN, 0, 0)
			if(istext(new_data))
				O.data = new_data
				to_chat(user, span_notice("You set \the [src]'s memory to [O.display_data(O.data)]."))
		if("number")
			if(isnum(new_data))
				O.data = new_data
				to_chat(user, span_notice("You set \the [src]'s memory to [O.display_data(O.data)]."))

/obj/item/integrated_circuit/memory/constant/afterattack(atom/target, mob/living/user, proximity)
	if(accepting_refs && proximity)
		var/datum/integrated_io/O = outputs[1]
		O.data = ic_ref(target)
		act_message(user, src, others = span_notice("%U% slides %T% over \the [target]."))
		to_chat(user, span_notice("You set \the [src]'s memory to a reference to [O.display_data(O.data)]. The ref scanner is \
		now off."))
		accepting_refs = 0
