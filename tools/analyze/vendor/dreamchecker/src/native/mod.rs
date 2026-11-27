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
use input::{CheckerInput, Site};
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
pub fn check_var_defs(m: &Model, context: &Context) {
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
                    if typevar.value_location.is_builtins() {
                        continue;
                    }
                    DMError::new(mydecl.location, format!("{path} redeclares var {varname:?}"))
                        .with_note(decl.location, format!("declared on {} here", pt.path))
                        .register(context);
                }
                if decl.flags.is_final() {
                    DMError::new(typevar.value_location, format!("{path} overrides final var {varname:?}"))
                        .with_errortype("final_var")
                        .with_note(decl.location, format!("declared final on {} here", pt.path))
                        .register(context);
                }
                if decl.flags.is_private() {
                    DMError::new(typevar.value_location, format!("{path} overrides private var {varname:?}"))
                        .with_errortype("private_var")
                        .with_note(decl.location, format!("declared private on {} here", pt.path))
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

/// One proc's settings: its final flag, declared return type and leading `set` statements, into `settings`; what is wrong with them
/// is registered to `context`.
pub fn settings_of(m: &Model, settings: &mut Settings, context: &Context, site: &mut dyn Site, proc: ProcId, body: &[Statement]) {
    let proc_location = m.value(proc).location;
    if let Some(decl) = m.ty(proc.ty).proc(m.proc_name(proc)).and_then(|p| p.declaration.as_ref()) {
        if decl.is_final {
            if let Err(e) = settings.directives.must_not_override.insert(m, proc, true, proc_location) {
                context.register_error(e);
            }
        }
    }
    if let Some(decl) = m.get_declaration(proc) {
        match &decl.return_type {
            model::ReturnType::Input(input) => {
                if let Some(t) = input.to_typepath().and_then(|p| m.find(p)) {
                    settings.return_type.insert(proc, TypeExpr::from(StaticType::Type(t)));
                }
            }
            model::ReturnType::TypePath(bits) => {
                if let Ok(ty) = walk::static_type(m, proc_location, bits) {
                    settings.return_type.insert(proc, TypeExpr::from(ty));
                }
            }
            model::ReturnType::None => {}
        }
    }
    let mut reader = Reader { site, shift: 0 };
    for statement in body {
        let StatementKind::Set { attribute: name, relation, value } = &statement.kind else { break };
        let location = reader.site.locate(statement.header_span.start);
        let _ = relation;
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
                        e.register(context);
                        StaticType::None
                    }
                };
                settings.return_type.insert(proc, TypeExpr::from(ty));
            } else {
                match TypeExpr::compile(m, &m.value(proc).parameters, &mut reader, location, value) {
                    Ok(expr) => {
                        settings.return_type.insert(proc, expr);
                    }
                    Err(e) => e.with_component(dm::Component::DreamChecker).register(context),
                }
            }
        } else if name.starts_with("SpacemanDMM_") {
            add_directive(m, settings, context, &mut reader, proc, name, value, location);
        } else if !KNOWN_SETTING_NAMES.contains(&name.as_str()) {
            error(location, format!("unknown setting {name:?}")).set_severity(Severity::Warning).register(context);
        } else {
            let term = match reader.shape(value) {
                Shape::Base(b) if b.follows.is_empty() => Some(b.term),
                _ => None,
            };
            match name.as_str() {
                "background" | "waitfor" | "hidden" | "instant" | "popup_menu" => {
                    if directive_value(&mut reader, value, location).is_err() {
                        error(location, format!("set {name} must be 0/1/TRUE/FALSE"))
                            .set_severity(Severity::Warning)
                            .with_errortype("invalid_set_value")
                            .register(context);
                    }
                }
                "name" | "category" | "desc" => match term {
                    Some(Term::Str(_)) | Some(Term::Interp { .. }) | None => {}
                    Some(Term::Null) if name == "category" => {}
                    Some(_) => {
                        error(location, format!("set {name} must have a string value"))
                            .set_severity(Severity::Warning)
                            .with_errortype("invalid_set_value")
                            .register(context);
                    }
                },
                "invisibility" => {
                    if !matches!(term, Some(Term::Int(i)) if (0..=100).contains(&i)) {
                        error(location, "set invisibility must be 0-100").set_severity(Severity::Warning).with_errortype("invalid_set_value").register(context);
                    }
                }
                _ => {}
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn add_directive(m: &Model, settings: &mut Settings, context: &Context, reader: &mut Reader<'_, '_>, proc: ProcId, directive: &str, value: &dm_syntax::Expr, location: Location) {
    let Some(table) = settings.directives.by_name(directive) else {
        error(location, format!("unknown linter setting {directive:?}"))
            .with_errortype("unknown_linter_setting")
            .set_severity(Severity::Warning)
            .register(context);
        return;
    };
    if table.set_at_definition {
        if let Some(decl) = m.get_declaration(proc) {
            if decl.location != m.value(proc).location {
                error(location, format!("Can't define procs {directive} outside their initial definition")).set_severity(Severity::Warning).register(context);
                return;
            }
        }
    }
    match directive_value(reader, value, location) {
        Ok(truthy) => {
            let table = settings.directives.by_name(directive).expect("known directive");
            if let Err(e) = table.insert(m, proc, truthy, location) {
                context.register_error(e);
            }
        }
        Err(e) => context.register_error(e.with_errortype("invalid_lint_directive_value")),
    }
}

/// Procs that call through `..()` chains or call sites keep violations as (what, where).
#[derive(Default)]
pub struct Violations {
    pub violators: HashMap<ProcId, Vec<(String, Location)>>,
}

struct BadOverride {
    missing: Vec<String>,
    location: Location,
}

struct CalledAt {
    location: Location,
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
    call_tree: &'a HashMap<ProcId, Vec<(ProcId, Location, bool)>>,
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
    location: Location,
    new_context: bool,
    parent: Option<usize>,
}

fn reaching(call_tree: &HashMap<ProcId, Vec<(ProcId, Location, bool)>>, targets: impl Iterator<Item = ProcId>, expands: impl Fn(ProcId) -> bool, same_context_only: bool) -> HashSet<ProcId> {
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

    fn with_callstack(&self, mut e: DMError, steps: &[Step], at: usize) -> DMError {
        let mut path = VecDeque::new();
        let mut cur = Some(at);
        while let Some(i) = cur {
            path.push_front(i);
            cur = steps[i].parent;
        }
        for i in path {
            e.add_note(steps[i].location, format!("{}() called here", self.model.proc_display(steps[i].proc)));
        }
        e
    }

    fn with_list(mut e: DMError, list: &[(String, Location)], what: &str) -> DMError {
        for (name, location) in list {
            e.add_note(*location, format!("{name}{what}"));
        }
        e
    }

    fn sleep_findings(&self, procref: ProcId, location: Location) -> Vec<DMError> {
        let m = self.model;
        let at = m.value(procref).location;
        let mut out = Vec::new();
        if let Some(sleepvec) = self.sleeping_procs.violators.get(&procref) {
            out.push(Self::with_list(
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
                out.push(Self::with_list(self.with_callstack(e, steps, i), sleepvec, "() called here"));
            } else if let Some(children) = self.sleeping_overrides.get(&nextproc) {
                for child in children {
                    if m.is_subtype_of(procref.ty, nextproc.ty) && !m.is_subtype_of(child.ty, procref.ty) {
                        continue;
                    }
                    let e = error(at, format!("{} calls {} which has override child proc that sleeps {}", m.proc_display(procref), m.proc_display(nextproc), m.proc_display(*child)))
                        .with_note(location, "SpacemanDMM_should_not_sleep set here")
                        .with_errortype("must_not_sleep");
                    out.push(Self::with_list(self.with_callstack(e, steps, i), &self.sleeping_procs.violators[child], "() called here"));
                }
            }
            true
        });
        out
    }

    fn pure_findings(&self, procref: ProcId, location: Location) -> Vec<DMError> {
        let m = self.model;
        let at = m.value(procref).location;
        let mut out = Vec::new();
        if let Some(impurevec) = self.impure_procs.violators.get(&procref) {
            out.push(Self::with_list(
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
                out.push(Self::with_list(self.with_callstack(e, steps, i), impurevec, " happens here"));
            } else if let Some(children) = self.impure_overrides.get(&nextproc) {
                for child in children {
                    if m.is_subtype_of(procref.ty, nextproc.ty) && !m.is_subtype_of(child.ty, procref.ty) {
                        continue;
                    }
                    let e = error(at, format!("{} calls {} which has override child proc that does impure operations {}", m.proc_display(procref), m.proc_display(nextproc), m.proc_display(*child)))
                        .with_note(location, "SpacemanDMM_should_not_pure set here")
                        .with_errortype("must_be_pure");
                    out.push(Self::with_list(self.with_callstack(e, steps, i), &self.impure_procs.violators[child], "() called here"));
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

/// One proc's body facts, as the body pass computes them: the entry point an incremental store keeps per proc.
pub fn body_facts(input: &CheckerInput<'_>, shared: &Shared, site: &mut dyn Site, proc: ProcId) -> ProcFacts {
    let m = &input.model;
    let Some(body) = m.value(proc).body else { return ProcFacts::default() };
    let mut walk = Walk::new(m, shared, site, proc);
    walk.run(&input.bodies[body as usize].statements);
    walk.facts
}

/// DreamChecker over the native input, registering diagnostics to `context`; `cli` prints its progress.
pub fn run(context: &Context, input: &CheckerInput<'_>, cli: bool, threads: usize) {
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
    check_var_defs(m, context);
    lap("variables");

    cli_println!(cli, "============================================================");
    cli_println!(cli, "Gathering proc settings...\n");
    let mut procs: Vec<ProcId> = Vec::new();
    m.recurse(m.root(), &mut |t| procs.extend(m.self_procs(t)));
    let mut settings = Settings::default();
    settings.return_type.insert(m.get_proc(m.root(), "get_step").expect("builtin get_step"), StaticType::Type(m.expect("/turf")).into());
    {
        let mut site = input.sites.site();
        for &p in &procs {
            if let Some(body) = m.value(p).body {
                settings_of(m, &mut settings, context, &mut *site, p, &input.bodies[body as usize].statements);
            }
        }
    }
    lap("settings");

    cli_println!(cli, "============================================================");
    cli_println!(cli, "Analyzing proc bodies...\n");
    let bodies: Vec<ProcId> = procs.iter().copied().filter(|&p| m.value(p).body.is_some()).collect();
    for &p in &bodies {
        settings.directives.must_not_sleep.try_copy_from_parent(m, p);
        settings.directives.must_be_pure.try_copy_from_parent(m, p);
    }
    let shared = Shared { return_type: settings.return_type, directives: settings.directives };
    let facts: Vec<ProcFacts> = {
        // One site per worker thread, kept for its batch of bodies.
        let chunk = 64;
        let batches: Vec<&[ProcId]> = bodies.chunks(chunk).collect();
        parallel_map(&batches, threads, |batch| {
            let mut site = input.sites.site();
            batch.iter().map(|&p| body_facts(input, &shared, &mut *site, p)).collect::<Vec<_>>()
        })
        .into_iter()
        .flatten()
        .collect()
    };
    let mut call_tree: HashMap<ProcId, Vec<(ProcId, Location, bool)>> = HashMap::new();
    let mut sleeping = Violations::default();
    let mut impure = Violations::default();
    let mut waitfor: HashSet<ProcId> = HashSet::new();
    let mut used_kwargs: BTreeMap<String, KwargInfo> = BTreeMap::new();
    for (&p, f) in bodies.iter().zip(facts) {
        for e in f.diagnostics {
            context.register_error(e);
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
                    kwargs.bad_overrides_at.insert(m.ty(p.ty).path.clone(), BadOverride { missing, location: m.value(p).location });
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
                e.add_note(called.location, format!("called with {:?} here, and {} other places", arg, called.others));
            } else {
                e.add_note(called.location, format!("called with {arg:?} here"));
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
    let in_order = |table: &ProcDirective| {
        let mut v: Vec<(ProcId, Location)> = table.directive.iter().map(|(p, &(_, l))| (*p, l)).collect();
        v.sort_by_key(|(p, l)| (m.value(*p).location, *l, m.proc_display(*p)));
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
