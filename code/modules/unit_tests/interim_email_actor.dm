/// Observe the actor while retaining real inbox/spam delivery and timestamps.
/datum/computer_file/data/email_account/interim_actor
	var/delivery_actor_ref
	var/deliveries = 0

/datum/computer_file/data/email_account/interim_actor/receive_mail(datum/computer_file/data/email_message/received_message, relayed, mob/user)
	delivery_actor_ref = user ? REF(user) : null
	deliveries++
	return ..()

/// Only the fixture mailbox receives broadcasts; every other scheduled clone is deleted.
/datum/computer_file/data/email_account/service/broadcaster/interim_actor
	var/fixture_address
	var/relay_actor_ref
	var/fixture_relays = 0

/datum/computer_file/data/email_account/service/broadcaster/interim_actor/send_mail(recipient_address, datum/computer_file/data/email_message/message, relayed = 0, mob/user)
	if(recipient_address != fixture_address)
		qdel(message)
		return FALSE
	relay_actor_ref = user ? REF(user) : null
	fixture_relays++
	return ..()

/datum/unit_test/interim_email_ui_sender/Run()
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/computer_file/data/email_account/sender = allocate(/datum/computer_file/data/email_account)
	var/datum/computer_file/data/email_account/interim_actor/recipient = allocate(/datum/computer_file/data/email_account/interim_actor)
	sender.login = "interim-sender-[REF(sender)]"
	sender.password = "interim-fixture-password"
	recipient.login = "interim-recipient-[REF(recipient)]"
	var/datum/tgui_module/email_client/module = allocate(/datum/tgui_module/email_client)
	module.stored_login = sender.login
	module.stored_password = sender.password
	TEST_ASSERT(module.log_in(), "the real email module logs into the registered fixture account")
	module.msg_title = "Actor fixture"
	module.msg_body = "In-game delivery fixture"
	module.msg_recipient = recipient.login
	module.ui_act_send(actor, list(), null, null, "send")
	TEST_ASSERT_EQUAL(recipient.deliveries, 1, "the UI sends exactly one actual email")
	TEST_ASSERT_EQUAL(recipient.delivery_actor_ref, REF(actor), "real account delivery receives the explicit UI actor")
	var/list/messages = recipient.all_emails()
	TEST_ASSERT_EQUAL(length(messages), 1, "the recipient mailbox really stores the sent message")
	var/datum/computer_file/data/email_message/message = messages[1]
	own(message)
	TEST_ASSERT_EQUAL(message.source, sender.login, "delivery preserves the authenticated account address")
	TEST_ASSERT_EQUAL(message.title, "Actor fixture", "delivery preserves the drafted title")
	TEST_ASSERT_EQUAL(message.stored_data, "In-game delivery fixture", "delivery preserves the drafted body")
	TEST_ASSERT(length(message.timestamp), "real delivery stamps the email")
	TEST_ASSERT_EQUAL(module.msg_title, "", "successful delivery clears the compose state")

/datum/unit_test/interim_email_broadcast_sender/Run()
	test_driver_begin()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/computer_file/data/email_account/interim_actor/recipient = allocate(/datum/computer_file/data/email_account/interim_actor)
	recipient.login = "interim-broadcast-recipient-[REF(recipient)]"
	// glob_load skips registering the fixture broadcaster as an additional service address.
	var/datum/computer_file/data/email_account/service/broadcaster/interim_actor/broadcaster = allocate(/datum/computer_file/data/email_account/service/broadcaster/interim_actor, TRUE)
	broadcaster.fixture_address = recipient.login
	var/datum/computer_file/data/email_message/message = allocate(/datum/computer_file/data/email_message)
	message.title = "Relay fixture"
	message.stored_data = "Scheduled in-game delivery"
	message.source = "interim-broadcast-sender"
	message.spam = TRUE // Do not emit an unrelated admin announcement from this fixture.
	TEST_ASSERT(broadcaster.receive_mail(message, FALSE, actor), "the actual broadcaster schedules accepted mail")
	TEST_ASSERT_EQUAL(length(broadcaster.pending_messages), length(GLOB.ntnet_global.email_accounts), "the broadcaster owns every scheduled clone before any timer runs")
	TEST_ASSERT_EQUAL(recipient.deliveries, 0, "the broadcaster does not deliver before its timer runs")
	test_time((length(GLOB.ntnet_global.email_accounts) + 1) * (0.2 SECONDS))
	TEST_ASSERT_NULL(broadcaster.pending_messages, "successful and rejected fixture deliveries drain the owned pending queue")
	TEST_ASSERT_EQUAL(broadcaster.fixture_relays, 1, "the actual broadcaster schedules this mailbox exactly once")
	TEST_ASSERT_EQUAL(broadcaster.relay_actor_ref, REF(actor), "the scheduled send retains the originating actor")
	TEST_ASSERT_EQUAL(recipient.delivery_actor_ref, REF(actor), "the real receive chain retains the actor after the timer")
	TEST_ASSERT_EQUAL(recipient.deliveries, 1, "the scheduled relay really delivers one message")
	var/list/messages = recipient.all_emails()
	TEST_ASSERT_EQUAL(length(messages), 1, "the real mailbox holds the broadcast clone")
	var/datum/computer_file/data/email_message/clone = messages[1]
	TEST_ASSERT_NULL(owner_of(clone), "successful delivery releases broadcaster ownership while retaining the real mailbox relation")
	own(clone)
	TEST_ASSERT(clone != message, "broadcast delivery creates a distinct real email")
	TEST_ASSERT_EQUAL(clone.title, message.title, "the actual clone preserves the title")
	TEST_ASSERT_EQUAL(clone.stored_data, message.stored_data, "the actual clone preserves the body")
	TEST_ASSERT_EQUAL(clone.source, message.source, "the actual clone preserves the sender address")
	TEST_ASSERT(clone.spam, "the relay preserves the spam marker")
	TEST_ASSERT(!broadcaster.receive_mail(message, TRUE, actor), "a relayed broadcast cannot recurse")
	TEST_ASSERT_EQUAL(broadcaster.fixture_relays, 1, "rejecting recursion creates no new fixture relay")

/// A disappeared mailbox must discard its queued clone rather than retain it forever.
/datum/unit_test/interim_email_broadcast_missing_recipient/Run()
	var/datum/computer_file/data/email_account/service/broadcaster/broadcaster = allocate(/datum/computer_file/data/email_account/service/broadcaster, TRUE)
	var/datum/computer_file/data/email_message/message = allocate(/datum/computer_file/data/email_message)
	TEST_ASSERT(own_add(broadcaster, nameof(broadcaster.pending_messages), message), "the broadcaster owns the actual queued clone")
	TEST_ASSERT_EQUAL(owner_of(message), broadcaster, "the queued clone is strongly owned by its broadcaster")
	TEST_ASSERT(!broadcaster.deliver_broadcast("interim-missing-[REF(broadcaster)]", message, null), "a nonexistent mailbox rejects the real send")
	TEST_ASSERT(QDELETED(message), "failed delivery deletes the undelivered clone")
	TEST_ASSERT_NULL(broadcaster.pending_messages, "failed delivery drains the pending queue")

/// Deleting the broadcaster cancels its timers and disposes every not-yet-delivered clone.
/datum/unit_test/interim_email_broadcast_cancelled/Run()
	test_driver_begin()
	var/datum/computer_file/data/email_account/service/broadcaster/interim_actor/broadcaster = allocate(/datum/computer_file/data/email_account/service/broadcaster/interim_actor, TRUE)
	var/datum/computer_file/data/email_message/message = allocate(/datum/computer_file/data/email_message)
	message.spam = TRUE
	TEST_ASSERT(broadcaster.receive_mail(message, FALSE, null), "the actual broadcaster queues a broadcast")
	TEST_ASSERT(length(broadcaster.pending_messages), "the real pending queue contains cloned messages")
	var/list/pending = broadcaster.pending_messages.Copy()
	for(var/datum/computer_file/data/email_message/clone in pending)
		TEST_ASSERT_EQUAL(owner_of(clone), broadcaster, "every queued clone has broadcaster ownership")
	qdel(broadcaster)
	for(var/datum/computer_file/data/email_message/clone in pending)
		TEST_ASSERT(QDELETED(clone), "broadcaster deletion destroys the actual queued clone")
	TEST_ASSERT(!QDELETED(message), "cancellation preserves the original independently held message")
	test_time((length(GLOB.ntnet_global.email_accounts) + 1) * (0.2 SECONDS))
