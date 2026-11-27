//! DreamChecker on the compiler front end's own tree (doc/rewrite/proposals/lean_unified.md, "2b DREAMCHECKER").
//!
//! The checks are SpacemanDMM DreamChecker's, read off dmbc's semantic tree and typed bodies instead of a SpacemanDMM object tree:
//! the [`model`] holds BYOND's builtins and the project's declarations, [`walk`] checks one body, and this module runs the passes
//! in DreamChecker's order: var definitions, proc settings, bodies, override validity, the call tree.
//!
//! Shape for incremental storage: a proc's settings ([`settings_of`]) read only its own leading `set` statements and declaration;
//! its body facts ([`walk::Walk::run`] into [`walk::ProcFacts`]) read its body, the model and the settings table; the call-tree
//! passes ([`CallTables`]) read only the per-proc facts. Each per-proc result is keyed by the proc's identity ([`model::ProcId`]:
//! type, name, definition index) and is a pure function of those inputs.
pub mod analysis;
pub mod builtins;
pub mod directives;
pub mod facts;
pub mod input;
pub mod model;
mod switch_rand;
pub mod type_expr;
pub mod view;
pub mod walk;

use std::collections::{BTreeMap, VecDeque};

use dm::{Context, DMError, Location, Severity};
use dm_syntax::{Statement, StatementKind};
use foldhash::{HashMap, HashMapExt, HashSet, HashSetExt};

use analysis::StaticType;
use directives::{error, Directives, ProcDirective, KNOWN_SETTING_NAMES};
use facts::{Diag, SettingEvent, SettingsFacts};
use input::{CheckerInput, Site, Sites, Where};
use model::{Model, ProcId};
use type_expr::TypeExpr;
use view::{Reader, Shape, Term};
use walk::{ProcFacts, Shared, Walk};

macro_rules! cli_println {
    ($cli:expr, $($rest:tt)*) => {
        if $cli { dq_hostio::out(true, format_args!($($rest)*), true) }
    }
}

/// Examines the model for var definitions that are invalid (a redeclaration, an override of a final or private var).
pub fn check_var_defs(m: &Model, context: &Context, site: &dyn Site) {
    for t in m.type_ids() {
        let ty = m.ty(t);
        let path = &ty.path;
        let mut parent = Some(t);
        while let Some(p) = parent {
            let pt = m.ty(p);
            if pt.is_root() {
                break;
            }
            parent = m.parent_type(p);
            if &pt.path == path {
                continue;
            }
            for (varname, typevar) in ty.vars.iter() {
                if varname == "vars" || (path == "/client" && varname == "parent_type") {
                    continue;
                }
                let Some(parentvar) = pt.var(varname) else { continue };
                let Some(decl) = &parentvar.declaration else { continue };
                if let Some(mydecl) = &typevar.declaration {
                    if matches!(typevar.value_location, Where::Fixed(l) if l.is_builtins()) {
                        continue;
                    }
                    DMError::new(site.place(mydecl.location), format!("{path} redeclares var {varname:?}"))
                        .with_note(site.place(decl.location), format!("declared on {} here", pt.path))
                        .register(context);
                }
                if decl.flags.is_final() {
                    DMError::new(site.place(typevar.value_location), format!("{path} overrides final var {varname:?}"))
                        .with_errortype("final_var")
                        .with_note(site.place(decl.location), format!("declared final on {} here", pt.path))
                        .register(context);
                }
                if decl.flags.is_private() {
                    DMError::new(site.place(typevar.value_location), format!("{path} overrides private var {varname:?}"))
                        .with_errortype("private_var")
                        .with_note(site.place(decl.location), format!("declared private on {} here", pt.path))
                        .register(context);
                }
            }
        }
    }
}

/// SpacemanDMM's `{:?}` of a setting's value: a term with no follows is spelled out, anything else abbreviated.
fn expression_debug(reader: &mut Reader<'_, '_>, e: &dm_syntax::Expr) -> String {
    match reader.shape(e) {
        Shape::Base(b) if b.follows.is_empty() => {
            let l = reader.site.locate(reader.shift + b.term_at);
            format!(
                "Base {{ term: Spanned {{ location: Location {{ file: {:?}, line: {}, column: {} }}, elem: {} }}, follow: [] }}",
                l.file,
                l.line,
                l.column,
                b.term.debug()
            )
        }
        _ => "..".into(),
    }
}

fn directive_value(reader: &mut Reader<'_, '_>, e: &dm_syntax::Expr, location: Location) -> Result<bool, DMError> {
    match reader.shape(e) {
        Shape::Base(b) if b.follows.is_empty() => match &b.term {
            Term::Int(0) => return Ok(false),
            Term::Int(1) => return Ok(true),
            Term::Ident(i) if i == "FALSE" => return Ok(false),
            Term::Ident(i) if i == "TRUE" => return Ok(true),
            _ => {}
        },
        _ => {}
    }
    Err(error(location, format!("invalid value for set {}", expression_debug(reader, e))).set_severity(Severity::Warning))
}

/// The tables the settings pass fills, then shares with every body walk.
#[derive(Default)]
pub struct Settings {
    pub return_type: HashMap<ProcId, TypeExpr>,
    pub directives: Directives,
}

/// One proc's settings as events: its final flag, its declared return type and its leading `set` statements. A pure function of the
/// proc's declaration, its leading statements and the model.
pub fn settings_facts(m: &Model, site: &dyn Site, proc: ProcId, body: &[Statement]) -> SettingsFacts {
    let mut events = Vec::new();
    let diag = |events: &mut Vec<SettingEvent>, e: DMError| events.push(SettingEvent::Diag(Diag::of(&e)));
    let proc_location = site.place(m.value(proc).location);
    if let Some(decl) = m.ty(proc.ty).proc(m.proc_name(proc)).and_then(|p| p.declaration.as_ref()) {
        if decl.is_final {
            events.push(SettingEvent::Final(proc_location));
        }
    }
    if let Some(decl) = m.get_declaration(proc) {
        match &decl.return_type {
            model::ReturnType::Input(input) => {
                if let Some(t) = input.to_typepath().and_then(|p| m.find(p)) {
                    events.push(SettingEvent::ReturnType(TypeExpr::from(StaticType::Type(t))));
                }
            }
            model::ReturnType::TypePath(bits) => {
                if let Ok(ty) = walk::static_type(m, proc_location, bits) {
                    events.push(SettingEvent::ReturnType(TypeExpr::from(ty)));
                }
            }
            model::ReturnType::None => {}
        }
    }
    let mut reader = Reader { site, shift: 0 };
    for statement in body {
        let StatementKind::Set { attribute: name, value, .. } = &statement.kind else { break };
        let location = reader.site.locate(statement.header_span.start);
        if name == "SpacemanDMM_return_type" {
            let prefab = match reader.shape(value) {
                Shape::Base(b) if b.follows.is_empty() => match b.term {
                    Term::Prefab { path, .. } => Some(path),
                    _ => None,
                },
                _ => None,
            };
            if let Some(path) = prefab {
                let bits: Vec<String> = walk::type_path(path).into_iter().map(|(_, n)| n).collect();
                let ty = match walk::static_type(m, location, &bits) {
                    Ok(s) => s,
                    Err(e) => {
                        diag(&mut events, e);
                        StaticType::None
                    }
                };
                events.push(SettingEvent::ReturnType(TypeExpr::from(ty)));
            } else {
                match TypeExpr::compile(m, &m.value(proc).parameters, &mut reader, location, value) {
                    Ok(expr) => events.push(SettingEvent::ReturnType(expr)),
                    Err(e) => diag(&mut events, e.with_component(dm::Component::DreamChecker)),
                }
            }
        } else if name.starts_with("SpacemanDMM_") {
            let mut tables = Directives::default();
            let Some(table) = tables.by_name(name) else {
                diag(
                    &mut events,
                    error(location, format!("unknown linter setting {name:?}")).with_errortype("unknown_linter_setting").set_severity(Severity::Warning),
                );
                continue;
            };
            if table.set_at_definition {
                if let Some(decl) = m.get_declaration(proc) {
                    if decl.location != m.value(proc).location {
                        diag(&mut events, error(location, format!("Can't define procs {name} outside their initial definition")).set_severity(Severity::Warning));
                        continue;
                    }
                }
            }
            match directive_value(&mut reader, value, location) {
                Ok(enable) => events.push(SettingEvent::Directive { name: name.clone(), enable, location }),
                Err(e) => diag(&mut events, e.with_errortype("invalid_lint_directive_value")),
            }
        } else if !KNOWN_SETTING_NAMES.contains(&name.as_str()) {
            diag(&mut events, error(location, format!("unknown setting {name:?}")).set_severity(Severity::Warning));
        } else {
            let term = match reader.shape(value) {
                Shape::Base(b) if b.follows.is_empty() => Some(b.term),
                _ => None,
            };
            match name.as_str() {
                "background" | "waitfor" | "hidden" | "instant" | "popup_menu" => {
                    if directive_value(&mut reader, value, location).is_err() {
                        diag(
                            &mut events,
                            error(location, format!("set {name} must be 0/1/TRUE/FALSE")).set_severity(Severity::Warning).with_errortype("invalid_set_value"),
                        );
                    }
                }
                "name" | "category" | "desc" => match term {
                    Some(Term::Str(_)) | Some(Term::Interp { .. }) | None => {}
                    Some(Term::Null) if name == "category" => {}
                    Some(_) => diag(
                        &mut events,
                        error(location, format!("set {name} must have a string value")).set_severity(Severity::Warning).with_errortype("invalid_set_value"),
                    ),
                },
                "invisibility" => {
                    if !matches!(term, Some(Term::Int(i)) if (0..=100).contains(&i)) {
                        diag(&mut events, error(location, "set invisibility must be 0-100").set_severity(Severity::Warning).with_errortype("invalid_set_value"));
                    }
                }
                _ => {}
            }
        }
    }
    SettingsFacts { events }
}

/// One proc's settings into the tables, in order; what the tables refuse (a directive set twice, one that cannot be set there) and
/// what the settings reported are registered to `context`.
pub fn apply_settings(m: &Model, settings: &mut Settings, context: &Context, proc: ProcId, facts: &SettingsFacts) {
    for event in &facts.events {
        match event {
            SettingEvent::Diag(d) => context.register_error(d.error()),
            SettingEvent::Final(location) => {
                if let Err(e) = settings.directives.must_not_override.insert(m, proc, true, *location) {
                    context.register_error(e);
                }
            }
            SettingEvent::ReturnType(expr) => {
                settings.return_type.insert(proc, expr.clone());
            }
            SettingEvent::Directive { name, enable, location } => {
                let table = settings.directives.by_name(name).expect("a known directive");
                if let Err(e) = table.insert(m, proc, *enable, *location) {
                    context.register_error(e);
                }
            }
        }
    }
}

/// Where the per-proc results come from: computed, or kept between runs (dmbc keeps them as queries, `dreamchecker_input.rs`).
/// `compute(i)` is the result for `procs[i]`; a store returns one result per proc, in order, equal to what `compute` gives.
pub trait Store: Sync {
    /// `bodies[i]` is `procs[i]`'s body (`ProcValue::body`).
    fn settings(&self, procs: &[ProcId], bodies: &[u32], compute: &(dyn Fn(usize) -> SettingsFacts + Sync)) -> Vec<SettingsFacts>;
    /// `settings` is every proc's settings facts (the tables a body walk reads are made of them).
    fn bodies(&self, procs: &[ProcId], bodies: &[u32], settings: &[SettingsFacts], compute: &(dyn Fn(usize) -> ProcFacts + Sync)) -> Vec<ProcFacts>;
}

/// A store that computes every result, on `threads` threads.
pub struct Compute {
    pub threads: usize,
}

impl Store for Compute {
    fn settings(&self, procs: &[ProcId], _bodies: &[u32], compute: &(dyn Fn(usize) -> SettingsFacts + Sync)) -> Vec<SettingsFacts> {
        let ix: Vec<usize> = (0..procs.len()).collect();
        parallel_map(&ix, self.threads, |&i| compute(i))
    }
    fn bodies(&self, procs: &[ProcId], _bodies: &[u32], _settings: &[SettingsFacts], compute: &(dyn Fn(usize) -> ProcFacts + Sync)) -> Vec<ProcFacts> {
        let ix: Vec<usize> = (0..procs.len()).collect();
        parallel_map(&ix, self.threads, |&i| compute(i))
    }
}

/// Procs that call through `..()` chains or call sites keep violations as (what, where).
#[derive(Default)]
pub struct Violations {
    pub violators: HashMap<ProcId, Vec<(String, Where)>>,
}

struct BadOverride {
    missing: Vec<String>,
    location: Location,
}

struct CalledAt {
    location: Where,
    others: u32,
}

#[derive(Default)]
struct KwargInfo {
    location: Location,
    called_at: BTreeMap<String, CalledAt>,
    bad_overrides_at: BTreeMap<String, BadOverride>,
}

/// The tables the call-tree checks read, all built from the per-proc facts before they start.
pub struct CallTables<'a> {
    model: &'a Model,
    sites: &'a dyn Sites,
    call_tree: &'a HashMap<ProcId, Vec<(ProcId, Where, bool)>>,
    waitfor_procs: &'a HashSet<ProcId>,
    sleep_exempt: &'a ProcDirective,
    sleeping_procs: &'a Violations,
    impure_procs: &'a Violations,
    sleeping_overrides: &'a HashMap<ProcId, Vec<ProcId>>,
    impure_overrides: &'a HashMap<ProcId, Vec<ProcId>>,
    reach: &'a Reach,
}

/// The procs that can reach a blocking or impure operation through calls (each set closed over callers).
#[derive(Default, PartialEq)]
struct Reach {
    can_sleep: HashSet<ProcId>,
    sleeps_in_context: HashSet<ProcId>,
    can_be_impure: HashSet<ProcId>,
}

struct Step {
    proc: ProcId,
    location: Where,
    new_context: bool,
    parent: Option<usize>,
}

/// Every proc that reaches one of `targets` through `callers`, expanding only through callers `expands` admits.
fn reaching(callers: &HashMap<ProcId, Vec<ProcId>>, targets: impl Iterator<Item = ProcId>, expands: impl Fn(ProcId) -> bool) -> HashSet<ProcId> {
    let mut seen = HashSet::new();
    let mut stack: Vec<ProcId> = targets.collect();
    while let Some(p) = stack.pop() {
        if seen.insert(p) {
            if let Some(c) = callers.get(&p) {
                stack.extend(c.iter().copied().filter(|c| expands(*c)));
            }
        }
    }
    seen
}

impl Reach {
    fn compute(fold: &Fold, overrides: &Overrides, d: &Directives) -> Reach {
        // Callers of each proc: through every call, and through calls in the same context only.
        let mut all: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
        let mut same: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
        for (caller, calls) in &fold.call_tree {
            for (callee, _, new_context) in calls {
                all.entry(*callee).or_default().push(*caller);
                if !*new_context {
                    same.entry(*callee).or_default().push(*caller);
                }
            }
        }
        let exempt = |p: ProcId| !fold.waitfor.contains(&p) && d.sleep_exempt.get(p).is_none();
        let sleepers = || fold.sleeping.violators.keys().chain(overrides.sleeping.keys()).copied();
        Reach {
            can_sleep: reaching(&all, sleepers(), exempt),
            sleeps_in_context: reaching(&same, sleepers().filter(|p| exempt(*p)), exempt),
            can_be_impure: reaching(&all, fold.impure.violators.keys().chain(overrides.impure.keys()).copied(), |_| true),
        }
    }

    /// The procs whose membership differs between the two.
    fn changed(&self, other: &Reach, into: &mut HashSet<ProcId>) {
        for (a, b) in [(&self.can_sleep, &other.can_sleep), (&self.sleeps_in_context, &other.sleeps_in_context), (&self.can_be_impure, &other.can_be_impure)] {
            into.extend(a.symmetric_difference(b).copied());
        }
    }
}

/// Every proc a finding's search looked up in a table (the reads that decide it: a later run judges it again only when one of
/// them changed).
type Reads = Vec<ProcId>;

impl CallTables<'_> {
    fn search(&self, root: ProcId, within: &HashSet<ProcId>, reads: &mut Reads, mut visit: impl FnMut(&[Step], usize, &mut Reads) -> bool) {
        let mut steps: Vec<Step> = Vec::new();
        let mut visited = HashSet::new();
        let mut next = 0;
        reads.push(root);
        if let Some(called) = self.call_tree.get(&root) {
            for (proc, location, new_context) in called {
                reads.push(*proc);
                if within.contains(proc) && visited.insert(*proc) {
                    steps.push(Step { proc: *proc, location: *location, new_context: *new_context, parent: None });
                }
            }
        }
        while next < steps.len() {
            let at = next;
            next += 1;
            if !visit(&steps, at, reads) {
                continue;
            }
            if let Some(called) = self.call_tree.get(&steps[at].proc) {
                for (proc, location, new_context) in called {
                    reads.push(*proc);
                    if within.contains(proc) && visited.insert(*proc) {
                        steps.push(Step { proc: *proc, location: *location, new_context: *new_context, parent: Some(at) });
                    }
                }
            }
        }
    }

    fn with_callstack(&self, site: &dyn Site, mut e: DMError, steps: &[Step], at: usize) -> DMError {
        let mut path = VecDeque::new();
        let mut cur = Some(at);
        while let Some(i) = cur {
            path.push_front(i);
            cur = steps[i].parent;
        }
        for i in path {
            e.add_note(site.place(steps[i].location), format!("{}() called here", self.model.proc_display(steps[i].proc)));
        }
        e
    }

    fn with_list(site: &dyn Site, mut e: DMError, list: &[(String, Where)], what: &str) -> DMError {
        for (name, location) in list {
            e.add_note(site.place(*location), format!("{name}{what}"));
        }
        e
    }

    fn sleep_findings(&self, procref: ProcId, location: Location, reads: &mut Reads) -> Vec<DMError> {
        let m = self.model;
        let site = self.sites.site();
        let at = site.place(m.value(procref).location);
        let mut out = Vec::new();
        reads.push(procref);
        if let Some(sleepvec) = self.sleeping_procs.violators.get(&procref) {
            out.push(Self::with_list(&*site,
                error(at, format!("{} sets SpacemanDMM_should_not_sleep but calls blocking built-in(s)", m.proc_display(procref)))
                    .with_note(location, "SpacemanDMM_should_not_sleep set here")
                    .with_errortype("must_not_sleep"),
                sleepvec,
                "() called here",
            ));
        }
        let reaches = self.call_tree.get(&procref).is_some_and(|c| {
            c.iter().any(|(p, _, nc)| {
                reads.push(*p);
                !nc && self.reach.sleeps_in_context.contains(p)
            })
        });
        if !reaches {
            return out;
        }
        self.search(procref, &self.reach.can_sleep, reads, |steps, i, reads| {
            let nextproc = steps[i].proc;
            if self.waitfor_procs.contains(&nextproc) || self.sleep_exempt.get(nextproc).is_some() || steps[i].new_context {
                return false;
            }
            if let Some(sleepvec) = self.sleeping_procs.violators.get(&nextproc) {
                let e = error(at, format!("{} sets SpacemanDMM_should_not_sleep but calls blocking proc {}", m.proc_display(procref), m.proc_display(nextproc)))
                    .with_note(location, "SpacemanDMM_should_not_sleep set here")
                    .with_errortype("must_not_sleep");
                out.push(Self::with_list(&*site, self.with_callstack(&*site, e, steps, i), sleepvec, "() called here"));
            } else if let Some(children) = self.sleeping_overrides.get(&nextproc) {
                for child in children {
                    if m.is_subtype_of(procref.ty, nextproc.ty) && !m.is_subtype_of(child.ty, procref.ty) {
                        continue;
                    }
                    reads.push(*child);
                    let e = error(at, format!("{} calls {} which has override child proc that sleeps {}", m.proc_display(procref), m.proc_display(nextproc), m.proc_display(*child)))
                        .with_note(location, "SpacemanDMM_should_not_sleep set here")
                        .with_errortype("must_not_sleep");
                    out.push(Self::with_list(&*site, self.with_callstack(&*site, e, steps, i), &self.sleeping_procs.violators[child], "() called here"));
                }
            }
            true
        });
        out
    }

    fn pure_findings(&self, procref: ProcId, location: Location, reads: &mut Reads) -> Vec<DMError> {
        let m = self.model;
        let site = self.sites.site();
        let at = site.place(m.value(procref).location);
        let mut out = Vec::new();
        reads.push(procref);
        if let Some(impurevec) = self.impure_procs.violators.get(&procref) {
            out.push(Self::with_list(&*site,
                error(at, format!("{} does impure operations", m.proc_display(procref)))
                    .with_errortype("must_be_pure")
                    .with_note(location, "SpacemanDMM_should_be_pure set here"),
                impurevec,
                " happens here",
            ));
        }
        self.search(procref, &self.reach.can_be_impure, reads, |steps, i, reads| {
            let nextproc = steps[i].proc;
            if let Some(impurevec) = self.impure_procs.violators.get(&nextproc) {
                let e = error(at, format!("{} sets SpacemanDMM_should_be_pure but calls a {} that does impure operations", m.proc_display(procref), m.proc_display(nextproc)))
                    .with_note(location, "SpacemanDMM_should_be_pure set here")
                    .with_errortype("must_be_pure");
                out.push(Self::with_list(&*site, self.with_callstack(&*site, e, steps, i), impurevec, " happens here"));
            } else if let Some(children) = self.impure_overrides.get(&nextproc) {
                for child in children {
                    if m.is_subtype_of(procref.ty, nextproc.ty) && !m.is_subtype_of(child.ty, procref.ty) {
                        continue;
                    }
                    reads.push(*child);
                    let e = error(at, format!("{} calls {} which has override child proc that does impure operations {}", m.proc_display(procref), m.proc_display(nextproc), m.proc_display(*child)))
                        .with_note(location, "SpacemanDMM_should_not_pure set here")
                        .with_errortype("must_be_pure");
                    out.push(Self::with_list(&*site, self.with_callstack(&*site, e, steps, i), &self.impure_procs.violators[child], "() called here"));
                }
            }
            true
        });
        out
    }
}

/// `f` over `items` on up to `threads` threads, results in `items`' order.
fn parallel_map<T: Sync, R: Send>(items: &[T], threads: usize, f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    if threads <= 1 || items.len() < 2 {
        return items.iter().map(&f).collect();
    }
    let next = std::sync::atomic::AtomicUsize::new(0);
    let slots: std::sync::Mutex<Vec<Option<R>>> = std::sync::Mutex::new((0..items.len()).map(|_| None).collect());
    std::thread::scope(|scope| {
        for _ in 0..threads.min(items.len()) {
            std::thread::Builder::new()
                .name("dreamchecker".into())
                .stack_size(64 * 1024 * 1024)
                .spawn_scoped(scope, || loop {
                    let i = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(item) = items.get(i) else { break };
                    let r = f(item);
                    slots.lock().unwrap()[i] = Some(r);
                })
                .expect("dreamchecker worker thread");
        }
    });
    slots.into_inner().unwrap().into_iter().map(|r| r.expect("every item mapped")).collect()
}

/// The section headers [`run`] prints under `cli`, in order (a host that registers a kept run again prints them itself).
pub const SECTIONS: [&str; 5] = [
    "Analyzing variables...\n",
    "Gathering proc settings...\n",
    "Analyzing proc bodies...\n",
    "Analyzing proc override validity...\n",
    "Analyzing proc call tree...\n",
];

/// Prints [`SECTIONS`] as [`run`] does.
pub fn print_sections() {
    for s in SECTIONS {
        cli_println!(true, "============================================================");
        cli_println!(true, "{s}");
    }
}

/// One proc's body facts: a pure function of its body, the model and the settings tables.
pub fn body_facts(model: &Model, shared: &Shared, site: &dyn Site, proc: ProcId, body: &[Statement]) -> ProcFacts {
    let mut walk = Walk::new(model, shared, site, proc);
    walk.run(body);
    walk.facts
}

/// DreamChecker over the native input, registering diagnostics to `context`; `cli` prints its progress. The per-proc results come
/// from `store`.
/// The call-tree searches run on `threads` threads.
pub fn run(context: &Context, input: &CheckerInput<'_>, cli: bool, store: &dyn Store, threads: usize) {
    let kept = Kept::compute(input, store, threads);
    if cli {
        print_sections();
    }
    kept.register(context);
}

/// What one proc's walk hands the passes after it, without its places: what the call-tree pass reads (calls, blocking and impure
/// operations, `waitfor`) and what the keyword-argument check reads. A recomputed proc whose shape is the one it had moves nothing
/// in those passes but places.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
struct FactsShape {
    calls: u64,
    kwargs: u64,
}

fn shape_of(f: &ProcFacts) -> FactsShape {
    use std::hash::{Hash, Hasher};
    let mut h = std::hash::DefaultHasher::new();
    for (callee, _, new_context) in &f.calls {
        (callee, new_context).hash(&mut h);
    }
    0xffu8.hash(&mut h);
    for (name, _) in &f.sleeps {
        name.hash(&mut h);
    }
    0xfeu8.hash(&mut h);
    for (name, _) in &f.impure {
        name.hash(&mut h);
    }
    0xfdu8.hash(&mut h);
    f.waitfor.hash(&mut h);
    let calls = h.finish();
    let mut h = std::hash::DefaultHasher::new();
    for (key, _, name, _) in &f.kwargs {
        (key, name).hash(&mut h);
    }
    FactsShape { calls, kwargs: h.finish() }
}

/// Everything one run found, kept so that a later run over an edited tree with the same declarations computes only what the edit
/// reaches ([`Kept::update`]). Its places are the revision's it was last computed or updated for: `Where`s are offsets into that
/// revision's expanded text, locations are that revision's lines.
pub struct Kept {
    /// Every proc in model order, and the procs with a body (with their body occurrence).
    procs: Vec<ProcId>,
    bodies: Vec<ProcId>,
    body_ix: Vec<u32>,
    position: HashMap<ProcId, usize>,
    var_defs: Vec<Diag>,
    settings_facts: Vec<SettingsFacts>,
    /// What applying the settings registered, in order.
    settings_diags: Vec<Diag>,
    shared: Shared,
    /// By body position: its walk's diagnostics and its shape ([`shape_of`]).
    diags: Vec<Vec<Diag>>,
    shapes: Vec<FactsShape>,
    fold: Fold,
    overrides: Overrides,
    call_tree: CallTree,
}

/// One proc's call-tree findings (a `SpacemanDMM_should_not_sleep` or `SpacemanDMM_should_be_pure` proc) and the procs its search
/// read: judged again only when one of them changed.
struct Unit {
    proc: ProcId,
    location: Location,
    pure: bool,
    diags: Vec<Diag>,
    reads: Vec<ProcId>,
}

#[derive(Default)]
struct CallTree {
    reach: Reach,
    units: Vec<Unit>,
}

/// The per-proc facts the override and call-tree passes read, folded.
#[derive(Default)]
struct Fold {
    call_tree: HashMap<ProcId, Vec<(ProcId, Where, bool)>>,
    sleeping: Violations,
    impure: Violations,
    waitfor: HashSet<ProcId>,
    /// By body position: an inexact call's keyword arguments (`ProcFacts::kwargs`).
    kwargs: BTreeMap<usize, Vec<(String, Location, String, Where)>>,
}

#[derive(Default)]
struct Overrides {
    /// The keyword-argument diagnostics.
    diags: Vec<Diag>,
    sleeping: HashMap<ProcId, Vec<ProcId>>,
    impure: HashMap<ProcId, Vec<ProcId>>,
}

/// The diagnostics `f` registers, as data, in order.
fn captured(f: impl FnOnce(&Context)) -> Vec<Diag> {
    let context = Context::default();
    f(&context);
    context.take_errors().iter().map(Diag::of).collect()
}

fn statements_of(input: &CheckerInput<'_>, p: ProcId) -> std::sync::Arc<Vec<Statement>> {
    input.model.value(p).body.and_then(|b| input.bodies.statements(b)).unwrap_or_default()
}

/// What [`Kept::update`] did, for its trace.
#[derive(Debug, Default)]
pub struct Updated {
    pub recomputed: usize,
    pub var_defs: bool,
    /// The keyword-argument check ran again.
    pub kwargs: bool,
    /// The call-tree findings judged again, of all.
    pub units: usize,
    pub of_units: usize,
    /// Where the time went: moving the kept locations, moving the folded places, the walks, the later passes.
    pub relocate: std::time::Duration,
    pub shift: std::time::Duration,
    pub walks: std::time::Duration,
    pub passes: std::time::Duration,
}

impl Kept {
    /// Every pass over `input`, the per-proc results from `store`.
    pub fn compute(input: &CheckerInput<'_>, store: &dyn Store, threads: usize) -> Kept {
        let timing = dq_hostio::var_os("DQ_DREAMCHECKER_TIMING").is_some();
        let mut mark = std::time::Instant::now();
        let mut lap = |what: &str| {
            if timing {
                dq_hostio::out(false, format_args!("dreamchecker timing: {what} {:.1} s", mark.elapsed().as_secs_f64()), true);
            }
            mark = std::time::Instant::now();
        };
        let m = &input.model;
        let var_defs = captured(|c| check_var_defs(m, c, &*input.sites.site()));
        lap("variables");

        let mut procs: Vec<ProcId> = Vec::new();
        m.recurse(m.root(), &mut |t| procs.extend(m.self_procs(t)));
        let bodies: Vec<ProcId> = procs.iter().copied().filter(|&p| m.value(p).body.is_some()).collect();
        let body_ix: Vec<u32> = bodies.iter().map(|&p| m.value(p).body.expect("a proc with a body")).collect();
        let position: HashMap<ProcId, usize> = bodies.iter().enumerate().map(|(i, &p)| (p, i)).collect();
        let settings_facts: Vec<SettingsFacts> = store.settings(&bodies, &body_ix, &|i| {
            let site = input.sites.site();
            settings_facts(m, &*site, bodies[i], &statements_of(input, bodies[i]))
        });
        let mut settings = Settings::default();
        let settings_diags = captured(|c| {
            settings.return_type.insert(m.get_proc(m.root(), "get_step").expect("builtin get_step"), StaticType::Type(m.expect("/turf")).into());
            for (&p, f) in bodies.iter().zip(&settings_facts) {
                apply_settings(m, &mut settings, c, p, f);
            }
        });
        lap("settings");

        for &p in &bodies {
            settings.directives.must_not_sleep.try_copy_from_parent(m, p);
            settings.directives.must_be_pure.try_copy_from_parent(m, p);
        }
        let shared = Shared { return_type: settings.return_type, directives: settings.directives };
        let facts: Vec<ProcFacts> = store.bodies(&bodies, &body_ix, &settings_facts, &|i| {
            let site = input.sites.site();
            body_facts(m, &shared, &*site, bodies[i], &statements_of(input, bodies[i]))
        });
        let mut fold = Fold::default();
        let mut diags = Vec::with_capacity(facts.len());
        let mut shapes = Vec::with_capacity(facts.len());
        for (i, (&p, f)) in bodies.iter().zip(facts).enumerate() {
            shapes.push(shape_of(&f));
            fold.put(i, p, f.calls, f.sleeps, f.impure, f.waitfor, f.kwargs);
            diags.push(f.diagnostics);
        }
        lap("bodies");

        let (sleeping, impure) = Overrides::violations(m, &procs, &fold);
        let overrides = Overrides { diags: Overrides::kwargs(m, &procs, &fold, &*input.sites.site()), sleeping, impure };
        lap("overrides");
        let call_tree = CallTree::compute(m, input.sites, &fold, &overrides, &shared.directives, threads);
        lap("call tree");
        Kept { procs, bodies, body_ix, position, var_defs, settings_facts, settings_diags, shared, diags, shapes, fold, overrides, call_tree }
    }

    /// Registers what the passes found to `context`, in the order DreamChecker registers it.
    pub fn register(&self, context: &Context) {
        for d in self.var_defs.iter().chain(&self.settings_diags).chain(self.diags.iter().flatten()).chain(&self.overrides.diags).chain(self.call_tree.diags()) {
            context.register_error(d.error());
        }
    }

    /// Every diagnostic, in registration order.
    pub fn diagnostics(&self) -> Vec<Diag> {
        self.var_defs.iter().chain(&self.settings_diags).chain(self.diags.iter().flatten()).chain(&self.overrides.diags).chain(self.call_tree.diags()).cloned().collect()
    }

    /// What is kept, by size (for the traces).
    pub fn stats(&self) -> String {
        let calls: usize = self.fold.call_tree.values().map(Vec::len).sum();
        let reads: usize = self.call_tree.units.iter().map(|u| u.reads.len()).sum();
        format!(
            "{} procs, {} bodies, {} calls folded, {} call-tree findings reading {} procs, reach sets {}/{}/{}",
            self.procs.len(),
            self.bodies.len(),
            calls,
            self.call_tree.units.len(),
            reads,
            self.call_tree.reach.can_sleep.len(),
            self.call_tree.reach.sleeps_in_context.len(),
            self.call_tree.reach.can_be_impure.len()
        )
    }

    /// The body occurrences of the procs with bodies, in order (a host maps an edit's bodies to positions with it).
    pub fn body_occurrences(&self) -> &[u32] {
        &self.body_ix
    }

    /// Brings a kept run up to `input`, a revision with the same declarations (the same model but for places) whose bodies at the
    /// positions `changed` changed. `shift(i)` is how far body position `i` moved in the expanded text; `relocate` moves a location
    /// of the kept revision to this one, or refuses (`false`: a line the edit changed). What a refused location belongs to is
    /// computed again: a proc's settings and walk, the var definitions, the override or call-tree pass. `Err` when the edit reaches
    /// what this does not update (a proc's settings changed, a setting's place cannot be moved): the caller computes a new run.
    pub fn update(
        &mut self,
        input: &CheckerInput<'_>,
        changed: &[usize],
        shift: &(dyn Fn(usize) -> isize + Sync),
        relocate: &(dyn Fn(&mut Location) -> bool + Sync),
        threads: usize,
    ) -> Result<Updated, String> {
        let m = &input.model;
        let mut out = Updated::default();
        let mut lap = std::time::Instant::now();
        let mut took = move || {
            let t = lap.elapsed();
            lap = std::time::Instant::now();
            t
        };
        let moved = |l: &mut Location| relocate(l);
        let all_moved = |d: &mut [Diag]| {
            let mut ok = true;
            for x in d.iter_mut() {
                x.map_locations(&mut |l| ok &= moved(l));
            }
            ok
        };
        // What is kept apart from any one proc.
        if !all_moved(&mut self.settings_diags) {
            return Err("a settings diagnostic sits on an edited line".into());
        }
        let mut directives_ok = true;
        self.shared.directives.map_locations(&mut |l| directives_ok &= moved(l));
        if !directives_ok {
            return Err("a directive sits on an edited line".into());
        }
        out.var_defs = !all_moved(&mut self.var_defs);
        out.kwargs = !all_moved(&mut self.overrides.diags);
        // A finding holding a location the edit changed is judged again.
        let mut unmoved: Vec<bool> = self.call_tree.units.iter_mut().map(|u| !moved(&mut u.location) | !all_moved(&mut u.diags)).collect();
        // The procs whose results must be computed again: the changed ones and those holding a location the edit changed.
        let mut again: Vec<bool> = vec![false; self.bodies.len()];
        for &i in changed {
            if let Some(a) = again.get_mut(i) {
                *a = true;
            }
        }
        for i in 0..self.bodies.len() {
            let mut ok = true;
            self.settings_facts[i].map_locations(&mut |l| ok &= moved(l));
            ok &= all_moved(&mut self.diags[i]);
            if !ok {
                again[i] = true;
            }
        }
        for (&i, list) in self.fold.kwargs.iter_mut() {
            for (_, l, _, _) in list.iter_mut() {
                if !moved(l) {
                    again[i] = true;
                }
            }
        }
        out.relocate = took();
        // The folded places of every proc follow its body.
        let position = &self.position;
        let by = |p: &ProcId| position.get(p).map_or(0, |&i| shift(i));
        let mv = |w: &mut Where, d: isize| match w {
            Where::At(o) | Where::LineEnd(o) | Where::DeclEnd(o) => *o = o.wrapping_add_signed(d),
            Where::Fixed(_) => {}
        };
        for (caller, calls) in self.fold.call_tree.iter_mut() {
            let d = by(caller);
            if d != 0 {
                calls.iter_mut().for_each(|(_, w, _)| mv(w, d));
            }
        }
        for violations in [&mut self.fold.sleeping, &mut self.fold.impure] {
            for (p, list) in violations.violators.iter_mut() {
                let d = by(p);
                if d != 0 {
                    list.iter_mut().for_each(|(_, w)| mv(w, d));
                }
            }
        }
        for (&i, list) in self.fold.kwargs.iter_mut() {
            let d = shift(i);
            if d != 0 {
                list.iter_mut().for_each(|(_, _, _, w)| mv(w, d));
            }
        }
        out.shift = took();
        // Computed again: settings first (a changed one ends the update), then the walks.
        let positions: Vec<usize> = (0..self.bodies.len()).filter(|&i| again[i]).collect();
        out.recomputed = positions.len();
        let bodies = &self.bodies;
        let fresh: Vec<SettingsFacts> = parallel_map(&positions, threads, |&i| {
            let site = input.sites.site();
            settings_facts(m, &*site, bodies[i], &statements_of(input, bodies[i]))
        });
        for (&i, f) in positions.iter().zip(&fresh) {
            if *f != self.settings_facts[i] {
                return Err(format!("the settings of {} changed", m.proc_display(bodies[i])));
            }
        }
        let shared = &self.shared;
        let walked: Vec<ProcFacts> = parallel_map(&positions, threads, |&i| {
            let site = input.sites.site();
            body_facts(m, shared, &*site, bodies[i], &statements_of(input, bodies[i]))
        });
        // The procs whose calls, blocking or impure operations or `waitfor` changed (what the call-tree findings read), and whether
        // any keyword arguments did.
        let mut changed_calls: HashSet<ProcId> = HashSet::new();
        for (&i, f) in positions.iter().zip(walked) {
            let shape = shape_of(&f);
            let p = self.bodies[i];
            if shape.calls != self.shapes[i].calls {
                changed_calls.insert(p);
            }
            out.kwargs |= shape.kwargs != self.shapes[i].kwargs;
            self.shapes[i] = shape;
            self.fold.put(i, p, f.calls, f.sleeps, f.impure, f.waitfor, f.kwargs);
            self.diags[i] = f.diagnostics;
        }
        out.walks = took();
        if out.var_defs {
            self.var_defs = captured(|c| check_var_defs(m, c, &*input.sites.site()));
        }
        // Keyword arguments: the check reads every override chain, so it runs again when any proc's keyword arguments changed (or a
        // diagnostic of it sat on an edited line); else it found the same, at the places relocated above.
        if out.kwargs {
            self.overrides.diags = Overrides::kwargs(m, &self.procs, &self.fold, &*input.sites.site());
        }
        // Violations up the inheritance chains (cheap: only the violators' chains), then the call-tree findings whose reads changed:
        // a proc with other calls or violations, one whose override lists changed, one that entered or left a reach set.
        if !changed_calls.is_empty() {
            let (sleeping, impure) = Overrides::violations(m, &self.procs, &self.fold);
            for (old, new) in [(&self.overrides.sleeping, &sleeping), (&self.overrides.impure, &impure)] {
                for (p, list) in old.iter() {
                    if new.get(p) != Some(list) {
                        changed_calls.insert(*p);
                    }
                }
                for p in new.keys() {
                    if !old.contains_key(p) {
                        changed_calls.insert(*p);
                    }
                }
            }
            self.overrides.sleeping = sleeping;
            self.overrides.impure = impure;
            let reach = Reach::compute(&self.fold, &self.overrides, &self.shared.directives);
            reach.changed(&self.call_tree.reach, &mut changed_calls);
            self.call_tree.reach = reach;
        }
        for (i, u) in self.call_tree.units.iter().enumerate() {
            if changed_calls.contains(&u.proc) || u.reads.iter().any(|p| changed_calls.contains(p)) {
                unmoved[i] = true;
            }
        }
        let again: Vec<usize> = (0..unmoved.len()).filter(|&i| unmoved[i]).collect();
        out.units = again.len();
        out.of_units = unmoved.len();
        self.call_tree.judge(m, input.sites, &self.fold, &self.overrides, &self.shared.directives, &again, threads);
        out.passes = took();
        Ok(out)
    }
}

impl Fold {
    /// Body position `i` (proc `p`)'s facts, in place of what it held.
    #[allow(clippy::too_many_arguments)]
    fn put(
        &mut self,
        i: usize,
        p: ProcId,
        calls: Vec<(ProcId, Where, bool)>,
        sleeps: Vec<(String, Where)>,
        impure: Vec<(String, Where)>,
        waitfor: bool,
        kwargs: Vec<(String, Location, String, Where)>,
    ) {
        let set = |map: &mut HashMap<ProcId, Vec<(String, Where)>>, v: Vec<(String, Where)>| {
            if v.is_empty() {
                map.remove(&p);
            } else {
                map.insert(p, v);
            }
        };
        set(&mut self.sleeping.violators, sleeps);
        set(&mut self.impure.violators, impure);
        if calls.is_empty() {
            self.call_tree.remove(&p);
        } else {
            self.call_tree.insert(p, calls);
        }
        if waitfor {
            self.waitfor.insert(p);
        } else {
            self.waitfor.remove(&p);
        }
        if kwargs.is_empty() {
            self.kwargs.remove(&i);
        } else {
            self.kwargs.insert(i, kwargs);
        }
    }

    /// The keyword arguments by callee key, folded in body order (the first call names the place).
    fn used_kwargs(&self) -> BTreeMap<String, KwargInfo> {
        let mut used: BTreeMap<String, KwargInfo> = BTreeMap::new();
        for list in self.kwargs.values() {
            for (key, proc_location, name, location) in list {
                used.entry(key.clone())
                    .or_insert_with(|| KwargInfo { location: *proc_location, ..Default::default() })
                    .called_at
                    .entry(name.clone())
                    .and_modify(|c| c.others += 1)
                    .or_insert(CalledAt { location: *location, others: 0 });
            }
        }
        used
    }
}

impl Overrides {
    /// The violations up each inheritance chain (`New()` propagates through `..()` and is left out), each list in proc order.
    fn violations(m: &Model, procs: &[ProcId], fold: &Fold) -> (HashMap<ProcId, Vec<ProcId>>, HashMap<ProcId, Vec<ProcId>>) {
        let mut sleeping: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
        let mut impure: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
        for &p in procs {
            if m.proc_name(p) == "New" {
                continue;
            }
            for (violations, overrides) in [(&fold.sleeping, &mut sleeping), (&fold.impure, &mut impure)] {
                if violations.violators.contains_key(&p) {
                    let mut next = m.parent_proc(p);
                    while let Some(current) = next {
                        overrides.entry(current).or_default().push(p);
                        next = m.parent_proc(current);
                    }
                }
            }
        }
        (sleeping, impure)
    }

    /// The keyword arguments overrides are missing, as diagnostics.
    fn kwargs(m: &Model, procs: &[ProcId], fold: &Fold, kw_site: &dyn Site) -> Vec<Diag> {
        let mut used_kwargs = fold.used_kwargs();
        if used_kwargs.is_empty() {
            return Vec::new();
        }
        for &p in procs {
            let names: HashSet<&str> = m.value(p).parameters.iter().map(|x| x.name.as_str()).collect();
            let mut next = m.parent_proc(p);
            while let Some(current) = next {
                if let Some(kwargs) = used_kwargs.get_mut(&m.proc_display(current)) {
                    let missing: Vec<String> = kwargs.called_at.keys().filter(|k| !names.contains(k.as_str())).cloned().collect();
                    if !missing.is_empty() {
                        kwargs.bad_overrides_at.insert(m.ty(p.ty).path.clone(), BadOverride { missing, location: kw_site.place(m.value(p).location) });
                    }
                }
                next = m.parent_proc(current);
            }
        }
        captured(|context| {
            for (base, info) in used_kwargs.iter() {
                if info.bad_overrides_at.is_empty() {
                    continue;
                }
                let msg = match info.bad_overrides_at.len() {
                    1 => format!("an override of {base} is missing keyword args"),
                    len => format!("{len} overrides of {base} are missing keyword args"),
                };
                let mut e = error(info.location, msg).with_errortype("override_missing_keyword_arg");
                let mut missing = HashSet::new();
                for (child, bad) in info.bad_overrides_at.iter() {
                    e.add_note(bad.location, format!("{} is missing \"{}\"", child, bad.missing.join("\", \"")));
                    missing.extend(bad.missing.iter());
                }
                for (arg, called) in info.called_at.iter() {
                    if !missing.contains(arg) {
                        continue;
                    }
                    if called.others > 0 {
                        e.add_note(kw_site.place(called.location), format!("called with {:?} here, and {} other places", arg, called.others));
                    } else {
                        e.add_note(kw_site.place(called.location), format!("called with {arg:?} here"));
                    }
                }
                e.register(context);
            }
        })
    }
}

impl CallTree {
    fn diags(&self) -> impl Iterator<Item = &Diag> {
        self.units.iter().flat_map(|u| u.diags.iter())
    }

    /// The call-tree pass: what each `SpacemanDMM_should_not_sleep` and `SpacemanDMM_should_be_pure` proc reaches.
    fn compute(m: &Model, sites: &dyn Sites, fold: &Fold, overrides: &Overrides, d: &Directives, threads: usize) -> CallTree {
        let order_site = sites.site();
        let in_order = |table: &ProcDirective, pure: bool| {
            let mut v: Vec<(ProcId, Location)> = table.directive.iter().map(|(p, &(_, l))| (*p, l)).collect();
            v.sort_by_key(|(p, l)| (order_site.place(m.value(*p).location), *l, m.proc_display(*p)));
            v.into_iter().map(move |(proc, location)| Unit { proc, location, pure, diags: Vec::new(), reads: Vec::new() })
        };
        let units: Vec<Unit> = in_order(&d.must_not_sleep, false).chain(in_order(&d.must_be_pure, true)).collect();
        let mut tree = CallTree { reach: Reach::compute(fold, overrides, d), units };
        let all: Vec<usize> = (0..tree.units.len()).collect();
        tree.judge(m, sites, fold, overrides, d, &all, threads);
        tree
    }

    /// Judges the units at `which` again.
    #[allow(clippy::too_many_arguments)]
    fn judge(&mut self, m: &Model, sites: &dyn Sites, fold: &Fold, overrides: &Overrides, d: &Directives, which: &[usize], threads: usize) {
        if which.is_empty() {
            return;
        }
        let tables = CallTables {
            model: m,
            sites,
            call_tree: &fold.call_tree,
            waitfor_procs: &fold.waitfor,
            sleep_exempt: &d.sleep_exempt,
            sleeping_procs: &fold.sleeping,
            impure_procs: &fold.impure,
            sleeping_overrides: &overrides.sleeping,
            impure_overrides: &overrides.impure,
            reach: &self.reach,
        };
        let units = &self.units;
        let judged: Vec<(Vec<Diag>, Vec<ProcId>)> = parallel_map(which, threads, |&i| {
            let u = &units[i];
            let mut reads = Vec::new();
            let found = if u.pure { tables.pure_findings(u.proc, u.location, &mut reads) } else { tables.sleep_findings(u.proc, u.location, &mut reads) };
            reads.sort_unstable();
            reads.dedup();
            (found.iter().map(Diag::of).collect(), reads)
        });
        for (&i, (diags, reads)) in which.iter().zip(judged) {
            self.units[i].diags = diags;
            self.units[i].reads = reads;
        }
    }
}

