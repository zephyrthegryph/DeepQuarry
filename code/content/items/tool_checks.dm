//Quick type checks for some tools
GLOBAL_LIST_INIT(common_tools, list(
/obj/item/stack/cable_coil,
/obj/item/tool/wrench,
/obj/item/weldingtool,
/obj/item/tool/screwdriver,
/obj/item/tool/wirecutters,
/obj/item/multitool,
/obj/item/tool/crowbar,
/obj/item/tool/transforming))

/proc/is_hot(obj/item/W as obj)
	switch(W.type)
		if(/obj/item/weldingtool)
			var/obj/item/weldingtool/WT = W
			if(WT.isOn())
				return 3800
			else
				return 0
		if(/obj/item/tool/transforming)
			var/obj/item/tool/transforming/TT = W
			if(LAZYACCESS(TT.possible_tooltypes, TT.current_tooltype) == TOOL_WELDER)
				return 3800
			else
				return 0
		if(/obj/item/flame/lighter)
			if(W:lit)
				return 1500
			else
				return 0
		if(/obj/item/flame/match)
			if(W:lit)
				return 1000
			else
				return 0
		if(/obj/item/clothing/mask/smokable/cigarette)
			if(W:lit)
				return 1000
			else
				return 0
		if(/obj/item/pickaxe/plasmacutter)
			return 3800
		if(/obj/item/melee/energy)
			return 3500
		else
			return 0

//Whether or not the given item counts as sharp in terms of dealing damage
/proc/is_sharp(obj/item/O)
	READS_FROM(O)
	if(!isitem(O))
		return FALSE
	if(combat_of(O).sharp)
		return TRUE
	if(combat_of(O).edge)
		return TRUE
	return FALSE

//Whether or not the given item counts as cutting with an edge in terms of removing limbs
/proc/has_edge(obj/item/O)
	READS_FROM(O)
	if(!isitem(O))
		return FALSE
	if(combat_of(O).edge)
		return TRUE
	return FALSE

//Returns 1 if the given item is capable of popping things like balloons, inflatable barriers, or cutting police tape.
/proc/can_puncture(obj/item/W as obj)		// For the record, WHAT THE HELL IS THIS METHOD OF DOING IT?
	READS_FROM(W)
	if(!W)
		return FALSE
	if(combat_of(W).sharp)
		return TRUE
	return ( \
		W.has_tool_quality(TOOL_SCREWDRIVER)		     				              || \
		istype(W, /obj/item/pen)                           || \
		W.has_tool_quality(TOOL_WELDER)					  || \
		istype(W, /obj/item/flame/lighter/zippo)			  || \
		istype(W, /obj/item/flame/match)            		  || \
		istype(W, /obj/item/clothing/mask/smokable/cigarette) 		      || \
		istype(W, /obj/item/shovel) \
	)
