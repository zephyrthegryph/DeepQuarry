REGISTRY_MEMBERSHIP(/obj/structure/janitorialcart, REGISTRY_JANITORIAL_CARTS)

/obj/structure/janitorialcart
	name = "janitorial cart"
	desc = "The ultimate in janitorial carts! Has space for water, mops, signs, trash bags, and more!"
	icon = 'icons/obj/janitor.dmi'
	icon_state = "cart"
	anchored = FALSE
	density = TRUE
	flags = OPENCONTAINER
	//copypaste sorry
	var/amount_per_transfer_from_this = 5 //shit I dunno, adding this so syringes stop runtime erroring. --NeoFite
	var/obj/item/storage/bag/trash/mybag	= null
	var/obj/item/mop/mymop = null
	var/obj/item/reagent_containers/spray/myspray = null
	var/obj/item/lightreplacer/myreplacer = null
	var/obj/structure/mopbucket/mybucket = null
	var/has_items = FALSE
	var/dismantled = TRUE
	var/signs = 0	//maximum capacity hardcoded below
	var/list/tgui_icons

	var/static/list/equippable_item_whitelist

CAPABILITIES(/obj/structure/janitorialcart)
	owns_one(nameof(mybag), /obj/item/storage/bag/trash)
	owns_one(nameof(mymop), /obj/item/mop)
	owns_one(nameof(myreplacer), /obj/item/lightreplacer)
	owns_one(nameof(myspray), /obj/item/reagent_containers/spray)
	climb()
	owns_one(nameof(mybucket), /obj/structure/mopbucket)
	interface("JanitorCart")
	op("bag", ui_act("bag"), then(PROC_REF(ui_act_bag)))
	op("mop", ui_act("mop"), then(PROC_REF(ui_act_mop)))
	op("spray", ui_act("spray"), then(PROC_REF(ui_act_spray)))
	op("replacer", ui_act("replacer"), then(PROC_REF(ui_act_replacer)))
	op("sign", ui_act("sign"), then(PROC_REF(ui_act_sign)))
	op("bucket", ui_act("bucket"), then(PROC_REF(ui_act_bucket)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(janicart_blast))))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Use item"), then(PROC_REF(interaction_alt)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("drag", item(/atom/movable), gesture(GESTURE_DRAG), label("Mount bucket"), then(PROC_REF(interaction_drag)))

/obj/structure/janitorialcart/proc/equip_janicart_item(mob/user, obj/item/I)
	if(!equippable_item_whitelist)
		equippable_item_whitelist = typecacheof(list(
			/obj/item/storage/bag/trash,
			/obj/item/mop,
			/obj/item/mop/advanced,
			/obj/item/reagent_containers/spray,
			/obj/item/lightreplacer,
			/obj/item/clothing/suit/caution,
		))

	if(!is_type_in_typecache(I, equippable_item_whitelist))
		user.balloon_alert(user, "there's no room in [src] for [I].")
		return FALSE

	if(!user.canUnEquip(I))
		user.balloon_alert(user, "[I] is stuck to your hand.")
		return FALSE

	if(istype(I, /obj/item/storage/bag/trash))
		if(mybag)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(mybag), I)
		setTguiIcon("mybag", mybag)

	else if(istype(I, /obj/item/mop) || istype(I, /obj/item/mop/advanced))
		if(mymop)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(mymop), I)
		setTguiIcon("mymop", mymop)

	else if(istype(I, /obj/item/reagent_containers/spray))
		if(myspray)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(myspray), I)
		setTguiIcon("myspray", myspray)

	else if(istype(I, /obj/item/lightreplacer))
		if(myreplacer)
			user.balloon_alert(user, "[src] already has \an [I].")
			return FALSE
		rel_set(src, nameof(myreplacer), I)
		setTguiIcon("myreplacer", myreplacer)

	else if(istype(I, /obj/item/clothing/suit/caution))
		if(signs < 4)
			signs++
			setTguiIcon("signs", I)
		else
			user.balloon_alert(user, "[src] can't hold any more signs.")
			return FALSE
	else
		// This may look like duplicate code, but it's important that we don't call unEquip *and* warn the user if
		// something horrible goes wrong. (this else is never supposed to happen)
		user.balloon_alert(user, "there's no room in [src] for [I].")
		return FALSE

	user.drop_from_inventory(I, src)
	update_icon()
	user.balloon_alert(user, "you put [I] into [src].")
	return TRUE

/obj/structure/janitorialcart/proc/setTguiIcon(key, atom/A)
	if(!istype(A) || !key)
		return

	var/icon/F = getFlatIcon(A, defdir = SOUTH, no_anim = TRUE)
	LAZYSET(tgui_icons, "[key]", "'data:image/png;base64,[icon2base64(F)]'")
	SStgui.update_uis(src)

/obj/structure/janitorialcart/proc/nullTguiIcon(key)
	if(!key)
		return
	LAZYREMOVE(tgui_icons, key)
	SStgui.update_uis(src)

/obj/structure/janitorialcart/proc/clearTguiIcons()
	LAZYCLEARLIST(tgui_icons)
	SStgui.update_uis(src)


// drops its cached tgui icons.
/obj/structure/janitorialcart/on_destroy(force)
	clearTguiIcons()
	..()

/obj/structure/janitorialcart/examine(mob/user)
	. = ..(user)
	if(istype(mybucket))
		var/contains = mybucket.reagents.total_volume
		. += "[icon2html(src, user.client)] The bucket contains [contains] unit\s of liquid!"
	else
		. += "[icon2html(src, user.client)] There is no bucket mounted on it!"

/obj/structure/janitorialcart/proc/interaction_drag(datum/act/op/A)
	var/mob/living/user = A.actor
	var/atom/movable/O = A.held
	if (istype(O, /obj/structure/mopbucket) && !mybucket)
		move_into(src, nameof(src.mybucket), O, user)
		setTguiIcon("mybucket", mybucket)
		user.balloon_alert(user, "you mount the [O] on the janicart.")
		update_icon()
		return OP_PASS
	return OP_DECLINE

/obj/structure/janitorialcart/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/mop) || istype(I, /obj/item/reagent_containers/glass/rag) || istype(I, /obj/item/soap))
		if (mybucket)
			if(I.reagents.total_volume < I.reagents.maximum_volume)
				if(mybucket.reagents.total_volume < 1)
					user.balloon_alert(user, "[mybucket] is empty!")
				else
					mybucket.reagents.trans_to_obj(I, 5)	//
					user.balloon_alert(user, "you wet [I] in [mybucket].")
					play_sfx(src, SFX_EFFECTS_SLOSH)
			else
				user.balloon_alert(user, "[I] can't absorb anymore liquid!")
		else
			to_chat(user, span_notice("There is no bucket mounted here to dip [I] into!"))
		return TRUE

	else if (istype(I, /obj/item/reagent_containers/glass/bucket) && mybucket)
		I.afterattack(mybucket, user, 1, null, I_HELP) // wetting it in the bucket is a peaceful use
		update_icon()
		return TRUE

	else if(istype(I, /obj/item/reagent_containers/spray) && !myspray)
		equip_janicart_item(user, I)
		return TRUE

	else if(istype(I, /obj/item/lightreplacer) && !myreplacer)
		equip_janicart_item(user, I)
		return TRUE

	else if(istype(I, /obj/item/storage/bag/trash) && !mybag)
		equip_janicart_item(user, I)
		return TRUE

	else if(istype(I, /obj/item/clothing/suit/caution))
		equip_janicart_item(user, I)
		return TRUE

	else if(mybag)
		mybag.attackby(I, user)
		//This prevents dumb stuff like splashing the cart with the contents of a container, after putting said container into trash
	return TRUE

/obj/structure/janitorialcart/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(has_items)
		return OP_OK
	task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_timed_done), done_args = list(user))
	return OP_OK

/obj/structure/janitorialcart/proc/wrench_act_timed_done(mob/user)
	dismantle(user)

//New Altclick functionality!
//Altclick the cart with a mop to stow the mop away
//Altclick the cart with a reagent container to pour things into the bucket without putting the bottle in trash
/obj/structure/janitorialcart/proc/interaction_alt(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.incapacitated() || !Adjacent(user))	return TRUE
	var/obj/I = user.get_active_hand()
	if(istype(I, /obj/item/mop))
		equip_janicart_item(user, I)
	else if(istype(I, /obj/item/reagent_containers) && mybucket)
		var/obj/item/reagent_containers/C = I
		C.afterattack(mybucket, user, 1, null, I_HELP) // refilling from the bucket is a peaceful use
		update_icon()
	return TRUE

/obj/structure/janitorialcart/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/structure/janitorialcart/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["mybag"] = mybag ? capitalize(mybag.name) : null
	data["mybucket"] = mybucket ? capitalize(mybucket.name) : null
	data["mymop"] = mymop ? capitalize(mymop.name) : null
	data["myspray"] = myspray ? capitalize(myspray.name) : null
	data["myreplacer"] = myreplacer ? capitalize(myreplacer.name) : null
	data["signs"] = signs ? "[signs] sign\s" : null

	data["icons"] = (tgui_icons || list())
	return data

/obj/structure/janitorialcart/proc/ui_act_bag(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	if(mybag)
		user.put_in_hands(mybag)
		user.balloon_alert(user, "you take [mybag] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::mybag))
		nullTguiIcon("mybag")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(user, I)
	update_icon()
	return TRUE

/obj/structure/janitorialcart/proc/ui_act_mop(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	if(mymop)
		user.put_in_hands(mymop)
		user.balloon_alert(user, "you take [mymop] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::mymop))
		nullTguiIcon("mymop")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(user, I)
	update_icon()
	return TRUE

/obj/structure/janitorialcart/proc/ui_act_spray(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	if(myspray)
		user.put_in_hands(myspray)
		user.balloon_alert(user, "you take [myspray] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::myspray))
		nullTguiIcon("myspray")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(user, I)
	update_icon()
	return TRUE

/obj/structure/janitorialcart/proc/ui_act_replacer(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	if(myreplacer)
		user.put_in_hands(myreplacer)
		user.balloon_alert(user, "you take [myreplacer] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::myreplacer))
		nullTguiIcon("myreplacer")
	else if(is_type_in_typecache(I, equippable_item_whitelist))
		equip_janicart_item(user, I)
	update_icon()
	return TRUE

/obj/structure/janitorialcart/proc/ui_act_sign(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	if(istype(I, /obj/item/clothing/suit/caution) && signs < 4)
		equip_janicart_item(user, I)
	else if(signs)
		var/obj/item/clothing/suit/caution/sign = locate_within(src, /obj/item/clothing/suit/caution)
		if(sign)
			user.put_in_hands(sign)
			user.balloon_alert(user, "you take  [sign] from [src].")
			signs--
			if(!signs)
				nullTguiIcon("signs")
	else
		user.balloon_alert(user, "[src] doesn't have any signs left.")
	update_icon()
	return TRUE

/obj/structure/janitorialcart/proc/ui_act_bucket(datum/act/op/A)
	var/mob/user = A.actor
	if(mybucket)
		mybucket.forceMove(get_turf(user))
		user.balloon_alert(user, "you unmount [mybucket] from [src].")
		own_take(src, nameof(/obj/structure/janitorialcart::mybucket))
		nullTguiIcon("mybucket")
	else
		to_chat(user, span_notice("((Drag and drop a mop bucket onto [src] to equip it.))"))
		return FALSE
	update_icon()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/structure/janitorialcart, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/janitorialcart/appearance_overlays()
	. = list()

	if(mybucket)
		. += "cart_bucket"
		if(mybucket.reagents.total_volume >= 1)
			. += "water_cart"
	if(mybag)
		. += "cart_garbage"
	if(mymop)
		. += "cart_mop"
	if(myspray)
		. += "cart_spray"
	if(myreplacer)
		. += "cart_replacer"
	if(signs)
		. += "cart_sign[signs]"

//This is called if the cart is caught in an explosion, or destroyed by weapon fire
/obj/structure/janitorialcart/proc/spill(chance = 100)
	var/turf/dropspot = get_turf(src)
	if (mymop && prob(chance))
		mymop.forceMove(dropspot)
		mymop.tumble(2)
		own_take(src, nameof(mymop))

	if (myspray && prob(chance))
		myspray.forceMove(dropspot)
		myspray.tumble(3)
		own_take(src, nameof(myspray))

	if (myreplacer && prob(chance))
		myreplacer.forceMove(dropspot)
		myreplacer.tumble(3)
		own_take(src, nameof(myreplacer))

	if (mybucket && prob(chance*0.5))//bucket is heavier, harder to knock off
		mybucket.forceMove(dropspot)
		mybucket.tumble(1)
		own_take(src, nameof(mybucket))

	if (signs)
		for (var/obj/item/clothing/suit/caution/Sign in contents_of(src))
			if (prob(min((chance*2),100)))
				signs--
				Sign.forceMove(dropspot)
				Sign.tumble(3)
				if (signs < 0)//safety for something that shouldn't happen
					signs = 0
					update_icon()
					return

	if (mybag && prob(min((chance*2),100)))//Bag is flimsy
		mybag.forceMove(dropspot)
		mybag.tumble(1)
		mybag.spill()//trashbag spills its contents too
		own_take(src, nameof(mybag))

	update_icon()
	clearTguiIcons()

/obj/structure/janitorialcart/proc/dismantle(mob/user = null)
	if (!dismantled)
		if (has_items)
			spill()

		new /obj/item/stack/material/steel(src.loc, 10)
		new /obj/item/stack/material/plastic(src.loc, 10)
		dismantled = 1
		replace_with(src, /obj/item/stack/rods, 20)

/// A blast spills the gear before it lands; the hit goes on.
/obj/structure/janitorialcart/proc/janicart_blast(datum/act/hit/explosion/A)
	spill(100 / A.packet.severity)
	return HOOK_DECLINE
