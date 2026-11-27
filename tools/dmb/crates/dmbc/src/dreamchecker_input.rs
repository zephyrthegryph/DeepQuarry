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
use dreamchecker::native::facts::{Diag, SettingsFacts};
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

/// The per-proc results as entries of the analysis query database (`dq_analyze::incr::keyed_reading_by`: held in memory by the
/// daemon, persisted standalone), so a run computes only the procs whose inputs changed.
///
/// What decides a result, and so its key and context, in terms an edit elsewhere does not move:
///
/// * the proc (`ProcId`) and its body: the body's expanded text, its file's semantic path and the source text of the lines the
///   body spans (its *region*: a token's line and column come from them; a line added above the proc moves none of them);
/// * the model's structure (`structure_key`): every declaration's owner, name, kind, flags and spelling, the types and their
///   explicit parents, and the file-id table; not where the declarations are (see below);
/// * for a body, also every proc's settings facts in the form they are stored in (below).
///
/// A result's places are stored so that moving its region keeps it valid: its `Where` offsets relative to the body's start in
/// the expanded text, and each location inside its region (its own file, a line of the region) relative to the region's first
/// line; both are rebased to the current revision when it is read back. A location outside its region (a note naming another
/// declaration, a directive another proc set) is kept as it is and recorded as a read of its file's content
/// (`incr::Reads`): the result is computed again when that file changed.
pub struct QueryStore {
    structure_key: u128,
    /// By body occurrence.
    regions: Vec<Region>,
    /// Every file's content by semantic path (what a location outside a result's region reads).
    contents: dq_analyze::incr::Index<Arc<str>, u128>,
    /// By file id: its semantic path.
    paths: HashMap<dreammaker::FileId, Arc<str>>,
    /// The digest of every proc's settings in their stored form, set by `settings` for `bodies`.
    settings_digest: std::sync::Mutex<u128>,
}

/// One body's key and the region its places are stored relative to.
struct Region {
    key: u128,
    /// The body's start in the expanded text.
    start: usize,
    /// Its file's id, and the first and last line it spans (1-based).
    file: Option<dreammaker::FileId>,
    first: u32,
    last: u32,
}

/// A result with its places stored relative to its region (see [`QueryStore`]): `own` holds the indices (in `map_locations`
/// order) of the locations whose line is relative to the region's first line.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct Rel<T> {
    value: T,
    own: Vec<u32>,
}

fn h(bytes: &[u8]) -> u128 {
    xxhash_rust::xxh3::xxh3_128(bytes)
}

impl QueryStore {
    fn new(front: &Front, m: &crate::analysis_tree::Matched<'_>) -> Self {
        use rayon::prelude::*;
        let frontend: &ColdFrontend = &front.frontend;
        let by_path: HashMap<&Path, &dm_tree::frontend::SourceFile> = frontend.files.iter().map(|f| (f.path.as_path(), f)).collect();
        let expanded = frontend.expanded.text.as_str();
        let ids = &front.ids;
        let regions: Vec<Region> = frontend
            .bodies
            .par_iter()
            .map(|o| {
                let text = expanded.get(o.expanded_span.start..o.expanded_span.end).unwrap_or("");
                let (region_text, first, last) = match by_path.get(o.source.path.as_path()) {
                    Some(f) => {
                        let starts = &f.line_starts;
                        let src = f.text.as_str();
                        let row = |at: usize| starts.partition_point(|&s| s <= at).saturating_sub(1);
                        let (start, end) = (o.source.span.start as usize, o.source.span.end as usize);
                        let (a, b) = (row(start), row(end.saturating_sub(1).max(start)));
                        let from = starts.get(a).copied().unwrap_or(0).min(src.len());
                        let to = starts.get(b + 1).copied().unwrap_or(src.len()).min(src.len()).max(from);
                        (src.get(from..to).unwrap_or(""), a as u32 + 1, b as u32 + 1)
                    }
                    None => ("", 0, 0),
                };
                let key = dq_analyze::incr::mix(&[h(text.as_bytes()), h(o.source.semantic_path.as_bytes()), h(region_text.as_bytes())]);
                Region { key, start: o.expanded_span.start, file: ids.get(&o.source.semantic_path).copied(), first, last }
            })
            .collect();
        let tree = &frontend.snapshot.tree;
        let symbols = tree.symbols();
        let mut decl: Vec<u8> = Vec::new();
        decl.extend_from_slice(b"dreamchecker-native-structure-v1");
        for node in tree.types() {
            decl.extend_from_slice(symbols.text(node.path).unwrap_or("").as_bytes());
            decl.extend_from_slice(&[node.explicit_parent as u8, 0xff]);
            if let Some(parent) = node.parent.and_then(|p| tree.type_node(p)) {
                decl.extend_from_slice(symbols.text(parent.path).unwrap_or("").as_bytes());
            }
            decl.extend_from_slice(&[0xfe]);
        }
        for item in &m.items {
            decl.extend_from_slice(item.owner.as_bytes());
            decl.extend_from_slice(&[0xff]);
            decl.extend_from_slice(item.name.as_bytes());
            decl.extend_from_slice(&[item.slot as u8, item.member.definition as u8]);
            decl.extend_from_slice(&item.member.metadata.flags.to_le_bytes());
            decl.extend_from_slice(item.spelling.as_ref().map_or("", |s| s.header.as_str()).as_bytes());
            decl.extend_from_slice(&[0xfe]);
        }
        let mut ids: Vec<(&Arc<str>, &dreammaker::FileId)> = front.ids.iter().collect();
        ids.sort();
        decl.extend_from_slice(format!("{ids:?}").as_bytes());
        let structure_key = h(&decl);
        let paths: HashMap<dreammaker::FileId, Arc<str>> = front.ids.iter().map(|(p, id)| (*id, Arc::clone(p))).collect();
        let contents: HashMap<Arc<str>, u128> = {
            let by_file: HashMap<&Path, u128> =
                frontend.files.par_iter().map(|f| (f.path.as_path(), h(f.text.as_str().as_bytes()))).collect::<Vec<_>>().into_iter().collect();
            frontend
                .plan
                .occurrences
                .iter()
                .map(|o| (Arc::clone(&o.semantic_path), by_file.get(o.path.as_path()).copied().unwrap_or(0)))
                .collect()
        };
        // DQ_DREAMCHECKER_KEY_TRACE=1: what the structure key is made of, by part (an edit that recomputes every proc shows which moved).
        if dq_hostio::var_os("DQ_DREAMCHECKER_KEY_TRACE").is_some() {
            for item in &m.items {
                let header = item.spelling.as_ref().map_or("", |s| s.header.as_str());
                dq_hostio::out(false, format_args!("dreamchecker key: item {} {} {:?} {:032x}", item.owner, item.name, item.slot, h(header.as_bytes())), true);
            }
            dq_hostio::out(false, format_args!("dreamchecker key: structure {structure_key:032x}"), true);
        }
        QueryStore {
            structure_key,
            regions,
            contents: dq_analyze::incr::Index::new(contents),
            paths,
            settings_digest: std::sync::Mutex::new(0),
        }
    }

    fn keys(&self, bodies: &[u32], procs: &[ProcId]) -> Vec<u128> {
        procs
            .iter()
            .zip(bodies)
            .map(|(p, b)| {
                let body = self.regions.get(*b as usize).map_or(0, |r| r.key);
                dq_analyze::incr::mix(&[body, (p.ty.0 as u128) << 64 | (p.slot as u128) << 32 | p.idx as u128])
            })
            .collect()
    }

    /// `value` with its locations inside `region` made relative to it; every other location's file recorded as read.
    fn relative<T>(&self, mut value: T, region: Option<&Region>, reads: &dq_analyze::incr::Reads<'_, Arc<str>, u128>, map: impl Fn(&mut T, &mut dyn FnMut(&mut Location))) -> Rel<T> {
        let mut own = Vec::new();
        let mut i = 0u32;
        map(&mut value, &mut |l: &mut Location| {
            match region {
                Some(r) if r.file == Some(l.file) && (r.first..=r.last).contains(&l.line) => {
                    l.line -= r.first;
                    own.push(i);
                }
                _ => {
                    if let Some(path) = self.paths.get(&l.file) {
                        reads.get(path);
                    }
                }
            }
            i += 1;
        });
        Rel { value, own }
    }

    /// The inverse of [`Self::relative`] at `region`'s current place.
    fn absolute<T>(rel: &Rel<T>, region: Option<&Region>, map: impl Fn(&mut T, &mut dyn FnMut(&mut Location))) -> T
    where
        T: Clone,
    {
        let mut value = rel.value.clone();
        let first = region.map_or(0, |r| r.first);
        let mut i = 0u32;
        let mut next = rel.own.iter().copied().peekable();
        map(&mut value, &mut |l: &mut Location| {
            if next.peek() == Some(&i) {
                next.next();
                l.line += first;
            }
            i += 1;
        });
        value
    }
}

fn settings_locations(s: &mut SettingsFacts, f: &mut dyn FnMut(&mut Location)) {
    s.map_locations(f)
}

fn facts_locations(s: &mut ProcFacts, f: &mut dyn FnMut(&mut Location)) {
    s.map_locations(f)
}

impl dreamchecker::native::Store for QueryStore {
    fn settings(&self, procs: &[ProcId], bodies: &[u32], compute: &(dyn Fn(usize) -> SettingsFacts + Sync)) -> Vec<SettingsFacts> {
        let keys = self.keys(bodies, procs);
        let ctx = dq_analyze::incr::ctx_key(&("dreamchecker-settings-v2", self.structure_key));
        let region = |i: usize| self.regions.get(bodies[i] as usize);
        let stored: Vec<Rel<SettingsFacts>> = dq_analyze::incr::keyed_reading_by("dreamchecker-settings", ctx, &keys, &self.contents, |i, reads| {
            self.relative(compute(i), region(i), reads, settings_locations)
        });
        *self.settings_digest.lock().unwrap_or_else(|e| e.into_inner()) = dq_analyze::incr::ctx_key(&stored);
        stored.iter().enumerate().map(|(i, r)| Self::absolute(r, region(i), settings_locations)).collect()
    }
    fn bodies(&self, procs: &[ProcId], bodies: &[u32], _settings: &[SettingsFacts], compute: &(dyn Fn(usize) -> ProcFacts + Sync)) -> Vec<ProcFacts> {
        let keys = self.keys(bodies, procs);
        let settings = *self.settings_digest.lock().unwrap_or_else(|e| e.into_inner());
        let ctx = dq_analyze::incr::ctx_key(&("dreamchecker-bodies-v2", self.structure_key, settings));
        let region = |i: usize| self.regions.get(bodies[i] as usize);
        let stored: Vec<Rel<ProcFacts>> = dq_analyze::incr::keyed_reading_by("dreamchecker-bodies", ctx, &keys, &self.contents, |i, reads| {
            let mut f = compute(i);
            let at = region(i).map_or(0, |r| r.start);
            f.map_places(|o| o - at);
            self.relative(f, region(i), reads, facts_locations)
        });
        stored
            .iter()
            .enumerate()
            .map(|(i, r)| {
                let mut f = Self::absolute(r, region(i), facts_locations);
                let at = region(i).map_or(0, |r| r.start);
                f.map_places(|o| o + at);
                f
            })
            .collect()
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
pub fn with_input<R>(front: &Front, run: impl FnOnce(&CheckerInput<'_>, Vec<dreammaker::DMError>, &BuildStats, &QueryStore) -> R) -> R {
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

/// What one run registered, kept in the daemon for the front end revision it read (see [`check`]).
struct Remembered {
    dme: std::path::PathBuf,
    frontend: dm_tree::frontend::FrontendIssuance,
    checks: bool,
    /// Every file the run registered, in order (the ids its diagnostics carry).
    files: Vec<std::path::PathBuf>,
    /// Every diagnostic, in registration order, before the config's severities and filters.
    diagnostics: Vec<Diag>,
    bodies: usize,
}

static REMEMBERED: std::sync::Mutex<Option<Remembered>> = std::sync::Mutex::new(None);

/// `analyze dreamchecker` on the native checker: the files under the front end's ids, the preprocessor's warnings, then the checks.
///
/// Every diagnostic is registered on a context of its own (no config, nothing printed) and then onto `context` in the same order,
/// so what a run found is data apart from the config. In the daemon the last run's files and diagnostics are kept for the front
/// end revision they came from: a request whose front end is that revision (the hosted front end returns the remembered one
/// when no source changed) registers them again without checking anything.
pub fn check(dme: &Path, context: &dreammaker::Context, checks: bool, cli: bool, threads: usize) -> Result<(), String> {
    let trace = dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some();
    let started = std::time::Instant::now();
    let front = crate::analysis_tree::front(dme)?;
    if trace {
        dq_hostio::out(false, format_args!("dreamchecker: front end {:.1?} (built {:.1?})", started.elapsed(), front.built), true);
    }
    let hosted = crate::daemon::hosting();
    if hosted {
        let kept = REMEMBERED.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(r) = kept.as_ref().filter(|r| r.dme == dme && r.checks == checks && r.frontend.matches(&front.frontend)) {
            replay(context, &r.files, &r.diagnostics, r.bodies, checks, cli);
            if trace {
                dq_hostio::out(false, format_args!("dreamchecker: front end revision unchanged, {} diagnostics replayed at {:.1?}", r.diagnostics.len(), started.elapsed()), true);
            }
            return Ok(());
        }
    }
    let own = dreammaker::Context::default();
    let bodies = check_into(&front, &own, checks, threads, trace, started);
    let files: Vec<std::path::PathBuf> = {
        let mut v = Vec::new();
        own.clone_file_list().for_each(|p| v.push(p.to_path_buf()));
        v
    };
    let diagnostics: Vec<Diag> = own.take_errors().iter().map(Diag::of).collect();
    replay(context, &files, &diagnostics, bodies, checks, cli);
    if hosted {
        *REMEMBERED.lock().unwrap_or_else(|e| e.into_inner()) =
            Some(Remembered { dme: dme.to_path_buf(), frontend: front.frontend.issuance(), checks, files, diagnostics, bodies });
    }
    if trace {
        dq_hostio::out(false, format_args!("dreamchecker: done at {:.1?}; {}", started.elapsed(), dq_analyze::incr::stats()), true);
    }
    Ok(())
}

/// Registers a run's files and diagnostics on `context`, printing what the checker prints on the way under `cli`.
fn replay(context: &dreammaker::Context, files: &[std::path::PathBuf], diagnostics: &[Diag], bodies: usize, checks: bool, cli: bool) {
    for f in files {
        context.register_file(f);
    }
    if cli {
        dq_hostio::out(false, format_args!("parsed {bodies}/{bodies} proc bodies (100%)"), true);
        if checks {
            dreamchecker::native::print_sections();
        }
    }
    for d in diagnostics {
        context.register_error(d.error());
    }
}

/// The checks of `front` onto `context` (a context of the run's own); the number of bodies.
fn check_into(front: &Front, context: &dreammaker::Context, checks: bool, threads: usize, trace: bool, started: std::time::Instant) -> usize {
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
    with_input(front, |input, registered, stats, store| {
        for e in registered {
            context.register_error(e);
        }
        if checks {
            dreamchecker::native::run(context, input, false, store, threads);
        }
        stats.bodies
    })
}

/// Registers [`check`] as `analyze dreamchecker`'s checker.
pub fn register_native_checker() {
    dq_analyze::dreamchecker::register_native(check);
}
