#[path="raw_policy_next_frozen/lifeforms.rs"] mod frozen_0;
#[path="raw_policy_next_frozen/sys_contents.rs"] mod frozen_1;
#[path="raw_policy_next_frozen/sys_damage_reactions.rs"] mod frozen_2;
#[path="raw_policy_next_frozen/sys_emag.rs"] mod frozen_3;
#[path="raw_policy_next_frozen/sys_grants.rs"] mod frozen_4;
#[path="raw_policy_next_frozen/sys_dx_manual_transfer.rs"] mod frozen_5;
#[path="raw_policy_next_frozen/sys_dx_raw_delay.rs"] mod frozen_6;
#[path="raw_policy_next_frozen/sys_dx_raw_overlays.rs"] mod frozen_7;
#[path="raw_policy_next_frozen/sys_dx_review.rs"] mod frozen_8;
#[path="raw_policy_next_frozen/sys_messages.rs"] mod frozen_9;
#[path="raw_policy_next_frozen/sys_presentation.rs"] mod frozen_10;
#[path="raw_policy_next_frozen/sys_topic.rs"] mod frozen_11;
#[path="raw_policy_next_frozen/sys_usr_use.rs"] mod frozen_12;

use crate::{lint::{Cx,Registry,Sink},tree::{Tree,SourceFile},scopes::Scopes,captured_raw_file::{Config,File},captured_raw_policy::Configuration};
const NAMES:&[&str]=&["lifeform_allows","escape_hatches","sys/contents","sys/damage_reactions","sys/dx_manual_transfer","sys/dx_raw_delay","sys/dx_raw_overlays","sys/dx_review","sys/emag","sys/grants","sys/messages","sys/presentation","sys/topic","sys/usr_use"];
fn original()->Registry{let mut reg=Registry::default();frozen_0::register(&mut reg);frozen_1::register(&mut reg);frozen_2::register(&mut reg);frozen_5::register(&mut reg);frozen_6::register(&mut reg);frozen_7::register(&mut reg);frozen_8::register(&mut reg);frozen_3::register(&mut reg);frozen_4::register(&mut reg);frozen_9::register(&mut reg);frozen_10::register(&mut reg);frozen_11::register(&mut reg);frozen_12::register(&mut reg);reg}
const BODY:&str=r#"/obj/probe/examine()
    contents_of(src)
    qdel(src) // ALLOW(lifecycle): the flare is used up by this operation
    usr.visible_message("fixture")
    emag_act()
    on_emag()
    verbs += /obj/probe/verb/test // ALLOW(sys_verb_write): this annotation is deliberately ineffective
    refresh_vision()
    add_overlay("fixture")
    sleep(2)
    to_chat(usr, "fixture")
/obj/probe/Topic(href,href_list)
    if(href_list["x"])
        locate(href_list["target"])
    text2num(href_list["number"])
/obj/probe/verb/hello()
    usr.visible_message("verb caller")
/obj/probe/proc/plain()
    // ALLOW(init/INSTANCE_STATE): the constructor argument is received from its caller
    return 1
"#;
fn compare(config:Option<&[u8]>){let root=std::env::current_dir().unwrap().join("raw-next-original");let original=original();let interpreted=match config {Some(bytes)=>Scopes::parse(std::str::from_utf8(bytes).unwrap()).unwrap(),None=>Scopes::default()};let config=Config::capture(config.map_or(Configuration::ProvenMissing,Configuration::Captured)).unwrap();for rel in ["code/probe.dm","maps/probe.dm","code/engine/probe.dm","code/engine/_generated/probe.dm","code/.hidden/probe.dm"]{let file=File::capture(&root,&root.join(rel),BODY.into()).unwrap();let tree=Tree::from_files(vec![SourceFile::from_text(rel,BODY)]);for name in NAMES{let lint=original.find(name).unwrap();let scope=interpreted.for_lint(lint.meta().name,lint.meta().group);let cx=Cx{tree:&tree,meta:lint.meta(),scope:&scope};let mut expected=Sink::new();for f in cx.files(){expected.cur=f.rel.clone();lint.scan_file(&cx,f,&mut expected);}let actual=file.scan(&config.scope(name).unwrap()).unwrap();assert_eq!(actual.run.sites,expected.sites,"{name} {rel}");assert_eq!(actual.run.notes,expected.notes,"{name} {rel}");assert_eq!(actual.allow_used,expected.allow_used,"{name} {rel}");}}}
#[test]fn raw_next_full_original_scanners_preserve_all_findings_notes_allow_and_path_order(){compare(None);}
#[test]fn raw_next_full_original_configuration_and_ineffective_no_allow_match(){compare(Some(b"[lint.\"sys/emag\"]\nexempt_files=['code/probe.dm']\n[lint.escape_hatches]\nexempt_prefixes=['maps/']\n"));}

#[test]fn raw_next_original_selftests_and_legacy_registration_position_remain_identical(){let old=original();let current=crate::captured_raw_policy::registry();let expected:Vec<_>=old.lints.iter().map(|lint|lint.meta().name).filter(|name|NAMES.contains(name)).collect();let requested:Vec<_>=NAMES.iter().map(|name|(*name).to_owned()).collect();assert_eq!(crate::captured_raw_file::ordered_names(&requested).unwrap(),expected);for name in NAMES{assert_eq!(old.find(name).unwrap().selftest(),current.find(name).unwrap().selftest(),"{name}");}let mut legacy=Registry::default();crate::lints::register(&mut legacy);let names:Vec<_>=legacy.lints.iter().map(|l|l.meta().name).collect();let at=names.iter().position(|n|*n=="lifeforms").unwrap();assert_eq!(&names[at..at+3],&["lifeforms","lifeform_allows","escape_hatches"]);for name in NAMES{assert_eq!(names.iter().filter(|n|**n==*name).count(),1);}}
