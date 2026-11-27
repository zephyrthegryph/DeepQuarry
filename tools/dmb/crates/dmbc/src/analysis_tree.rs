//! `dmbc analysis-parity --tree [DME]`: the declaration feed (doc/rewrite/proposals/lean_unified.md, "One program", step 2b).
//!
//! Builds a dreammaker `ObjectTree` from dmbc's front end, with no dreammaker parse: the types, vars and procs of the semantic tree, in
//! `declarations()` order, through the builder's public registration API (`ObjectTreeBuilder::add_type_path`, `add_var_declaration`,
//! `add_var_override`, `add_proc_value`, `finish_tree`). Names, kinds, definition modes and var flags come from the semantic tree. The
//! semantic tree lowers initializers and parameter defaults (`DeclarationMeaning`), so their spelling comes from the declaration items
//! of the expanded text instead: each initializer is re-parsed with `dm_syntax::parse_expression` and converted by `analysis_bridge`, as
//! bodies are. Proc bodies are the converted typed bodies. Locations map through `frontend.debug_site`.
//!
//! It is then compared with dreammaker's own tree of the same `.dme` under one preprocessor environment (`analysis_parity`): the type
//! set, each type's var names, declarations, flags, declared type paths and initializer ASTs, each type's proc names, value counts,
//! declaration kinds and parameters (names, type paths, default ASTs).
use crate::analysis_bridge;
use crate::analysis_parity::{first_diff, kind, norm, shared_environment, short, spelling_equal, strip};
use dm_syntax::ItemKind;
use dm_tree::frontend::{BodyArena, ColdFrontend, ItemView};
use dm_tree::{DefinitionMode, MemberKind, Target};
use dreammaker::ast::{Block, Expression, InputType, Parameter, ProcDeclBuilder, ProcDeclKind, ProcReturnType, VarType, VarTypeFlags};
use dreammaker::objtree::{ObjectTree, ObjectTreeBuilder};
use dreammaker::Location;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// What a declaration item spells: its header (expanded text) and where it starts.
#[derive(Clone)]
pub(crate) struct Spelled {
    pub(crate) header: String,
    pub(crate) at: usize,
    /// From `at` to the end of the item (its body included).
    pub(crate) item_len: usize,
    /// The end of the header in the expanded text (the header string itself may be respelled on one line).
    pub(crate) header_end: usize,
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

/// A var header's owner, name, declared type pieces (flags removed) and initializer text, the way dm-tree's adapter reads it.
pub(crate) struct VarHeader<'h> {
    owner: String,
    name: String,
    pub(crate) type_parts: Vec<String>,
    initializer: Option<(&'h str, usize)>,
    /// `var/x as text` (no initializer): the declared input type.
    input: Option<InputType>,
    /// The `new /list(...)` a list suffix stands for when no value is written.
    suffix_initializer: Option<String>,
    /// The SpacemanDMM flags the spelling names.
    pub(crate) spaceman: VarTypeFlags,
}

pub(crate) fn var_header<'h>(owner: &str, header: &'h str) -> Option<VarHeader<'h>> {
    let (declaration, initializer) = match dm_syntax::top_level_assignment_index(header) {
        Some(index) => {
            let rest = &header[index + 1..];
            let lead = rest.len() - rest.trim_start().len();
            (header[..index].trim(), Some((rest.trim(), index + 1 + lead)))
        }
        None => (header, None),
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
    let input = normalized.split_once(" as ").map(|(_, t)| input_text(t));
    let tail = normalized.split_once(" as ").map_or(normalized, |(d, _)| d).trim();
    let parts: Vec<&str> = tail.split('/').collect();
    let last = parts.last()?.split(" as ").next()?;
    let name = last.split('[').next()?.trim().to_owned();
    // `var/L[10]`, `var/L[2][][3]`: dreammaker's suffix makes the type `list/...` and, without a value, `new /list(2, 3)`.
    let dims: Option<Vec<String>> = last.contains('[').then(|| {
        last.split('[').skip(1).map(|d| d.split(']').next().unwrap_or("").trim().to_owned()).filter(|d| !d.is_empty()).collect()
    });
    if name.is_empty() {
        return None;
    }
    let mut type_parts: Vec<String> = parts[..parts.len() - 1]
        .iter()
        .filter(|p| VarTypeFlags::from_name(p).is_none())
        .map(|p| p.to_string())
        .collect();
    if dims.is_some() {
        type_parts.insert(0, "list".to_owned());
    }
    let suffix_initializer = dims.filter(|d| !d.is_empty() && initializer.is_none()).map(|d| format!("new /list({})", d.join(", ")));
    // `SpacemanDMM_private`, `_protected`, `_final` (the analysis build's VAR_PRIVATE and friends) are flags in dreammaker, which the
    // semantic tree does not carry: read them from the spelling.
    let spaceman = parts[..parts.len() - 1].iter().filter_map(|p| VarTypeFlags::from_name(p)).fold(VarTypeFlags::default(), |a, b| a | b)
        & (VarTypeFlags::PRIVATE | VarTypeFlags::PROTECTED | VarTypeFlags::FINAL);
    Some(VarHeader { owner, name, type_parts, initializer, input, suffix_initializer, spaceman })
}

/// The input type an `as a|b` clause spells (the text after `as`, up to an `in` list).
fn input_text(text: &str) -> InputType {
    let text = text.split(" in ").next().unwrap_or(text).trim().trim_start_matches('(').trim_end_matches(')');
    analysis_bridge::input_type(&text.split('|').map(|t| t.trim().to_owned()).collect::<Vec<_>>())
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
        let entry = Spelled { header: header.to_owned(), at, item_len: item.span().end.saturating_sub(at), header_end: item.header_span().end };
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

/// A body's location mapper with the source line map: [`analysis_bridge::Locate::line_end`] reads a line's length from its source.
struct Site<'a> {
    locate: Box<dyn FnMut(usize) -> Location + 'a>,
    frontend: &'a ColdFrontend,
    line_files: HashMap<Arc<str>, usize>,
}

impl analysis_bridge::Locate for Site<'_> {
    fn locate(&mut self, offset: usize) -> Location {
        (self.locate)(offset)
    }
    fn line_end(&mut self, offset: usize) -> Location {
        let at = (self.locate)(offset);
        match line_end_column(self.frontend, offset, &mut self.line_files) {
            Some(column) if at.line != 0 => Location { column, ..at },
            _ => at,
        }
    }
}

/// Re-parse `text` (at expanded offset `at`) with dm-syntax and convert it.
fn expression(text: &str, at: usize, locate: &mut dyn FnMut(usize) -> Location, failures: &mut usize) -> Option<Expression> {
    specified(text, at, locate, failures).value
}

/// A value with the input specifier dreammaker reads after it (`null as text`, `0 as num in list(0, 1)`): the parser takes the
/// expression, then `as T` and `in L` as the declaration's input type and list, not as part of the value.
#[derive(Default)]
struct Specified {
    value: Option<Expression>,
    input_type: Option<InputType>,
    in_list: Option<Expression>,
}

fn is_input_call(e: &dm_syntax::Expr) -> bool {
    use dm_syntax::ExprKind;
    matches!(&e.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(n) if n == "input"))
}

fn specified(text: &str, at: usize, locate: &mut dyn FnMut(usize) -> Location, failures: &mut usize) -> Specified {
    use dm_syntax::ExprKind;
    let parsed = dm_syntax::parse_expression(text);
    let e = match parsed.expr {
        Some(e) if parsed.diagnostics.is_empty() => e,
        _ => {
            *failures += 1;
            return Specified::default();
        }
    };
    let mut shifted = |offset: usize| locate(at + offset);
    let mut out = Specified::default();
    let mut value = &e;
    if let ExprKind::Binary { op, lhs, rhs } = &value.kind {
        if op == "in" && matches!(&lhs.kind, ExprKind::TypeFilter { value, .. } if !is_input_call(value)) {
            out.in_list = Some(analysis_bridge::convert_expression_with(rhs, &mut shifted));
            value = lhs;
        }
    }
    if let ExprKind::TypeFilter { value: inner, types } = &value.kind {
        if !is_input_call(inner) {
            out.input_type = Some(analysis_bridge::input_type(types));
            value = inner;
        }
    }
    out.value = Some(analysis_bridge::convert_expression_with(value, &mut shifted));
    out
}

pub(crate) fn var_flags(bits: u32) -> VarTypeFlags {
    let mut flags = VarTypeFlags::default();
    if bits & (1 | 8) != 0 {
        flags |= VarTypeFlags::STATIC;
    }
    if bits & 2 != 0 {
        flags |= VarTypeFlags::CONST;
    }
    if bits & 4 != 0 {
        flags |= VarTypeFlags::TMP;
    }
    flags
}

/// One parameter declaration (`var/mob/user = null`, `atom/A as obj in view()`): its name, type pieces and default text.
fn parameter(text: &str, at: usize, locate: &mut dyn FnMut(usize) -> Location, failures: &mut usize) -> Parameter {
    let (declaration, default) = match dm_syntax::top_level_assignment_index(text) {
        Some(index) => {
            let rest = &text[index + 1..];
            let lead = rest.len() - rest.trim_start().len();
            (text[..index].trim(), Some((rest.trim(), at + index + 1 + lead)))
        }
        None => (text.trim(), None),
    };
    // `name as T in L` with no default: the specifier is on the declaration side.
    let mut declared_input = None;
    let mut declared_list = None;
    if let Some(index) = declaration.find(" in ") {
        let rest = &declaration[index + 4..];
        let lead = rest.len() - rest.trim_start().len();
        declared_list = expression(rest.trim(), at + index + 4 + lead, locate, failures);
    }
    let declaration = declaration.split(" in ").next().unwrap_or(declaration);
    if let Some((_, t)) = declaration.split_once(" as ") {
        declared_input = Some(input_text(t));
    }
    let declaration = declaration.split(" as ").next().unwrap_or(declaration).trim();
    let suffixed = declaration.contains('[');
    let declaration = declaration.split('[').next().unwrap_or(declaration).trim();
    let declaration = declaration.strip_prefix("var/").unwrap_or(declaration);
    let pieces: Vec<&str> = declaration.split('/').filter(|p| !p.is_empty()).collect();
    let name = pieces.last().copied().unwrap_or("").to_owned();
    let mut type_path: Vec<String> = pieces[..pieces.len().saturating_sub(1)]
        .iter()
        .filter(|p| VarTypeFlags::from_name(p).is_none())
        .map(|p| p.to_string())
        .collect();
    if suffixed {
        type_path.insert(0, "list".to_owned());
    }
    let specified = default.map(|(t, a)| specified(t, a, locate, failures)).unwrap_or_default();
    Parameter {
        name,
        var_type: VarType { flags: VarTypeFlags::default(), type_path: type_path.into_boxed_slice(), input_type: Default::default() },
        default: specified.value,
        input_type: specified.input_type.or(declared_input),
        in_list: specified.in_list.or(declared_list),
        location: locate(at),
    }
}

/// A proc's `as T` return annotation (the header text after the parameter list): an input type, or `/a/b` as a type path.
fn return_annotation(after: &str) -> ProcReturnType {
    let Some(rest) = after.trim().strip_prefix("as") else { return ProcReturnType::default() };
    let rest = rest.trim();
    if rest.starts_with('/') {
        ProcReturnType::TypePath(rest.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect())
    } else if rest.is_empty() {
        ProcReturnType::default()
    } else {
        ProcReturnType::InputType(input_text(rest))
    }
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

/// What one declaration contributes to the tree, computed away from the builder so the work runs on many threads.
#[derive(Clone, PartialEq, serde::Serialize, serde::Deserialize)]
enum Prepared {
    Var { location: Location, type_parts: Vec<String>, value: Option<Expression>, input: Option<InputType>, spaceman: VarTypeFlags },
    Override { location: Location, value: Option<Expression> },
    Proc { location: Location, parameters: Vec<Parameter>, return_type: ProcReturnType },
}

/// What decides a remembered conversion besides the declaration itself: the files bytes and the file ids the locations carry. Off
/// (the default) converts everything.
#[derive(Default)]
pub struct CacheKeys {
    pub enabled: bool,
    /// What the file ids stand for.
    pub files_key: u128,
    /// A file path and bytes, by its include spelling and by its id.
    pub by_path: HashMap<Arc<str>, u128>,
    pub by_id: HashMap<dreammaker::FileId, u128>,
}

/// One converted declaration as it is remembered.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct DeclarationResult {
    prepared: Option<Prepared>,
    failures: usize,
}

/// One converted body as it is remembered.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct BodyResult {
    block: Option<Block>,
    error: Option<(Location, String)>,
}

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
    pub(crate) spelled: HashMap<Key, VecDeque<Spelled>>,
}

/// Match each declaration of the semantic tree with its spelling (in declaration order: a queue per key).
pub(crate) fn matched<'f>(frontend: &'f ColdFrontend, stats: &mut FeedStats) -> Matched<'f> {
    let mut spelled: HashMap<Key, VecDeque<Spelled>> = HashMap::new();
    let mut type_sites: HashMap<String, usize> = HashMap::new();
    let mut starts: Vec<usize> = Vec::new();
    for chunk in frontend.syntax.chunks().iter() {
        walk(chunk.items(), "/", &mut spelled, &mut type_sites, &mut starts);
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
    Matched { items, type_sites, spelled }
}

/// One worker's state.
struct Worker<'a> {
    locate: Box<dyn FnMut(usize) -> Location + 'a>,
    line_files: HashMap<Arc<str>, usize>,
}

fn prepare(frontend: &ColdFrontend, w: &mut Worker<'_>, item: &Item<'_>, failures: &mut usize) -> Prepared {
    let Item { owner, slot, member, spelling, .. } = item;
    let locate: &mut dyn FnMut(usize) -> Location = &mut *w.locate;
    let location = spelling.as_ref().map(|s| locate(s.at)).unwrap_or_else(Location::builtins);
    match slot {
        Slot::VarDeclare => {
            let mut spaceman = VarTypeFlags::default();
            let (type_parts, value, input) = match spelling.as_ref().and_then(|s| var_header(owner, &s.header).map(|v| (s, v))) {
                Some((s, v)) => {
                    let value = v.initializer.map(|(t, off)| specified(t, s.at + off, locate, failures)).unwrap_or_default();
                    let suffix = v.suffix_initializer.as_deref().and_then(|t| expression(t, s.at, locate, failures));
                    spaceman = v.spaceman;
                    (v.type_parts, value.value.or(suffix), value.input_type.or(v.input))
                }
                None => (Vec::new(), None, None),
            };
            // dreammaker places a var declaration at the token after its name: the `=`, or the end of its line.
            let location = match spelling.as_ref() {
                Some(s) => match dm_syntax::top_level_assignment_index(&s.header) {
                    Some(index) => locate(s.at + index),
                    None => {
                        let at = locate(s.at);
                        match line_end_column(frontend, s.at, &mut w.line_files) {
                            Some(column) if at.line != 0 => Location { column, ..at },
                            _ => at,
                        }
                    }
                },
                None => location,
            };
            Prepared::Var { location, type_parts, value, input, spaceman }
        }
        Slot::VarOverride => {
            let value = spelling.as_ref().and_then(|s| {
                let index = dm_syntax::top_level_assignment_index(&s.header)?;
                let rest = &s.header[index + 1..];
                let lead = rest.len() - rest.trim_start().len();
                expression(rest.trim(), s.at + index + 1 + lead, locate, failures)
            });
            // dreammaker places an override at the token after its name: the `=`.
            let location = match spelling.as_ref().and_then(|s| Some(s.at + dm_syntax::top_level_assignment_index(&s.header)?)) {
                Some(at) => locate(at),
                None => location,
            };
            Prepared::Override { location, value }
        }
        Slot::Proc | Slot::Verb => {
            let mut parameters = Vec::new();
            let mut return_type = ProcReturnType::default();
            // dreammaker places a proc at its parameter list's `(`.
            let mut location = location;
            if let (Some(s), Some(procedure)) = (spelling.as_ref(), member.metadata.procedure.as_ref()) {
                if let Some((before, arguments, after)) = signature_parts(&s.header) {
                    let base = s.at + before.len() + 1;
                    location = locate(base - 1);
                    for p in procedure.signature.parameters.iter() {
                        let (start, end) = (p.relative_span.start, p.relative_span.end);
                        if let Some(t) = arguments.get(start..end) {
                            let mut p = parameter(t, base + start, locate, failures);
                            // dreammaker places a parameter at the token after it (its `,` or the closing `)`).
                            p.location = locate(base + end);
                            parameters.push(p);
                        }
                    }
                    // `proc/f(a, ...)`: dreammaker keeps the marker as a parameter named `...` with no type.
                    if procedure.signature.variadic {
                        let at = arguments.rfind("...").map_or(base, |i| base + i);
                        parameters.push(Parameter { name: "...".into(), location: locate(at), ..Default::default() });
                    }
                    return_type = return_annotation(after);
                }
            }
            Prepared::Proc { location, parameters, return_type }
        }
    }
}

/// dmbc's front end as a dreammaker object tree. `locator` makes the offset-to-location mappers.
pub fn build_tree(frontend: &ColdFrontend, locator: &Locator<'_>) -> (ObjectTree, FeedStats) {
    build_tree_in(&dreammaker::Context::default(), frontend, locator, &CacheKeys::default())
}

/// [`build_tree`] registering what finishing the tree reports (bad parent types, constant evaluation) to `context`.
pub fn build_tree_in(context: &dreammaker::Context, frontend: &ColdFrontend, locator: &Locator<'_>, keys: &CacheKeys) -> (ObjectTree, FeedStats) {
    use rayon::prelude::*;
    let trace = dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some();
    let phase = |name: &str, t: std::time::Instant| {
        if trace {
            dq_hostio::out(false, format_args!("analyze: tree phase {name} {:.1?}", t.elapsed()), true);
        }
    };
    let mut stats = FeedStats::default();
    let t = std::time::Instant::now();
    let Matched { items, type_sites, mut spelled } = matched(frontend, &mut stats);
    phase("spelling and matching", t);

    // Converted bodies by member, on every core, each remembered by what decides it: its expanded text, where it sits in its file, that
    // file's bytes (the line map reads them) and the file ids. An edit converts the bodies of the edited files again; the rest are read.
    let t = std::time::Instant::now();
    let arena = BodyArena::new_typed(frontend, |_| true);
    let expanded = frontend.expanded.text.as_str();
    let body_keys: Vec<u128> = frontend
        .bodies
        .par_iter()
        .map(|o| {
            let text = expanded.get(o.expanded_span.start..o.expanded_span.end).unwrap_or("");
            let source = &o.source;
            dq_analyze::incr::mix(&[
                xxhash_rust::xxh3::xxh3_128(text.as_bytes()),
                keys.by_path.get(&source.semantic_path).copied().unwrap_or(0),
                xxhash_rust::xxh3::xxh3_128(source.semantic_path.as_bytes()),
                source.span.start as u128 | (source.span.end as u128) << 64,
                keys.files_key,
            ])
        })
        .collect();
    let convert = |i: usize| {
        let mut site = Site { locate: locator(), frontend, line_files: HashMap::new() };
        let Ok(body) = arena.take_parsed(&frontend.bodies[i]) else { return BodyResult::default() };
        let Some(statements) = body.statement_body() else { return BodyResult::default() };
        match analysis_bridge::convert_body_checked(&statements.parsed().statements, &mut site, expanded) {
            Ok(block) => BodyResult { block: Some(block), error: None },
            Err(error) => BodyResult { block: None, error: Some(error) },
        }
    };
    let results: Vec<BodyResult> = if keys.enabled {
        dq_analyze::incr::keyed_by("tree-bodies", dq_analyze::incr::ctx_key("tree-bodies-v2"), &body_keys, convert)
    } else {
        (0..frontend.bodies.len()).into_par_iter().map(convert).collect()
    };
    let mut bodies: HashMap<u32, Block> = HashMap::new();
    for (occurrence, result) in frontend.bodies.iter().zip(results) {
        // A body dreammaker's parser rejects has no code, and its error is a parse diagnostic.
        if let Some((location, message)) = result.error {
            stats.parse_errors.push(dreammaker::DMError::new(location, message));
        }
        if let Some(block) = result.block {
            bodies.insert(occurrence.member.0, block);
        }
    }
    phase("bodies", t);

    let mut builder = ObjectTreeBuilder::with_builtin_types();
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).unwrap_or("").to_owned();
    let t = std::time::Instant::now();
    let type_paths: Vec<String> = tree.types().iter().map(|node| text(node.path)).collect();
    let type_locations: Vec<Location> = type_paths
        .par_iter()
        .map_init(|| locator(), |locate, path| type_sites.get(path).map(|&at| locate(at)).unwrap_or_else(Location::builtins))
        .collect();
    for (path, location) in type_paths.iter().zip(type_locations) {
        builder.add_type_path(location, path);
        stats.types += 1;
    }
    phase("types", t);


    // Each declaration's initializer, parameters and locations, on every core.
    let t = std::time::Instant::now();
    let compute = |w: &mut Worker<'_>, item: &Item<'_>| {
        let mut failures = 0;
        let p = prepare(frontend, w, item, &mut failures);
        DeclarationResult { prepared: Some(p), failures }
    };
    let results: Vec<DeclarationResult> = if keys.enabled {
        // Remembered by the declaration spelling, its place and its file bytes.
        let decl_keys: Vec<u128> = items
            .par_iter()
            .map_init(
                || locator(),
                |locate, item| {
                    let signature = item.member.metadata.procedure.as_ref().map(|p| {
                        let spans: Vec<(usize, usize)> = p.signature.parameters.iter().map(|q| (q.relative_span.start, q.relative_span.end)).collect();
                        format!("{spans:?}{}", p.signature.variadic)
                    });
                    let (header, site) = match &item.spelling {
                        Some(s) => (s.header.as_str(), locate(s.at)),
                        None => ("", Location::builtins()),
                    };
                    let file = keys.by_id.get(&site.file).copied().unwrap_or(0);
                    dq_analyze::incr::mix(&[
                        xxhash_rust::xxh3::xxh3_128(header.as_bytes()),
                        xxhash_rust::xxh3::xxh3_128(format!("{}|{}|{:?}|{signature:?}", item.owner, item.name, item.slot).as_bytes()),
                        file,
                        site.line as u128 | (site.column as u128) << 32,
                        keys.files_key,
                    ])
                },
            )
            .collect();
        dq_analyze::incr::keyed_by("tree-declarations", dq_analyze::incr::ctx_key("tree-declarations-v2"), &decl_keys, |i| {
            let mut w = Worker { locate: locator(), line_files: HashMap::new() };
            compute(&mut w, &items[i])
        })
    } else {
        items.par_iter().map_init(|| Worker { locate: locator(), line_files: HashMap::new() }, |w, item| compute(w, item)).collect()
    };
    let prepared: Vec<(Prepared, usize)> = results.into_iter().filter_map(|r| r.prepared.map(|p| (p, r.failures))).collect();
    phase("declarations", t);

    let t = std::time::Instant::now();
    for (item, (prepared, failures)) in items.iter().zip(prepared) {
        stats.expression_failures += failures;
        let ty = builder.add_type_path(Location::builtins(), &item.owner);
        match prepared {
            Prepared::Var { location, type_parts, value, input, spaceman } => {
                stats.vars += 1;
                let var_type = VarType {
                    flags: var_flags(item.member.metadata.flags) | spaceman,
                    type_path: type_parts.into_boxed_slice(),
                    input_type: input.unwrap_or_default(),
                };
                builder.add_var_declaration(ty, &item.name, location, var_type, value);
            }
            Prepared::Override { location, value } => {
                stats.vars += 1;
                if let Some(value) = value {
                    builder.add_var_override(ty, &item.name, location, value);
                }
            }
            Prepared::Proc { location, parameters, return_type } => {
                stats.procs += 1;
                let declaration = (item.member.definition == DefinitionMode::Declare)
                    .then(|| ProcDeclBuilder::new(if item.slot == Slot::Verb { ProcDeclKind::Verb } else { ProcDeclKind::Proc }, None));
                let code = bodies.remove(&item.id.0);
                stats.bodies += usize::from(code.is_some());
                match builder.add_proc_value(context, location, ty, &item.name, declaration, parameters, return_type, code) {
                    Ok(_) => {}
                    Err(_) => stats.proc_errors += 1,
                }
            }
        }
    }
    phase("builder", t);
    // `parent_type = /x`: the semantic tree holds it as the type's explicit parent, dreammaker as an override it reads at finish.
    let mut locate = locator();
    let mut parents: Vec<_> = spelled.iter_mut().filter(|(k, _)| k.1 == "parent_type" && k.2 == Slot::VarOverride).collect();
    parents.sort_by(|a, b| a.0.cmp(b.0));
    for ((owner, _, _), entries) in parents {
        let ty = builder.add_type_path(Location::builtins(), owner);
        while let Some(s) = entries.pop_front() {
            let Some(index) = dm_syntax::top_level_assignment_index(&s.header) else { continue };
            let rest = &s.header[index + 1..];
            let lead = rest.len() - rest.trim_start().len();
            if let Some(value) = expression(rest.trim(), s.at + index + 1 + lead, &mut *locate, &mut stats.expression_failures) {
                stats.vars += 1;
                builder.add_var_override(ty, "parent_type", locate(s.at + index), value);
            }
        }
    }
    let t = std::time::Instant::now();
    let tree = builder.finish_tree(context, false);
    phase("finish", t);
    (tree, stats)
}

#[derive(Default)]
struct Facet {
    compared: usize,
    equal: usize,
    categories: BTreeMap<String, (usize, Vec<String>)>,
}

impl Facet {
    fn record(&mut self, equal: bool, category: impl FnOnce() -> (String, String), examples: usize) {
        self.compared += 1;
        if equal {
            self.equal += 1;
            return;
        }
        let (name, example) = category();
        let entry = self.categories.entry(name).or_default();
        entry.0 += 1;
        if entry.1.len() < examples {
            entry.1.push(example);
        }
    }
}

fn ast_value<T: serde::Serialize>(v: &T) -> Value {
    let mut value = serde_json::to_value(v).unwrap_or(Value::Null);
    strip(&mut value);
    value
}

fn ast_category(a: &Value, b: &Value) -> (String, String) {
    let mut path = Vec::new();
    let (da, db) = first_diff(a, b, &mut path).unwrap_or((a, b));
    let ctx: Vec<_> = path.iter().rev().take(2).rev().cloned().collect();
    (format!("{} | dmbc {} vs dreammaker {}", ctx.join(">"), kind(da), kind(db)), format!("dmbc {}  dm {}", short(da, 200), short(db, 200)))
}

fn user_location(files: &dreammaker::FileList, location: Location) -> bool {
    norm(&files.get_path(location.file).to_string_lossy()) != "(builtins)"
}

pub fn run(dme: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let started = std::time::Instant::now();
    let examples = std::env::var("DQ_PARITY_EXAMPLES").ok().and_then(|v| v.parse().ok()).unwrap_or(3usize);
    let category_count = std::env::var("DQ_PARITY_CATEGORIES").ok().and_then(|v| v.parse().ok()).unwrap_or(25usize);
    let dm_dme = dme.to_path_buf();
    let dm_thread = std::thread::Builder::new()
        .name("parity-dreammaker".into())
        .stack_size(64 * 1024 * 1024)
        .spawn(move || dq_analyze::sem::parse_for_checker_with_env(&dm_dme, &dm_dme, shared_environment()))?;
    let frontend = crate::analysis_parity::build_frontend(dme)?;
    eprintln!("analysis-parity --tree: front end built in {:.1?}", started.elapsed());
    let parsed = dm_thread.join().map_err(|_| "dreammaker parse panicked")??;
    let mut dm_file_ids: HashMap<String, dreammaker::FileId> = HashMap::new();
    let mut dm_paths: Vec<PathBuf> = Vec::new();
    parsed.files.for_each(|p| dm_paths.push(p.to_path_buf()));
    for p in &dm_paths {
        if let Some(id) = parsed.files.get_id(p) {
            dm_file_ids.insert(norm(&p.to_string_lossy()), id);
        }
    }
    let locator = || -> Box<dyn FnMut(usize) -> Location + '_> {
        let (frontend, dm_file_ids) = (&frontend, &dm_file_ids);
        let mut cache: HashMap<usize, Location> = HashMap::new();
        Box::new(move |offset: usize| -> Location {
            *cache.entry(offset).or_insert_with(|| match frontend.debug_site(offset) {
                Some((path, line)) => Location { file: dm_file_ids.get(&norm(&path)).copied().unwrap_or_default(), line: line as u32, column: 0 },
                None => Location::default(),
            })
        })
    };
    let build_started = std::time::Instant::now();
    let (mine, stats) = build_tree(&frontend, &locator);
    eprintln!("analysis-parity --tree: dmbc object tree built in {:.1?}: {stats:?}", build_started.elapsed());
    let dm = &parsed.objtree;

    let mut types = Facet::default();
    let mut var_names = Facet::default();
    let mut var_decls = Facet::default();
    let mut var_flags = Facet::default();
    let mut var_type_paths = Facet::default();
    let mut var_values = Facet::default();
    let mut proc_names = Facet::default();
    let mut proc_values = Facet::default();
    let mut params = Facet::default();
    let mut param_defaults = Facet::default();
    let mut var_inputs = Facet::default();
    let mut return_types = Facet::default();
    let mut proc_flags = Facet::default();
    let mut param_inputs = Facet::default();

    let paths = |t: &ObjectTree| t.iter_types().map(|t| t.get().path.clone()).collect::<BTreeSet<_>>();
    let (dm_types, my_types) = (paths(dm), paths(&mine));
    for path in dm_types.union(&my_types) {
        let both = dm_types.contains(path) && my_types.contains(path);
        types.record(both, || ((if my_types.contains(path) { "type only in dmbc" } else { "type only in dreammaker" }).into(), path.clone()), examples);
        if !both {
            continue;
        }
        let (Some(a), Some(b)) = (mine.find(path), dm.find(path)) else { continue };
        let (a, b) = (a.get(), b.get());
        let shown = if path.is_empty() { "/" } else { path.as_str() };
        // Vars.
        let names: BTreeSet<&String> = a.vars.keys().chain(b.vars.keys()).collect();
        for name in names {
            let site = format!("{shown}/{name}");
            match (a.vars.get(name), b.vars.get(name)) {
                (Some(x), Some(y)) => {
                    var_names.record(true, || unreachable!(), examples);
                    var_decls.record(x.declaration.is_some() == y.declaration.is_some(), || {
                        ((if x.declaration.is_some() { "declared only in dmbc" } else { "declared only in dreammaker" }).into(), site.clone())
                    }, examples);
                    if let (Some(dx), Some(dy)) = (&x.declaration, &y.declaration) {
                        var_flags.record(dx.var_type.flags == dy.var_type.flags, || {
                            (format!("flags dmbc {:?} vs dreammaker {:?}", dx.var_type.flags, dy.var_type.flags), site.clone())
                        }, examples);
                        var_type_paths.record(dx.var_type.type_path == dy.var_type.type_path, || {
                            ("declared type path".into(), format!("{site}: dmbc {:?} dm {:?}", dx.var_type.type_path, dy.var_type.type_path))
                        }, examples);
                        var_inputs.record(dx.var_type.input_type == dy.var_type.input_type, || {
                            ("declared input type".into(), format!("{site}: dmbc {:?} dm {:?}", dx.var_type.input_type, dy.var_type.input_type))
                        }, examples);
                    }
                    // Values only where either side wrote one in source.
                    if user_location(&parsed.files, y.value.location) || x.value.expression.is_some() || y.value.expression.is_some() {
                        let (va, vb) = (ast_value(&x.value.expression), ast_value(&y.value.expression));
                        var_values.record(spelling_equal(&va, &vb), || {
                            let (c, e) = ast_category(&va, &vb);
                            (c, format!("{site}: {e}"))
                        }, examples);
                    }
                }
                (x, _) => var_names.record(false, || ((if x.is_some() { "var only in dmbc" } else { "var only in dreammaker" }).into(), site.clone()), examples),
            }
        }
        // Procs.
        let names: BTreeSet<&String> = a.procs.keys().chain(b.procs.keys()).collect();
        for name in names {
            let site = format!("{shown}/{name}()");
            match (a.procs.get(name), b.procs.get(name)) {
                (Some(x), Some(y)) => {
                    proc_names.record(true, || unreachable!(), examples);
                    let decl = |p: &dreammaker::objtree::TypeProc| p.declaration.as_ref().map(|d| d.kind);
                    proc_values.record(x.value.len() == y.value.len() && decl(x) == decl(y), || {
                        (
                            if decl(x) != decl(y) { format!("declaration kind dmbc {:?} vs dreammaker {:?}", decl(x), decl(y)) } else { "proc value count".into() },
                            format!("{site}: dmbc {} dm {}", x.value.len(), y.value.len()),
                        )
                    }, examples);
                    if let (Some(dx), Some(dy)) = (&x.declaration, &y.declaration) {
                        return_types.record(dx.return_type == dy.return_type, || {
                            ("return type".into(), format!("{site}: dmbc {:?} dm {:?}", dx.return_type, dy.return_type))
                        }, examples);
                        proc_flags.record(dx.flags == dy.flags, || ("proc flags".into(), format!("{site}: dmbc {:?} dm {:?}", dx.flags, dy.flags)), examples);
                    }
                    for (px, py) in x.value.iter().zip(&y.value) {
                        let sig = |v: &dreammaker::objtree::ProcValue| v.parameters.iter().map(|p| (p.name.clone(), p.var_type.type_path.clone())).collect::<Vec<_>>();
                        let (sx, sy) = (sig(px), sig(py));
                        params.record(sx == sy, || ("parameter names / type paths".into(), format!("{site}: dmbc {sx:?} dm {sy:?}")), examples);
                        if sx == sy {
                            for (qx, qy) in px.parameters.iter().zip(py.parameters.iter()) {
                                if qx.input_type.is_some() || qy.input_type.is_some() || qx.in_list.is_some() || qy.in_list.is_some() {
                                    let (la, lb) = (ast_value(&qx.in_list), ast_value(&qy.in_list));
                                    param_inputs.record(qx.input_type == qy.input_type && spelling_equal(&la, &lb), || {
                                        ("parameter input type / in list".into(), format!("{site} {}: dmbc {:?} {} dm {:?} {}", qx.name, qx.input_type, short(&la, 120), qy.input_type, short(&lb, 120)))
                                    }, examples);
                                }
                                if qx.default.is_none() && qy.default.is_none() {
                                    continue;
                                }
                                let (va, vb) = (ast_value(&qx.default), ast_value(&qy.default));
                                param_defaults.record(spelling_equal(&va, &vb), || {
                                    let (c, e) = ast_category(&va, &vb);
                                    (c, format!("{site} {}: {e}", qx.name))
                                }, examples);
                            }
                        }
                    }
                }
                (x, _) => proc_names.record(false, || ((if x.is_some() { "proc only in dmbc" } else { "proc only in dreammaker" }).into(), site.clone()), examples),
            }
        }
    }

    let facets: [(&str, &Facet); 14] = [
        ("types", &types),
        ("var names", &var_names),
        ("var declared/overridden", &var_decls),
        ("var flags", &var_flags),
        ("var declared type paths", &var_type_paths),
        ("var initializer ASTs", &var_values),
        ("proc names", &proc_names),
        ("proc value counts / kinds", &proc_values),
        ("proc parameters", &params),
        ("parameter default ASTs", &param_defaults),
        ("var input types", &var_inputs),
        ("proc return types", &return_types),
        ("proc flags", &proc_flags),
        ("parameter input types", &param_inputs),
    ];
    let pct = |f: &Facet| 100.0 * f.equal as f64 / f.compared.max(1) as f64;
    let (mut compared, mut equal) = (0, 0);
    println!("object tree parity (one environment; spelling normalized)");
    for (name, f) in &facets {
        compared += f.compared;
        equal += f.equal;
        println!("  {name:<28} {:>8} of {:>8} equal ({:.2}%)", f.equal, f.compared, pct(f));
    }
    println!("TREE PARITY {} of {} ({:.2}%)", equal, compared, 100.0 * equal as f64 / compared.max(1) as f64);
    println!("feed: {stats:?}");
    for (name, f) in &facets {
        if f.categories.is_empty() {
            continue;
        }
        let mut cats: Vec<_> = f.categories.iter().collect();
        cats.sort_by(|a, b| b.1 .0.cmp(&a.1 .0));
        println!("{name}: {} difference categories", cats.len());
        for (cat, (n, ex)) in cats.into_iter().take(category_count) {
            println!("  {n:>6}  {cat}");
            for e in ex {
                println!("          {e}");
            }
        }
    }
    eprintln!("analysis-parity --tree: done in {:.1?}", started.elapsed());
    Ok(())
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
    let mut defines = crate::analysis_parity::native_defines();
    defines.insert("SPACEMAN_DMM".into(), "1".into());
    let initial: Vec<String> =
        dm_preprocess::regions::predefined_macros().into_iter().map(|(n, _, _)| n).chain(defines.keys().cloned())
            // dreammaker's builtin function macros (its `builtins::default_defines`): an `#undef` of one is no warning there.
            .chain(["EXCEPTION", "ASSERT"].map(String::from))
            .collect();
    // Inside the daemon, the retained compile session of this root supplies it (incrementally after an edit); elsewhere it is
    // built cold.
    let frontend = match crate::daemon::hosted_frontend(dme, &defines) {
        Some(revision) => revision?,
        None => dm_tree::frontend::FrontendRevision::new(
            crate::analysis_parity::build_frontend_with(dme, defines).map_err(|e| e.to_string())?,
        ),
    };
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

pub fn parse_for_analysis(dme: &Path, checker: bool) -> Result<dq_analyze::sem::model_store::Parsed, String> {
    let Front { frontend, files_ctx, mut ids, initial, built, root, root_abs } = front(dme)?;
    let registered = |path: &str| -> PathBuf {
        let p = Path::new(path);
        let abs = if p.is_absolute() { p.to_path_buf() } else { root.join(p) };
        let abs = std::fs::canonicalize(&abs).unwrap_or(abs);
        match abs.strip_prefix(&root_abs) {
            Ok(rel) => PathBuf::from(rel.to_string_lossy().replace('\\', "/")),
            Err(_) => abs,
        }
    };
    // What a remembered conversion depends on besides its own text: the files paths and bytes, and the ids the locations carry.
    let cache_keys = {
        use rayon::prelude::*;
        let path_hashes: HashMap<&PathBuf, u128> = frontend
            .files
            .par_iter()
            .map(|f| (&*f.path, xxhash_rust::xxh3::xxh3_128(f.text.as_str().as_bytes())))
            .collect::<Vec<_>>()
            .into_iter()
            .collect();
        let mut by_path: HashMap<Arc<str>, u128> = HashMap::new();
        for occurrence in &frontend.plan.occurrences {
            let content = path_hashes.get(&*occurrence.path).copied().unwrap_or(0);
            by_path.entry(occurrence.semantic_path.clone()).or_insert_with(|| {
                dq_analyze::incr::mix(&[xxhash_rust::xxh3::xxh3_128(occurrence.semantic_path.as_bytes()), content])
            });
        }
        let by_id: HashMap<dreammaker::FileId, u128> = ids.iter().filter_map(|(path, id)| by_path.get(path).map(|h| (*id, *h))).collect();
        let mut order: Vec<_> = ids.iter().map(|(path, id)| (path.clone(), *id)).collect();
        order.sort_by(|a, b| a.0.cmp(&b.0));
        let files_key = xxhash_rust::xxh3::xxh3_128(format!("{order:?}").as_bytes());
        CacheKeys { enabled: true, files_key, by_path, by_id }
    };
    let unregistered = std::sync::atomic::AtomicUsize::new(0);
    let locator = || -> Box<dyn FnMut(usize) -> Location + '_> {
        let mapper = frontend.site_mapper();
        let (ids, unregistered) = (&ids, &unregistered);
        let mut cache: HashMap<usize, Location> = HashMap::new();
        Box::new(move |offset: usize| -> Location {
            if let Some(l) = cache.get(&offset) {
                return *l;
            }
            let l = match mapper.debug_site_column(offset) {
                Some((path, line, column)) => match ids.get(&path) {
                    Some(&file) => Location { file, line: line as u32, column: column.min(u16::MAX as usize) as u16 },
                    None => {
                        unregistered.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        Location::builtins()
                    }
                },
                None => Location::builtins(),
            };
            cache.insert(offset, l);
            l
        })
    };
    let finish = dreammaker::Context::default();
    let tree_started = std::time::Instant::now();
    let (objtree, stats) = build_tree_in(&finish, &frontend, &locator, &cache_keys);
    let tree_time = tree_started.elapsed();
    // The preprocessor's warnings, in DreamChecker's stream as dreammaker's preprocessor registers them.
    let stream = if checker {
        let mut place = |path: &str, line: usize, column: usize| {
            let file = *ids.entry(Arc::from(path)).or_insert_with(|| files_ctx.register_file(&registered(path)));
            Location { file, line: line as u32, column: column.min(u16::MAX as usize) as u16 }
        };
        let mut stream = macro_warnings(&frontend, initial, &mut place);
        stream.extend(stats.parse_errors.iter().cloned());
        stream
    } else {
        Vec::new()
    };
    let files = files_ctx.clone_file_list();
    if dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some() {
        dq_hostio::out(false, format_args!("analyze: dmbc front end {built:.1?}, object tree {tree_time:.1?} (unregistered files: {}), {} bodies", unregistered.load(std::sync::atomic::Ordering::Relaxed), stats.bodies), true);
    }
    let finish_errors: Vec<dreammaker::DMError> = std::mem::take(&mut *finish.errors_mut());
    let errors = finish_errors
        .iter()
        .filter(|e| matches!(e.severity(), dreammaker::Severity::Error))
        .map(|e| format!("{e}"))
        .collect();
    let raw = checker.then(|| dq_analyze::sem::model_store::CheckerDiagnostics {
        stream,
        summary: Some({
            let total = stats.bodies + stats.parse_errors.len();
            format!("parsed {}/{} proc bodies ({}%)", stats.bodies, total, (stats.bodies * 100).checked_div(total).unwrap_or(100))
        }),
        finish: finish_errors,
    });
    Ok(dq_analyze::sem::model_store::Parsed { objtree, files, errors, env: None, structure: None, defines: None, raw, fatal: false })
}

/// Registers [`parse_for_analysis`] as dq-analyze's parse provider (used only under `DQ_ANALYZE_PARSE=dmbc`).
pub fn register_analysis_provider() {
    // Inside the daemon the provider remembers its conversion between requests (daemon/analysis_model.rs).
    dq_analyze::sem::register_parse_provider(crate::daemon::analysis_provider);
}
#[cfg(test)]
#[path = "analysis_tree_tests.rs"]
mod analysis_tree_tests;
