/////////////////
//SMOKING PIPES//
/////////////////
/obj/item/clothing/mask/smokable/pipe
	name = "smoking pipe"
	desc = "A pipe, for smoking. Made of fine, stained cherry wood."
	icon_state = "pipe"
	item_state = "pipe"
	smoketime = 0
	chem_volume = 50
	matchmes = span_notice("USER lights their NAME with their FLAME.")
	lightermes = span_notice("USER manages to light their NAME with FLAME.")
	zippomes = span_notice(span_rose("With much care, USER lights their NAME with their FLAME."))
	weldermes = span_notice("USER recklessly lights NAME with FLAME.")
	ignitermes = span_notice("USER fiddles with FLAME, and manages to light their NAME with the power of science.")
	is_pipe = 1

CAPABILITIES(/obj/item/clothing/mask/smokable/pipe)
	configure(atom_rules(description_fluff = "ClassiCo Accessories and Haberdashers, originating out of Mars, \
	claim to produce products 'for the modern gentlefolk'. Most of their items are high-end \
	and expensive, but they pledge to back their prices up with quality, and usually do."))
	op("put_out", in_hand(), stance(I_HELP, I_DISARM, I_GRAB), then(PROC_REF(put_out)))
	op("empty_out", in_hand(), stance(I_HURT), priority(OP_PRIORITY_ATTACK), then(PROC_REF(empty_out)))
	name_prefix("empty")

/// Using a lit pipe in the hand puts it out. The clothing's own self-use still follows, as the old ..() did.
/obj/item/clothing/mask/smokable/pipe/proc/put_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% puts out %T%."))
		quench()
	return OP_DECLINE

/// In the hurt stance the lit pipe is emptied on the floor.
/obj/item/clothing/mask/smokable/pipe/proc/empty_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% empties the lit [src] on the floor!."))
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
		die(1)
	return OP_DECLINE

/// A pipe takes what any smokable takes, and is packed with a dried plant (an active energy sword does nothing to it).
/obj/item/clothing/mask/smokable/pipe/item_applied(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/melee/energy/sword))
		return OP_OK

	..()

	if (istype(W, /obj/item/reagent_containers/food/snacks))
		var/obj/item/reagent_containers/food/snacks/grown/G = W
		if (!G.dry)
			to_chat(user, span_notice("[G] must be dried before you stuff it into [src]."))
			return OP_OK
		if (smoketime)
			to_chat(user, span_notice("[src] is already packed."))
			return OP_OK
		set_max_smoketime(1000)
		set_smoketime(1000)
		if(G.reagents)
			G.reagents.trans_to_obj(src, G.reagents.total_volume)
		name = "[G.name]-packed [initial(name)]"
		consume(G, user)

	else if(istype(W, /obj/item/flame/lighter))
		var/obj/item/flame/lighter/L = W
		if(L.lit)
			light(span_notice("[user] manages to light their [name] with [W]."), user)

	else if(istype(W, /obj/item/flame/match))
		var/obj/item/flame/match/M = W
		if(M.lit)
			light(span_notice("[user] lights their [name] with their [W]."), user)

	else if(istype(W, /obj/item/assembly/igniter))
		light(span_notice("[user] fiddles with [W], and manages to light their [name] with the power of science."), user)

	return OP_OK

/obj/item/clothing/mask/smokable/pipe/cobpipe
	name = "corn cob pipe"
	desc = "A nicotine delivery system popularized by folksy backwoodsmen, kept popular in the modern age and beyond by space hipsters."
	icon_state = "cobpipe"
	item_state = "cobpipe"
	chem_volume = 35

/obj/item/clothing/mask/smokable/pipe/bonepipe
	name = "Europan bone pipe"
	desc = "A smoking pipe made out of the bones of the Europan bone whale."
	icon_state = "bonepipe"
	item_state = "bonepipe"
	chem_volume = 30

CAPABILITIES(/obj/item/clothing/mask/smokable/pipe/bonepipe)
	configure(atom_rules(description_fluff = "While most commonly associated with bone charms, bones from various sea creatures on Europa are used in a \
	variety of goods, such as this smoking pipe. While smoking in submarines is often an uncommon occurrence, due to a lack of \
	available air or space, these pipes are a common sight in the many stations of Europa. Higher-quality pipes typically have \
	scenes etched into their bones, and can tell the story of their owner's time on Europa."))
