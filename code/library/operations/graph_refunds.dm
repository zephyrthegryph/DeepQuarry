/// Puts back what a ledger entry names, where the holder is: stack units and consumed items as new things, the contents of a slot out of it.
/datum/graph_refund(list/ledger, mob/actor)
	var/datum/E = src
	var/turf/where = get_turf(E)
	if(!where)
		return
	for(var/list/row in ledger?["rows"])
		switch(row["res"])
			if(RES_STACK)
				if(row["moved"] || !ispath(row["type"], /obj/item))
					continue
				var/item_path = row["type"]
				var/obj/item/refunded = ispath(item_path, /obj/item/stack) ? new item_path(where, row["n"]) : new item_path(where)
				if(!isnull(row["material"]) && ("material" in refunded.vars))
					refunded.vars["material"] = row["material"] // ALLOW(api): the refund restores the material the ledger recorded
				if(!ispath(item_path, /obj/item/stack) && ("amount" in refunded.vars))
					refunded.vars["amount"] = row["n"] // ALLOW(api): the refund restores the units the ledger recorded
			if(RES_ITEM)
				if(ispath(row["type"], /atom/movable))
					var/refunded_type = row["type"]
					new refunded_type(where)
			if("slot")
				var/atom/holder = E
				if(!istype(holder))
					continue
				for(var/atom/movable/thing as anything in holder.slot_contents(row["slot"]))
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
					if(holder.slot_remove(thing, where, actor))
						TEST_REC_TRANSFER(thing, holder, where, row["slot"])
#else
					holder.slot_remove(thing, where, actor)
#endif


/atom/movable/op_consume(mob/actor)
	return consume(src, actor)
