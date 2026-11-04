//set_pin_data()
//This sets Data of a pin, You can use IC_INPUT to target the input side, second argument to select which input, thied Argument is the data to push
//get_pin_data()
//Same as above but fetches data instead, This literally does all the work for you.
//do:work()
//This happens when the wire is pulsed.
//pins start at 1 not 0, lists always start at 1 in this.

//Activators (pulsing stuff) seems to work similiarly im gonna add some conditional pulsing to mine as an example
//All of the behaviour of these procs is defined in core/helpers.dm

//push_data() makes sure any connections actually update

/obj/item/integrated_circuit/logic/conditional
	name = "conditional operator"
	desc = "This operator checks a boolean and based on its state either outputs the first or second inputs value, this is also known as the ?: operator."
	icon_state = "equal"
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	inputs = list("Condition"= IC_PINTYPE_BOOLEAN,"True","False")
	outputs = list("Result" = IC_PINTYPE_ANY)
	activators = list("compare" = IC_PINTYPE_PULSE_IN, "on true" = IC_PINTYPE_PULSE_OUT, "on false" = IC_PINTYPE_PULSE_OUT)

/obj/item/integrated_circuit/logic/conditional/do_work()
	pull_data()
	if(get_pin_data(IC_INPUT, 1))
		set_pin_data(IC_OUTPUT, 1,get_pin_data(IC_INPUT, 2))
		activate_pin(2)
	else
		set_pin_data(IC_OUTPUT, 1,get_pin_data(IC_INPUT, 3))
		activate_pin(3)
	return push_data()

/obj/item/integrated_circuit/logic/boollatch
	name = "boolean latch"
	desc = "A boolean latch is essentially a toggle swapping between true and false on being pulsed."
	icon_state = "equal"
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	inputs = list()
	outputs = list("State" = IC_PINTYPE_BOOLEAN)
	activators = list("Toggle" = IC_PINTYPE_PULSE_IN, "on true" = IC_PINTYPE_PULSE_OUT, "on false" = IC_PINTYPE_PULSE_OUT)

/obj/item/integrated_circuit/logic/boollatch/do_work()
	if(get_pin_data(IC_OUTPUT, 1))
		set_pin_data(IC_OUTPUT, 1,FALSE)
		activate_pin(3)
	else
		set_pin_data(IC_OUTPUT, 1,TRUE)
		activate_pin(2)
	return push_data()

/obj/item/electronic_assembly/drone
	w_class = ITEMSIZE_NORMAL
	max_components = IC_COMPONENTS_BASE * 6
	max_complexity = IC_COMPLEXITY_BASE * 6
