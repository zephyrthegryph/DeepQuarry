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
struct Spelled {
    header: String,
    at: usize,
    /// From `at` to the end of the item (its body included).
    item_len: usize,
    /// The end of the header in the expanded text (the header string itself may be respelled on one line).
    header_end: usize,
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Debug)]
enum Slot {
    VarDeclare,
    VarOverride,
    Proc,
    Verb,
}

type Key = (String, String, Slot);

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
fn signature_parts(header: &str) -> Option<(&str, &str, &str)> {
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
struct VarHeader<'h> {
    owner: String,
    name: String,
    type_parts: Vec<String>,
    initializer: Option<(&'h str, usize)>,
    /// `var/x as text` (no initializer): the declared input type.
    input: Option<InputType>,
    /// The `new /list(...)` a list suffix stands for when no value is written.
    suffix_initializer: Option<String>,
    /// The SpacemanDMM flags the spelling names.
    spaceman: VarTypeFlags,
}

fn var_header<'h>(owner: &str, header: &'h str) -> Option<VarHeader<'h>> {
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

/// The column one past the end of the source line `offset` maps to (its comments included), as dreammaker's newline token sits.
fn line_end_column(frontend: &ColdFrontend, offset: usize, files: &mut HashMap<Arc<str>, usize>) -> Option<u16> {
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

fn var_flags(bits: u32) -> VarTypeFlags {
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

/// dmbc's front end as a dreammaker object tree. `locate` maps an expanded offset to a dreammaker location.
pub fn build_tree(
    frontend: &ColdFrontend,
    locate: &mut dyn FnMut(usize) -> Location,
    docs: &mut dyn FnMut(usize) -> dreammaker::docs::DocCollection,
) -> (ObjectTree, FeedStats) {
    build_tree_in(&dreammaker::Context::default(), frontend, locate, docs)
}

/// [`build_tree`] registering what finishing the tree reports (bad parent types, constant evaluation) to `context`.
pub fn build_tree_in(
    context: &dreammaker::Context,
    frontend: &ColdFrontend,
    locate: &mut dyn FnMut(usize) -> Location,
    docs: &mut dyn FnMut(usize) -> dreammaker::docs::DocCollection,
) -> (ObjectTree, FeedStats) {
    let mut stats = FeedStats::default();
    let mut spelled: HashMap<Key, VecDeque<Spelled>> = HashMap::new();
    let mut type_sites: HashMap<String, usize> = HashMap::new();
    let mut starts: Vec<usize> = Vec::new();
    for chunk in frontend.syntax.chunks().iter() {
        walk(chunk.items(), "/", &mut spelled, &mut type_sites, &mut starts);
    }
    starts.sort_unstable();
    // dreammaker hands a line's docs to the first tree entry read from it (a macro expanding to a type and its vars documents the
    // type): only the earliest declaration of each line takes them.
    let mut first_on_line: HashMap<(dreammaker::FileId, u32), usize> = HashMap::new();
    for &at in type_sites.values().chain(spelled.values().flatten().map(|s| &s.at)) {
        let l = locate(at);
        let e = first_on_line.entry((l.file, l.line)).or_insert(at);
        *e = (*e).min(at);
    }
    let claims: std::collections::HashSet<usize> = first_on_line.into_values().collect();
    let mut docs = |at: usize| if claims.contains(&at) { docs(at) } else { Default::default() };

    // Converted bodies by member.
    let arena = BodyArena::new_typed(frontend, |_| true);
    let mut bodies: HashMap<u32, Block> = HashMap::new();
    for occurrence in frontend.bodies.iter() {
        let Ok(body) = arena.take_parsed(occurrence) else { continue };
        let Some(statements) = body.statement_body() else { continue };
        match analysis_bridge::convert_body_checked(&statements.parsed().statements, &mut |o: usize| locate(o)) {
            Ok(block) => {
                bodies.insert(occurrence.member.0, block);
            }
            // A body dreammaker's parser rejects has no code, and its error is a parse diagnostic.
            Err((location, message)) => stats.parse_errors.push(dreammaker::DMError::new(location, message)),
        }
    }

    let mut line_files: HashMap<Arc<str>, usize> = HashMap::new();
    let mut builder = ObjectTreeBuilder::with_builtin_types();
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).unwrap_or("").to_owned();
    for node in tree.types() {
        let path = text(node.path);
        let location = type_sites.get(&path).map(|&at| locate(at)).unwrap_or_else(Location::builtins);
        builder.add_type_path(location, &path);
        stats.types += 1;
    }
    for target in tree.declarations() {
        let Target::Member(id) = *target else { continue };
        let Some(member) = tree.member(id) else { continue };
        let Some(owner) = tree.type_node(member.owner) else { continue };
        let owner = text(owner.path);
        let name = text(member.name);
        let ty = builder.add_type_path(Location::builtins(), &owner);
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
        let location = spelling.as_ref().map(|s| locate(s.at)).unwrap_or_else(Location::builtins);
        match slot {
            Slot::VarDeclare => {
                stats.vars += 1;
                let mut spaceman = VarTypeFlags::default();
                let (type_parts, value, input) = match spelling.as_ref().and_then(|s| var_header(&owner, &s.header).map(|v| (s, v))) {
                    Some((s, v)) => {
                        let value = v
                            .initializer
                            .map(|(t, off)| specified(t, s.at + off, locate, &mut stats.expression_failures))
                            .unwrap_or_default();
                        let suffix = v.suffix_initializer.as_deref().and_then(|t| expression(t, s.at, locate, &mut stats.expression_failures));
                        spaceman = v.spaceman;
                        (v.type_parts, value.value.or(suffix), value.input_type.or(v.input))
                    }
                    None => (Vec::new(), None, None),
                };
                let var_type = VarType {
                    flags: var_flags(member.metadata.flags) | spaceman,
                    type_path: type_parts.into_boxed_slice(),
                    input_type: input.unwrap_or_default(),
                };
                // dreammaker places a var declaration at the token after its name: the `=`, or the end of its line.
                let location = match spelling.as_ref() {
                    Some(s) => match dm_syntax::top_level_assignment_index(&s.header) {
                        Some(index) => locate(s.at + index),
                        None => {
                            let at = locate(s.at);
                            match line_end_column(frontend, s.at, &mut line_files) {
                                Some(column) if at.line != 0 => Location { column, ..at },
                                _ => at,
                            }
                        }
                    },
                    None => location,
                };
                let var = builder.add_var_declaration(ty, &name, location, var_type, value);
                if let Some(s) = spelling.as_ref() {
                    var.value.docs = docs(s.at);
                }
            }
            Slot::VarOverride => {
                stats.vars += 1;
                let value = spelling.as_ref().and_then(|s| {
                    let index = dm_syntax::top_level_assignment_index(&s.header)?;
                    let rest = &s.header[index + 1..];
                    let lead = rest.len() - rest.trim_start().len();
                    expression(rest.trim(), s.at + index + 1 + lead, locate, &mut stats.expression_failures)
                });
                if let Some(value) = value {
                    let var = builder.add_var_override(ty, &name, location, value);
                    if let Some(s) = spelling.as_ref() {
                        var.value.docs.extend(docs(s.at));
                    }
                }
            }
            Slot::Proc | Slot::Verb => {
                stats.procs += 1;
                let declaration = (member.definition == DefinitionMode::Declare)
                    .then(|| ProcDeclBuilder::new(if slot == Slot::Verb { ProcDeclKind::Verb } else { ProcDeclKind::Proc }, None));
                let mut parameters = Vec::new();
                let mut return_type = ProcReturnType::default();
                let mut body_range = None;
                // dreammaker places a proc at its parameter list's `(`.
                let mut location = location;
                if let (Some(s), Some(procedure)) = (spelling.as_ref(), member.metadata.procedure.as_ref()) {
                    if let Some((before, arguments, after)) = signature_parts(&s.header) {
                        let base = s.at + before.len() + 1;
                        location = locate(base - 1);
                        for p in procedure.signature.parameters.iter() {
                            let (start, end) = (p.relative_span.start, p.relative_span.end);
                            if let Some(t) = arguments.get(start..end) {
                                let mut p = parameter(t, base + start, locate, &mut stats.expression_failures);
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
                        let after_at = base + arguments.len() + 1;
                        return_type = return_annotation(after);
                        // The body runs from the end of the header to the end of the item (dreammaker: the first token after it).
                        let _ = after_at;
                        // dreammaker's range ends at the first token after the body: the next declaration item, in this file or the
                        // next one the include order reads.
                        let end = s.at + s.item_len;
                        let _ = &starts;
                        body_range = Some(locate(s.header_end)..locate(end));
                    }
                }
                let code = bodies.remove(&id.0);
                stats.bodies += usize::from(code.is_some());
                match builder.add_proc_value(context, location, ty, &name, declaration, parameters, return_type, code) {
                    Ok((_, value)) => {
                        value.body_range = body_range;
                        if let Some(s) = spelling.as_ref() {
                            value.docs = docs(s.at);
                        }
                    }
                    Err(_) => stats.proc_errors += 1,
                }
            }
        }
    }
    // `parent_type = /x`: the semantic tree holds it as the type's explicit parent, dreammaker as an override it reads at finish.
    let mut parents: Vec<_> = spelled.iter_mut().filter(|(k, _)| k.1 == "parent_type" && k.2 == Slot::VarOverride).collect();
    parents.sort_by(|a, b| a.0.cmp(b.0));
    for ((owner, _, _), entries) in parents {
        let ty = builder.add_type_path(Location::builtins(), owner);
        while let Some(s) = entries.pop_front() {
            let Some(index) = dm_syntax::top_level_assignment_index(&s.header) else { continue };
            let rest = &s.header[index + 1..];
            let lead = rest.len() - rest.trim_start().len();
            if let Some(value) = expression(rest.trim(), s.at + index + 1 + lead, locate, &mut stats.expression_failures) {
                stats.vars += 1;
                builder.add_var_override(ty, "parent_type", locate(s.at), value);
            }
        }
    }
    (builder.finish_tree(context, false), stats)
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

/// The source files in the order the preprocessor reads them (the manifest left out), spelled as the docs closures spell them:
/// [`crate::analysis_docs::DocIndex::with_order`] carries docs pending at a file's end to the next one.
fn doc_order(frontend: &ColdFrontend, root: &Path) -> Vec<String> {
    let plan = &frontend.plan;
    plan.items
        .iter()
        .filter_map(|item| match item {
            dm_preprocess::regions::OrderedItem::Text(region) if !plan.regions[*region].manifest_source => {
                let p = plan.occurrences[plan.regions[*region].occurrence].path.as_ref();
                let p = if p.is_absolute() { p.to_path_buf() } else { root.join(p) };
                Some(p.to_string_lossy().into_owned())
            }
            _ => None,
        })
        .collect()
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
    let mut cache: HashMap<usize, Location> = HashMap::new();
    let mut locate = |offset: usize| -> Location {
        *cache.entry(offset).or_insert_with(|| match frontend.debug_site(offset) {
            Some((path, line)) => Location { file: dm_file_ids.get(&norm(&path)).copied().unwrap_or_default(), line: line as u32, column: 0 },
            None => Location::default(),
        })
    };
    let root = dme.parent().map(Path::to_path_buf).unwrap_or_default();
    let mut doc_index = crate::analysis_docs::DocIndex::with_order(doc_order(&frontend, &root));
    let mut docs = |offset: usize| match frontend.debug_site(offset) {
        Some((path, line)) => {
            let path = Path::new(&*path);
            let path = if path.is_absolute() { path.to_path_buf() } else { root.join(path) };
            doc_index.docs(&path.to_string_lossy(), line as u32)
        }
        None => Default::default(),
    };
    let build_started = std::time::Instant::now();
    let (mine, stats) = build_tree(&frontend, &mut locate, &mut docs);
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
    let mut var_docs = Facet::default();
    let mut proc_docs = Facet::default();
    let mut return_types = Facet::default();
    let mut proc_flags = Facet::default();
    let mut param_inputs = Facet::default();
    let mut body_ranges = Facet::default();
    let docs = |d: &dreammaker::docs::DocCollection| d.text();

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
                    if !x.value.docs.is_empty() || !y.value.docs.is_empty() {
                        let (da, db) = (docs(&x.value.docs), docs(&y.value.docs));
                        var_docs.record(da == db, || ("var docs".into(), format!("{site}: dmbc {da:?} dm {db:?}")), examples);
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
                        if !px.docs.is_empty() || !py.docs.is_empty() {
                            let (da, db) = (docs(&px.docs), docs(&py.docs));
                            proc_docs.record(da == db, || ("proc docs".into(), format!("{site}: dmbc {da:?} dm {db:?}")), examples);
                        }
                        // Start and end lines of the body (dmbc's locations carry no column).
                        let lines = |v: &dreammaker::objtree::ProcValue| v.body_range.as_ref().map(|r| (r.start.file, r.start.line, r.end.file, r.end.line));
                        body_ranges.record(lines(px) == lines(py), || ("body range lines".into(), format!("{site}: dmbc {:?} dm {:?}", lines(px), lines(py))), examples);
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

    let facets: [(&str, &Facet); 17] = [
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
        ("var docs", &var_docs),
        ("proc return types", &return_types),
        ("proc flags", &proc_flags),
        ("proc docs", &proc_docs),
        ("parameter input types", &param_inputs),
        ("proc body ranges", &body_ranges),
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
fn macro_warnings(
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
pub fn parse_for_analysis(dme: &Path, checker: bool) -> Result<dq_analyze::sem::model_store::Parsed, String> {
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
    let registered = |path: &str| -> PathBuf {
        let p = Path::new(path);
        let abs = if p.is_absolute() { p.to_path_buf() } else { root.join(p) };
        let abs = std::fs::canonicalize(&abs).unwrap_or(abs);
        match abs.strip_prefix(&root_abs) {
            Ok(rel) => PathBuf::from(rel.to_string_lossy().replace('\\', "/")),
            Err(_) => abs,
        }
    };
    let mut ids: HashMap<Arc<str>, dreammaker::FileId> = HashMap::new();
    let mut cache: HashMap<usize, Location> = HashMap::new();
    let mut locate = |offset: usize| -> Location {
        *cache.entry(offset).or_insert_with(|| match frontend.debug_site_column(offset) {
            Some((path, line, column)) => {
                let file = *ids.entry(path.clone()).or_insert_with(|| files_ctx.register_file(&registered(&path)));
                Location { file, line: line as u32, column: column.min(u16::MAX as usize) as u16 }
            }
            None => Location::builtins(),
        })
    };
    let mut doc_index = crate::analysis_docs::DocIndex::with_order(doc_order(&frontend, &root));
    let mut docs = |offset: usize| match frontend.debug_site(offset) {
        Some((path, line)) => {
            let p = Path::new(&*path);
            let p = if p.is_absolute() { p.to_path_buf() } else { root.join(p) };
            doc_index.docs(&p.to_string_lossy(), line as u32)
        }
        None => Default::default(),
    };
    let finish = dreammaker::Context::default();
    let (objtree, stats) = build_tree_in(&finish, &frontend, &mut locate, &mut docs);
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
    if std::env::var_os("DQ_ANALYZE_PARSE_TRACE").is_some() {
        eprintln!("analyze: dmbc front end {built:.1?}, object tree {:.1?}: {stats:?}", started.elapsed() - built);
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
