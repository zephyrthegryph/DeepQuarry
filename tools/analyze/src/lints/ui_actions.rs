//! Port of `tools/ci/ui_actions_lint.py`: TSX `act()` calls against `act_<action>` procs
//! (doc/rewrite/dx_conventions.md section 5; design review C1, C2).
//!
//! Whole-tree lint over `code/**/*.dm` and the tgui interface sources. Hard failures (an act()
//! the dispatcher rejects or no host answers, a key it drops or the proc doesn't declare) are the
//! banned rule `problem`; the C1/C2 ratchets are `ui_unsent_param` / `ui_unvalidated_param` on the
//! fingerprint baseline. The dispatcher's `ui_action_key()` normalisation is read out of
//! `code/library/capabilities/ui_actions.dm`, as in the Python.
//!
//! Quirks replicated: the problem list is not baselined and ignores ALLOW; an unsent parameter
//! yields one site per parameter (several sites on the proc head line); `$` in the dispatcher's
//! raw regex keeps Python's "also before a trailing newline" meaning.

use std::cell::{OnceCell, RefCell};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::rc::Rc;
use serde::{Deserialize, Serialize};

use crate::dm::dx::{enclosing_call, is_subtype, lineage, procs_in, Proc};
use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{Select, SourceFile, Tree};
use crate::util::{py_rstrip, py_strip};
use crate::{pat, pat_match};

use crate::ui_actions_policy::{META,DISPATCHER,INTERFACES,R_UNSENT,R_UNVALIDATED,R_PROBLEM};
use crate::ui_actions_hosts::CAPS_DIR;

// SAME dispatcher normalizer shared by both actual source owners.
use crate::ui_actions_normalizer::{Normaliser,normaliser_from};

// SAME TSX scanner shared by legacy and native source owners.
use crate::ui_actions_js::{RawCall,tsx_calls};

// SAME original host/action/constructor tables, borrowed source-local facts.
use crate::ui_actions_hosts::{Call,Acts,Hosts,DmFacts,dm_facts,name_hash};

// ---- analysis ---------------------------------------------------------------------------------

struct Analysis<'a> {
    tree: &'a Tree,
    hosts: &'a Hosts,
    norm: &'a Normaliser,
    acts: &'a Acts,
    pats: RefCell<HashMap<String, Rc<Pat>>>,
    helpers: &'a Helpers<'a>,
    c2: Option<&'a C2Cache>,
}

/// Every proc of a given name, loaded on demand from the (few) files that define one; the names a
/// root evaluation asked for are recorded as its dependencies.
struct Helpers<'a> {
    tree: &'a Tree,
    files: &'a [&'a SourceFile],
    facts: &'a [DmFacts],
    by_name: OnceCell<HashMap<u64, Vec<usize>>>,
    loaded: RefCell<HashMap<String, Rc<Vec<Proc>>>>,
    touched: RefCell<BTreeSet<u64>>,
}

impl<'a> Helpers<'a> {
    fn new(tree: &'a Tree, files: &'a [&'a SourceFile], facts: &'a [DmFacts]) -> Helpers<'a> {
        Helpers { tree, files, facts, by_name: OnceCell::new(), loaded: RefCell::new(HashMap::new()), touched: RefCell::new(BTreeSet::new()) }
    }

    fn begin(&self) {
        self.touched.borrow_mut().clear();
    }

    fn end(&self) -> Vec<u64> {
        self.touched.borrow().iter().copied().collect()
    }

    /// `procs_named(name)`: file order, then the file's own order.
    fn named(&self, name: &str) -> Rc<Vec<Proc>> {
        let nh = name_hash(name);
        self.touched.borrow_mut().insert(nh);
        if let Some(v) = self.loaded.borrow().get(name) {
            return v.clone();
        }
        let by_name = self.by_name.get_or_init(|| {
            let mut m: HashMap<u64, Vec<usize>> = HashMap::new();
            for (i, fa) in self.facts.iter().enumerate() {
                for (h, _) in &fa.names {
                    let e = m.entry(*h).or_default();
                    if e.last() != Some(&i) {
                        e.push(i);
                    }
                }
            }
            m
        });
        let mut out: Vec<Proc> = Vec::new();
        for &i in by_name.get(&nh).map(|v| v.as_slice()).unwrap_or(&[]) {
            let rel = &self.files[i].rel;
            if let Some(f) = self.tree.get(rel) {
                out.extend(procs_in(f).into_iter().filter(|p| p.name == name));
            }
        }
        let rc = Rc::new(out);
        self.loaded.borrow_mut().insert(name.to_string(), rc.clone());
        rc
    }
}

// Only the original compatibility entry owns a legacy Tree and disk cache.
struct LegacyC2Source<'b,'a>{tree:&'b Tree,helpers:&'b Helpers<'a>}
impl crate::ui_actions_c2::Sources<crate::key_policy_control::Compatibility> for LegacyC2Source<'_,'_>{
 fn named(&self,name:&str,_:&mut crate::key_policy_control::Compatibility)->Result<Rc<Vec<Proc>>,std::convert::Infallible>{Ok(self.helpers.named(name))}
 fn lines(&self,proc:&Proc,c:&mut crate::key_policy_control::Compatibility,visit:&mut dyn FnMut(usize,&str,&mut crate::key_policy_control::Compatibility)->Result<bool,std::convert::Infallible>)->Result<(),std::convert::Infallible>{for(number,text)in proc.lines(self.tree){if !visit(number,text,c)?{break}}Ok(())}
}

#[derive(Serialize, Deserialize, Clone)]
struct C2Entry {
    deps: Vec<(u64, u128)>,
    off: Option<u32>,
}

/// The persistent C2 answers (`old`), the group hashes that validate them, and what this run used.
struct C2Cache {
    old: HashMap<u128, C2Entry>,
    groups: HashMap<u64, u128>,
    used: RefCell<HashMap<u128, C2Entry>>,
}

#[derive(Serialize, Deserialize, Default)]
struct C2File {
    stamp: String,
    map: HashMap<u128, C2Entry>,
}

fn c2_path() -> Option<std::path::PathBuf> {
    incr::dir().map(|d| d.join("incr-ui_actions-c2.bin"))
}

fn c2_load() -> HashMap<u128, C2Entry> {
    let (Some(path), Some(stamp)) = (c2_path(), incr::stamp()) else { return HashMap::new() };
    match std::fs::read(&path).ok().and_then(|b| bincode::deserialize::<C2File>(&b).ok()) {
        Some(f) if f.stamp == stamp => f.map,
        _ => HashMap::new(),
    }
}

fn c2_save(old_len: usize, cache: &C2Cache) {
    let (Some(path), Some(stamp)) = (c2_path(), incr::stamp()) else { return };
    let used = cache.used.borrow();
    let unchanged = used.len() == old_len && used.keys().all(|k| cache.old.contains_key(k));
    if unchanged {
        return;
    }
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(bytes) = bincode::serialize(&C2File { stamp, map: used.clone() }) {
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() {
            let _ = std::fs::rename(&tmp, &path);
        } else {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

/// Group hash per proc name: every proc of that name folded in file order.
fn group_hashes(facts: &[DmFacts]) -> HashMap<u64, u128> {
    let mut g: HashMap<u64, u128> = HashMap::new();
    for fa in facts {
        for (nh, ph) in &fa.names {
            g.entry(*nh).and_modify(|h| *h = (h.rotate_left(17) ^ ph).wrapping_mul(0x9E37_79B9_7F4A_7C15_F39C_C060_5CED_C835)).or_insert(*ph);
        }
    }
    g
}

impl<'a> Analysis<'a> {
    fn proc(&self, n: usize) -> &Proc {
        &self.hosts.procs[n]
    }

    fn checks(&self)->crate::ui_actions_check::Checks<'_>{crate::ui_actions_check::Checks{hosts:self.hosts,norm:self.norm,acts:self.acts}}
    fn check(&self)->Vec<(String,usize,String)>{compat(self.checks().check(&mut crate::key_policy_control::Compatibility))}
    fn ui_procs(&self)->Vec<usize>{compat(self.checks().ui_procs(&mut crate::key_policy_control::Compatibility))}
    fn unsent_params(&self,procs:&[usize])->Vec<(usize,String)>{compat(self.checks().unsent_params(procs,&mut crate::key_policy_control::Compatibility))}

    fn first_bad_use(&self,proc:&Proc,param:&str,depth:usize)->Option<usize>{let source=LegacyC2Source{tree:self.tree,helpers:self.helpers};let view=crate::ui_actions_c2::FirstUse{source:&source,pats:&self.pats};match view.first_bad_use(proc,param,depth,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}

    /// `first_bad_use(proc, param, 0)` through the persistent cache: an entry is the answer plus the
    /// proc-name groups the evaluation looked up (helpers), valid while the root proc and each such
    /// group (every proc of that name, in file order) hash the same.
    fn cached_bad_use(&self, n: usize, proc: &Proc, param: &str) -> Option<usize> {
        let Some(cache) = &self.c2 else { return self.first_bad_use(proc, param, 0) };
        let root = self.hosts.hashes[n];
        let key = incr::mix(&[root, incr::ctx_key(param)]);
        if let Some(e) = cache.old.get(&key) {
            if e.deps.iter().all(|(nh, gh)| cache.groups.get(nh).copied().unwrap_or(0) == *gh) {
                cache.used.borrow_mut().insert(key, e.clone());
                return e.off.map(|o| proc.body_start + o as usize);
            }
        }
        self.helpers.begin();
        let got = self.first_bad_use(proc, param, 0);
        let deps: Vec<(u64, u128)> = self.helpers.end().into_iter().map(|nh| (nh, cache.groups.get(&nh).copied().unwrap_or(0))).collect();
        let off = got.map(|l| (l - proc.body_start) as u32);
        cache.used.borrow_mut().insert(key, C2Entry { deps, off });
        got
    }

    fn unvalidated_params(&self,procs:&[usize])->Vec<(usize,String,usize)>{compat(self.checks().unvalidated_params(procs,&mut crate::key_policy_control::Compatibility,&mut|n,proc,param,_|Ok(self.cached_bad_use(n,proc,param))))}

    /// `dx_sites`: `(C1 sites, C2 sites)`, each `(rel, line)`, ALLOW honoured through `allowed`.
    fn dx_sites(&self, allowed: &mut dyn FnMut(&str, usize) -> bool) -> (Vec<(String, usize)>, Vec<(String, usize)>) {
        let procs = self.ui_procs();
        let mut unsent = Vec::new();
        let mut unvalidated = Vec::new();
        for (n, _param) in self.unsent_params(&procs) {
            let p = self.proc(n);
            if !allowed(&p.rel, p.line) {
                unsent.push((p.rel.clone(), p.line));
            }
        }
        for (n, _param, line) in self.unvalidated_params(&procs) {
            let p = self.proc(n);
            if !allowed(&p.rel, line) {
                unvalidated.push((p.rel.clone(), line));
            }
        }
        (unsent, unvalidated)
    }
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct TsxFacts {
    calls: Vec<RawCall>,
}

struct UiActions;

impl Lint for UiActions {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let dm: Vec<&SourceFile> = files.iter().copied().filter(|f| f.ext() == "dm").collect();
        let Some(dispatcher) = cx.tree.get(DISPATCHER) else { return };
        let norm = match normaliser_from(dispatcher.text()) {
            Ok(n) => n,
            Err(msg) => {
                out.note(msg.clone());
                out.site_in_msg(R_PROBLEM, DISPATCHER, 1, msg);
                return;
            }
        };
        // TSX act() calls: per file, cached by content.
        let tsx_files: Vec<&SourceFile> =
            files.iter().copied().filter(|f| matches!(f.ext(), "tsx" | "ts" | "jsx" | "js") && !f.rel.ends_with(".d.ts")).collect();
        let tsx_facts = incr::facts("ui_actions-tsx", &tsx_files, |f| TsxFacts { calls: tsx_calls(f.text()) });
        let tsx: Vec<(String, Vec<Call>)> = tsx_files
            .iter()
            .zip(&tsx_facts)
            .map(|(f, fa)| (f.rel.clone(), fa.calls.iter().map(|c| Call::new(&f.rel, c, &norm)).collect()))
            .collect();
        let acts = Acts::real(tsx);
        // DM hosts and procs: per file, cached by content.
        let facts = incr::facts("ui_actions-dm", &dm, dm_facts);
        let hosts = Hosts::new(&dm, &facts);
        let helpers = Helpers::new(cx.tree, &dm, &facts);
        let old = c2_load();
        let old_len = old.len();
        let c2 = C2Cache { old, groups: group_hashes(&facts), used: RefCell::new(HashMap::new()) };
        let an = Analysis {
            tree: cx.tree,
            hosts: &hosts,
            norm: &norm,
            acts: &acts,
            pats: RefCell::new(HashMap::new()),
            helpers: &helpers,
            c2: Some(&c2),
        };
        let by_rel: HashMap<&str, usize> = dm.iter().enumerate().map(|(i, f)| (f.rel.as_str(), i)).collect();
        let (unsent, unvalidated) = an.dx_sites(&mut |rel, line| {
            let Some(&i) = by_rel.get(rel) else { return false };
            match facts[i].kept.iter().find(|k| k.0 as usize == line) {
                Some((_, at, code)) => {
                    let u = crate::lint::AllowUse { rel: rel.to_string(), line: *at, name: "ui_actions".to_string(), code: code.clone() };
                    if !out.allow_used.contains(&u) {
                        out.allow_used.push(u);
                    }
                    true
                }
                None => false,
            }
        });
        c2_save(old_len, &c2);
        let problems = an.check();
        for (rel, line) in unsent {
            out.site_in(R_UNSENT, &rel, line);
        }
        for (rel, line) in unvalidated {
            out.site_in(R_UNVALIDATED, &rel, line);
        }
        out.note(format!("ui_actions_lint: {} problem(s)", problems.len()));
        for (rel, line, msg) in problems {
            out.site_in_msg(R_PROBLEM, &rel, line, msg);
        }
    }

    fn selftest(&self) -> Result<String, String> {
        selftest().map(|_| "ui_actions_lint selftest ok".to_string())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/ui_actions_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLine,
            update: Some(&["tools/ci/ui_actions_lint.py", "--update"]),
            seed: Some(&["tools/ci/ui_actions_lint.py", "--seed"]),
            files: &[],
            selftest: Some(&["tools/ci/ui_actions_lint.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(UiActions);
}

// ---- selftest ---------------------------------------------------------------------------------

use crate::ui_selftest_policy::{DISPATCHER_FIXTURE,DM_FIXTURE,BUNDLE_FIXTURE,TSX_FIXTURE};

fn ensure(cond: bool, what: impl FnOnce() -> String) -> Result<(), String> {
    if cond {
        Ok(())
    } else {
        Err(what())
    }
}

fn selftest() -> Result<(), String> {
    let error=|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(error)=>error.to_string()};
    let mut control=crate::derived_selftest_policy::LegacyAssertions;
    let norm=crate::ui_selftest_policy::normalizer(&mut control).map_err(error)?;
    let manifest=std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut live=None;
    for candidate in [std::path::PathBuf::from(DISPATCHER),manifest.join("../..").join(DISPATCHER)]{if let Ok(text)=std::fs::read_to_string(candidate){live=Some(text);break;}}
    crate::ui_selftest_policy::live(live.as_deref(),&mut control).map_err(error)?;
    let calls=crate::ui_selftest_policy::calls(&mut control).map_err(error)?;
    let caps_rel = format!("{}library/fixture.dm", CAPS_DIR);
    let tree = Tree::from_files(vec![SourceFile::from_text("x.dm", DM_FIXTURE), SourceFile::from_text(&caps_rel, BUNDLE_FIXTURE)]);
    let files: Vec<&SourceFile> = tree.files.iter().collect();
    let facts: Vec<DmFacts> = files.iter().map(|f| dm_facts(f)).collect();
    let hosts = Hosts::new(&files, &facts);
    let helpers = Helpers::new(&tree, &files, &facts);
    let table = vec![
        ("Thing".to_string(), calls.iter().map(|c| Call::new("x.tsx", c, &norm)).collect::<Vec<_>>()),
        ("Old".to_string(), vec![Call::new("o.tsx", &RawCall { line: 1, action: "nope".to_string(), keys: Some(vec![]) }, &norm)]),
    ];
    let acts = Acts::fixed(table);
    let an = Analysis { tree: &tree, hosts: &hosts, norm: &norm, acts: &acts, pats: RefCell::new(HashMap::new()), helpers: &helpers, c2: None };
    let problems = an.check();
    let breaker=||hosts.actions_of("/obj/thing").contains_key("breaker")&&hosts.caps_of("/obj/thing")==BTreeSet::from(["/datum/capability/breakers".to_string()]);
    crate::ui_selftest_policy::problems(problems.iter().map(|row|row.2.as_str()),breaker,&mut control).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(error)=>error.to_string()})?;
    let(unsent,unvalidated)=an.dx_sites(&mut|_,_|false);
    crate::ui_selftest_policy::dx_rows(unsent.iter().map(|row|row.1),unvalidated.iter().map(|row|row.1),&mut control).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(error)=>error.to_string()})?;
    Ok(())
}

fn compat<T>(value:Result<T,std::convert::Infallible>)->T{match value{Ok(value)=>value,Err(never)=>match never{}}}
