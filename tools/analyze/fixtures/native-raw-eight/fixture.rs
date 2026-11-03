//! Initial raw source only. No generated answers or source authority.
pub const CONFIG:&str=r#"
[lint.pool.lists]
exempt_prefixes=["code/pool_exempt/"]
[lint.cap_bits.lists]
registry=["code/__defines/cap_bits.dm"]
writers=["code/engine/cap_writer.dm"]
write_exempt_prefixes=["code/allowed/"]
[lint.pollers.lists]
step_exempt_prefixes=["code/tests/"]
"#;
pub const FILES:&[(&str,&str)]=&[
("code/__defines/cap_bits.dm","#define CAP_FIRST (1<<0)\n#define CAP_SECOND (1<<1)\n"),
("code/a.dm",r#"CAPABILITIES(/obj/input_holder)
	click_on(PROC_REF(first))
	click_on(PROC_REF(second))
CAPABILITIES(/obj/duplicate)
CAPABILITIES(/obj/backslash, one)
BUNDLE(old_group)
DECLARE_INTERACTIONS(/obj/parent)
DECLARE_INTERACTIONS(/obj/parent/child)
/obj/latent_holder
	latent_contents = TRUE
/obj/latent_holder/proc/walk()
	for(var/obj/item in contents)
		consume(item)
/obj/cool/proc/tick()
	if(world.time > next_tick)
		return 1
/obj/poller
	process() START_PROCESSING(SSobj,src)
/datum/notice/unmarked
	var/answer = 0
/proc/handler(datum/notice/unmarked/event)
	event.answer = 1
	var/list/answers = event.answers
	answers += 2
/proc/cast_handler(N)
	var/datum/notice/unmarked/event = N
	event.answer = 3 // ALLOW(read_back): this direct legacy caller deliberately waits for the handler response before continuing
/proc/taking_notice()
	var/datum/notice/unmarked/event = notice_take()
	event.answer = 4
/datum/notice/unmarked/fill()
	src.answer = 5
#define CAP_COLLISION (1<<1)
/obj/caps/proc/write()
	cap_state |= CAP_FIRST
"#),
("code/z.dm",r#"CAPABILITIES(/obj/duplicate)
CAPABILITIES(/obj/input_holder)
	click_on(PROC_REF(third))
DECLARE_INTERACTIONS(/obj/parent/child/grandchild) // ALLOW(interactions): this separate legacy interaction dispatch deliberately replaces inherited entries
/obj/latent_holder/proc/kept()
	for(var/x in contents) // ALLOW(latent): the legacy container path deliberately materializes its ledger before enumeration
/obj/cool/proc/kept()
	if(world.time > next_tick) // ALLOW(cooldown): this external engine handshake deliberately reads the legacy timing boundary
/obj/kept_poller
	process() // ALLOW(pollers): this external fixture pump deliberately exercises legacy process annotation behavior
/datum/notice/answered
	read_back = TRUE
/proc/answered(datum/notice/answered/event)
	event.answer = 2
"#),
("code/selected_handler.dm",r#"CAPABILITIES(/obj/input_holder)
	click_on(PROC_REF(fourth))
/proc/answered_elsewhere(datum/notice/answered/event)
	event.answer = 9
#define CAP_EXTRA (1<<25)
"#),
("code/pool_declaration.dm","/datum/pool_packet\n\tparent_type = /datum/pooled\n"),
("code/pool_use.dm","/proc/pool_bad()\n\tvar/datum/pool_packet/P = new /datum/pool_packet\n/proc/pool_leak()\n\tvar/datum/pool_packet/P = take(/datum/pool_packet)\n"),
("code/pool_factory.dm","/proc/pool_factory()\n\tvar/datum/pool_packet/P = take(/datum/pool_packet)\n\tP.zone = 1\n\treturn P\n"),
("code/pool_exempt/use.dm","/proc/exempt_pool_bad()\n\tvar/datum/pool_packet/P = new /datum/pool_packet\n"),
("code/.hidden/pool.dm","/proc/hidden_pool_bad()\n\tvar/datum/pool_packet/P = new /datum/pool_packet\n"),
("maps/pool.dm","/proc/map_pool_bad()\n\tvar/datum/pool_packet/P = new /datum/pool_packet\n"),
("maps/poller.dm","/obj/machinery/map_machine/machine_step()\n	return 1\n"),
("code/.hidden/latent.dm","/obj/latent_holder/proc/hidden_walk()\n	for(var/x in contents)\n		consume(x)\n"),
];

pub fn configuration(configured:bool)->String{let mut value=CONFIG.to_string();if configured{value.push_str(r#"
[lint.cooldown]
exempt_files=["code/z.dm"]
[lint.declaration_block]
exempt_files=["code/a.dm"]
[lint.duplicate_input_key]
exempt_files=["code/a.dm"]
[lint.interactions]
exempt_files=["code/a.dm"]
[lint.latent]
exempt_files=["code/z.dm"]
[lint.pollers]
exempt_files=["maps/poller.dm"]
[lint.read_back]
exempt_files=["code/z.dm"]
[lint.pool]
exempt_files=["code/pool_declaration.dm"]
[lint.cap_bits]
exempt_files=["code/a.dm"]
"#);}value}
