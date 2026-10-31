//! `analyze gen auto_tracked` -> `code/engine/_generated/auto_tracked.dm`: read-driven tracking (doc/rewrite/final_api.html section 7,
//! "Reactive closure", mechanism 1).
//!
//! A var that reactive code reads is tracked without anyone declaring it. Reactive code is what the dependency analysis walks
//! (`gens::deps`): a stat's contributions, conditions, requirements and formulas, a draw(), an every() gate, a Life step's `woken_by`,
//! an on_change consumer, a derived value. Every `(type, var)` those read off the holder (or across a declared relation) that no
//! declaration already makes reactive (tracked, a relation, a stat, a derived value) and that something writes is written here as the
//! `TRACKED(T, v)` the author would have written:
//!
//! ```text
//! TRACKED(/mob/living/carbon/human, w_uniform)   ->   /mob/living/carbon/human/proc/set_w_uniform(value)
//! ```
//!
//! so the setter has the semantics of every other tracked var (`TRACKED_UNCHANGED` compare, publish through `tracked_changed`, a list
//! gets the generated `add_v` / `remove_v` / ... of `gens::tracked_lists`) and the `tracked` lint holds every write of it to that setter;
//! `analyze fix` rewrites `v = x`, `src.v = x` and `O.v = x` to the setter call.
//!
//! The inference never reads its own output, so it is stable: it judges "is this var already reactive" from the declarations a person
//! wrote (`Decls::tracked_explicit`: TRACKED, SETTER and the other declaration forms outside this file) and not from the file it writes. A var stays here while
//! a consumer reads it, or while a call `set_v(...)` exists in the tree (a call written by `analyze fix` must keep compiling after the
//! last reader goes). A var is left alone (and listed in `blocked`) when a proc named `set_v` already exists on its type, an ancestor or a
//! subtype without being its registered setter, or when it cannot take a generated setter: a built-in var, a `static` / `const` var, a
//! var of a type that is not a /datum.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::Arc;

use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::sem::reads::ReadsEngine;
use crate::tree::{Tree, CODE_DM};
use dreammaker::ast::{Expression, Follow, Term};

/// The file `analyze gen auto_tracked` writes.
pub const AUTO_REL: &str = "code/engine/_generated/auto_tracked.dm";

/// Names a generated setter must never shadow: the macro parameter and DM keywords.
const RESERVED: &[&str] = &["value", "src", "usr", "null", "world"];

/// Suffix of a `set_calls` entry that records a list mutator call (`add_V(`, `remove_V(`, `set_V_at(`, ...) instead of `set_V(`.
/// The file `gens::tracked_lists` writes: the list mutators it declares are the generator's own, not a clash.
const TRACKED_LISTS_REL: &str = "code/engine/_generated/tracked_lists.dm";

const LIST_CALL: &str = "[]";

/// The var names `V` of every call `set_V(...)` in the tree (a definition, `proc/set_V(` or a type-path `/t/set_V(` at column 0, is not a call).
pub fn set_calls(tree: &Tree) -> Arc<BTreeSet<String>> {
    tree.memo("gen/auto-set-calls", || {
        let files = tree.select(&CODE_DM);
        let facts: Vec<Vec<String>> = crate::incr::facts("auto-tracked-set-calls", &files, |f| {
            crate::auto_setter_calls_policy::collect_file(&mut crate::key_policy_control::Compatibility, &f.rel, f.text(), || &f.code().text).unwrap()
        });
        facts.into_iter().flatten().collect()
    })
}

/// Whether a declaration a person wrote already makes `owner.var` reactive.
fn declared_reactive(eng: &ReadsEngine, owner: &str, var: &str) -> bool {
    let mut cur = Some(owner.to_string());
    let mut guard = 0;
    while let Some(t) = cur {
        if eng.decls.tracked_explicit.get(&t).map(|s| s.contains(var)).unwrap_or(false) {
            return true;
        }
        guard += 1;
        if guard > 64 {
            break;
        }
        cur = eng.sem.parent_of(&t).filter(|p| p != &t && p != "/");
    }
    eng.is_relation(owner, var) || eng.is_stat(owner, var) || eng.is_derived(owner, var)
}

/// The var names some proc writes, not counting a setter's write of its own var (`set_v` writing `v`: the TRACKED() macro's body, and the one line of
/// every hand-written setter): a var written only there is written by nobody who could be asked to publish.
pub fn writes_outside_setters(sem: &crate::sem::Sem) -> crate::sem::reads::WriteIndex {
    // The generated setters and list mutators write the vars they are generated for: counting them would keep a var tracked because it was tracked.
    let procs: Vec<dreammaker::objtree::ProcRef> = sem.objtree.iter_types().flat_map(|t| t.iter_self_procs().collect::<Vec<_>>()).filter(|p| !p.is_builtin() && !matches!(sem.file_of(p.get().location), Some(AUTO_REL) | Some(TRACKED_LISTS_REL))).collect();
    // Per proc, kept between runs by file (`body_facts`); sorted, as the facts are digested. The writes carry the type that declares the var (`reads::WriteIndex`).
    let fact = |p: dreammaker::objtree::ProcRef| -> Vec<(String, String)> {
        let mut w = crate::sem::reads::typed_writes(sem, p);
        if let Some(v) = p.name().strip_prefix("set_") {
            w.retain(|(_, var)| var != v);
        }
        w
    };
    crate::sem::body_facts::indexed(sem, "writes-outside-setters-typed", sem.structure_digest(), &procs, fact, crate::sem::reads::WriteIndex::from_facts)
}

/// `writes_outside_setters`, computed once per tree.
pub fn writes_outside_setters_of(tree: &Tree, sem: &crate::sem::Sem) -> Arc<crate::sem::reads::WriteIndex> {
    tree.memo("gen/writes-outside-setters", || writes_outside_setters(sem))
}

/// A var named in a CAPABILITIES block: tracked unless a declaration already makes it reactive, or it is constant.
struct LegacyCandidate<'a,'s>{eng:&'a ReadsEngine<'s>,written:Option<&'a crate::sem::reads::WriteIndex>}
impl crate::key_policy_control::Control for LegacyCandidate<'_,'_>{type Error=std::convert::Infallible;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn overflow(&mut self)->Self::Error{unreachable!("legacy allocation path")}fn allocation_failed(&mut self)->Self::Error{unreachable!("legacy allocation path")}}
impl crate::auto_tracking_policy::Source for LegacyCandidate<'_,'_>{
 fn variable(&mut self,owner:&str,var:&str)->Result<Option<crate::auto_tracking_policy::Variable>,Self::Error>{Ok(self.eng.sem.var_decl(owner,var).map(|v|{let is_list=v.is_list();crate::auto_tracking_policy::Variable{file:v.file,is_static:v.is_static,is_const:v.is_const,is_list}}))}
 fn subtype(&mut self,a:&str,b:&str)->Result<bool,Self::Error>{Ok(self.eng.sem.is_subtype(a,b))}
 fn var_owner(&mut self,o:&str,v:&str)->Result<Option<String>,Self::Error>{Ok(self.eng.sem.var_owner(o,v))}
}
impl crate::auto_tracking_policy::ReactiveSource for LegacyCandidate<'_,'_>{fn declared_reactive(&mut self,o:&str,v:&str)->Result<bool,Self::Error>{Ok(declared_reactive(self.eng,o,v))}}
impl crate::auto_tracking_policy::CandidateSource for LegacyCandidate<'_,'_>{
 fn outside_written_on(&mut self,o:&str,v:&str)->Result<bool,Self::Error>{Ok(self.written.expect("candidate requires actual outside-setter writes").is_written_on(self.eng.sem,o,v))}
}
pub fn named_candidate(eng:&ReadsEngine,owner:&str,var:&str)->bool{crate::auto_tracking_policy::named_candidate(&mut LegacyCandidate{eng,written:None},owner,var).unwrap()}
pub fn candidate(eng:&ReadsEngine,written:&crate::sem::reads::WriteIndex,calls:&BTreeSet<String>,owner:&str,var:&str)->bool{crate::auto_tracking_policy::candidate(&mut LegacyCandidate{eng,written:Some(written)},calls,owner,var).unwrap()}

/// The `(declaring type, var)` pairs a `set_v(` / `add_v(` call in the tree names, whether or not reactive code reads them: the transition set.
/// A var is tracked when something reads it (`candidate` over the read set) or when it is written through its setter. The second kind is what the
/// dropped `TRACKED(T, v)` lines become: a var nobody walked reads is still published for what asks at run time (`on_change`, a Life step's
/// `woken_by`, an observer, a VV edit), and the calls `analyze fix` wrote have to keep compiling when the last static reader goes. Only the
/// declaring type of a var is a candidate (a subtype reads the same var), and `decide` drops the ones a hand-written `set_v` already covers.
pub fn called_candidates(tree: &Tree, sem: &crate::sem::Sem, eng: &ReadsEngine, written: &crate::sem::reads::WriteIndex, calls: &BTreeSet<String>) -> BTreeSet<(String, String)> {
    let defs = setter_defs(tree, sem);
    let mut out = BTreeSet::new();
    for t in sem.objtree.iter_types() {
        let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        for (name, v) in &t.get().vars {
            if v.declaration.is_none() {
                continue;
            }
            if let Ok(want) = std::env::var("DQ_AUTO_DEBUG") {
                if *name == want {
                    eprintln!("auto_tracked debug typed: {:?} calls: {} {}", typed_set_calls(tree).get(&format!("remove_{want}")).or(typed_set_calls(tree).get(&format!("add_{want}"))), calls.contains(want.as_str()), calls.contains(&format!("{want}[]")));
                    eprintln!("auto_tracked debug: {}.{} called_here={} candidate={} declared_reactive={}", path, name, called_here(tree, sem, &defs, calls, &path, name), candidate(eng, written, calls, &path, name), declared_reactive(eng, &path, name));
                }
            }
            if called_here(tree, sem, &defs, calls, &path, name) && candidate(eng, written, calls, &path, name) {
                out.insert((path.clone(), name.clone()));
            }
        }
    }
    out
}

/// The receiver of a setter-shaped call that `typed_set_calls` could not type.
pub const UNTYPED: &str = "?";

/// Whether some call of `set_v` / a list mutator of `v` has a receiver the scan could not type: it may be this var's setter, whatever the typed calls say.
pub fn untyped_call(tree: &Tree, var: &str) -> bool {
    let typed = typed_set_calls(tree);
    setter_names(var).iter().any(|n| typed.get(n).is_some_and(|t| t.contains(UNTYPED)))
}

fn setter_names(var: &str) -> [String; 9] {
    [format!("set_{var}"), format!("add_{var}"), format!("include_{var}"), format!("remove_{var}"), format!("set_{var}_at"), format!("clear_{var}"), format!("insert_{var}"), format!("swap_{var}"), format!("cut_{var}")]
}

struct LegacyTypedCalls<'a,'h>{sem:&'a crate::sem::Sem,hits:&'h mut Vec<(String,String)>}
impl crate::key_policy_control::Control for LegacyTypedCalls<'_,'_>{type Error=std::convert::Infallible;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn overflow(&mut self)->Self::Error{unreachable!("legacy allocation")}fn allocation_failed(&mut self)->Self::Error{unreachable!("legacy allocation")}}
impl crate::typed_set_calls_policy::Source for LegacyTypedCalls<'_,'_>{fn variable_type(&mut self,owner:&str,name:&str)->Result<Option<String>,Self::Error>{Ok(self.sem.var_decl(owner,name).map(|v|v.declared))}fn record(&mut self,name:&str,receiver:&str)->Result<(),Self::Error>{self.hits.push((name.to_owned(),receiver.to_owned()));Ok(())}}

/// The static type of each receiver of a setter-shaped call (`set_*`, `add_*`, ... ) in the tree, by call name: an unqualified call and `src.` are the
/// proc's own type, `X.set_v()` is the declared type of the proc's parameter or local `X`, or of the var `X` of the proc's type, followed through
/// `a.b.c` field hops. A receiver it cannot type is not recorded. Names are flat per proc (the last declaration of a name wins).
pub fn typed_set_calls(tree: &Tree) -> Arc<HashMap<String, BTreeSet<String>>> {
    tree.memo("gen/typed-set-calls", || {
        let mut out: HashMap<String, BTreeSet<String>> = HashMap::new();
        let Some(sem) = crate::sem::sem_for(tree) else { return out };
        let mut work: Vec<(String, dreammaker::objtree::ProcRef)> = Vec::new();
        for t in sem.objtree.iter_types() {
            let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
            for p in t.iter_self_procs() {
                if p.is_builtin() {
                    continue;
                }
                let rel = p.get().location;
                if matches!(sem.file_of(rel), Some(AUTO_REL) | Some(TRACKED_LISTS_REL)) {
                    continue;
                }
                work.push((path.clone(), p));
            }
        }
        // Per proc, kept between runs by file (`body_facts`): a hit reads the body and the declared types of vars (the structure).
        let refs: Vec<dreammaker::objtree::ProcRef> = work.iter().map(|(_, p)| *p).collect();
        let fact = |p: dreammaker::objtree::ProcRef| -> Vec<(String, String)> {
            let owner = if p.ty().get().path.is_empty() { "/".to_string() } else { p.ty().get().path.clone() };
            let owner = &owner;
            let mut hits: Vec<(String, String)> = Vec::new();
            let Some(code) = &*p.get().code else { return hits };
            let mut locals: HashMap<String, String> = HashMap::new();
            for prm in p.get().parameters.iter() {
                if !prm.var_type.type_path.is_empty() {
                    locals.insert(prm.name.clone(), format!("/{}", prm.var_type.type_path.join("/")));
                }
            }
            collect_local_types(code, &mut locals);
            let mut source=LegacyTypedCalls{sem:&sem,hits:&mut hits};
            crate::sem::ast::walk_block(code,&mut|e,_|{
                use crate::typed_set_calls_policy as policy;
                let Expression::Base{term,follow}=e else{return};
                let base=match &term.elem{Term::Ident(name)=>policy::Base::Ident(name),Term::Call(name,_)=>policy::Base::Call(name.as_str()),_=>policy::Base::Unknown};
                let mut current=policy::begin(&mut source,owner,&locals,base).unwrap();
                for item in follow.iter(){match &item.elem{
                    Follow::Field(_,name)=>current=policy::field(&mut source,current,name.as_str()).unwrap(),
                    Follow::Call(_,name,_)=>{policy::call(&mut source,&current,name.as_str(),None).unwrap();current=None},
                    _=>current=None,
                }}
            });
            drop(source);
            hits
        };
        crate::sem::body_facts::indexed(&sem, "typed-set-calls", sem.structure_digest(), &refs, fact, |found: Vec<Vec<(String, String)>>| {
            for (n, t) in found.into_iter().flatten() {
                out.entry(n).or_default().insert(t);
            }
            out
        })
    })
}

fn collect_local_types(b: &dreammaker::ast::Block, out: &mut HashMap<String, String>) {
    use dreammaker::ast::Statement;
    for st in b.iter() {
        match &st.elem {
            Statement::Var(vs) if !vs.var_type.type_path.is_empty() => {
                out.insert(vs.name.clone(), format!("/{}", vs.var_type.type_path.join("/")));
            }
            Statement::Vars(list) => {
                for vs in list.iter().filter(|v| !v.var_type.type_path.is_empty()) {
                    out.insert(vs.name.clone(), format!("/{}", vs.var_type.type_path.join("/")));
                }
            }
            Statement::ForList(fl) => {
                if let Some(vt) = fl.var_type.as_ref().filter(|v| !v.type_path.is_empty()) {
                    out.insert(fl.name.as_str().to_string(), format!("/{}", vt.type_path.join("/")));
                }
            }
            _ => {}
        }
        for nb in crate::sem::ast::stmt_blocks(&st.elem) {
            collect_local_types(nb, out);
        }
    }
}

/// Whether a `set_v(` / `add_v(` call in the tree can be a call of `owner.v`'s setter. The calls are collected by name, so a name another type owns a
/// hand-written setter for (`set_active`, `set_id`) says nothing about this var by itself. Calls with a typed receiver decide it when there are any
/// (`typed_set_calls`: a type related to `owner` receives one); when none is typed, the name is enough if every non-generated definition of `set_v` /
/// its list mutators is on a type related to `owner`.
pub fn called_here(tree:&Tree,sem:&crate::sem::Sem,defs:&HashMap<String,Vec<String>>,calls:&BTreeSet<String>,owner:&str,var:&str)->bool{
 crate::auto_tracking_policy::called_here(&mut LegacyDecision{sem},defs,||Ok(typed_set_calls(tree)),calls,owner,var).unwrap()
}

pub use crate::auto_tracking_policy::{Auto,AutoSet};

/// Whether a proc definition at `loc` is the expansion of a `TRACKED(T, v)` line (the macro writes `set_v` at the line of its invocation): that is
/// the declaration the generator replaces, not a hand-written proc it would clash with.
fn from_tracked_macro(tree: &Tree, sem: &crate::sem::Sem, loc: dreammaker::Location) -> bool {
    let Some(rel) = sem.file_of(loc) else { return false };
    let Some(f) = tree.get(rel) else { return false };
    f.raw().lines().nth((loc.line as usize).saturating_sub(1)).is_some_and(|l| {
        let t = l.trim_start();
        t.starts_with("TRACKED(") || t.starts_with("TRACKED_BRIDGED(")
    })
}

/// Every `set_*` proc defined outside the generated file, by name: the types that define it.
pub fn setter_defs(tree: &Tree, sem: &crate::sem::Sem) -> HashMap<String, Vec<String>> {
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for t in sem.objtree.iter_types() {
        let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        for (name, p) in &t.get().procs {
            if !["set_", "add_", "include_", "remove_", "clear_", "insert_", "swap_", "cut_"].iter().any(|p| name.starts_with(p)) {
                continue;
            }
            if p.declaration.is_some() && p.value.iter().any(|v| sem.file_of(v.location) != Some(AUTO_REL) && sem.file_of(v.location) != Some(TRACKED_LISTS_REL) && !from_tracked_macro(tree, sem, v.location)) {
                out.entry(name.clone()).or_default().push(path.clone());
            }
        }
    }
    out
}

/// The vars of `candidates` the generator can give a setter, and the ones it cannot (with why).
struct LegacyDecision<'a>{sem:&'a crate::sem::Sem}
impl crate::key_policy_control::Control for LegacyDecision<'_>{type Error=std::convert::Infallible;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn overflow(&mut self)->Self::Error{unreachable!("legacy allocation path")}fn allocation_failed(&mut self)->Self::Error{unreachable!("legacy allocation path")}}
impl crate::auto_tracking_policy::Source for LegacyDecision<'_>{
 fn variable(&mut self,owner:&str,var:&str)->Result<Option<crate::auto_tracking_policy::Variable>,Self::Error>{Ok(self.sem.var_decl(owner,var).map(|v|{let is_list=v.is_list();crate::auto_tracking_policy::Variable{file:v.file,is_static:v.is_static,is_const:v.is_const,is_list}}))}
 fn subtype(&mut self,child:&str,parent:&str)->Result<bool,Self::Error>{Ok(self.sem.is_subtype(child,parent))}
 fn var_owner(&mut self,owner:&str,var:&str)->Result<Option<String>,Self::Error>{Ok(self.sem.var_owner(owner,var))}
}
pub fn decide(tree:&Tree,sem:&crate::sem::Sem,candidates:&BTreeSet<(String,String)>,exclude:&[String])->AutoSet{
 let defs=setter_defs(tree,sem);crate::auto_tracking_policy::decide(&mut LegacyDecision{sem},&defs,candidates,exclude).unwrap()
}

/// The inference for a tree (memoized: the generator, the lints and `analyze fix` share it).
pub fn inferred(tree: &Tree) -> Arc<Option<AutoSet>> {
    tree.memo("gen/auto-tracked", || {
        let an = super::deps::analyzed(tree);
        let an = an.as_ref().as_ref()?;
        let sem = crate::sem::sem_for(tree)?;
        let scopes = crate::scopes::Scopes::load(&tree.root.join("tools/ci/lint_scopes.toml")).unwrap_or_default();
        let scope = scopes.for_lint("auto_tracked", "");
        let exclude: Vec<String> = scope.list("exclude").iter().chain(scope.list("exclude_fixtures")).chain(scope.list("exclude_heat")).chain(scope.list("exclude_memo")).cloned().collect();
        // Vars whose setter calls reach them through an accessor the call scan cannot type (`connected().set_locked(...)`): named by hand.
        let mut candidates = an.candidates.clone();
        for entry in scope.list("include") {
            if let Some((ty, var)) = entry.split_once("::") {
                candidates.insert((ty.to_string(), var.to_string()));
            }
        }
        Some(decide(tree, &sem, &candidates, &exclude))
    })
}

struct AutoTracked;

impl Generator for AutoTracked {
    fn name(&self) -> &'static str {
        "auto_tracked"
    }

    fn stage(&self) -> u8 {
        0
    }

    fn output(&self) -> &'static str {
        "auto_tracked.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let mut documents=crate::sparse_slots_policy::Output::default();
        crate::auto_tracking_emitter::documents(&mut documents);append_policy_output(out,documents);
        let inf = inferred(cx.tree);
        let Some(set) = inf.as_ref().as_ref() else {
            out.diag("deepquarry.dme", 1, "the semantic model could not be built; read-driven tracking cannot be generated");
            return;
        };
        if std::env::var("DQ_AUTO_REPORT").is_ok() {
            eprintln!("auto_tracked: {} tracked ({} lists), {} blocked", set.tracked.len(), set.tracked.iter().filter(|a| a.list).count(), set.blocked.len());
            for (t, v, why) in &set.blocked {
                eprintln!("auto_tracked: blocked {}.{}: {}", t, v, why);
            }
            // A write through a receiver the scan could not type counts for every var of that name: these are the names whose tracking rests on one.
            if let Some(sem) = crate::sem::sem_for(cx.tree) {
                let writes = writes_outside_setters_of(cx.tree, &sem);
                for a in &set.tracked {
                    if writes.untyped().contains(&a.var) {
                        eprintln!("auto_tracked: untyped writer: {}.{} is written through a receiver that could not be typed", a.ty, a.var);
                    }
                }
            }
        }
        let tests = crate::sem::gen::test_only_types(cx.tree);
        let mut rendered=crate::sparse_slots_policy::Output::default();
        crate::auto_tracking_emitter::emit_rows(set,&tests,&mut rendered);append_policy_output(out,rendered);
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(AutoTracked));
}

/// Nominal legacy GenOut bridge; shared policy keeps the unique template.
fn append_policy_output(out:&mut GenOut,rendered:crate::sparse_slots_policy::Output){for line in rendered.body.split_terminator('\n'){out.line(line);}for diagnostic in rendered.diags{out.diag(&diagnostic.rel,diagnostic.line,diagnostic.msg);}}
