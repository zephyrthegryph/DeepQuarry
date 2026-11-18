//! Source-neutral data and exact shared notice publisher scan.
use crate::raw_fixture_policy::PatternApi as _;
use std::collections::{BTreeMap,BTreeSet};

use crate::{
    actions_policy::past_tense,
    key_policy_control::{self as kc,Control},
    lint::{Meta,Policy,RuleMeta,ScanKind},
    pat::Pat,
    raw_tree_report::{self,Reporter},
    tree::{SourceFile, CODE_DM},
};

const HINT: &str = "nothing publishes this notice, so this subscriber never runs: wire up the publisher, or delete the subscriber and the notice. doc/rewrite/reactions.md section 3";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::notice_publisher::SCOPE_META_0.name,
    group: crate::allow_registry_fields::notice_publisher::SCOPE_META_0.group,
    label: "notice_publisher",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "no_publisher", hint: HINT }],
    allow: crate::allow_registry_fields::notice_publisher::ALLOW_0,
    lists: crate::allow_registry_fields::notice_publisher::SCOPE_META_0.lists,
};

pub(crate) struct Patterns<P=Pat> {
    path: P,
    subscribes: P,
    publishes: P,
    assigned: P,
    action: P,
    action_notice: P,
    token_call: P,
    token_macro: P,
}

impl Patterns {
    pub(crate) fn new() -> Patterns {
        Patterns {
            path: Pat::new(r"/datum/notice/([A-Za-z0-9_/]+)"),
            subscribes: Pat::new(r"(?:^|[^\w])(?:on_notice|observe)\("),
            publishes: Pat::new(r"PUBLISH_LEGACY\(|(?:^|[^\w])publish\(|take_notice\(|notice_take\(|\w_publish\("),
            assigned: Pat::new(r"\bnotice(?:_type)?\s*=\s*/datum/notice/([A-Za-z0-9_/]+)"),
            action: Pat::new(r"^ACTION\(\s*([A-Za-z0-9_/]+)"),
            action_notice: Pat::new(r"\bnotice\s*=\s*/datum/notice/([A-Za-z0-9_/]+)"),
            token_call: Pat::new(r"\b(?:act|publish)_(\w+)"),
            token_macro: Pat::new(r"\b(?:ACT_ATTEMPT|PUBLISH)\([^,]*,\s*(\w+)"),
        }
    }
}

fn is_test(relative:&str)->usize{relative.starts_with("code/tests/") as usize}

#[derive(Default)]
pub(crate) struct PublisherIndex {
    published:[BTreeSet<String>;2],
    tokens:[BTreeSet<String>;2],
    actions:BTreeMap<String,String>,
}

fn insert<C:Control>(set:&mut BTreeSet<String>,value:&str,work:&mut C)->Result<(),C::Error>{
    work.checkpoint()?;
    if !set.contains(value){
        kc::reserve(work,||value.len().checked_mul(4)?.checked_add(2048))?;
        set.insert(value.to_owned());
    }
    Ok(())
}

impl PublisherIndex {
    pub(crate) fn index<P:crate::raw_fixture_policy::PatternApi,C:Control,T:Control<Error=C::Error>>(
        &mut self,file:&SourceFile,patterns:&Patterns<P>,retained:&mut C,temporary:&mut T,
    )->Result<(),C::Error>{
        retained.checkpoint()?;
        if file.rel.contains("/_generated/"){return Ok(())}
        let side=is_test(&file.rel);
        let mut peak=0;
        for(_,text) in file.code().numbered(){
            temporary.checkpoint()?;
            if let Some(action)=patterns.action.captures(text){
                let name=action.s(1);
                // Fund the shared past-tense helper's split and rendered
                // names, plus the exact replacement retained in the map.
                let explicit=patterns.action_notice.captures(text);
                let size=name.len().checked_add(explicit.as_ref().map_or(0,|notice|notice.s(1).len()));
                raw_tree_report::peak(temporary,&mut peak,||size?.checked_add(1)?.checked_mul(128)?.checked_add(4096))?;
                kc::reserve(retained,||size?.checked_mul(4)?.checked_add(2048))?;
                let notice=explicit.map_or_else(||past_tense(name),|notice|notice.s(1).to_owned());
                self.actions.insert(name.replace('/',"_"),notice);
                continue
            }
            if text.starts_with("/datum/notice/"){continue}
            for token in patterns.token_call.captures_iter(text){
                insert(&mut self.tokens[side],token.s(1),retained)?;
            }
            for token in patterns.token_macro.captures_iter(text){
                insert(&mut self.tokens[side],token.s(1),retained)?;
            }
            if patterns.publishes.is_match(text){
                for path in patterns.path.captures_iter(text){
                    insert(&mut self.published[side],path.s(1),retained)?;
                }
            }
            for path in patterns.assigned.captures_iter(text){
                insert(&mut self.published[side],path.s(1),retained)?;
            }
        }
        retained.checkpoint()
    }

    pub(crate) fn finish<C:Control>(self,work:&mut C)->Result<Publishers,C::Error>{
        let Self{mut published,tokens,actions}=self;
        for side in 0..2{
            for(token,notice) in &actions{
                work.checkpoint()?;
                if tokens[side].contains(token){insert(&mut published[side],notice,work)?}
            }
        }
        work.checkpoint()?;
        Ok(Publishers(published))
    }
}

pub(crate) struct Publishers([BTreeSet<String>;2]);
impl Publishers{
    pub(crate) fn judge<P:crate::raw_fixture_policy::PatternApi,C:Control>(
        &self,file:&SourceFile,patterns:&Patterns<P>,work:&mut C,out:&mut impl Reporter,
    )->Result<(),C::Error>{
        work.checkpoint()?;
        if file.rel.contains("/_generated/"){return Ok(())}
        let test=is_test(&file.rel)!=0;
        let heard=|set:&BTreeSet<String>,notice:&str,child:&str|{
            use std::ops::Bound::{Included,Unbounded};
            set.contains(notice)||set.range::<str,_>((Included(child),Unbounded)).next().is_some_and(|path|path.starts_with(child))
        };
        let mut peak=0;
        for(line,text) in file.code().numbered(){
            work.checkpoint()?;
            if !patterns.subscribes.is_match(text){continue}
            for path in patterns.path.captures_iter(text){
                work.checkpoint()?;
                let notice=path.s(1);
                raw_tree_report::peak(work,&mut peak,||notice.len().checked_mul(8)?.checked_add(1024))?;
                let child=format!("{notice}/");
                if heard(&self.0[0],notice,&child)||(test&&heard(&self.0[1],notice,&child)){continue}
                if !out.allowed_here(file,line,"notice_publisher"){
                    out.site_in_msg("no_publisher",&file.rel,line,
                        format!("a subscriber waits for /datum/notice/{notice}, which nothing publishes"));
                }
                if !out.checkpoint(){return Ok(())}
            }
        }
        work.checkpoint()
    }
}

const NOTICE_PATTERN_SOURCES:&[&str]=&[r"/datum/notice/([A-Za-z0-9_/]+)",r"(?:^|[^\w])(?:on_notice|observe)\(",r"PUBLISH_LEGACY\(|(?:^|[^\w])publish\(|take_notice\(|notice_take\(|\w_publish\(",r"\bnotice(?:_type)?\s*=\s*/datum/notice/([A-Za-z0-9_/]+)",r"^ACTION\(\s*([A-Za-z0-9_/]+)",r"\bnotice\s*=\s*/datum/notice/([A-Za-z0-9_/]+)",r"\b(?:act|publish)_(\w+)",r"\b(?:ACT_ATTEMPT|PUBLISH)\([^,]*,\s*(\w+)"];
#[cfg(feature="native-policy")]
pub(crate) fn native_patterns<'f,'a>(fixture:&'f crate::raw_fixture_policy::Fixture<'a>)->Patterns<crate::raw_fixture_policy::Pattern<'f,'a>>{Patterns{path:fixture.pattern(NOTICE_PATTERN_SOURCES[0],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[0])),subscribes:fixture.pattern(NOTICE_PATTERN_SOURCES[1],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[1])),publishes:fixture.pattern(NOTICE_PATTERN_SOURCES[2],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[2])),assigned:fixture.pattern(NOTICE_PATTERN_SOURCES[3],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[3])),action:fixture.pattern(NOTICE_PATTERN_SOURCES[4],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[4])),action_notice:fixture.pattern(NOTICE_PATTERN_SOURCES[5],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[5])),token_call:fixture.pattern(NOTICE_PATTERN_SOURCES[6],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[6])),token_macro:fixture.pattern(NOTICE_PATTERN_SOURCES[7],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(NOTICE_PATTERN_SOURCES[7]))}}
