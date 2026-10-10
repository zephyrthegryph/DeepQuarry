GLOBAL_LIST_INIT(biblenames, list(
	"Bible", "Koran", "Scrapbook",
	"Pagan", "White Bible", "Holy Light",
	"Athiest", "Tome", "The King in Yellow",
	"Ithaqua", "Scientology", "the bible melts",
	"Necronomicon", "Orthodox", "Torah"))
//If you get these two lists not matching in size, there will be runtimes and I will hurt you in ways you couldn't even begin to imagine
// if your bible has no custom itemstate, use one of the existing ones
GLOBAL_LIST_INIT(biblestates, list(
	"bible", "koran", "scrapbook",
	"shadows", "white", "holylight",
	"athiest", "tome", "kingyellow",
	"ithaqua", "scientology", "melted",
	"necronomicon", "orthodoxy", "torah"))
GLOBAL_LIST_INIT(bibleitemstates, list(
	"bible", "koran", "scrapbook",
	"syringe_kit", "syringe_kit", "syringe_kit",
	"syringe_kit", "syringe_kit", "kingyellow",
	"ithaqua", "scientology", "melted",
	"necronomicon", "bible", "clipboard"))

/obj/item/storage/bible
	name = "bible"
	desc = "Apply to head repeatedly."
	icon_state ="bible"
	item_state = "bible"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_books.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_books.dmi'
		)
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	var/deity_name = "Christ"
	use_sound = SFX_BUREAUCRACY_BOOKOPEN
	drop_sound = SFX_BUREAUCRACY_BOOKCLOSE
	special_handling = TRUE

// An item put into a bible turns a page first, and then goes on to the storage's insertion (passes()). Used in hand by a chaplain: the first use chooses the
// skin from a ring around the user, a later one invokes the religion.
CAPABILITIES(/obj/item/storage/bible)
	op("page_turn", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), label("Put in"), then(PROC_REF(turn_page)), passes())
	op("skin", in_hand(), when(req_bool(PROC_REF(chaplain_unconfigured))), label("Choose a bible"),
		asks(/datum/prompt/choice, fields = list("question" = "Choose a bible", "choices" = computed(PROC_REF(skin_choices)), "radial" = TRUE, "radius" = 40)),
		then(PROC_REF(skin_chosen)))
	op("invoke", in_hand(), priority(above("skin")), when(req_bool(PROC_REF(chaplain_configured))), label("Invoke"), then(PROC_REF(invoke_religion)))

/// What a bible asks of its user: 0 not a chaplain with a religion, 1 a religion whose bible is not yet chosen, 2 one that has it. The role and the religion
/// are the mind's own state, read when the op resolves.
/proc/chaplain_state(mob/living/carbon/human/user)
	READS_FROM()
	if(!istype(user) || user.mind?.assigned_role != JOB_CHAPLAIN || isnull(user.mind.my_religion))
		return 0
	return user.mind.my_religion.configured ? 2 : 1

/// A chaplain with a religion whose bible is not yet chosen.
/obj/item/storage/bible/proc/chaplain_unconfigured(datum/act/op/A)
	return chaplain_state(A.actor) == 1

/// A chaplain whose religion has its bible.
/obj/item/storage/bible/proc/chaplain_configured(datum/act/op/A)
	return chaplain_state(A.actor) == 2

/// The ring's choices: each bible's name with its picture.
/obj/item/storage/bible/proc/skin_choices(datum/act/op/A)
	var/list/skins = list()
	for(var/i in 1 to GLOB.biblestates.len)
		var/image/bible_image = image(icon = 'icons/obj/storage.dmi', icon_state = GLOB.biblestates[i])
		skins += list("[GLOB.biblenames[i]]" = bible_image)
	return skins

/// The chosen skin becomes the religion's bible, and the bible takes it.
/obj/item/storage/bible/proc/skin_chosen(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	var/datum/prompt/choice/picked = A.answer
	var/bible_index = GLOB.biblenames.Find(picked.value)
	if(!bible_index)
		return OP_FAILED
	user.mind.my_religion.bible_icon_state = GLOB.biblestates[bible_index]
	user.mind.my_religion.bible_item_state = GLOB.bibleitemstates[bible_index]
	user.mind.my_religion.configured = TRUE
	apply_religion(user)
	return OP_OK

/// A later use: the bible takes the religion's name and look.
/obj/item/storage/bible/proc/invoke_religion(datum/act/op/A)
	apply_religion(A.actor)
	return OP_OK

/obj/item/storage/bible/proc/apply_religion(mob/living/carbon/human/user)
	deity_name = user.mind.my_religion.deity
	name = user.mind.my_religion.bible_name
	icon_state = user.mind.my_religion.bible_icon_state
	item_state = user.mind.my_religion.bible_item_state
	to_chat(user, span_notice("You invoke [user.mind.my_religion.deity] and prepare a copy of [src]."))

/obj/item/storage/bible/booze
	name = "bible"
	desc = "To be applied to the head repeatedly."
	icon_state ="bible"

/obj/item/storage/bible/booze/Initialize(mapload)
	. = ..()
	starts_with = list(
		/obj/item/reagent_containers/food/drinks/bottle/small/beer,
		/obj/item/reagent_containers/food/drinks/bottle/small/beer,
		/obj/item/spacecash/c100,
		/obj/item/spacecash/c100,
		/obj/item/spacecash/c100
	)

/obj/item/storage/bible/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity) return
	if(user.mind && (user.mind.assigned_role == JOB_CHAPLAIN))
		if(A.reagents && A.reagents.has_reagent(REAGENT_ID_WATER)) //blesses all the water in the holder
			to_chat(user, span_notice("You bless [A]."))
			var/water2holy = A.reagents.get_reagent_amount(REAGENT_ID_WATER)
			A.reagents.del_reagent(REAGENT_ID_WATER)
			A.reagents.add_reagent(REAGENT_ID_HOLYWATER,water2holy)

/// The page-turn sound.
/obj/item/storage/bible/proc/turn_page(datum/act/op/A)
	if (src.use_sound)
		playsound(src, src.use_sound, 50, 1, -5)
	return OP_OK
