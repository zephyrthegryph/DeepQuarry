//--------------------------------------------
// Omni device port types
//--------------------------------------------
#define ATM_NONE	0
#define ATM_INPUT	1
#define ATM_OUTPUT	2

#define ATM_O2		3
#define ATM_N2		4
#define ATM_CO2		5
#define ATM_P		6	//Phoron
#define ATM_N2O		7
#define ATM_METHANE 8
#define ATM_LASTGAS	8 // Keep updated to match the latest gas in list above

//--------------------------------------------
// Omni port datum
//
// Used by omni devices to manage connections
//  to other atmospheric objects.
//--------------------------------------------
/datum/omni_port
	var/obj/machinery/atmospherics/omni/master
	var/dir
	var/update = 1
	var/mode = 0
	var/concentration = 0
	var/con_lock = 0
	var/transfer_moles = 0
	var/datum/gas_mixture/air
	var/obj/machinery/atmospherics/node
	var/datum/pipe_network/network

/datum/omni_port/New(obj/machinery/atmospherics/omni/M, direction = NORTH)
	..()
	dir = direction
	if(istype(M))
		master = M
	air = new
	air.set_volume(200)

/datum/omni_port/proc/connect()
	if(node)
		return
	master.atmos_init()
	if(node)
		node.atmos_init()
	master.rust_register_pipe_topology()

/datum/omni_port/proc/disconnect()
	if(node)
		var/port_index = master.ports.Find(src)
		var/neighbor_index = node.rust_pipe_port_index_for_neighbor(master)
		if(port_index && neighbor_index && length(master.rust_pipe_port_ids) && length(node.rust_pipe_port_ids))
			SSair.rust_queue_pipe_operation(RUST_PIPE_OP_DISCONNECT, master.rust_pipe_port_ids[port_index], node.rust_pipe_port_ids[neighbor_index])
			SSair.rust_commit_pending_pipenets()
		node.disconnect(master)
		master.disconnect(node)


//--------------------------------------------
// Need to find somewhere else for these
//--------------------------------------------

//returns a text string based on the direction flag input
// if capitalize is true, it will return the string capitalized
// otherwise it will return the direction string in lower case
/proc/dir_name(dir, capitalize = 0)
	var/string = null
	switch(dir)
		if(NORTH)
			string = "North"
		if(SOUTH)
			string = "South"
		if(EAST)
			string = "East"
		if(WEST)
			string = "West"

	if(!capitalize && string)
		string = lowertext(string)

	return string

//returns a direction flag based on the string passed to it
// case insensitive
/proc/dir_flag(dir)
	dir = lowertext(dir)
	switch(dir)
		if("north")
			return NORTH
		if("south")
			return SOUTH
		if("east")
			return EAST
		if("west")
			return WEST
		else
			return 0

/proc/mode_to_gasid(mode)
	switch(mode)
		if(ATM_O2)
			return GAS_O2
		if(ATM_N2)
			return GAS_N2
		if(ATM_CO2)
			return GAS_CO2
		if(ATM_P)
			return GAS_PHORON
		if(ATM_N2O)
			return GAS_N2O
		if(ATM_METHANE)
			return GAS_CH4
		else
			return null
