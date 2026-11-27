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
use dreamchecker::native::input::{Body, CheckerInput, InputType, Site, Sites};
use dreamchecker::native::model::{ModelBuilder, Param, ProcDecl, ProcKind, ProcValue, ReturnType, TypeId, VarFlags};
use dreammaker::Location;
use std::collections::HashMap;

use crate::analysis_tree::{line_end_column, locate_in, matched, signature_parts, var_header, FeedStats, Front, Item, Slot};

struct FrontSites<'f> {
    frontend: &'f ColdFrontend,
    ids: &'f HashMap<Arc<str>, dreammaker::FileId>,
}

struct FrontSite<'f> {
    frontend: &'f ColdFrontend,
    ids: &'f HashMap<Arc<str>, dreammaker::FileId>,
    mapper: dm_tree::frontend::SiteMapper<'f>,
    cache: HashMap<usize, Location>,
    line_files: HashMap<Arc<str>, usize>,
    unregistered: std::sync::atomic::AtomicUsize,
}

impl Sites for FrontSites<'_> {
    fn site(&self) -> Box<dyn Site + '_> {
        Box::new(FrontSite {
            frontend: self.frontend,
            ids: self.ids,
            mapper: self.frontend.site_mapper(),
            cache: HashMap::new(),
            line_files: HashMap::new(),
            unregistered: Default::default(),
        })
    }
}

impl Site for FrontSite<'_> {
    fn locate(&mut self, offset: usize) -> Location {
        if let Some(l) = self.cache.get(&offset) {
            return *l;
        }
        let l = locate_in(self.ids, &self.mapper, offset, &self.unregistered);
        self.cache.insert(offset, l);
        l
    }
    fn line_end(&mut self, offset: usize) -> Location {
        let at = self.locate(offset);
        match line_end_column(self.frontend, offset, &mut self.line_files) {
            Some(column) if at.line != 0 => Location { column, ..at },
            _ => at,
        }
    }
    fn text(&self) -> &str {
        self.frontend.expanded.text.as_str()
    }
    fn invocation(&mut self, offset: usize) -> Option<(Range<usize>, String, Vec<String>)> {
        let found = self.mapper.invocation_output(offset)?;
        Some((found.output, found.name.to_owned(), found.nested.into_iter().map(str::to_owned).collect()))
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
pub fn with_input<R>(front: &Front, run: impl FnOnce(&CheckerInput<'_>, Vec<dreammaker::DMError>, &BuildStats) -> R) -> R {
    use rayon::prelude::*;
    let frontend: &ColdFrontend = &front.frontend;
    let trace = dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some();
    let t = std::time::Instant::now();
    let mut feed = FeedStats::default();
    let m = matched(frontend, &mut feed);
    let sites = FrontSites { frontend, ids: &front.ids };

    // Bodies by member, parsed on every core.
    let arena = BodyArena::new_typed(frontend, |_| true);
    let parsed: Vec<Option<Vec<dm_syntax::Statement>>> = frontend
        .bodies
        .par_iter()
        .map(|o| {
            let body = arena.take_parsed(o).ok()?;
            Some(body.statement_body()?.parsed().statements.clone())
        })
        .collect();
    let mut bodies = Vec::new();
    let mut body_of: HashMap<u32, u32> = HashMap::new();
    for (occurrence, statements) in frontend.bodies.iter().zip(parsed) {
        if let Some(statements) = statements {
            body_of.insert(occurrence.member.0, bodies.len() as u32);
            bodies.push(Body { statements });
        }
    }

    let mut builder = ModelBuilder::with_builtins();
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).unwrap_or("").to_owned();
    let mut site = sites.site();
    let mut line_files = HashMap::new();
    let mut parents: HashMap<TypeId, String> = HashMap::new();
    for node in tree.types() {
        let path = text(node.path);
        let location = m.type_sites.get(&path).map(|&at| site.locate(at)).unwrap_or_else(Location::builtins);
        let ty = builder.add_type_path(location, &path);
        if node.explicit_parent {
            if let Some(parent) = node.parent.and_then(|p| tree.type_node(p)) {
                parents.insert(ty, text(parent.path));
            }
        }
    }
    let mut registered = Vec::new();
    let mut stats = BuildStats { bodies: bodies.len(), ..Default::default() };
    for item in &m.items {
        let Item { owner, name, slot, member, spelling, id } = item;
        let ty = builder.add_type_path(Location::builtins(), owner);
        let location = spelling.as_ref().map(|s| site.locate(s.at)).unwrap_or_else(Location::builtins);
        match slot {
            Slot::VarDeclare => {
                let (type_path, spaceman) = match spelling.as_ref().and_then(|s| var_header(owner, &s.header)) {
                    Some(v) => (v.type_parts, spaceman_bits(v.spaceman)),
                    None => (Vec::new(), 0),
                };
                // SpacemanDMM places a var declaration at the token after its name: the `=`, or the end of its line.
                let location = match spelling.as_ref() {
                    Some(s) => match dm_syntax::top_level_assignment_index(&s.header) {
                        Some(index) => site.locate(s.at + index),
                        None => match line_end_column(frontend, s.at, &mut line_files) {
                            Some(column) if location.line != 0 => Location { column, ..location },
                            _ => location,
                        },
                    },
                    None => location,
                };
                builder.declare_var(ty, name, location, VarFlags(semantic_bits(member.metadata.flags) | spaceman), type_path);
                stats.vars += 1;
            }
            Slot::VarOverride => {
                let location = match spelling.as_ref().and_then(|s| Some(s.at + dm_syntax::top_level_assignment_index(&s.header)?)) {
                    Some(at) => site.locate(at),
                    None => location,
                };
                builder.override_var(ty, name, location);
                stats.vars += 1;
            }
            Slot::Proc | Slot::Verb => {
                let mut parameters = Vec::new();
                let mut return_type = ReturnType::None;
                let mut location = location;
                if let (Some(s), Some(procedure)) = (spelling.as_ref(), member.metadata.procedure.as_ref()) {
                    if let Some((before, arguments, after)) = signature_parts(&s.header) {
                        // SpacemanDMM places a proc at its parameter list's `(`, a parameter at the token after it.
                        let base = s.at + before.len() + 1;
                        location = site.locate(base - 1);
                        for p in procedure.signature.parameters.iter() {
                            let (start, end) = (p.relative_span.start, p.relative_span.end);
                            if let Some(t) = arguments.get(start..end) {
                                let (name, type_path) = parameter(t);
                                parameters.push(Param { name, type_path, location: site.locate(base + end) });
                            }
                        }
                        if procedure.signature.variadic {
                            let at = arguments.rfind("...").map_or(base, |i| base + i);
                            parameters.push(Param { name: "...".into(), type_path: Vec::new(), location: site.locate(at) });
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
                let body = body_of.get(&id.0).copied();
                let r = builder.add_proc(ty, name, declaration, ProcValue { location, parameters, body });
                registered.extend(r.hint);
                stats.procs += 1;
            }
        }
    }
    drop(site);
    let model = builder.finish(&parents);
    if trace {
        dq_hostio::out(false, format_args!("dreamchecker: native input in {:.1?} ({} types, {} bodies)", t.elapsed(), model.types.len(), bodies.len()), true);
    }
    let input = CheckerInput { model, bodies, sites: &sites };
    run(&input, registered, &stats)
}

#[derive(Default)]
pub struct BuildStats {
    pub bodies: usize,
    pub vars: usize,
    pub procs: usize,
}

/// `analyze dreamchecker` on the native checker: the files under the front end's ids, the preprocessor's warnings, then the checks.
pub fn check(dme: &Path, context: &dreammaker::Context, checks: bool, cli: bool, threads: usize) -> Result<(), String> {
    let front = crate::analysis_tree::front(dme)?;
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
    with_input(&front, |input, registered, stats| {
        for e in registered {
            context.register_error(e);
        }
        if cli {
            dq_hostio::out(false, format_args!("parsed {}/{} proc bodies (100%)", stats.bodies, stats.bodies), true);
        }
        if checks {
            dreamchecker::native::run(context, input, cli, threads);
        }
    });
    Ok(())
}

/// Registers [`check`] as `analyze dreamchecker`'s checker.
pub fn register_native_checker() {
    dq_analyze::dreamchecker::register_native(check);
}
