/obj/item/mail
	name = "mail"
	desc = "An officially postmarked, tamper-evident parcel regulated by CentCom and made of high-quality materials."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "mail_small"
	item_flags = NOBLUDGEON
	w_class = ITEMSIZE_SMALL
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	mouse_drag_pointer = MOUSE_ACTIVE_POINTER
	/// Destination tagging for the mail sorter.
	var/sortTag = 0
	/// Who this mail is for and who can open it (relation view).
	var/datum/mind/addressee
	/// How many goodies this mail contains.
	var/goodie_count = 1
	// Goodies which can be given to anyone.
	/// Weight sum will be 1000
	var/static/list/generic_goodies = list(
		/obj/item/spacecash/c50 = 75,
		/obj/item/reagent_containers/food/drinks/cans/cola = 75,
		/obj/item/reagent_containers/food/snacks/chips = 75,
		/obj/item/reagent_containers/food/drinks/coffee = 75,
		/obj/item/reagent_containers/food/drinks/tea = 75,
		/obj/item/reagent_containers/food/drinks/glass2/coffeemug/nt = 50,
		/obj/item/spacecash/c100 = 40,
		/obj/item/spacecash/c200 = 25,
		/obj/item/spacecash/c500 = 15,
		/obj/item/spacecash/c1000 = 5,
		/obj/item/reagent_containers/food/drinks/bluespace_coffee = 5
	)
	// Overlays (pure fluff)
	/// Does the letter have the postmark overlay?
	var/postmarked = TRUE
	/// Does the letter have a stamp overlay?
	var/stamped = TRUE
	/// List of all stamp overlays on the letter.
	var/list/stamps = list() // ALLOW(instance_list): d: mail items are stamped on creation
	/// Maximum number of stamps on the letter.
	var/stamp_max = 1
	/// Physical offset of stamps on the object. X direction.
	var/stamp_offset_x = 0
	/// Physical offset of stamps on the object. Y direction.
	var/stamp_offset_y = 2
	/// If the mail is actively being opened right now
	/// If the mail has been scanned with a mail scanner
	var/scanned
	/// Does it have a colored envelope?
	var/colored_envelope

	///Var for attack_self chainn
	var/special_handling = FALSE
	resistance_flags = FLAMMABLE

/obj/item/mail/container_resist(mob/living/M)
	if(istype(M, /mob/living/voice)) return
	if(isdisposalpacket(loc))
		M.forceMove(loc)
	else
		M.forceMove(get_turf(src))
	to_chat(M, span_warning("You climb out of \the [src]."))

/obj/item/mail/envelope
	name = "envelope"
	icon_state = "mail_large"
	goodie_count = 2
	stamp_max = 2
	stamp_offset_y = 5

/obj/item/mail/Initialize(mapload)
	. = ..()

	// Icons
	// Add some random stamps.
	if(stamped == TRUE)
		var/stamp_count = rand(1, stamp_max)
		for(var/i = 1, i <= stamp_count, i++)
			stamps += list("stamp_[rand(2, 8)]")

/obj/item/mail/blank
	desc = "A blank envelope."
	stamped = FALSE
	postmarked = FALSE
	var/set_recipient = FALSE
	var/set_content = FALSE
	var/sealed = FALSE
	var/list/mail_recipients
	special_handling = TRUE

TRACKED(/obj/item/mail/blank, sealed)
TRACKED(/obj/item/mail/blank, set_recipient)

CAPABILITIES(/obj/item/mail/blank)
	// a blank envelope is sealed or opened in hand, not unwrapped
	without("unwrap")
	op("seal", in_hand(), label("Seal or open"), then(PROC_REF(interaction_seal)))
	// a pen addresses a sealed envelope (to a player picked from the directory)
	op("address", item(/obj/item/pen), label("Address"), priority(OP_PRIORITY_PART + 1),
		asks(/datum/prompt/choice, fields = list("title" = "Recipients", "question" = "Choose recipient", "choices" = computed(PROC_REF(recipient_choices)), "timeout" = 0), when = PROC_REF(addressable)),
		then(PROC_REF(recipient_chosen)))
	// the old attackby: anything goes inside an open, empty envelope (a tagger tags it first, then goes on here)
	op("put_in", item(/obj/item), label("Put inside"), then(PROC_REF(interaction_blank_item)))
	// alt-click takes the contents back out of an open envelope
	op("take_out", hand(), ungated(), gesture(GESTURE_ALT), label("Take out"), then(PROC_REF(interaction_alt)))

/// A sealed envelope with nobody on it yet can be addressed.
/obj/item/mail/blank/proc/addressable(datum/act/op/A)
	return sealed && !set_recipient

/// Old attackby: the item goes inside an open, empty envelope.
/obj/item/mail/blank/proc/interaction_blank_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!set_content && !sealed)
		task_start(/datum/task/timed/blank_attackby, user, user, receiver = src, W = W)
	return OP_PASS

/datum/task/timed/blank_attackby
	duration = 1.5 SECONDS
	complete_proc = /obj/item/mail/blank/proc/attackby_timed_done
	cancel_proc = /obj/item/mail/blank/proc/attackby_timed_failed
	var/obj/item/W

/obj/item/mail/blank/proc/attackby_timed_done(datum/task/timed/blank_attackby/task)
	var/obj/item/W = task.W
	var/mob/user = task.actor
	user.drop_item()
	W.forceMove(src)
	balloon_alert(user, "placed \the [W] into \the [src]")
	set_content = TRUE
	return

/obj/item/mail/blank/proc/attackby_timed_failed(datum/task/timed/blank_attackby/task)
	set_content = FALSE

/// The players who can be sent mail (not antagonists, and listed in the directory).
/obj/item/mail/blank/proc/recipient_choices(datum/act/op/A)
	. = list()
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!SSantag.player_is_antag(player.mind) && player.mind.show_in_directory)
			. += player

/// The pen's choice: the envelope is addressed to them (an unsealed or addressed one lets the pen go inside instead).
/obj/item/mail/blank/proc/recipient_chosen(datum/act/op/A)
	if(!addressable(A))
		return OP_DECLINE
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	var/mob/living/recipient_mob = R?.value
	if(istype(recipient_mob) && recipient_mob?.mind)
		initialize_for_recipient(recipient_mob.mind, preset_goodies = TRUE)
		set_set_recipient(TRUE)
	return OP_PASS

/// Old click_alt.
/obj/item/mail/blank/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(sealed)
		return OP_OK

	for(var/obj/stuff as anything in contents)
		if(isitem(stuff))
			user.put_in_hands(stuff)
		else
			stuff.forceMove(drop_location())
	set_content = FALSE
	return OP_OK

/obj/item/mail/blank/inspected_by(mob/user)
	..()
	if(!sealed)
		open_request(src, /datum/prompt/text, PROC_REF(sender_named), answerer = user, title = "Name", question = "Write name", default = user.name, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)

/obj/item/mail/blank/proc/sender_named(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value && !sealed)
		desc = "A signed envelope, from [A.answer.value]."

/// Old attack_self: seal an open envelope, or open a sealed one.
/obj/item/mail/blank/proc/interaction_seal(datum/act/op/A)
	var/mob/user = A.actor
	if(!sealed)
		task_timed(user, 1.5 SECONDS, target = user, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(), on_fail = PROC_REF(attack_self_timed_failed), fail_args = list())
		return OP_OK
	unwrap(user)
	return OP_OK

/obj/item/mail/blank/proc/attack_self_timed_done()
	set_sealed(TRUE)
	return

/obj/item/mail/blank/proc/attack_self_timed_failed()
	set_sealed(FALSE)

DECLARE_APPEARANCE_PROC(/obj/item/mail, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/mail/appearance_overlays()
	. = list()
	. += ..()
	if(colored_envelope)
		var/image/envelope = image(icon, icon_state)
		envelope.color = colored_envelope
		. += envelope
	var/bonus_stamp_offset = 0
	for(var/stamp in stamps)
		var/image/stamp_image = image(
			icon_state = stamp,
			pixel_x = stamp_offset_x,
			pixel_y = stamp_offset_y + bonus_stamp_offset
		)
		stamp_image.appearance_flags |= RESET_COLOR
		. += stamp_image
		bonus_stamp_offset -= 5

	if(postmarked == TRUE)
		var/image/postmark_image = image(
			icon = icon,
			icon_state = "postmark",
			pixel_x = stamp_offset_x + rand(-4, 0),
			pixel_y = stamp_offset_y + rand(bonus_stamp_offset + 3, 1)
		)
		postmark_image.appearance_flags |= RESET_COLOR
		. += postmark_image

CAPABILITIES(/obj/item/mail)
	// the old attack_self: open the letter
	op("unwrap", in_hand(), label("Unwrap"), then(PROC_REF(interaction_unwrap)))
	// a destination tagger labels it
	op("tag", item(/obj/item/destTagger), label("Tag"), priority(OP_PRIORITY_PART + 2), then(PROC_REF(interaction_tag)))

/// Old attackby: destination tagging.
/obj/item/mail/proc/interaction_tag(datum/act/op/A)
	tag_with(A.actor, A.held)
	return OP_PASS

/obj/item/mail/proc/tag_with(mob/user, obj/item/destTagger/O)
	if(O.currTag)
		if(src.sortTag != O.currTag)
			balloon_alert(user, "labeled for [O.currTag].")
			src.sortTag = O.currTag
			play_sfx(src, SFX_MACHINES_TWOBEEP)
		else
			balloon_alert(user, "already labeled for [O.currTag].")
	else
		balloon_alert(user, "destination not set!")


/// Old attack_self: open the letter.
/obj/item/mail/proc/interaction_unwrap(datum/act/op/A)
	unwrap(A.actor)
	return OP_OK

/obj/item/mail/proc/unwrap(mob/user)
	if(addressee)
		var/datum/mind/recipient = addressee
		if(recipient && recipient.current?.dna.unique_enzymes != user.dna.unique_enzymes)
			balloon_alert(user, "you can't open somebody's mail! That's <em>illegal</em>")
			return FALSE

	if(task_busy(src)) // opening claims the envelope
		balloon_alert(user, "already opening that!")
		return FALSE

	return !istext(task_timed(user, 1.5 SECONDS, target = user, receiver = src, on_done = PROC_REF(unwrap_timed_done), done_args = list(user), busy = src))

/// Opened: out come the contents (special handling keeps them in).
/obj/item/mail/proc/unwrap_timed_done(mob/user)
	if(special_handling)
		return
	after_unwrap(user)

/obj/item/mail/proc/after_unwrap(mob/user)
	user.temporarilyRemoveItemFromInventory(src, TRUE)
	for(var/obj/stuff as anything in contents)
		if(isitem(stuff))
			user.put_in_hands(stuff)
		else
			stuff.forceMove(drop_location())
	//Now here's the kicker
	if(has_trait(user, TRAIT_UNLUCKY) && prob(5)) //1 in 20 chance for your mail to be rigged with a glitter bomb
		to_chat(user, span_bolddanger("You open the mail and - OH SHIT IS THAT A BOMB!"))
		var/obj/item/grenade/confetti/confetti_nade = new /obj/item/grenade/confetti()
		confetti_nade.name = "Pipebomb"
		confetti_nade.desc = span_bolddanger("What the hell are you looking at it for?! RUN!!")
		confetti_nade.activate()
	play_sfx(loc, SFX_ITEMS_POSTER_RIPPED)
	consume(src, user)

/obj/item/mail/proc/initialize_for_recipient(datum/mind/recipient, preset_goodies = FALSE)
	var/current_title = recipient.role_alt_title ? recipient.role_alt_title : recipient.assigned_role
	name = "[initial(name)] for [recipient.name] ([current_title])"
	rel_set(src, nameof(addressee), recipient)

	var/datum/job/this_job = SSjob.get_job(recipient.assigned_role)

	var/list/goodies = generic_goodies
	if(this_job)
		colored_envelope = this_job.get_mail_color()
		if(!preset_goodies)
			var/list/job_goodies = this_job.get_mail_goodies(recipient.current, current_title)
			if(LAZYLEN(job_goodies))
				if(this_job.get_mail_goodies(recipient.current, current_title))
					goodies = job_goodies
				else
					goodies += job_goodies

	if(!preset_goodies)
		for(var/iterator in 1 to goodie_count)
			var/target_good = pickweight(goodies)
			var/atom/movable/target_atom = new target_good(src)
			log_game("[key_name(recipient)] received [target_atom.name] in the mail ([target_good])")

	update_icon()
	return TRUE

// Mail spawn for events
ADMIN_VERB(spawn_mail, R_SPAWN, "Spawn Mail", "Spawn mail for a specific player, with a specific item.", ADMIN_CATEGORY_FUN_EVENT_KIT, object as text)
	var/list/types = typesof(/atom)
	var/list/matches = new()
	for(var/path in types)
		if(findtext("[path]", object))
			matches += path

	if(matches.len==0)
		return
	if(matches.len==1)
		user.spawn_mail_type_chosen(matches[1])
		return
	if(!ismob(user.mob) || QDELETED(user.mob))
		return
	open_request(user, /datum/prompt/choice/admin_mail, TYPE_PROC_REF(/client, spawn_mail_type_picked), answerer = user.mob, title = "Spawn Atom in Mail", question = "Select an atom type", choices = matches)

/// The admin "Spawn Mail" questions: the type, the recipient, then where. Re-checked on each answer: still holds R_SPAWN.
/datum/prompt/choice/admin_mail
	rights = R_SPAWN
	timeout = 0
	/// The atom type to put in the envelope.
	var/chosen
	/// The recipient picked at the second step.
	var/mob/living/recipient
	var/recipient_expected = FALSE

CAPABILITIES(/datum/prompt/choice/admin_mail)
	ref_one(nameof(recipient), /mob/living)

/datum/prompt/choice/admin_mail/prepare(datum/act/A)
	. = ..()
	var/mob/living/captured = recipient
	rel_clear(src, nameof(recipient))
	rel_set(src, nameof(recipient), captured)

/datum/prompt/choice/admin_mail/recheck_extra()
	. = ..()
	if(.)
		return
	if(recipient_expected && QDELETED(recipient))
		return "gone"
	if(isdatum(value))
		var/datum/selected = value
		if(QDELETED(selected))
			return "gone"
	return null

/client/proc/spawn_mail_type_picked(datum/act/request/A)
	if(!A.answer)
		return
	return apply_spawn_mail_type_picked(A)

/client/proc/apply_spawn_mail_type_picked(datum/act/request/A)
	spawn_mail_type_chosen(A.answer.value)

/client/proc/spawn_mail_type_chosen(chosen)
	var/list/recipients = list()
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		recipients += player
	if(!ismob(mob) || QDELETED(mob))
		return
	open_request(src, /datum/prompt/choice/admin_mail, PROC_REF(spawn_mail_recipient_picked), answerer = mob, title = "Recipients", question = "Choose recipient", choices = recipients, chosen = chosen)

/client/proc/spawn_mail_recipient_picked(datum/act/request/A)
	if(!A.answer)
		return
	return apply_spawn_mail_recipient_picked(A)

/client/proc/apply_spawn_mail_recipient_picked(datum/act/request/A)
	var/datum/prompt/choice/admin_mail/ask = A.request
	if(!ismob(mob) || QDELETED(mob))
		return
	open_request(src, /datum/prompt/choice/admin_mail, PROC_REF(spawn_mail_finish), answerer = mob, title = "Spawn mail", question = "Spawn mail at location or in the shuttle?", choices = list("Location", "Shuttle"), buttons = TRUE, chosen = ask.chosen, recipient = A.answer.value, recipient_expected = !isnull(A.answer.value))

/client/proc/spawn_mail_finish(datum/act/request/A)
	if(!A.answer)
		return
	return apply_spawn_mail_finish(A)

/client/proc/apply_spawn_mail_finish(datum/act/request/A)
	var/datum/prompt/choice/admin_mail/ask = A.request
	var/mob/user_mob = mob
	var/mob/living/chosen_player = ask.recipient
	var/datum/mind/recipient_mind = chosen_player?.mind
	var/chosen = ask.chosen
	if(!recipient_mind || !user_mob)
		return
	if(A.answer.value == "Shuttle")
		var/obj/item/mail/new_mail = new
		new_mail.initialize_for_recipient(recipient_mind, TRUE)
		new chosen(new_mail)
		SSmail.admin_mail += new_mail
		log_and_message_admins("spawned [chosen] inside an envelope at the shuttle")
	else
		var/obj/item/mail/ground_mail = new /obj/item/mail(user_mob.loc)
		ground_mail.initialize_for_recipient(recipient_mind, TRUE)
		new chosen(ground_mail)
		log_and_message_admins("spawned [chosen] inside an envelope at ([user_mob.x],[user_mob.y],[user_mob.z])")

	feedback_add_details("admin_verb","SM")

// Mail Crate
/obj/structure/closet/crate/mail
	name = "mail crate"
	desc = "An official mail crate from CentCom"
	points_per_crate = 0
	closet_appearance = /datum/decl/closet_appearance/crate/nanotrasen

/obj/structure/closet/crate/mail/full/Initialize(mapload)
	. = ..()
	var/list/mail_recipients = list()
	for(var/mob/living/carbon/human/alive in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(alive.stat != DEAD && alive.client && alive.client.inactivity <= 10 MINUTES)
			mail_recipients += alive
	for(var/iterator in 1 to storage_capacity)
		var/obj/item/mail/new_mail
		if(prob(70))
			new_mail = new /obj/item/mail(src)
		else
			new_mail = new /obj/item/mail/envelope(src)
		var/mob/living/carbon/human/mail_to
		if(length(mail_recipients))
			mail_to = pick(mail_recipients)
		if(mail_to)
			new_mail.initialize_for_recipient(mail_to.mind)
			mail_recipients -= mail_to
		else
			new_mail.junk_mail()

// Mailbag
/obj/item/storage/bag/mail
	name = "mail bag"
	desc = "A bag for letters, envelopes and other postage."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "mailbag"
	slot_flags = SLOT_BELT | SLOT_POCKET
	w_class = ITEMSIZE_NORMAL
	storage_slots = 31
	max_storage_space = 50
	use_to_pickup = TRUE
	allow_quick_gather = TRUE


CAPABILITIES(/obj/item/storage/bag/mail)
	configure(storage(accepts = list(
		/obj/item/mail,
		/obj/item/smallDelivery,
		/obj/item/paper,
		/obj/item/stolenpackage,
		/obj/item/contraband,
		/obj/item/mail_scanner,
		/obj/item/pen), max_size = ITEMSIZE_NORMAL))

/obj/item/storage/bag/mail/borg
	name = "letter compartment"
	desc = "A compartment specifically made for small postage."

/obj/item/storage/bag/mail/borg/proc/upgrade()
	name += " of holding"
	storage_slots = 45
	max_storage_space = 75

// Mail Scanner
/obj/item/mail_scanner
	name = "mail scanner"
	desc = "Sponsored by the Intergalactic Mail Service, this device logs mail deliveries in exchance for financial compensation."
	force = 0
	throwforce = 0
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "mail_scanner"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	var/cargo_points = 5
	/// Relation view: the last scanned envelope (it stays wherever it is).
	var/obj/item/mail/saved

/obj/item/mail_scanner/examine(mob/user)
	. = ..()
	. += span_notice("Scan a letter to log it into the active database, then scan the person you wish to hand the letter to. Correctly scanning the recipient of the letter logged into the active database will add points to the supply budget.")

/obj/item/mail_scanner/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/mail_scanner/afterattack(atom/A, mob/user)
	if(istype(A, /obj/item/mail))
		var/obj/item/mail/saved_mail = A
		if(saved_mail.scanned)
			balloon_alert(user, "already scanned!")
			play_sfx(loc, SFX_ITEMS_MAIL_MAILDENIED)
			return
		balloon_alert(user, "added to database")
		play_sfx(loc, SFX_ITEMS_MAIL_MAILSCANNED)
		rel_set(src, nameof(saved), A)
		return
	if(isliving(A))
		if(!saved)
			balloon_alert(user, "no logged mail!")
			play_sfx(loc, SFX_ITEMS_MAIL_MAILDENIED)
			return

		var/datum/mind/recipient
		recipient = saved.addressee

		if(isnull(recipient) || isnull(recipient.current))
			return

		if(recipient.current.stat == DEAD)
			to_chat(user, span_warning("Consent Verification failed: You can't deliver mail to a corpse!"))
			play_sfx(loc, SFX_ITEMS_MAIL_MAILDENIED)
			return
		var/mob/living/carbon/human/scanned_human = A
		var/mob/living/carbon/human/intended = recipient.current
		if(!ishuman(scanned_human) || !ishuman(intended) || !scanned_human.dna || !intended.dna || scanned_human.dna.unique_enzymes != intended.dna.unique_enzymes)
			to_chat(user, span_warning("Identity Verification failed: Target is not authorized recipient of this envelope!"))
			play_sfx(loc, SFX_ITEMS_MAIL_MAILDENIED)
			return
		if(!recipient.current.client)
			to_chat(user, span_warning("Consent Verification failed: The scanner does not accept orders from SSD crewmemmbers!"))
			play_sfx(loc, SFX_ITEMS_MAIL_MAILDENIED)
			return

		saved.scanned = TRUE
		rel_clear(src, nameof(saved))

		cargo_points = rand(5, 10)
		to_chat(user, span_notice("Succesful delivery acknowledged! [cargo_points] points added to Supply."))
		play_sfx(loc, SFX_ITEMS_MAIL_MAILAPPROVED)
		SSsupply.adjust_budget(SSsupply.export_revenue(cargo_points), "Mail delivery proceeds")

// JUNK MAIL STUFF

/obj/item/mail/junkmail/Initialize(mapload)
	. = ..()
	junk_mail()

/obj/item/mail/proc/junk_mail()

	var/obj/junk = /obj/item/paper/fluff/junkmail_generic
	var/special_name = FALSE

	if(prob(25))
		special_name = TRUE
		junk = pick(list(
			/obj/item/paper/fluff/junkmail_redpill,
			/obj/effect/decal/cleanable/ash,
			/obj/item/paper/fluff/love_letter,
			/obj/item/reagent_containers/food/snacks/donkpocket/berry,
			/obj/item/reagent_containers/food/snacks/donkpocket/dankpocket,
			/obj/item/reagent_containers/food/snacks/donkpocket/gondola,
			/obj/item/reagent_containers/food/snacks/donkpocket/honk,
			/obj/item/reagent_containers/food/snacks/donkpocket/pizza,
			/obj/item/reagent_containers/food/snacks/donkpocket/spicy,
			/obj/item/reagent_containers/food/snacks/donkpocket/teriyaki,
			/obj/item/toy/figure,
			/obj/item/contraband/package,
			/obj/item/tool/screwdriver/sdriver,
			/obj/item/storage/briefcase/target_toy
		))

	var/list/junk_names = list(
		/obj/item/paper/fluff/junkmail_redpill = "[initial(name)] for those feeling tired working at Nanotrasen",
		/obj/effect/decal/cleanable/ash = "[initial(name)] with INCREDIBLY IMPORTANT ARTIFACT- DELIVER TO SCIENCE DIVISION. HANDLE WITH CARE.",
		/obj/item/paper/fluff/love_letter = "[initial(name)] for STUPID CARGO MAILMEN.",
		/obj/item/reagent_containers/food/snacks/donkpocket/berry = "[initial(name)] with NEW BERRY-POCKET.",
		/obj/item/reagent_containers/food/snacks/donkpocket/dankpocket = "[initial(name)] with NEW DANK-POCKET.",
		/obj/item/reagent_containers/food/snacks/donkpocket/gondola = "[initial(name)] with NEW GONDOLA-POCKET.",
		/obj/item/reagent_containers/food/snacks/donkpocket/honk = "[initial(name)] with NEW HONK-POCKET.",
		/obj/item/reagent_containers/food/snacks/donkpocket/pizza = "[initial(name)] with NEW PIZZA-POCKET.",
		/obj/item/reagent_containers/food/snacks/donkpocket/spicy = "[initial(name)] with NEW SPICY-POCKET.",
		/obj/item/reagent_containers/food/snacks/donkpocket/teriyaki = "[initial(name)] with NEW TERIYAKI-POCKET.",
		/obj/item/toy/figure = "[initial(name)] from DoN**K*oC",
		/obj/item/contraband/package = "[pick("oddly shaped", "strangely wrapped", "weird", "bulging")] [initial(name)]",
		/obj/item/tool/screwdriver/sdriver = "[initial(name)] for Proffesor Who",
		/obj/item/storage/briefcase/target_toy = "[initial(name)] for SIMPATHY, SUCCESS, MANHATTAN, BELIEFS"
	)

	name = special_name ? junk_names[junk] : "important [initial(name)]"

	junk = new junk(src)
	update_icon()
	return TRUE

CAPABILITIES(/obj/item/paper/fluff/junkmail_generic)
	rolls(nameof(info), PROC_REF(roll_info))

/// Rolled before init (rolls()): one of the junk letters.
/obj/item/paper/fluff/junkmail_generic/proc/roll_info(datum/roller/R)
	return R.weighted(list("Hello! I am executive at Nanotrasen Nigel Takall. Due to accounting error all of my salary is stored in an account unreachable. In order to withdraw I am required to utilize your account to make a deposit to confirm my reality situation. In exchange for a temporary deposit I will give you a payment 1000 credits. All I need is access to your account. Will you be assistant please?" = 5, "WE NEED YOUR BLOOD! WE ARE AN ANARCHO-COMMUNIST VAMPIRE COMMUNE. BLOOD ONLY LASTS 42 DAYS BEFORE IT GOES BAD! WE DO NOT HAVE NANOTRASEN STASIS! PLEASE, SEND BLOOD! THANK YOU! OR WE KILL YOU!" = 5, "Triple deposits are waiting for you at MaxBet Online when you register to play with us. You can qualify for a 200% Welcome Bonus at MaxBet Online when you sign up today. Once you are a player with MaxBet, you will also receive lucrative weekly and monthly promotions. You will be able to enjoy over 450 top-flight casino games at MaxBet." = 5, "Hello !, I'm the former HoS of your deerest station accused by the Nanotrasen of being a traitor . I was the best we had to offer but it seems that nanotramsen has turned their back on me. I need 2000 credits to pay for my bail and then we can restore order on space station 14!" = 5, "Hello, I noticed you riding in a 2555 Ripley and wondered if you'd be interested in selling. Low mileage mechs sell very well in our current market. Please call 223-334-3245 if you're interested" = 5, "Resign Now. I'm on you now. You are fucking with me now Let's see who you are. Watch your back , bitch. Call me.  Don't be afraid, you piece of shit.  Stand up.  If you don't call, you're just afraid. And later: I already know where you live, I'm on you.  You might as well call me. You will see me. I promise.  Bro." = 5, "Clown Planet Is Going To Become Awesome Possum Again! If This Wasn't Sent To A Clown, Disregard. If This Was Sent To A Mime, Blow It Out Your Ass, Space Frenchie! Anyway! We Make Big Progress On Clown Planet After Stupid Mimes BLOW IT ALL TO SAM HELL!!!!! Sorry I Am Mad.. Anyway Come And Visit, Honkles! We Thought You Were Dead Long Time :^()" = 5, "MONTHPEOPLE ARE REAL, THE NANOTRASEN DEEP STATE DOESN'T WANT YOU TO SEE THIS! I'VE SEEN THEM IN REAL LIFE, THEY HAVE HUGE EYEBALLS AND NO HEAD. THEY'RE SENTIENT CALENDARS. I'M NOT CRAZY. SEARCH THE CALENDAR INCIDENT ON NTNET. USE A PROXY! #BIGTRUTHS #WAKEYWAKEYSPACEMEN #21STOFSEPTEMBER" = 5, "hello :wave::wave: nanotrasens! fuck :point_left::ok_hand: the syndicate! they :older_woman: got ☄ me :heart_eyes::cold_sweat: questioning my :pregnant_woman: loyalty to nanotraben! so :ok_hand::100: please :tired_face: lets :no_entry::eyes: gather our :camera_with_flash::poop: energy :sunglasses: and :moneybag::symbols: QUICK. :astonished: send this :wastebasket::point_left: to :sweat_drops::pill: 10 :joy::joy: other loyal :100: nanotraysens to :sweat_drops::thinking: show we :dog: dont :person_gesturing_no::no_entry_sign: take :shopping_bags: nothing from :joy: the ✝ syndicate!! bless your :point_right_tone2: heart :heart_eyes::broken_heart:" = 5, "Hello, my name is Immigration officer Mimi Sashimi from the American-Felinid Homeworld consulate. It appears your current documents are either inaccurate if not entirely fraudulent. This action in it's current state is a federal offense as listed in the United Earth Commission charter section NY-4. Please pay a fine of 300,000 Space credits or $3000 United States Dollars or face deportation" = 5, "Hi %name%, We are unable to validate your billing information for the next billing cycle of your subscription to HONK Weekly therefore we'll suspend your membership if we do not receive a response from you within 48 hours. Obviously we'd love to have you back, simply mail %address% to update your details and continue to enjoy all the best pranks & gags without interruption." = 5, "Loyal customer, DonkCo Customer Service. We appreciate your brand loyalty support. As such, it is our responsibility and pleasure to inform you of the status of your package. Your package for one \"Moth-Fuzz Parka\" has been delayed. Due to local political tensions, an animal rights group has seized and eaten your package. We appreciate the patience, DonkCo" = 5, "MESSAGE FROM CENTCOMM HIGH COMMAND: DO NOT ACCEPT THE FRIEND REQUEST OF TICKLEBALLS THE CLOWN. HE IS NOT FUNNY AND ON TOP OF THAT HE WILL HACK YOUR NTNET ACCOUNT AND MAKE YOU UNFUNNY TOO. YOU WILL LOSE ALL YOUR SPACECREDITS!!!!! SPREAD THE WORD. ANYONE WHO BECOMES FRIENDS WITH TINKLEBALLS THE CLOWN IS GOING TO LOSE ALL OF THEIR SPACECREDITS AND LOOK LIKE A HUGE IDIOT." = 5, "i WAS A NORMAL BOY AND I CAME HOME FROM SCHOOL AND I WANTED TO PLAY SOME ORION TRAIL WHICH IS A VERY FUN GAME BUT WHEN WENT TO ARCADE MACHINE SOMETHING WAS WEIRD TEH LOGO HASD BLOD IN IT AND I BECAME VERY SCARE AND I CHECK OPTIONS AND TEHRES ONLY 1 \"GO BACK\" I CKLICK IT AND I SEE CHAT  SI EMPTY THERE'S ONLY ONE CHARACTER CALLED \"CLOSE TEH GAME  \" AND I GO TO ANOTHER MACHINE AND PLAY THERE BUT WHEN I PLAY GAME IS FULL OF BLOOD AND DEAD BODIES FROM SPACEMAN LOOK CLOSER AND SEE CLOWN AND CLOWN COMES CLOSER AND LOOKS AT ME AND SAYS \"DON'T SAY I DIKDNT' WWARN YOU\" AND CLOWN CLOSEUP APPEARS WITH BLOOD-RED HYPERREALISTIC EYES AND HE TELLS ME \"YOU WILL BE THE NEXT ONE\" AND ARCADE MACHINE POWER SHUT OFF AND THAT NITE CLOWN APPEAR AT MY WINDOW AND KILL ME AT 3 AM AND NOW IM DEAD AND YOU WILL BE TRHNE NEXT OEN UNLESS YOU PASTE THIS STORY TO 10 NTNET FRIENDS" = 5))

/obj/item/paper/fluff/junkmail_redpill
	name = "smudged paper"
	icon_state = "scrap"

CAPABILITIES(/obj/item/paper/fluff/junkmail_redpill)
	rolls(nameof(info), PROC_REF(roll_info))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/paper/fluff/junkmail_redpill/proc/roll_info(datum/roller/R)
	return "You need to escape the simulation. Don't forget the numbers, they help you remember: '[R.number(0, 9)]*[R.number(0, 9)][R.number(0, 9)]...'"

/obj/item/paper/fluff/love_letter
	name = "love letter"
	icon_state = "paper_words"

/obj/item/paper/fluff/love_letter/Initialize(mapload)
	. = ..()
	info = "I HATE CARGO MAIL\n\"GRAA LEMME BREAK YOUR DOORS DOWN I GOTTA GIVE YOU MAIL\nREE YOU GOTTA GET YOUR MAIL I SORTED IT\nYOU'RE WASTIN YOUR TIME IF YOU DONT GET MAIL YOU NEED TO GET YOUR MAIL NOW\nWHY ARENT YO UGETTING YOUR MAIL RAAA\""

/obj/item/paper/fluff/junkmail_generic
	name = "important document"
	icon_state = "paper_words"

