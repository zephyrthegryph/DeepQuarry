use super::*;
use crate::captured_raw_file::RawPolicyViews;
use crate::captured_raw_policy::Configuration;
use crate::lint::AllowUse;
use std::cell::Cell;

const FIXTURE:&[(&str,&str)]=&[
    ("code/_generated/publishers.dm",concat!(
        "publish(/datum/notice/generated_only)\n",
        "on_notice(/datum/notice/generated_subscriber)\n",
    )),
    ("code/exempt.dm",concat!(
        "notice_type = /datum/notice/exempt_publisher\n",
        "on_notice(/datum/notice/exempt_subscriber)\n",
    )),
    ("code/live.dm",concat!(
        "/proc/start()\n",
        "    publish(/datum/notice/subtype/child)\n",
        "    on_notice(/datum/notice/subtype)\n",
        "    on_notice(/datum/notice/test_only)\n",
        "    on_notice(/datum/notice/generated_only)\n",
        "    on_notice(/datum/notice/exempt_publisher)\n",
        "    on_notice(/datum/notice/allow_one, /datum/notice/allow_two) // ALLOW(notice_publisher/TEST): observe the actual duplicate scanner consultation\n",
        "    // ALLOW(notice_publisher): the check only reads the subscriber line\n",
        "    observe(receiver, /datum/notice/previous_line)\n",
        "    act_fall(receiver)\n",
        "    on_notice(/datum/notice/fell)\n",
        "    on_notice(/datum/notice/test_action_done)\n",
        "ACTION(fall)\n",
        "ACTION(test_action, notice = /datum/notice/test_action_done)\n",
    )),
    ("code/tests/probe.dm",concat!(
        "take_notice(/datum/notice/test_only/child)\n",
        "observe(receiver, /datum/notice/test_only)\n",
        "observe(receiver, /datum/notice/subtype)\n",
        "ACT_ATTEMPT(receiver, test_action)\n",
        "on_notice(/datum/notice/test_action_done)\n",
        "on_notice(/datum/notice/generated_only)\n",
    )),
];

struct Pages{
    files:Vec<SourceFile>,
    passes:Cell<usize>,
    stop_after_index:bool,
}
impl RawPolicyPages for Pages{
    fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
        let pass=self.passes.get();
        self.passes.set(pass+1);
        for file in &self.files{
            if !visit(&file.rel,RawPolicyViews::from_source(file))?{return Ok(false)}
            if pass==1&&self.stop_after_index{return Ok(false)}
        }
        Ok(true)
    }
}

fn fixture(stop_after_index:bool)->(Pages,Config){
    let files=FIXTURE.iter().map(|(relative,text)|SourceFile::from_text(relative,text)).collect();
    let config=Config::capture(Configuration::Captured(b"[lint.notice_publisher]\nexempt_files=['code/exempt.dm']\n")).unwrap();
    (Pages{files,passes:Cell::new(0),stop_after_index},config)
}

#[test]
fn notice_publisher_preserves_exact_sites_and_used_allow_from_both_facades(){
    let (pages,config)=fixture(false);
    let budget=Budget::new(16<<20).unwrap();
    let policy=Policy::from_name("notice_publisher").unwrap();
    assert_eq!(policy,Policy::NoticePublisher);
    assert!(policy.metadata().allow.is_empty());
    assert!(policy.permits_used_allow("notice_publisher"));
    assert!(!policy.permits_used_allow("scheduler"));
    let result=collect(&pages,policy,&config,&budget,&||Ok(())).unwrap();
    assert_eq!(pages.passes.get(),2);
    assert!(result.message_only()&&result.source_text().is_empty());
    let expected=[
        ("code/live.dm",4,"test_only"),
        ("code/live.dm",5,"generated_only"),
        ("code/live.dm",9,"previous_line"),
        ("code/live.dm",12,"test_action_done"),
        ("code/tests/probe.dm",6,"generated_only"),
    ].map(|(rel,line,notice)|Site{
        rel:rel.into(),line,rule:"no_publisher".into(),key:String::new(),ident:String::new(),
        msg:format!("a subscriber waits for /datum/notice/{notice}, which nothing publishes"),
    });
    assert_eq!(result.sites(),expected.as_slice());
    assert_eq!(result.allow_used(),&[AllowUse{
        rel:"code/live.dm".into(),line:7,name:"notice_publisher".into(),code:"TEST".into(),
    }]);
    assert_eq!(result.allow_source_digest("code/live.dm"),Some(&crate::captured_raw_file::source_allow_digest(&pages.files[2])));
    #[cfg(feature="legacy-sem")]
    {
        let registry=crate::run::registry();
        let lint=registry.find("notice_publisher").unwrap();
        let tree=crate::tree::Tree::from_files(pages.files);
        let scope=config.borrowed_report_scope(lint.meta().name,lint.meta().group).unwrap();
        let mut old=crate::lint::Sink::new();
        lint.scan_tree(&crate::lint::Cx{tree:&tree,meta:lint.meta(),scope},&mut old);
        assert_eq!(old.sites.as_slice(),result.sites());
        assert_eq!(old.allow_used.as_slice(),result.allow_used());
        assert_eq!(old.notes.as_slice(),result.notes());
    }
}

#[test]
fn notice_publisher_requires_both_whole_code_visits_and_preserves_first_io(){
    let (pages,config)=fixture(true);
    let budget=Budget::new(16<<20).unwrap();
    let failure=collect(&pages,Policy::NoticePublisher,&config,&budget,&||Ok(()));
    assert!(matches!(failure,Err(Failure::Unsupported(ref reason)) if reason.contains("judge stopped")));
    assert_eq!(pages.passes.get(),2);
    let (pages,config)=fixture(false);
    let budget=Budget::new(16<<20).unwrap();
    let calls=Cell::new(0);
    let failure=collect(&pages,Policy::NoticePublisher,&config,&budget,&||{
        let n=calls.get()+1;calls.set(n);
        if n==16{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}
    });
    assert!(matches!(failure,Err(Failure::Operational(ref actual)) if actual.raw_os_error()==Some(1450)));
    assert_eq!(calls.get(),16);
}
