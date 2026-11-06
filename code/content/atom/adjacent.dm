// The content half of code/host/adjacent.dm: what names content, so the layer the engine calls cannot hold it.

// This is necessary for storage items not on your person.
/obj/item/Adjacent(atom/neighbor, recurse = 1)
	if(neighbor == loc) return 1
	if(istype(loc,/obj/item))
		if(recurse > 0)
			return loc.Adjacent(neighbor,recurse - 1)
		return 0
	return ..()
/*
	Special case: This allows you to reach a door when it is visally on top of,
	but technically behind, a fire door

	You could try to rewrite this to be faster, but I'm not sure anything would be.
	This can be safely removed if border firedoors are ever moved to be on top of doors
	so they can be interacted with without opening the door.
*/
/obj/machinery/door/Adjacent(atom/neighbor)
	var/obj/machinery/door/firedoor/border_only/BOD = locate_within(loc, /obj/machinery/door/firedoor/border_only)
	if(BOD)
		BOD.set_throwpass(1)// allow click to pass
		. = ..()
		BOD.set_throwpass(0)
		return .
	return ..()

/*
	This checks if you there is uninterrupted airspace between that turf and this one.
	This is defined as any dense ON_BORDER object, or any dense object without throwpass.
	The border_only flag allows you to not objects (for source and destination squares)
*/
/turf/ClickCross(target_dir, border_only, target_atom = null)
	for(var/obj/O in turf_contents_of_type(src, /obj))
		if( !O.density || O == target_atom || atom_rules_of(O).throwpass) continue // throwpass is used for anything you can click through

		if( O.flags&ON_BORDER) // windows have throwpass but are on border, check them first
			if( O.dir & target_dir || O.dir&(O.dir-1) ) // full tile windows are just diagonals mechanically
				var/obj/structure/window/W = target_atom
				if(istype(W))
					if(!W.is_fulltile())	//exception for breaking full tile windows on top of single pane windows
						return 0
				else
					return 0

		else if( !border_only ) // dense, not on border, cannot pass over
			return 0
	return 1
