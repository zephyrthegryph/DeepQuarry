/*
 *	A stock record: one product of a vending machine or smartfridge (roadmap C9,
 *	code/datums/containment/stock.dm).
 *
 *	`amount` copies are latent: they exist only as this record, all sharing one
 *	state (pristine `item_path` with `variant`, or `latent_blob`). A real item is
 *	made from them when it is taken out. Items put in whose state no latent copy
 *	shares stay real, in the holder's stock slot and in `instances`.
 */
/datum/stored_item
	var/item_name = "name"	//Name of the item(s) displayed
	var/item_desc
	var/item_path = null
	/// Latent copies.
	var/amount = 0
	/// Real items with state of their own, held in the stock slot. Lazy.
	var/list/instances
	var/stored				//The thing holding it is
	var/variant = null // variant key for consolidated parent types
	/// The state blob latent copies share, or null for a pristine spawn.
	var/list/latent_blob
	/// state_hash() of latent_blob.
	var/latent_hash
	/// Whether inserted items may collapse into the latent count at all.
	var/collapsible = TRUE
	/// Whether the first collapsible item inserted into an empty record sets the
	/// latent state (smartfridges). Otherwise latent copies are always pristine
	/// and only items identical to a pristine one collapse (vending).
	var/adopt_state = TRUE

/datum/stored_item/New(stored, path, name = null, amount = 0)
	src.item_path = path

	if(!name)
		var/atom/tmp = path
		src.item_name = initial(tmp.name)
	else
		src.item_name = name

	src.amount  = amount
	src.stored = stored

	..()

/datum/stored_item/Destroy()
	for(var/atom/movable/product as anything in instances)
		if(product.loc == stored)
			qdel(product)
	instances = null
	stored = null
	. = ..()

/datum/stored_item/proc/get_amount()
	return amount + LAZYLEN(instances)

/// Makes one latent copy real at `loc`. Does not touch `amount`.
/datum/stored_item/proc/materialize(loc)
	if(latent_blob)
		return state_materialize(latent_blob, loc)
	return spawn_with_variant(item_path, loc, variant)

/// Makes every latent copy real at `loc`. Only destruction does this.
/datum/stored_item/proc/materialize_all(loc)
	for(var/i in 1 to amount)
		materialize(loc)
	amount = 0

/datum/stored_item/proc/get_product(product_location)
	if(!get_amount() || !product_location)
		return
	var/atom/movable/product
	if(LAZYLEN(instances))
		product = instances[instances.len]	// Remove the last added product
		LAZYREMOVE(instances, product)
		product.forceMove(product_location)
	else
		amount--
		product = materialize(product_location)
	if(istype(product, /obj/item))
		var/obj/item/our_item = product
		our_item.persist_storable = FALSE
	return product

/// The hash `blob` is merged by.
/datum/stored_item/proc/hash_of(list/blob)
	return state_hash(blob)

/// Folds `product` into the latent count if its state matches. TRUE if it did
/// (the product is then deleted).
/datum/stored_item/proc/try_collapse(atom/movable/product)
	if(!collapsible)
		return FALSE
	var/list/blob = dq_stock_blob(product)
	if(!blob)
		return FALSE
	var/hash = hash_of(blob)
	if(amount <= 0 && adopt_state)
		latent_blob = blob
		latent_hash = hash
	else if(latent_blob)
		if(hash != latent_hash)
			return FALSE
	else if(hash != dq_stock_pristine_hash(item_path, variant))
		return FALSE
	amount += collapse_units(product)
	qdel(product)
	return TRUE

/// Latent units one collapsed product adds.
/datum/stored_item/proc/collapse_units(atom/movable/product)
	return 1

/datum/stored_item/proc/add_product(atom/movable/product)
	if(product.type != item_path)
		return FALSE
	if(try_collapse(product))
		return TRUE
	if(!product.move_into(stored, CONTAINER_SLOT_STOCK))
		product.forceMove(stored)
	LAZYADD(instances, product)
	return TRUE

/// Restock: adds latent copies. Nothing is created.
/datum/stored_item/proc/refill_products(refill_amount)
	amount += max(0, refill_amount)

/// A var of one of this record's items, without keeping anything made.
/datum/stored_item/proc/sample_var(var_name)
	if(LAZYLEN(instances))
		var/atom/movable/real = instances[1]
		return real.vars[var_name]
	if(amount <= 0)
		return null
	var/atom/movable/sample = materialize(null)
	if(!sample)
		return null
	. = sample.vars[var_name]
	qdel(sample)

/// The holder calls this when a thing leaves its stock slot some other way.
/datum/stored_item/proc/forget(atom/movable/thing)
	LAZYREMOVE(instances, thing)

// ---- Stacks: the latent count is in sheets ----

/datum/stored_item/stack/collapse_units(atom/movable/product)
	var/obj/item/stack/S = product
	return S.get_amount()

/// Stacks merge regardless of their amount.
/datum/stored_item/stack/hash_of(list/blob)
	var/list/copy = blob.Copy()
	var/list/vars = copy[STATE_KEY_VARS]
	if(islist(vars))
		vars = vars.Copy()
		vars -= "amount"
		copy[STATE_KEY_VARS] = vars
	return state_hash(copy)

/datum/stored_item/stack/get_amount()
	. = amount
	for(var/obj/item/stack/S as anything in instances)
		. += S.get_amount()

/datum/stored_item/stack/materialize(loc, count = 1)
	var/obj/item/stack/S
	if(latent_blob)
		S = state_materialize(latent_blob, loc)
	else
		S = new item_path(loc, count)
	if(istype(S) && S.get_amount() != count)
		S.set_amount(count)
	return S

/datum/stored_item/stack/materialize_all(loc)
	var/obj/item/stack/proto = item_path
	var/max_amount = initial(proto.max_amount) || 50
	while(amount > 0)
		var/n = min(amount, max_amount)
		amount -= n
		materialize(loc, n)

/datum/stored_item/stack/get_product(product_location, count)
	if(!product_location || count < 1)
		return null
	var/obj/item/stack/proto = item_path
	var/max_amount = initial(proto.max_amount) || 50
	count = min(count, max_amount) // We won't vend more than one full stack per call
	if(amount > 0)
		var/n = min(count, amount)
		amount -= n
		return materialize(product_location, n)
	if(!LAZYLEN(instances))
		return null

	var/obj/item/stack/S = instances[1]
	// Case 1: Draw the full amount from the first instance
	if(count < S.get_amount())
		S = S.split(count)
	// Case 2: Amount at least one stack, or have to accumulate
	else
		count -= S.get_amount()
		LAZYREMOVE(instances, S)
		for(var/obj/item/stack/T as anything in instances?.Copy())
			if(count <= 0)
				break
			if(T.get_amount() <= count)
				LAZYREMOVE(instances, T)
			count -= T.transfer_to(S, count)

	S.forceMove(product_location)
	return S
