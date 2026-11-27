//! The declaration items of dmbc's front end matched to the semantic tree's declarations, and the source-line helpers DreamChecker's
//! native input reads (`crate::dreamchecker_input`). The tree converted from them to dreammaker's shapes for dq-analyze is gone: the
//! analysis reads the front end directly (`dq_analyze::model`, doc/rewrite/proposals/lean_unified.md, 2a).
use dm_syntax::ItemKind;
use dm_tree::frontend::{ColdFrontend, ItemView};
use dm_tree::{DefinitionMode, MemberKind, Target};
use dreammaker::ast::VarTypeFlags;
use dreammaker::Location;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// What a declaration item spells: its header (expanded text) and where it starts.
#[derive(Clone)]
pub(crate) struct Spelled {
    pub(crate) header: String,
    pub(crate) at: usize,
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Debug)]
pub(crate) enum Slot {
    VarDeclare,
    VarOverride,
    Proc,
    Verb,
}

pub(crate) type Key = (String, String, Slot);

fn absolute(owner: &str, path: &str) -> String {
    let path = path.trim_end_matches('/');
    if path.is_empty() {
        owner.into()
    } else if path.starts_with('/') {
        path.into()
    } else if owner == "/" {
        format!("/{path}")
    } else {
        format!("{owner}/{path}")
    }
}

/// `(before, arguments, after)` of a proc header: the first top-level parenthesis group.
pub(crate) fn signature_parts(header: &str) -> Option<(&str, &str, &str)> {
    let mut open = None;
    let mut depth = 0usize;
    for token in dm_syntax::lex(header).tokens {
        match token.text.as_str() {
            "(" => {
                if depth == 0 {
                    open = Some(token.span.start);
                }
                depth += 1;
            }
            ")" => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    let start = open?;
                    return Some((&header[..start], &header[start + 1..token.span.start], &header[token.span.end..]));
                }
            }
            _ => {}
        }
    }
    None
}

/// A var header's owner, name, declared type pieces (flags removed) and SpacemanDMM flags, the way dm-tree's adapter reads it.
pub(crate) struct VarHeader {
    owner: String,
    name: String,
    pub(crate) type_parts: Vec<String>,
    /// The SpacemanDMM flags the spelling names.
    pub(crate) spaceman: VarTypeFlags,
}

pub(crate) fn var_header(owner: &str, header: &str) -> Option<VarHeader> {
    let declaration = match dm_syntax::top_level_assignment_index(header) {
        Some(index) => header[..index].trim(),
        None => header,
    };
    let separator = declaration.match_indices("var/").find(|(index, _)| *index == 0 || declaration.as_bytes()[index - 1] == b'/')?.0;
    let (prefix, tail) = (&declaration[..separator], &declaration[separator + 4..]);
    let owner = if prefix == "/" || (prefix.is_empty() && header.starts_with('/')) {
        "/".into()
    } else if prefix.is_empty() {
        owner.into()
    } else {
        absolute(owner, prefix.trim_end_matches('/'))
    };
    let normalized = dm_syntax::normalize_declaration_type(tail);
    let tail = normalized.split_once(" as ").map_or(normalized, |(d, _)| d).trim();
    let parts: Vec<&str> = tail.split('/').collect();
    let last = parts.last()?.split(" as ").next()?;
    let name = last.split('[').next()?.trim().to_owned();
    // `var/L[10]`, `var/L[2][][3]`: dreammaker's suffix makes the type `list/...`.
    let suffixed = last.contains('[');
    if name.is_empty() {
        return None;
    }
    let mut type_parts: Vec<String> = parts[..parts.len() - 1]
        .iter()
        .filter(|p| VarTypeFlags::from_name(p).is_none())
        .map(|p| p.to_string())
        .collect();
    if suffixed {
        type_parts.insert(0, "list".to_owned());
    }
    // `SpacemanDMM_private`, `_protected`, `_final` (the analysis build's VAR_PRIVATE and friends) are flags in dreammaker, which the
    // semantic tree does not carry: read them from the spelling.
    let spaceman = parts[..parts.len() - 1].iter().filter_map(|p| VarTypeFlags::from_name(p)).fold(VarTypeFlags::default(), |a, b| a | b)
        & (VarTypeFlags::PRIVATE | VarTypeFlags::PROTECTED | VarTypeFlags::FINAL);
    Some(VarHeader { owner, name, type_parts, spaceman })
}

/// Walk the declaration items as dm-tree's adapter does (`adapter::walk`): the owner a Type item names carries to its children and to
/// the items after it.
fn walk<'a>(
    items: impl Iterator<Item = ItemView<'a>>,
    owner: &str,
    spelled: &mut HashMap<Key, VecDeque<Spelled>>,
    types: &mut HashMap<String, usize>,
    starts: &mut Vec<usize>,
) {
    let nesting = owner.to_owned();
    let mut containing = owner.to_owned();
    for item in items {
        // dm-tree normalizes `var/`, `proc/` and `verb/` members to absolute headers under the block they are written in
        // (`normalize::walk`) before the adapter's carry applies, so only the other items take the carried owner.
        let owner = if matches!(item.kind(), ItemKind::Var | ItemKind::Proc | ItemKind::Verb) { nesting.clone() } else { containing.clone() };
        let raw = item.header();
        let header = raw.trim();
        let at = item.header_span().start + (raw.len() - raw.trim_start().len());
        starts.push(at);
        let entry = Spelled { header: header.to_owned(), at };
        match item.kind() {
            ItemKind::Type => {
                let path = absolute(&owner, header);
                types.entry(path.clone()).or_insert(at);
                // A bare relative word with no block (`clown` under `/mob/.../clown`) declares the child type only: the items after it
                // stay on the enclosing type, as the semantic tree reads them.
                if header.starts_with('/') || item.children().next().is_some() {
                    containing = path.clone();
                }
                walk(item.children(), &path, spelled, types, starts);
            }
            ItemKind::Var => {
                if let Some(v) = var_header(&owner, header) {
                    spelled.entry((v.owner, v.name, Slot::VarDeclare)).or_default().push_back(entry);
                }
            }
            ItemKind::Proc | ItemKind::Verb => {
                let Some((raw, _, _)) = signature_parts(header) else { continue };
                let raw = raw.trim().trim_end_matches('/');
                let marker = if item.kind() == ItemKind::Verb { "verb/" } else { "proc/" };
                let (prefix, name) = raw
                    .strip_prefix(marker)
                    .map(|name| ("", name))
                    .or_else(|| raw.rsplit_once(&format!("/{marker}")))
                    .or_else(|| raw.rsplit_once('/'))
                    .unwrap_or(("", raw));
                let owner = if prefix == "/" || (prefix.is_empty() && raw.starts_with('/')) {
                    "/".into()
                } else if prefix.is_empty() {
                    owner.clone()
                } else {
                    absolute(&owner, prefix)
                };
                let slot = if item.kind() == ItemKind::Verb { Slot::Verb } else { Slot::Proc };
                spelled.entry((owner, name.to_owned(), slot)).or_default().push_back(entry);
            }
            ItemKind::Unknown | ItemKind::Statement => {
                let Some(index) = dm_syntax::top_level_assignment_index(header) else {
                    // A bare word with an indented block (`clown` under `/mob/.../clown`): the semantic tree reads its children as
                    // members of the enclosing owner.
                    walk(item.children(), &owner, spelled, types, starts);
                    continue;
                };
                let target = header[..index].trim();
                let (owner, name) = match target.rsplit_once('/') {
                    Some(("", name)) => ("/".to_owned(), name),
                    Some((prefix, name)) => (absolute(&owner, prefix), name),
                    None => (owner.clone(), target),
                };
                // `parent_type = /x` is no member of the semantic tree (it is the type's explicit parent); it stays here and the
                // builder gets it as the override dreammaker records.
                spelled.entry((owner, name.to_owned(), Slot::VarOverride)).or_default().push_back(entry);
            }
        }
    }
}

/// The source line `offset` maps to, without its line break.
pub(crate) fn source_line<'f>(frontend: &'f ColdFrontend, offset: usize, files: &mut HashMap<Arc<str>, usize>) -> Option<&'f str> {
    let (path, line, _) = frontend.debug_site_column(offset)?;
    if files.is_empty() {
        for (i, f) in frontend.files.iter().enumerate() {
            files.insert(Arc::from(f.path.to_string_lossy().as_ref()), i);
        }
    }
    let file = frontend.files.get(*files.get(&path).or_else(|| {
        let p = Path::new(&*path);
        files.iter().find(|(k, _)| Path::new(&**k as &str).ends_with(p)).map(|(_, v)| v)
    })?)?;
    let text = file.text.as_str();
    let start = *file.line_starts.get(line.checked_sub(1)?)?;
    let rest = &text[start.min(text.len())..];
    let len = rest.find('\n').unwrap_or(rest.len());
    Some(rest[..len].strip_suffix('\r').unwrap_or(&rest[..len]))
}

/// The column one past the end of the source line `offset` maps to (its comments included), as dreammaker's newline token sits.
pub(crate) fn line_end_column(frontend: &ColdFrontend, offset: usize, files: &mut HashMap<Arc<str>, usize>) -> Option<u16> {
    let (path, line, _) = frontend.debug_site_column(offset)?;
    if files.is_empty() {
        for (i, f) in frontend.files.iter().enumerate() {
            files.insert(Arc::from(f.path.to_string_lossy().as_ref()), i);
        }
    }
    let file = frontend.files.get(*files.get(&path).or_else(|| {
        let p = Path::new(&*path);
        files.iter().find(|(k, _)| Path::new(&**k as &str).ends_with(p)).map(|(_, v)| v)
    })?)?;
    let text = file.text.as_str();
    let start = *file.line_starts.get(line.checked_sub(1)?)?;
    let rest = &text[start.min(text.len())..];
    let len = rest.find('\n').unwrap_or(rest.len());
    let len = rest[..len].strip_suffix('\r').map_or(len, str::len);
    Some((len + 1).min(u16::MAX as usize) as u16)
}

/// Counters of the feed itself.
#[derive(Default, Debug)]
pub struct FeedStats {
    pub types: usize,
    pub vars: usize,
    pub procs: usize,
    pub bodies: usize,
    pub missing_spelling: usize,
    pub expression_failures: usize,
    pub proc_errors: usize,
    /// Bodies dreammaker's parser would reject, as its parse errors (their procs have no code).
    pub parse_errors: Vec<dreammaker::DMError>,
}

/// Makes one location mapper per worker thread: an expanded offset to a dreammaker location. The mappers answer alike (they read the
/// same front end and the same file ids); each keeps its own cache.
pub type Locator<'a> = dyn Fn() -> Box<dyn FnMut(usize) -> Location + 'a> + Sync + 'a;

/// A declaration of the semantic tree with the spelling matched to it.
pub(crate) struct Item<'t> {
    pub(crate) id: dm_tree::MemberId,
    pub(crate) owner: String,
    pub(crate) name: String,
    pub(crate) slot: Slot,
    pub(crate) member: &'t dm_tree::MemberNode,
    pub(crate) spelling: Option<Spelled>,
}

/// The semantic tree's declarations with the spelling of each matched to it, the place each type path is first written, and the
/// spellings no declaration took (`parent_type = /x`, which the semantic tree holds as the type's parent).
pub(crate) struct Matched<'t> {
    pub(crate) items: Vec<Item<'t>>,
    pub(crate) type_sites: HashMap<String, usize>,
}

/// Match each declaration of the semantic tree with its spelling (in declaration order: a queue per key).
pub(crate) fn matched<'f>(frontend: &'f ColdFrontend, stats: &mut FeedStats) -> Matched<'f> {
    use rayon::prelude::*;
    // Each chunk's spellings on its own core, merged in chunk order (a key's queue keeps source order).
    type Spellings = (HashMap<Key, VecDeque<Spelled>>, Vec<(String, usize)>);
    let per_chunk: Vec<Spellings> = frontend
        .syntax
        .chunks()
        .par_iter()
        .map(|chunk| {
            let (mut spelled, mut types, mut starts) = (HashMap::new(), HashMap::new(), Vec::new());
            walk(chunk.items(), "/", &mut spelled, &mut types, &mut starts);
            let mut types: Vec<(String, usize)> = types.into_iter().collect();
            types.sort_by_key(|(_, at)| *at);
            (spelled, types)
        })
        .collect();
    let mut spelled: HashMap<Key, VecDeque<Spelled>> = HashMap::new();
    let mut type_sites: HashMap<String, usize> = HashMap::new();
    for (chunk_spelled, chunk_types) in per_chunk {
        for (key, entries) in chunk_spelled {
            spelled.entry(key).or_default().extend(entries);
        }
        for (path, at) in chunk_types {
            type_sites.entry(path).or_insert(at);
        }
    }
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).unwrap_or("").to_owned();
    let mut items: Vec<Item<'_>> = Vec::new();
    for target in tree.declarations() {
        let Target::Member(id) = *target else { continue };
        let Some(member) = tree.member(id) else { continue };
        let Some(owner) = tree.type_node(member.owner) else { continue };
        let owner = text(owner.path);
        let name = text(member.name);
        let slot = match (member.kind, member.definition) {
            (MemberKind::Var, DefinitionMode::Declare) => Slot::VarDeclare,
            (MemberKind::Var, _) => Slot::VarOverride,
            (MemberKind::Proc, _) => Slot::Proc,
            (MemberKind::Verb, _) => Slot::Verb,
        };
        // An override spells no `verb/` or `proc/` marker (`/mob/living/pointed()` overrides a verb), so either slot holds it.
        let alternate = match slot {
            Slot::Proc => Some(Slot::Verb),
            Slot::Verb => Some(Slot::Proc),
            _ => None,
        };
        let spelling = spelled.get_mut(&(owner.clone(), name.clone(), slot)).and_then(VecDeque::pop_front).or_else(|| {
            let alternate = alternate?;
            spelled.get_mut(&(owner.clone(), name.clone(), alternate)).and_then(VecDeque::pop_front)
        });
        if spelling.is_none() {
            stats.missing_spelling += 1;
            if std::env::var_os("DQ_TREE_DEBUG_MISSING").is_some() {
                let near: Vec<_> = spelled.iter().filter(|(k, _)| k.1 == name).map(|(k, v)| (k.0.clone(), k.2, v.len())).collect();
                eprintln!("missing spelling: {owner:?} {name:?} {slot:?} near {near:?}");
            }
        }
        items.push(Item { id, owner, name, slot, member, spelling });
    }
    Matched { items, type_sites }
}

/// dreammaker's preprocessor warnings, from dmbc's plan: `macro redefined` (a `#define` of a name already defined, `FILE_DIR` excepted)
/// and `macro undefined while not defined` (an `#undef` of a name that is not). The plan's regions carry their active `#define` /
/// `#undef` effects in order; each is placed at its directive's name, the next matching directive line of the region's source.
/// `initial`: the names defined before the first file (the predefines and the caller's defines).
pub(crate) fn macro_warnings(
    frontend: &dm_tree::frontend::ColdFrontend,
    initial: impl IntoIterator<Item = String>,
    place: &mut dyn FnMut(&str, usize, usize) -> Location,
) -> Vec<dreammaker::DMError> {
    use dm_preprocess::regions::{MacroEffect, OrderedItem};
    let plan = &frontend.plan;
    let mut defined: HashMap<String, Location> = initial.into_iter().map(|n| (n, Location::builtins())).collect();
    let mut out = Vec::new();
    for item in &plan.items {
        let OrderedItem::Text(region) = item else { continue };
        let region = &plan.regions[*region];
        if region.effects.is_empty() {
            continue;
        }
        let path = plan.occurrences[region.occurrence].path.clone();
        let text = plan.source_texts.get(path.as_ref()).map(|t| t.as_str()).unwrap_or("");
        let starts = plan.source_line_starts.get(path.as_ref());
        let path_text = path.to_string_lossy().into_owned();
        let mut cursor = region.source_span.start.min(text.len());
        let end = region.source_span.end.min(text.len());
        // The next `#word NAME` directive line at or after the cursor: the offset of NAME.
        let find = |word: &str, name: &str, cursor: &mut usize| -> Option<usize> {
            let mut at = *cursor;
            while at < end {
                let line_end = text[at..end].find('\n').map_or(end, |i| at + i + 1);
                let line = &text[at..line_end];
                let lead = line.len() - line.trim_start().len();
                if let Some(d) = line.trim_start().strip_prefix('#') {
                    let dl = d.len() - d.trim_start().len();
                    let d = d.trim_start();
                    if let Some(rest) = d.strip_prefix(word) {
                        let rl = rest.len() - rest.trim_start().len();
                        let rest = rest.trim_start();
                        if rl > 0 && rest.starts_with(name) && !rest[name.len()..].starts_with(|c: char| c.is_alphanumeric() || c == '_') {
                            *cursor = line_end;
                            return Some(at + lead + 1 + dl + word.len() + rl);
                        }
                    }
                }
                at = line_end;
            }
            None
        };
        for effect in region.effects.iter() {
            let (word, name) = match effect {
                MacroEffect::Define { name, .. } => ("define", name),
                MacroEffect::Undef { name } => ("undef", name),
                _ => continue,
            };
            let location = match (find(word, name, &mut cursor), starts) {
                (Some(offset), Some(starts)) => {
                    let row = starts.partition_point(|&s| s <= offset).saturating_sub(1);
                    place(&path_text, row + 1, offset - starts.get(row).copied().unwrap_or(0) + 1)
                }
                _ => Location::builtins(),
            };
            if word == "define" {
                if let Some(previous) = defined.insert(name.clone(), location) {
                    if name != "FILE_DIR" {
                        out.push(
                            dreammaker::DMError::new(location, format!("macro redefined: {name}"))
                                .set_severity(dreammaker::Severity::Warning)
                                .with_note(previous, format!("previous definition of {name}"))
                                .with_errortype("macro_redefined"),
                        );
                    }
                }
            } else if defined.remove(name.as_str()).is_none() {
                out.push(
                    dreammaker::DMError::new(location, format!("macro undefined while not defined: {name}"))
                        .with_errortype("macro_undefined_no_definition")
                        .set_severity(dreammaker::Severity::Warning),
                );
            }
        }
    }
    out
}

/// dq-analyze's model (`Parsed`) from dmbc's front end: the provider `dmbc` registers with `dq_analyze::sem::register_parse_provider`
/// (selected by `DQ_ANALYZE_PARSE=dmbc`). Files are registered under their path relative to the `.dme`'s directory, as dreammaker's
/// preprocessor registers includes, in the order the tree first names them; locations carry the line (dmbc keeps no column).
/// `checker`: DreamChecker's parse; its diagnostics are what finishing the tree registers (the parser's own syntax diagnostics have no
/// counterpart: dmbc's front end reports its own, and refuses a tree it cannot build).
/// The compiler's front end of a `.dme` as analysis reads it, with its files registered for SpacemanDMM-style locations.
pub(crate) struct Front {
    pub(crate) frontend: dm_tree::frontend::FrontendRevision,
    /// The files under the ids locations carry: the `.dme` first, then every file in include order.
    pub(crate) files_ctx: dreammaker::Context,
    pub(crate) ids: HashMap<Arc<str>, dreammaker::FileId>,
    pub(crate) root: PathBuf,
    pub(crate) root_abs: PathBuf,
    /// The macros defined before the first file (a later `#define` of one is a redefinition).
    pub(crate) initial: Vec<String>,
    pub(crate) built: std::time::Duration,
}

impl Front {
    /// A path as dreammaker's preprocessor registers an include: relative to the `.dme`'s directory.
    pub(crate) fn registered(&self, path: &str) -> PathBuf {
        registered_in(&self.root, &self.root_abs, path)
    }
}

fn registered_in(root: &Path, root_abs: &Path, path: &str) -> PathBuf {
    let p = Path::new(path);
    let abs = if p.is_absolute() { p.to_path_buf() } else { root.join(p) };
    let abs = std::fs::canonicalize(&abs).unwrap_or(abs);
    match abs.strip_prefix(root_abs) {
        Ok(rel) => PathBuf::from(rel.to_string_lossy().replace('\\', "/")),
        Err(_) => abs,
    }
}

/// An expanded offset's location through `mapper`: dreammaker's file ids (`ids`), the line and column dreammaker gives the token.
pub(crate) fn locate_in(
    ids: &HashMap<Arc<str>, dreammaker::FileId>,
    mapper: &dm_tree::frontend::SiteMapper<'_>,
    offset: usize,
    unregistered: &std::sync::atomic::AtomicUsize,
) -> Location {
    {
        match mapper.debug_site_column(offset) {
            Some((path, line, column)) => match ids.get(&path) {
                Some(&file) => Location { file, line: line as u32, column: column.min(u16::MAX as usize) as u16 },
                None => {
                    unregistered.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    Location::builtins()
                }
            },
            None => Location::builtins(),
        }
    }
}

/// The front end of `dme` as analysis reads it: `SPACEMAN_DMM` defined, from the daemon's retained session when there is one.
pub(crate) fn front(dme: &Path) -> Result<Front, String> {
    let started = std::time::Instant::now();
    // dq-analyze reads the tree as SpacemanDMM tools do: `SPACEMAN_DMM` is defined (code under `#if defined(SPACEMAN_DMM)`, the
    // test fixtures among it, is part of the model).
    let defines = crate::analysis_frontend::analysis_defines();
    let initial: Vec<String> =
        dm_preprocess::regions::predefined_macros().into_iter().map(|(n, _, _)| n).chain(defines.keys().cloned())
            // dreammaker's builtin function macros (its `builtins::default_defines`): an `#undef` of one is no warning there.
            .chain(["EXCEPTION", "ASSERT"].map(String::from))
            .collect();
    let frontend = crate::analysis_frontend::frontend(dme)?;
    let built = started.elapsed();
    let root = dme.parent().map(Path::to_path_buf).filter(|p| !p.as_os_str().is_empty()).unwrap_or_else(|| PathBuf::from("."));
    let root_abs = std::fs::canonicalize(&root).unwrap_or_else(|_| root.clone());
    let files_ctx = dreammaker::Context::default();
    // The .dme is the preprocessor's first file.
    files_ctx.register_file(Path::new(dme.file_name().unwrap_or(dme.as_os_str())));
    // Files are registered up front, in include order (as dreammaker's preprocessor names them), so every worker thread maps a path
    // to its id with a plain read.
    let canonical: Vec<PathBuf> = {
        use rayon::prelude::*;
        frontend.plan.occurrences.par_iter().map(|o| registered_in(&root, &root_abs, &o.semantic_path)).collect()
    };
    let mut ids: HashMap<Arc<str>, dreammaker::FileId> = HashMap::new();
    for (occurrence, path) in frontend.plan.occurrences.iter().zip(&canonical) {
        ids.entry(occurrence.semantic_path.clone()).or_insert_with(|| files_ctx.register_file(path));
    }
    Ok(Front { frontend, files_ctx, ids, root, root_abs, initial, built })
}
