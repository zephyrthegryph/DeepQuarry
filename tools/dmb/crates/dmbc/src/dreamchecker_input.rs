//! The native DreamChecker's input from the compiler front end (doc/rewrite/proposals/lean_unified.md, "2b DREAMCHECKER"): the
//! semantic tree's types and declarations in a [`dreamchecker::native::model::Model`] (with BYOND's builtins), each proc body as its
//! typed statements, and locations placed where SpacemanDMM places them. No SpacemanDMM tree or syntax tree is built.
//!
//! The declaration spellings (a var's declared type, a parameter's name and type, where a declaration sits) are read from the
//! declaration items of the expanded text, matched to the semantic tree's declarations (`analysis_tree::matched`).
use std::ops::Range;
use std::path::Path;
use std::sync::Arc;

use dm_tree::frontend::{BodyArena, ColdFrontend};
use dm_tree::DefinitionMode;
use dreamchecker::native::facts::SettingsFacts;
use dreamchecker::native::input::{Bodies, CheckerInput, InputType, Site, Sites, Where};
use dreamchecker::native::model::ProcId;
use dreamchecker::native::walk::ProcFacts;
use dreamchecker::native::model::{ModelBuilder, Param, ProcDecl, ProcKind, ProcValue, ReturnType, TypeId, VarFlags};
use dreammaker::Location;
use std::collections::HashMap;

use crate::analysis_tree::{line_end_column, locate_in, source_line, matched, signature_parts, var_header, FeedStats, Front, Item, Slot};

struct FrontSites<'f> {
    frontend: &'f ColdFrontend,
    ids: &'f HashMap<Arc<str>, dreammaker::FileId>,
}

struct FrontSite<'f> {
    frontend: &'f ColdFrontend,
    ids: &'f HashMap<Arc<str>, dreammaker::FileId>,
    mapper: dm_tree::frontend::SiteMapper<'f>,
    cache: std::cell::RefCell<HashMap<usize, Location>>,
    line_files: std::cell::RefCell<HashMap<Arc<str>, usize>>,
    unregistered: std::sync::atomic::AtomicUsize,
}

impl Sites for FrontSites<'_> {
    fn site(&self) -> Box<dyn Site + '_> {
        Box::new(FrontSite {
            frontend: self.frontend,
            ids: self.ids,
            mapper: self.frontend.site_mapper(),
            cache: Default::default(),
            line_files: Default::default(),
            unregistered: Default::default(),
        })
    }
}

impl Site for FrontSite<'_> {
    fn locate(&self, offset: usize) -> Location {
        if let Some(l) = self.cache.borrow().get(&offset) {
            return *l;
        }
        let l = locate_in(self.ids, &self.mapper, offset, &self.unregistered);
        self.cache.borrow_mut().insert(offset, l);
        l
    }
    fn line_end(&self, offset: usize) -> Location {
        let at = self.locate(offset);
        match line_end_column(self.frontend, offset, &mut self.line_files.borrow_mut()) {
            Some(column) if at.line != 0 => Location { column, ..at },
            _ => at,
        }
    }
    fn decl_end(&self, offset: usize) -> Location {
        // A header its source line does not spell (`GLOBAL_RAW(/list/x)` writes `var/global/list/x`) comes from a macro.
        let text = self.text();
        let header = text.get(offset..).map(|r| r.split('\n').next().unwrap_or("").trim()).unwrap_or("");
        let spelled = source_line(self.frontend, offset, &mut self.line_files.borrow_mut()).is_some_and(|l| l.contains(header));
        if spelled {
            self.line_end(offset)
        } else {
            self.locate(offset)
        }
    }
    fn text(&self) -> &str {
        self.frontend.expanded.text.as_str()
    }
    fn invocation(&self, offset: usize) -> Option<(Range<usize>, String, Vec<String>)> {
        let found = self.mapper.invocation_output(offset)?;
        Some((found.output, found.name.to_owned(), found.nested.into_iter().map(str::to_owned).collect()))
    }
}

/// The front end's bodies, parsed on demand.
struct FrontBodies<'f> {
    frontend: &'f ColdFrontend,
    arena: &'f BodyArena<'f>,
    /// A body is taken from the arena once; the settings and the body pass both read it.
    parsed: Vec<std::sync::OnceLock<Option<Arc<Vec<dm_syntax::Statement>>>>>,
}

impl Bodies for FrontBodies<'_> {
    fn statements(&self, body: u32) -> Option<Arc<Vec<dm_syntax::Statement>>> {
        self.parsed
            .get(body as usize)?
            .get_or_init(|| {
                let parsed = self.arena.take_parsed(self.frontend.bodies.get(body as usize)?).ok()?;
                Some(Arc::new(parsed.statement_body()?.parsed().statements.clone()))
            })
            .clone()
    }
}

/// The per-proc results as entries of the analysis query database (`dq_analyze::incr::keyed_by`: held in memory by the daemon,
/// persisted standalone), so a run computes only the procs whose inputs changed.
///
/// What decides a result, and so its key:
///
/// * the proc (`ProcId`) and its body: the body's expanded text, the path and bytes of its file and its place there (a token's
///   line and column come from them);
/// * the model's declarations (`model_key`): every declaration's owner, name, kind, flags, spelling and place (its line, its
///   column), the types and their explicit parents, and the file-id table (a diagnostic of one proc names another's place);
/// * for a body, also every proc's settings facts (the tables a walk reads).
///
/// A body's places (`Where` offsets in the expanded text) are kept relative to the body's start, so a result is valid wherever the
/// body moved in the expanded text.
pub struct QueryStore<'f> {
    frontend: &'f ColdFrontend,
    model_key: u128,
    /// By body occurrence: its key and its start in the expanded text.
    body_keys: Vec<(u128, usize)>,
}

fn h(bytes: &[u8]) -> u128 {
    xxhash_rust::xxh3::xxh3_128(bytes)
}

impl<'f> QueryStore<'f> {
    fn new(front: &'f Front, m: &crate::analysis_tree::Matched<'_>) -> Self {
        use rayon::prelude::*;
        let frontend: &ColdFrontend = &front.frontend;
        let files: HashMap<&Path, u128> =
            frontend.files.par_iter().map(|f| (f.path.as_path(), h(f.text.as_str().as_bytes()))).collect::<Vec<_>>().into_iter().collect();
        let expanded = frontend.expanded.text.as_str();
        let body_keys: Vec<(u128, usize)> = frontend
            .bodies
            .par_iter()
            .map(|o| {
                let text = expanded.get(o.expanded_span.start..o.expanded_span.end).unwrap_or("");
                let path: &Path = o.source.path.as_path();
                let content = files.get(path).copied().unwrap_or(0);
                let key = dq_analyze::incr::mix(&[
                    h(text.as_bytes()),
                    h(o.source.semantic_path.as_bytes()),
                    content,
                    o.source.span.start as u128 | (o.source.span.end as u128) << 64,
                ]);
                (key, o.expanded_span.start)
            })
            .collect();
        let tree = &frontend.snapshot.tree;
        let symbols = tree.symbols();
        let mut decl: Vec<u8> = Vec::new();
        decl.extend_from_slice(b"dreamchecker-native-model-v1");
        for node in tree.types() {
            decl.extend_from_slice(symbols.text(node.path).unwrap_or("").as_bytes());
            decl.extend_from_slice(&[node.explicit_parent as u8, 0xff]);
            if let Some(parent) = node.parent.and_then(|p| tree.type_node(p)) {
                decl.extend_from_slice(symbols.text(parent.path).unwrap_or("").as_bytes());
            }
            decl.extend_from_slice(&[0xfe]);
        }
        // Each declaration with its place: the line it maps to and its column in the expanded text (a diagnostic of one proc names
        // another's place, which an edit elsewhere moves only by moving that line).
        let places: Vec<(usize, usize)> = m
            .items
            .par_iter()
            .map(|item| match &item.spelling {
                Some(s) => {
                    let line = frontend.debug_site(s.at).map_or(0, |(_, line)| line);
                    let column = s.at - expanded[..s.at.min(expanded.len())].rfind('\n').map_or(0, |i| i + 1);
                    (line, column)
                }
                None => (0, 0),
            })
            .collect();
        for (item, (line, column)) in m.items.iter().zip(places) {
            decl.extend_from_slice(item.owner.as_bytes());
            decl.extend_from_slice(&[0xff]);
            decl.extend_from_slice(item.name.as_bytes());
            decl.extend_from_slice(&[item.slot as u8, item.member.definition as u8]);
            decl.extend_from_slice(&item.member.metadata.flags.to_le_bytes());
            decl.extend_from_slice(&(line as u64).to_le_bytes());
            decl.extend_from_slice(&(column as u64).to_le_bytes());
            decl.extend_from_slice(item.spelling.as_ref().map_or("", |s| s.header.as_str()).as_bytes());
            decl.extend_from_slice(&[0xfe]);
        }
        let mut ids: Vec<(&Arc<str>, &dreammaker::FileId)> = front.ids.iter().collect();
        ids.sort();
        decl.extend_from_slice(format!("{ids:?}").as_bytes());
        let model_key = h(&decl);
        // DQ_DREAMCHECKER_KEY_TRACE=1: what the model key is made of, by part (an edit that recomputes every proc shows which moved).
        if dq_hostio::var_os("DQ_DREAMCHECKER_KEY_TRACE").is_some() {
            for item in &m.items {
                let header = item.spelling.as_ref().map_or("", |s| s.header.as_str());
                dq_hostio::out(false, format_args!("dreamchecker key: item {} {} {:?} {:032x}", item.owner, item.name, item.slot, h(header.as_bytes())), true);
            }
            dq_hostio::out(false, format_args!("dreamchecker key: model {model_key:032x}"), true);
        }
        QueryStore { frontend, model_key, body_keys }
    }

    fn keys(&self, bodies: &[u32], procs: &[ProcId]) -> Vec<u128> {
        procs
            .iter()
            .zip(bodies)
            .map(|(p, b)| {
                let body = self.body_keys.get(*b as usize).map_or(0, |(k, _)| *k);
                dq_analyze::incr::mix(&[body, (p.ty.0 as u128) << 64 | (p.slot as u128) << 32 | p.idx as u128])
            })
            .collect()
    }
}

impl dreamchecker::native::Store for QueryStore<'_> {
    fn settings(&self, procs: &[ProcId], bodies: &[u32], compute: &(dyn Fn(usize) -> SettingsFacts + Sync)) -> Vec<SettingsFacts> {
        let keys = self.keys(bodies, procs);
        let ctx = dq_analyze::incr::ctx_key(&("dreamchecker-settings-v1", self.model_key));
        dq_analyze::incr::keyed_by("dreamchecker-settings", ctx, &keys, compute)
    }
    fn bodies(&self, procs: &[ProcId], bodies: &[u32], settings: &[SettingsFacts], compute: &(dyn Fn(usize) -> ProcFacts + Sync)) -> Vec<ProcFacts> {
        let keys = self.keys(bodies, procs);
        let ctx = dq_analyze::incr::ctx_key(&("dreamchecker-bodies-v1", self.model_key, dq_analyze::incr::ctx_key(settings)));
        let base = |i: usize| self.body_keys.get(bodies[i] as usize).map_or(0, |(_, s)| *s);
        let mut out = dq_analyze::incr::keyed_by("dreamchecker-bodies", ctx, &keys, |i| {
            let mut f = compute(i);
            let at = base(i);
            f.map_places(|o| o - at);
            f
        });
        for (i, f) in out.iter_mut().enumerate() {
            let at = base(i);
            f.map_places(|o| o + at);
        }
        out
    }
}

/// A parameter declaration's name and type (`var/mob/user = null`, `atom/A as obj in view()`).
fn parameter(text: &str) -> (String, Vec<String>) {
    let declaration = match dm_syntax::top_level_assignment_index(text) {
        Some(index) => text[..index].trim(),
        None => text.trim(),
    };
    let declaration = declaration.split(" in ").next().unwrap_or(declaration);
    let declaration = declaration.split(" as ").next().unwrap_or(declaration).trim();
    let suffixed = declaration.contains('[');
    let declaration = declaration.split('[').next().unwrap_or(declaration).trim();
    let declaration = declaration.strip_prefix("var/").unwrap_or(declaration);
    let pieces: Vec<&str> = declaration.split('/').filter(|p| !p.is_empty()).collect();
    let name = pieces.last().copied().unwrap_or("").to_owned();
    let mut type_path: Vec<String> =
        pieces[..pieces.len().saturating_sub(1)].iter().filter(|p| VarFlags::from_name(p).is_none()).map(|p| p.to_string()).collect();
    if suffixed {
        type_path.insert(0, "list".to_owned());
    }
    (name, type_path)
}

/// A proc's `as T` return annotation (the header text after the parameter list).
fn return_annotation(after: &str) -> ReturnType {
    let Some(rest) = after.trim().strip_prefix("as") else { return ReturnType::None };
    let rest = rest.trim();
    if rest.starts_with('/') {
        ReturnType::TypePath(rest.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect())
    } else if rest.is_empty() {
        ReturnType::None
    } else {
        let text = rest.split(" in ").next().unwrap_or(rest).trim().trim_start_matches('(').trim_end_matches(')');
        ReturnType::Input(InputType::from_names(&text.split('|').map(str::trim).collect::<Vec<_>>()))
    }
}

fn spaceman_bits(flags: dreammaker::ast::VarTypeFlags) -> u8 {
    let mut bits = 0;
    if flags.is_final() {
        bits |= VarFlags::FINAL;
    }
    if flags.is_private() {
        bits |= VarFlags::PRIVATE;
    }
    if flags.is_protected() {
        bits |= VarFlags::PROTECTED;
    }
    bits
}

fn semantic_bits(bits: u32) -> u8 {
    let mut out = 0;
    if bits & (1 | 8) != 0 {
        out |= VarFlags::STATIC;
    }
    if bits & 2 != 0 {
        out |= VarFlags::CONST;
    }
    if bits & 4 != 0 {
        out |= VarFlags::TMP;
    }
    out
}

/// What the native checker reads, built from `front`; `run` then checks it.
/// `run` also gets what registering the declarations reported (SpacemanDMM's "override precedes definition" hints), in order.
pub fn with_input<R>(front: &Front, run: impl FnOnce(&CheckerInput<'_>, Vec<dreammaker::DMError>, &BuildStats, &QueryStore<'_>) -> R) -> R {
    let frontend: &ColdFrontend = &front.frontend;
    let trace = dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some();
    let t = std::time::Instant::now();
    let mut feed = FeedStats::default();
    let mut lap = {
        let mut mark = std::time::Instant::now();
        move |what: &str| {
            if trace {
                dq_hostio::out(false, format_args!("dreamchecker: native input {what} {:.1?}", mark.elapsed()), true);
            }
            mark = std::time::Instant::now();
        }
    };
    let m = matched(frontend, &mut feed);
    lap("matching");
    let sites = FrontSites { frontend, ids: &front.ids };

    // A member's body is its occurrence, parsed when a result for it is computed.
    let arena = BodyArena::new_typed(frontend, |_| true);
    let mut body_of: HashMap<u32, u32> = HashMap::new();
    for (i, occurrence) in frontend.bodies.iter().enumerate() {
        body_of.insert(occurrence.member.0, i as u32);
    }
    let bodies = FrontBodies { frontend, arena: &arena, parsed: (0..frontend.bodies.len()).map(|_| std::sync::OnceLock::new()).collect() };
    lap("bodies");
    let mut builder = ModelBuilder::with_builtins();
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).unwrap_or("").to_owned();
    let site = sites.site();
    let mut parents: HashMap<TypeId, String> = HashMap::new();
    for node in tree.types() {
        let path = text(node.path);
        let location = m.type_sites.get(&path).map_or(Where::Fixed(Location::builtins()), |&at| Where::At(at));
        let ty = builder.add_type_path(location, &path);
        if node.explicit_parent {
            if let Some(parent) = node.parent.and_then(|p| tree.type_node(p)) {
                parents.insert(ty, text(parent.path));
            }
        }
    }
    let mut registered = Vec::new();
    let mut stats = BuildStats { bodies: frontend.bodies.len(), ..Default::default() };
    // Each declaration's record on every core, registered in declaration order.
    enum Prep {
        Var(Where, VarFlags, Vec<String>),
        Override(Where),
        Proc(Option<ProcDecl>, ProcValue),
    }
    let prepared: Vec<Prep> = {
        use rayon::prelude::*;
        m.items
            .par_iter()
            .map(|item| {
                let Item { owner, slot, member, spelling, id, .. } = item;
                let location = spelling.as_ref().map_or(Where::Fixed(Location::builtins()), |s| Where::At(s.at));
                match slot {
                    Slot::VarDeclare => {
                        let (type_path, spaceman) = match spelling.as_ref().and_then(|s| var_header(owner, &s.header)) {
                            Some(v) => (v.type_parts, spaceman_bits(v.spaceman)),
                            None => (Vec::new(), 0),
                        };
                        // SpacemanDMM places a var declaration at the token after its name: the `=`, or the end of its line.
                        let location = match spelling.as_ref() {
                            Some(s) => match dm_syntax::top_level_assignment_index(&s.header) {
                                Some(index) => Where::At(s.at + index),
                                None => Where::DeclEnd(s.at),
                            },
                            None => location,
                        };
                        Prep::Var(location, VarFlags(semantic_bits(member.metadata.flags) | spaceman), type_path)
                    }
                    Slot::VarOverride => Prep::Override(
                        match spelling.as_ref().and_then(|s| Some(s.at + dm_syntax::top_level_assignment_index(&s.header)?)) {
                            Some(at) => Where::At(at),
                            None => location,
                        },
                    ),
                    Slot::Proc | Slot::Verb => {
                        let mut parameters = Vec::new();
                        let mut return_type = ReturnType::None;
                        let mut location = location;
                        if let (Some(s), Some(procedure)) = (spelling.as_ref(), member.metadata.procedure.as_ref()) {
                            if let Some((before, arguments, after)) = signature_parts(&s.header) {
                                // SpacemanDMM places a proc at its parameter list's `(`, a parameter at the token after it.
                                let base = s.at + before.len() + 1;
                                location = Where::At(base - 1);
                                for p in procedure.signature.parameters.iter() {
                                    let (start, end) = (p.relative_span.start, p.relative_span.end);
                                    if let Some(t) = arguments.get(start..end) {
                                        let (name, type_path) = parameter(t);
                                        parameters.push(Param { name, type_path, location: Where::At(base + end) });
                                    }
                                }
                                if procedure.signature.variadic {
                                    let at = arguments.rfind("...").map_or(base, |i| base + i);
                                    parameters.push(Param { name: "...".into(), type_path: Vec::new(), location: Where::At(at) });
                                }
                                return_type = return_annotation(after);
                            }
                        }
                        let declaration = (member.definition == DefinitionMode::Declare).then(|| ProcDecl {
                            kind: if *slot == Slot::Verb { ProcKind::Verb } else { ProcKind::Proc },
                            is_final: false,
                            location,
                            return_type,
                        });
                        Prep::Proc(declaration, ProcValue { location, parameters, body: body_of.get(&id.0).copied() })
                    }
                }
            })
            .collect()
    };
    for (item, prep) in m.items.iter().zip(prepared) {
        let ty = builder.add_type_path(Where::Fixed(Location::builtins()), &item.owner);
        match prep {
            Prep::Var(location, flags, type_path) => {
                builder.declare_var(ty, &item.name, location, flags, type_path);
                stats.vars += 1;
            }
            Prep::Override(location) => {
                builder.override_var(ty, &item.name, location);
                stats.vars += 1;
            }
            Prep::Proc(declaration, value) => {
                let r = builder.add_proc(ty, &item.name, declaration, value);
                registered.extend(r.hint.map(|h| h.error(&*site)));
                stats.procs += 1;
            }
        }
    }
    drop(site);
    let model = builder.finish(&parents);
    lap("model");
    if trace {
        dq_hostio::out(false, format_args!("dreamchecker: native input in {:.1?} ({} types, {} bodies)", t.elapsed(), model.types.len(), frontend.bodies.len()), true);
    }
    let input = CheckerInput { model, bodies: &bodies, sites: &sites };
    let store = QueryStore::new(front, &m);
    lap("keys");
    run(&input, registered, &stats, &store)
}

#[derive(Default)]
pub struct BuildStats {
    pub bodies: usize,
    pub vars: usize,
    pub procs: usize,
}

/// `analyze dreamchecker` on the native checker: the files under the front end's ids, the preprocessor's warnings, then the checks.
pub fn check(dme: &Path, context: &dreammaker::Context, checks: bool, cli: bool, threads: usize) -> Result<(), String> {
    let trace = dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some();
    let started = std::time::Instant::now();
    let front = crate::analysis_tree::front(dme)?;
    if trace {
        dq_hostio::out(false, format_args!("dreamchecker: front end {:.1?} (built {:.1?})", started.elapsed(), front.built), true);
    }
    front.files_ctx.clone_file_list().for_each(|p| {
        context.register_file(p);
    });
    let mut ids = front.ids.clone();
    let mut place = |path: &str, line: usize, column: usize| {
        let file = *ids.entry(Arc::from(path)).or_insert_with(|| context.register_file(&front.registered(path)));
        Location { file, line: line as u32, column: column.min(u16::MAX as usize) as u16 }
    };
    for e in crate::analysis_tree::macro_warnings(&front.frontend, front.initial.clone(), &mut place) {
        context.register_error(e);
    }
    if trace {
        dq_hostio::out(false, format_args!("dreamchecker: preprocessor warnings at {:.1?}", started.elapsed()), true);
    }
    let _ = threads;
    with_input(&front, |input, registered, stats, store| {
        for e in registered {
            context.register_error(e);
        }
        if cli {
            dq_hostio::out(false, format_args!("parsed {}/{} proc bodies (100%)", stats.bodies, stats.bodies), true);
        }
        if checks {
            dreamchecker::native::run(context, input, cli, store);
        }
    });
    Ok(())
}

/// Registers [`check`] as `analyze dreamchecker`'s checker.
pub fn register_native_checker() {
    dq_analyze::dreamchecker::register_native(check);
}
