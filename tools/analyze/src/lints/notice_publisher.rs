//! `notice_publisher`: a subscriber waits for a notice nothing publishes (doc/rewrite/reactions.md section 3).
//!
//! `on_notice(/datum/notice/x, ...)` or `observe(E, /datum/notice/x, ...)` on a type nobody publishes is behaviour that silently never runs. A notice has a
//! publisher when the type or a subtype (a handler hears its subtypes) is named on a line that publishes it (`PUBLISH_LEGACY`, `publish(`, `take_notice`,
//! `notice_take`, a `*_publish(` helper), is assigned to a `notice`/`notice_type` var (a publisher reading its type from data), or is the notice of an `ACTION()`
//! whose `act_x`, `publish_x`, `ACT_ATTEMPT(E, x` or `PUBLISH(E, x` appears. Publishers in code/tests only count for subscribers in code/tests. The check is
//! textual: it proves a publishing line exists, not that its proc runs (tools/ci/dead_code_scan.py lists procs nothing names). Generated files are not read.

use crate::{
    key_policy_control::Compatibility,
    lint::{Cx,Lint,Meta,Registry,Sink},
    notice_publisher_policy::{META,Patterns,PublisherIndex},
};

struct NoticePublisher(Patterns);
impl Lint for NoticePublisher {
    fn meta(&self)->&Meta{&META}

    fn scan_tree(&self,cx:&Cx,out:&mut Sink){
        let mut index=PublisherIndex::default();
        for file in cx.all_files(){
            index.index(file,&self.0,&mut Compatibility,&mut Compatibility).unwrap();
        }
        let published=index.finish(&mut Compatibility).unwrap();
        for file in cx.files(){
            published.judge(file,&self.0,&mut Compatibility,out).unwrap();
        }
    }
}

pub fn register(reg:&mut Registry){reg.add(NoticePublisher(Patterns::new()));}
