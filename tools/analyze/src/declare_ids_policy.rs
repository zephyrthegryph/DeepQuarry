//! Whole existing declare_ids marker/define policy shared by legacy and native.
use crate::{captured_generator_budget::Budget, sparse_slots_policy::Output};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
const CAP_BASE: u32 = 300;
const STAT_BASE: u32 = 100_000;
pub const MARKERS: &[&str] = &[
    "CAPABILITY_DEF",
    "CAPABILITY_TYPE",
    "STAT",
    "SOURCE_DEF",
    "STAGE_DEF",
    "STATE_GRAPH",
    "cap_keys",
];
fn up(s: &str) -> String {
    s.to_uppercase()
}
pub(crate) fn split_opt(arg:&str)->Option<(String,String)>{split_opt_borrowed(arg).map(|(key,value)|(key.to_owned(),value.to_owned()))}
pub(crate) fn split_opt_borrowed(arg:&str)->Option<(&str,&str)>{
    let b = arg.as_bytes();
    let mut i = 0;
    while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
        i += 1;
    }
    if i == 0 {
        return None;
    }
    let rest = arg[i..].trim_start();
    let rest = rest.strip_prefix('=')?;
    if rest.starts_with('=') {
        return None;
    }
    Some((&arg[..i],rest.trim()))
}

pub(crate) struct Cap {
    pub(crate) name: String,
    pub(crate) id: String,
    pub(crate) ty: String,
    pub(crate) key: Option<String>,
    pub(crate) stacks: Option<String>,
    pub(crate) params: Vec<(String, Option<String>)>,
    /// prefix = "name": the op key prefix, when it is not the constructor's name (a library constructor that cannot take the final name yet).
    pub(crate) prefix: Option<String>,
    pub(crate) rel: String,
    pub(crate) line: u32,
    pub(crate) is_def: bool,
}

pub(crate) fn parse_capability(marker:&str,rel:&str,line:u32,args:&[String],out:&mut Output)->Option<Cap>{
    match parse_capability_controlled(&mut crate::key_policy_control::Compatibility,marker,rel,line,args,out){Ok(value)=>value,Err(never)=>match never{}}
}
/// Native callers pass the SAME admitted Output sink; only Cap/string/param
/// work is charged here. Legacy uses the unchecked no-op control.
pub(crate) fn parse_capability_controlled<C:crate::key_policy_control::Control>(control:&mut C,marker:&str,rel:&str,line:u32,args:&[String],out:&mut Output)->Result<Option<Cap>,C::Error>{
    use crate::key_policy_control as kc;control.checkpoint()?;
    let is_def=marker=="CAPABILITY_DEF";let need=if is_def{2}else{3};
    if args.len()<need{out.diag_fmt(rel,line,format_args!("{} needs (name, CAP_X{}, ...)",marker,if is_def{""}else{", /datum/capability/x"}));return Ok(None)}
    let name=kc::own(control,&args[0])?;let id=kc::own(control,&args[1])?;
    let ty=if is_def{kc::format(control,format_args!("/datum/capability/def/{}",name))?}else{kc::own(control,&args[2])?};
    let mut cap=Cap{name,id,ty,key:None,stacks:None,params:Vec::new(),prefix:None,rel:kc::own(control,rel)?,line,is_def};
    for arg in &args[need..]{control.checkpoint()?;match split_opt_borrowed(arg){
        Some(("key",value))=>cap.key=Some(kc::own(control,value)?),
        Some(("stacks",value))=>cap.stacks=Some(kc::own(control,value)?),
        Some(("prefix",value))=>cap.prefix=Some(kc::own(control,value.trim().trim_matches('"'))?),
        Some((key,value))=>{kc::row(control,&mut cap.params)?;let key=kc::own(control,key)?;let value=kc::own(control,value)?;cap.params.push((key,Some(value)));},
        None=>if arg.chars().all(|ch|ch.is_alphanumeric()||ch=='_')&&!arg.is_empty(){kc::row(control,&mut cap.params)?;cap.params.push((kc::own(control,arg)?,None));}else{out.diag_fmt(rel,line,format_args!("capability {}: `{}` is neither key =, stacks = nor param = default",cap.name,arg));},
    }}
    control.checkpoint()?;Ok(Some(cap))
}

/// The exact old whole-file prefilter and raw line policy. Not evaluated defines.
pub fn visit_defines(text:&str,mut take:impl FnMut(&str)){try_visit_defines(text,|name|{take(name);Ok::<(),std::convert::Infallible>(())},||Ok(())).unwrap_or_else(|never|match never{})}
pub fn try_visit_defines<E>(text:&str,mut take:impl FnMut(&str)->Result<(),E>,mut checkpoint:impl FnMut()->Result<(),E>)->Result<(),E>{
    if !text.contains("#define") {
        return Ok(());
    }
    for line in text.lines() {
        checkpoint()?;
        let t = line.trim_start();
        if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start();
            if let Some(rest) = rest.strip_prefix("define") {
                let rest = rest.trim_start();
                let end = rest
                    .char_indices()
                    .take_while(|(_, c)| c.is_alphanumeric() || *c == '_')
                    .map(|(i, c)| i + c.len_utf8())
                    .last()
                    .unwrap_or(0);
                if end > 0 {
                    take(&rest[..end])?;
                }
            }
        }
    }
    Ok(())
}
struct Marker {
    name: String,
    rel: String,
    line: u32,
    args: Vec<String>,
}
#[derive(Default)]
pub struct Builder {
    rows: Vec<Marker>,
    defined: BTreeSet<String>,
    out: Output,
    budget: Option<Arc<Budget>>,
}
impl Builder {
    pub fn captured(budget: Arc<Budget>) -> Self {
        Self {
            rows: Vec::new(),
            defined: BTreeSet::new(),
            out: Output::captured(budget.clone()),
            budget: Some(budget),
        }
    }
    pub fn define(&mut self, name: &str) -> Result<(), String> {
        if self.defined.contains(name) {
            return Ok(());
        }
        if let Some(b) = &self.budget {
            b.charge(
                name.len()
                    .checked_mul(4)
                    .and_then(|n| n.checked_add(512))
                    .ok_or("declare_ids define accounting overflow")?,
            )?;
        }
        self.defined.insert(name.to_owned());
        Ok(())
    }
    pub fn push(
        &mut self,
        marker: &str,
        rel: &str,
        line: u32,
        args: &[String],
    ) -> Result<(), String> {
        if !MARKERS.contains(&marker) {
            return Err("declare_ids marker is not admitted".into());
        }
        if let Some(b) = &self.budget {
            if self.rows.len() >= crate::captured_generator_budget::MAX_ROWS {
                b.deny();
                return b.require();
            }
            // Conservative monotonic admission covers cloned arguments, capability rows,
            // stable-sort scratch and BTree coordination before any such allocation.
            // cap_keys has at most24 emitted repeated cap/name slots; Unicode uppercase
            // and old diagnostic strings use this reserve or the actual Output sink.
            let width = args
                .iter()
                .try_fold(marker.len() + rel.len(), |n, a| n.checked_add(a.len()))
                .ok_or("declare_ids row width overflow")?;
            let charge = width
                .checked_mul(192)
                .and_then(|n| n.checked_add(args.len().checked_mul(1024)?))
                .and_then(|n| n.checked_add(8192))
                .ok_or("declare_ids row accounting overflow")?;
            b.charge(charge)?;
            if !b.row(&mut self.rows) {
                return b.require();
            }
        }
        self.rows.push(Marker {
            name: marker.into(),
            rel: rel.into(),
            line,
            args: args.to_vec(),
        });
        Ok(())
    }
    fn markers<'a>(&'a self, name: &'a str) -> impl Iterator<Item = &'a Marker> + 'a {
        self.rows.iter().filter(move |m| m.name == name)
    }
    pub fn finish(self) -> Output {
        self.finish_checked(&mut || Ok(()))
            .expect("legacy ids have no resource or cancellation guard")
    }
    pub fn finish_checked(self,checkpoint:&mut impl FnMut()->Result<(),String>)->Result<Output,String>{self.finish_with(checkpoint)}
    /// Same exact judgement with a direct fallible caller checkpoint.
    pub fn finish_with<E:From<String>+for<'error>From<&'error str>>(
        mut self,
        checkpoint:&mut impl FnMut()->Result<(),E>,
    )->Result<Output,E>{
        checkpoint()?;
        if let Some(b) = &self.budget {
            b.require()?;
        }
        let mut out = std::mem::take(&mut self.out);
        let defined = &self.defined;
        let mut caps = Vec::new();
        for m in self
            .rows
            .iter()
            .filter(|m| m.name == "CAPABILITY_DEF" || m.name == "CAPABILITY_TYPE")
        {
            checkpoint()?;
            if let Some(cap) = parse_capability(&m.name, &m.rel, m.line, &m.args, &mut out) {
                caps.push(cap);
            }
        }
        caps.sort_by(|a, b| a.name.cmp(&b.name));
        let mut stats: BTreeMap<String, bool> = BTreeMap::new(); // NAME -> is a status
        for m in self.markers("STAT") {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            if let Some(n) = m.args.get(1) {
                let is_status = m
                    .args
                    .iter()
                    .skip(3)
                    .any(|a| split_opt(a).map(|(k, _)| k == "units").unwrap_or(false));
                *stats.entry(up(n)).or_insert(false) |= is_status;
            }
        }
        let sources: BTreeSet<String> = self
            .markers("SOURCE_DEF")
            .filter_map(|m| m.args.first().map(|n| up(n)))
            .collect();
        let stages: BTreeSet<String> = self
            .markers("STAGE_DEF")
            .filter_map(|m| match (m.args.first(), m.args.get(1)) {
                (Some(g), Some(n)) => Some(format!("{}_{}", up(g), up(n))),
                _ => None,
            })
            .collect();
        let graphs: BTreeSet<String> = self
            .markers("STATE_GRAPH")
            .filter_map(|m| m.args.first().cloned())
            .collect();

        out.doc("Stat ids: STAT_<NAME> for each STAT(T, name, ...), from 100001. A status (units =) also has STATUS_<NAME> and STAT_<NAME>_IMMUNE.");
        for (i, (name, status)) in stats.iter().enumerate() {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            let id = format!("STAT_{}", name);
            if !defined.contains(&id) {
                out.line_fmt(format_args!("#define {} {}", id, STAT_BASE + 1 + i as u32));
            }
            if *status {
                out.line_fmt(format_args!("#define STATUS_{} STAT_{}", name, name));
                out.line_fmt(format_args!(
                    "#define STAT_{}_IMMUNE STAT_IMMUNE(STAT_{})",
                    name, name
                ));
            }
        }
        out.blank();
        out.doc("Capability ids: the CAP_X of each CAPABILITY_TYPE/DEF whose id no hand-written define gives, from 300.");
        let mut next = CAP_BASE;
        let mut seen = BTreeSet::new();
        let mut ids: Vec<&String> = caps.iter().map(|c| &c.id).collect();
        ids.sort();
        for id in ids {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            if !seen.insert(id.clone()) {
                continue;
            }
            if !defined.contains(id) {
                out.line_fmt(format_args!("#define {} {}", id, next));
                next += 1;
            }
        }
        out.blank();
        out.doc("Source ids: SRC_<NAME> for each SOURCE_DEF(name).");
        for (i, name) in sources.iter().enumerate() {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            let id = format!("SRC_{}", name);
            if !defined.contains(&id) {
                out.line_fmt(format_args!("#define {} {}", id, i + 1));
            }
        }
        out.blank();
        out.doc("Build stage ids: STAGE_<GROUP>_<NAME> for each STAGE_DEF(group, name).");
        for (i, name) in stages.iter().enumerate() {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            let id = format!("STAGE_{}", name);
            if !defined.contains(&id) {
                out.line_fmt(format_args!("#define {} {}", id, i + 1));
            }
        }
        out.blank();
        out.doc("State graph ids: the GRAPH_X of each STATE_GRAPH(GRAPH_X, ...).");
        for (i, name) in graphs.iter().enumerate() {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            if !defined.contains(name) {
                out.line_fmt(format_args!("#define {} {}", name, i + 1));
            }
        }
        out.blank();
        out.doc("Capability state ids: <CAPNAME>_<KEY> for each key of a cap_keys(CAP_X, KEY = ..., ...), bit 1 first.");
        let by_id: BTreeMap<&String, &String> = caps.iter().map(|c| (&c.id, &c.name)).collect();
        let mut keys: Vec<(String, String, usize)> = Vec::new();
        for m in self.markers("cap_keys") {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            let Some(cap_id) = m.args.first() else {
                continue;
            };
            let cap_name = by_id
                .get(cap_id)
                .map(|n| up(n))
                .unwrap_or_else(|| cap_id.trim_start_matches("CAP_").to_string());
            let mut bit = 0;
            for a in m.args.iter().skip(1) {
                checkpoint()?;
                if let Some(b) = &self.budget {
                    b.require()?;
                }
                if let Some((k, _)) = split_opt(a) {
                    bit += 1;
                    if bit > 24 {
                        out.diag_fmt(
                            &m.rel,
                            m.line,
                            format_args!(
                                "cap_keys({}): more than 24 keys; a state word holds at most 24",
                                cap_id
                            ),
                        );
                        break;
                    }
                    keys.push((format!("{}_{}", cap_name, up(&k)), cap_id.clone(), bit));
                }
            }
        }
        keys.sort();
        for (id, cap_id, bit) in keys {
            checkpoint()?;
            if let Some(b) = &self.budget {
                b.require()?;
            }
            if !defined.contains(&id) {
                out.line_fmt(format_args!(
                    "#define {} CAPKEY_ID({}, {})",
                    id, cap_id, bit
                ));
            }
        }
        checkpoint()?;
        if let Some(b) = &self.budget {
            b.require()?;
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_define_prefilter_and_unicode_boundaries_are_preserved() {
        let mut names = Vec::new();
        visit_defines("# define MISSED 1\n", |n| names.push(n.to_owned()));
        assert!(names.is_empty());
        visit_defines(
            "#define PRESENT 1\n# define UNICODE_é 2\n#defineSOMETHING 3\n",
            |n| names.push(n.to_owned()),
        );
        assert_eq!(names, ["PRESENT", "UNICODE_é", "SOMETHING"]);
    }
    #[test]
    fn captured_row_denial_is_sticky_before_clone_and_small_next_operation_works() {
        let b = Budget::new(128).unwrap();
        let mut denied = Builder::captured(b.clone());
        assert!(denied
            .push(
                "STAT",
                "code/a.dm",
                1,
                &["/datum".into(), "value".into(), "SUM".into()]
            )
            .is_err());
        assert!(denied.rows.is_empty());
        assert!(b.denied());
        let b = Budget::new(1024 * 1024).unwrap();
        let mut okay = Builder::captured(b);
        okay.push(
            "STAT",
            "code/a.dm",
            1,
            &["/datum".into(), "value".into(), "SUM".into()],
        )
        .unwrap();
        let out = okay.finish_checked(&mut || Ok(())).unwrap();
        assert!(out.body.contains("#define STAT_VALUE 100001"));
    }
}

#[cfg(test)]mod typed_definition_visit_tests{use super::*;use std::cell::Cell;mod original{include!("declare_ids_original_define_visit.rs");}
 #[test]fn typed_define_walk_keeps_complete_original_word_quirks_and_stops_before_callback(){let source="#define FIRST 1\n  # define SECOND(x) 2\n#defineTHIRD 3\n#define λambda 4\n#define 99 5\n// #define NOPE\n";let mut old=Vec::new();original::visit_defines(source,|name|old.push(name.to_owned()));let mut current=Vec::new();try_visit_defines(source,|name|{current.push(name.to_owned());Ok::<(),std::io::Error>(())},||Ok(())).unwrap();assert_eq!(current,old);let visits=Cell::new(0);let error=try_visit_defines(source,|_|{visits.set(visits.get()+1);Ok(())},||Err(std::io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(visits.get(),0);}
 #[cfg(feature="native-policy")]#[test]fn typed_ids_finish_preserves_actual_checkpoint_cause_and_same_policy_retry(){fn fixture()->Builder{let mut rows=Builder::captured(Budget::new(1024*1024).unwrap());rows.push("STAT","code/a.dm",1,&["/datum/probe".into(),"charge".into(),"SUM".into()]).unwrap();rows}let expected=fixture().finish_checked(&mut||Ok(())).unwrap();let error=fixture().finish_with(&mut||Err::<(),_>(crate::captured_reactive_reads::Failure::Operational(std::io::Error::from_raw_os_error(1450)))).unwrap_err();assert!(matches!(error,crate::captured_reactive_reads::Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));let current=fixture().finish_with(&mut||Ok::<(),crate::captured_reactive_reads::Failure>(())).unwrap();assert_eq!(current,expected);}

}
