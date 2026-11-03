pub const NAME:&str="sys/dx_manual_fingerprint_log";
pub const FILES:&[(&str,&str)]=&[
("code/a.dm", "/obj/controller/proc/configure()\n    cap_hand(\"Named\", PROC_REF(named))\n    cap_tool(\"Remote\", TOOL_WRENCH, handler = TYPE_PROC_REF(/obj/remote, remote))\n    cap_entry(\"Global\", hand(), GLOBAL_PROC_REF(global_handler))\n/obj/controller/proc/act_toggle(user)\n    add_fingerprint(user)\n/obj/controller/proc/helper(user)\n    add_fingerprint(user)\n/obj/unrelated/proc/named(user)\n    log_game(\"not selected\")\n/proc/act_global(user)\n    log_game(\"global act prefix is not a dispatched instance handler\")\n"),
("code/z.dm", "/obj/controller/sub/proc/named(user)\n    message_admins(\"cross-file selected\")\n/obj/remote/child/proc/remote(user)\n    log_admin(\"typed reference child\")\n/proc/global_handler(user)\n    log_and_message_admins(\"global reference\")\n/obj/controller/proc/act_kept(user)\n    add_fingerprint(user) // ALLOW(sys_dx_manual_fingerprint_log): dispatch intentionally supplies this fixture history entry\n"),
("maps/handler.dm", "/obj/map_machine/proc/act_map(user)\n    log_game(\"actual maps domain\")\n"),
("code/.hidden/ignore.dm", "/obj/hidden/proc/act_hidden(user)\n    add_fingerprint(user)\n"),
("code/modules/unit_tests/ignore.dm", "/obj/test_fixture/proc/act_test(user)\n    log_admin(\"default sys exemption\")\n"),
];
pub const CONFIG:&str="[lint.sys]\nexempt_prefixes=[\"code/modules/unit_tests/\"]\n";
pub fn configuration(case:usize)->String{match case{0=>CONFIG.into(),1=>"[lint.sys]\nexempt_prefixes=[\"code/modules/unit_tests/\",\"code/a.dm\"]\n".into(),2=>format!("{CONFIG}[lint.\"sys/dx_manual_fingerprint_log\"]\nexempt_prefixes=[\"code/z.dm\"]\n"),3=>format!("{CONFIG}[lint.\"sys/dx_manual_fingerprint_log\".ceilings]\ndx_manual_fingerprint_log=50\n"),_=>panic!("unknown real configuration case")}}
