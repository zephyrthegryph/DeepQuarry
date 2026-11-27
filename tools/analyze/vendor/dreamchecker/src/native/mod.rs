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

fn reaching(call_tree: &HashMap<ProcId, Vec<(ProcId, Where, bool)>>, targets: impl Iterator<Item = ProcId>, expands: impl Fn(ProcId) -> bool, same_context_only: bool) -> HashSet<ProcId> {
    let mut callers: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
    for (caller, calls) in call_tree {
        for (callee, _, new_context) in calls {
            if !(same_context_only && *new_context) {
                callers.entry(*callee).or_default().push(*caller);
            }
        }
    }
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

impl CallTables<'_> {
    fn search(&self, root: ProcId, within: &HashSet<ProcId>, mut visit: impl FnMut(&[Step], usize) -> bool) {
        let mut steps: Vec<Step> = Vec::new();
        let mut visited = HashSet::new();
        let mut next = 0;
        if let Some(called) = self.call_tree.get(&root) {
            for (proc, location, new_context) in called {
                if within.contains(proc) && visited.insert(*proc) {
                    steps.push(Step { proc: *proc, location: *location, new_context: *new_context, parent: None });
                }
            }
        }
        while next < steps.len() {
            let at = next;
            next += 1;
            if !visit(&steps, at) {
                continue;
            }
            if let Some(called) = self.call_tree.get(&steps[at].proc) {
                for (proc, location, new_context) in called {
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

    fn sleep_findings(&self, procref: ProcId, location: Location) -> Vec<DMError> {
        let m = self.model;
        let site = self.sites.site();
        let at = site.place(m.value(procref).location);
        let mut out = Vec::new();
        if let Some(sleepvec) = self.sleeping_procs.violators.get(&procref) {
            out.push(Self::with_list(&*site, 
                error(at, format!("{} sets SpacemanDMM_should_not_sleep but calls blocking built-in(s)", m.proc_display(procref)))
                    .with_note(location, "SpacemanDMM_should_not_sleep set here")
                    .with_errortype("must_not_sleep"),
                sleepvec,
                "() called here",
            ));
        }
        let reaches = self.call_tree.get(&procref).is_some_and(|c| c.iter().any(|(p, _, nc)| !nc && self.sleeps_in_context.contains(p)));
        if !reaches {
            return out;
        }
        self.search(procref, &self.can_sleep, |steps, i| {
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

    fn pure_findings(&self, procref: ProcId, location: Location) -> Vec<DMError> {
        let m = self.model;
        let site = self.sites.site();
        let at = site.place(m.value(procref).location);
        let mut out = Vec::new();
        if let Some(impurevec) = self.impure_procs.violators.get(&procref) {
            out.push(Self::with_list(&*site, 
                error(at, format!("{} does impure operations", m.proc_display(procref)))
                    .with_errortype("must_be_pure")
                    .with_note(location, "SpacemanDMM_should_be_pure set here"),
                impurevec,
                " happens here",
            ));
        }
        self.search(procref, &self.can_be_impure, |steps, i| {
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
    let timing = dq_hostio::var_os("DQ_DREAMCHECKER_TIMING").is_some();
    let mut mark = std::time::Instant::now();
    let mut lap = |what: &str| {
        if timing {
            dq_hostio::out(false, format_args!("dreamchecker timing: {what} {:.1} s", mark.elapsed().as_secs_f64()), true);
        }
        mark = std::time::Instant::now();
    };
    let m = &input.model;
    cli_println!(cli, "============================================================");
    cli_println!(cli, "Analyzing variables...\n");
    check_var_defs(m, context, &*input.sites.site());
    lap("variables");

    cli_println!(cli, "============================================================");
    cli_println!(cli, "Gathering proc settings...\n");
    let mut procs: Vec<ProcId> = Vec::new();
    m.recurse(m.root(), &mut |t| procs.extend(m.self_procs(t)));
    let bodies: Vec<ProcId> = procs.iter().copied().filter(|&p| m.value(p).body.is_some()).collect();
    let statements = |p: ProcId| m.value(p).body.and_then(|b| input.bodies.statements(b)).unwrap_or_default();
    let body_ix: Vec<u32> = bodies.iter().map(|&p| m.value(p).body.expect("a proc with a body")).collect();
    let settings_facts: Vec<SettingsFacts> = store.settings(&bodies, &body_ix, &|i| {
        let site = input.sites.site();
        settings_facts(m, &*site, bodies[i], &statements(bodies[i]))
    });
    let mut settings = Settings::default();
    settings.return_type.insert(m.get_proc(m.root(), "get_step").expect("builtin get_step"), StaticType::Type(m.expect("/turf")).into());
    for (&p, f) in bodies.iter().zip(&settings_facts) {
        apply_settings(m, &mut settings, context, p, f);
    }
    lap("settings");

    cli_println!(cli, "============================================================");
    cli_println!(cli, "Analyzing proc bodies...\n");
    for &p in &bodies {
        settings.directives.must_not_sleep.try_copy_from_parent(m, p);
        settings.directives.must_be_pure.try_copy_from_parent(m, p);
    }
    let shared = Shared { return_type: settings.return_type, directives: settings.directives };
    let facts: Vec<ProcFacts> = store.bodies(&bodies, &body_ix, &settings_facts, &|i| {
        let site = input.sites.site();
        body_facts(m, &shared, &*site, bodies[i], &statements(bodies[i]))
    });
    let mut call_tree: HashMap<ProcId, Vec<(ProcId, Where, bool)>> = HashMap::new();
    let mut sleeping = Violations::default();
    let mut impure = Violations::default();
    let mut waitfor: HashSet<ProcId> = HashSet::new();
    let mut used_kwargs: BTreeMap<String, KwargInfo> = BTreeMap::new();
    for (&p, f) in bodies.iter().zip(facts) {
        for d in f.diagnostics {
            context.register_error(d.error());
        }
        if !f.calls.is_empty() {
            call_tree.entry(p).or_default().extend(f.calls);
        }
        if !f.sleeps.is_empty() {
            sleeping.violators.entry(p).or_default().extend(f.sleeps);
        }
        if !f.impure.is_empty() {
            impure.violators.entry(p).or_default().extend(f.impure);
        }
        if f.waitfor {
            waitfor.insert(p);
        }
        for (key, proc_location, name, location) in f.kwargs {
            used_kwargs
                .entry(key)
                .or_insert_with(|| KwargInfo { location: proc_location, ..Default::default() })
                .called_at
                .entry(name)
                .and_modify(|c| c.others += 1)
                .or_insert(CalledAt { location, others: 0 });
        }
    }
    lap("bodies");

    cli_println!(cli, "============================================================");
    cli_println!(cli, "Analyzing proc override validity...\n");
    let kw_site = input.sites.site();
    let mut sleeping_overrides: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
    let mut impure_overrides: HashMap<ProcId, Vec<ProcId>> = HashMap::new();
    for &p in &procs {
        // Keyword arguments an override is missing.
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
        // Violations up the inheritance chain (New() propagates through ..() and is left out).
        if m.proc_name(p) != "New" {
            for (violations, overrides) in [(&sleeping, &mut sleeping_overrides), (&impure, &mut impure_overrides)] {
                if violations.violators.contains_key(&p) {
                    let mut next = m.parent_proc(p);
                    while let Some(current) = next {
                        overrides.entry(current).or_default().push(p);
                        next = m.parent_proc(current);
                    }
                }
            }
        }
    }
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
    lap("overrides");

    cli_println!(cli, "============================================================");
    cli_println!(cli, "Analyzing proc call tree...\n");
    let d = &shared.directives;
    let exempt = |p: ProcId| !waitfor.contains(&p) && d.sleep_exempt.get(p).is_none();
    let tables = CallTables {
        model: m,
        sites: input.sites,
        call_tree: &call_tree,
        waitfor_procs: &waitfor,
        sleep_exempt: &d.sleep_exempt,
        sleeping_procs: &sleeping,
        impure_procs: &impure,
        sleeping_overrides: &sleeping_overrides,
        impure_overrides: &impure_overrides,
        can_sleep: reaching(&call_tree, sleeping.violators.keys().chain(sleeping_overrides.keys()).copied(), exempt, false),
        sleeps_in_context: reaching(&call_tree, sleeping.violators.keys().chain(sleeping_overrides.keys()).copied().filter(|p| exempt(*p)), exempt, true),
        can_be_impure: reaching(&call_tree, impure.violators.keys().chain(impure_overrides.keys()).copied(), |_| true, false),
    };
    let order_site = input.sites.site();
    let in_order = |table: &ProcDirective| {
        let mut v: Vec<(ProcId, Location)> = table.directive.iter().map(|(p, &(_, l))| (*p, l)).collect();
        v.sort_by_key(|(p, l)| (order_site.place(m.value(*p).location), *l, m.proc_display(*p)));
        v
    };
    let sleep = in_order(&d.must_not_sleep);
    let pure = in_order(&d.must_be_pure);
    for e in parallel_map(&sleep, threads, |&(p, l)| tables.sleep_findings(p, l)).into_iter().flatten() {
        e.register(context);
    }
    for e in parallel_map(&pure, threads, |&(p, l)| tables.pure_findings(p, l)).into_iter().flatten() {
        e.register(context);
    }
    lap("call tree");
}
