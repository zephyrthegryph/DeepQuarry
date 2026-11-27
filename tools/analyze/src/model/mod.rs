//! The analysis view over dmbc's own front end (doc/rewrite/proposals/lean_unified.md, "Workstream 2a LINTS").
//!
//! [`Model`] holds one `dm_tree::frontend::FrontendRevision` (the compiler's semantic tree, declaration occurrences, typed bodies and
//! site map) and borrowed handles over it: [`Ty`], [`Member`]. Nothing is converted or copied: a declaration's site is the expanded
//! offset of its item (`ColdFrontend::declaration_spans`), mapped to a file and line only when asked; a body is the compiler's own
//! typed body (`dm_syntax::Statement`), parsed once per revision.
//!
//! Until the cutover the view is built beside the converted dreammaker tree (`DQ_ANALYZE_PARSE=dmbc`); [`parity`] compares the two
//! (`analyze sem model-parity`), the converted tree being the oracle for what every lint reads today.

pub mod body_parity;
pub mod builtins;
pub mod expr;
pub mod walk;
pub mod parity;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use dm_tree::frontend::{ColdFrontend, FrontendRevision};
use dm_ir::TypeId;
use dm_tree::{DefinitionMode, MemberId, MemberKind, MemberNode, OccurrenceId, Target};

/// An expanded-arena offset: where a declaration or a body node starts. [`Model::line`] maps it to its file and line.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Site(pub u32);

/// The front end's declarations, typed bodies and sites, indexed for analysis.
pub struct Model {
    rev: FrontendRevision,
    /// Each proc's typed body (the compiler's own parse, once per revision), by member.
    bodies: std::sync::OnceLock<HashMap<MemberId, Arc<dm_tree::frontend::StatementBody>>>,
    root: PathBuf,
    /// Type path text by `TypeId` (`/` for the root).
    paths: Vec<Arc<str>>,
    by_path: HashMap<Arc<str>, TypeId>,
    /// Each type's own members in declaration order (`SemanticTree::declarations`).
    own: Vec<Vec<MemberId>>,
    /// Each member's declaration occurrence.
    occurrence: HashMap<MemberId, OccurrenceId>,
    /// Each type's first type block (`/obj/item/radio` as an item header), in the order the declaration items come.
    type_sites: HashMap<Arc<str>, Site>,
    /// Each type's last `parent_type = /x` assignment (the semantic tree holds the parent, not the assignment).
    parent_sites: HashMap<Arc<str>, Site>,
    /// The repo-relative spelling of each path the site map names (resolved once per path).
    rels: std::sync::Mutex<HashMap<Arc<str>, Arc<str>>>,
    root_abs: PathBuf,
}

impl Model {
    pub fn new(rev: FrontendRevision, root: &Path) -> Model {
        let started = std::time::Instant::now();
        let tree = &rev.snapshot.tree;
        let symbols = tree.symbols();
        let paths: Vec<Arc<str>> = tree
            .types()
            .iter()
            .map(|node| {
                let p = symbols.text(node.path).unwrap_or("");
                Arc::from(if p.is_empty() { "/" } else { p })
            })
            .collect();
        let by_path: HashMap<Arc<str>, TypeId> = paths.iter().enumerate().map(|(i, p)| (p.clone(), TypeId(i as u32))).collect();
        let mut own: Vec<Vec<MemberId>> = vec![Vec::new(); paths.len()];
        let mut occurrence = HashMap::new();
        for (ordinal, target) in tree.declarations().iter().enumerate() {
            let at = OccurrenceId(ordinal as u32);
            match *target {
                Target::Member(id) => {
                    if let Some(member) = tree.member(id) {
                        if let Some(list) = own.get_mut(member.owner.index()) {
                            list.push(id);
                        }
                        occurrence.entry(id).or_insert(at);
                    }
                }
                Target::Type(_) => {}
            }
        }
        // Source order (the expanded arena is in include order), except that a proc's declaring definition (`proc/x()`) comes first among
        // its definitions on the type, wherever it is written: the order a type's definitions of one proc are listed in.
        let start = |id: &MemberId| occurrence.get(id).and_then(|at: &OccurrenceId| rev.declaration_spans.get(at.0 as usize)).map_or(u32::MAX, |s| s.start);
        let declares = |id: &MemberId| tree.member(*id).is_some_and(|m| m.kind != MemberKind::Var && m.definition == DefinitionMode::Declare);
        for list in own.iter_mut() {
            list.sort_by_key(|id| start(id));
            // Stable: move each proc's declaration before the definitions of the same name that precede it.
            let mut placed: Vec<MemberId> = Vec::with_capacity(list.len());
            for &id in list.iter() {
                if declares(&id) {
                    let name = tree.member(id).map(|m| (m.name, m.kind));
                    let first = placed.iter().position(|p| tree.member(*p).map(|m| (m.name, m.kind)) == name);
                    match first {
                        Some(i) => placed.insert(i, id),
                        None => placed.push(id),
                    }
                } else {
                    placed.push(id);
                }
            }
            *list = placed;
        }
        let root_abs = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
        let mut sites = TypeSites::default();
        for chunk in rev.syntax.chunks().iter() {
            type_blocks(chunk.items(), "/", &mut sites);
        }
        let model = Model {
            bodies: std::sync::OnceLock::new(),
            rev,
            root: root.to_path_buf(),
            paths,
            by_path,
            own,
            occurrence,
            type_sites: sites.blocks,
            parent_sites: sites.parents,
            rels: Default::default(),
            root_abs,
        };
        if trace() {
            eprintln!(
                "analyze: model view: {} types, {} members, {} bodies in {:.1?}",
                model.paths.len(),
                model.occurrence.len(),
                model.rev.bodies.len(),
                started.elapsed()
            );
        }
        model
    }

    fn bodies(&self) -> &HashMap<MemberId, Arc<dm_tree::frontend::StatementBody>> {
        self.bodies.get_or_init(|| {
            use rayon::prelude::*;
            let started = std::time::Instant::now();
            let arena = dm_tree::frontend::BodyArena::new_typed(&self.rev, |_| true);
            let parsed: Vec<(MemberId, Option<Arc<dm_tree::frontend::StatementBody>>)> = self
                .rev
                .bodies
                .par_iter()
                .map(|o| (o.member, arena.take_parsed(o).ok().and_then(|b| b.shared_statement_body())))
                .collect();
            let map: HashMap<_, _> = parsed.into_iter().filter_map(|(m, b)| b.map(|b| (m, b))).collect();
            if trace() {
                eprintln!("analyze: model view: {} typed bodies parsed in {:.1?}", map.len(), started.elapsed());
            }
            map
        })
    }

    pub fn frontend(&self) -> &ColdFrontend {
        &self.rev
    }

    pub fn ty(&self, path: &str) -> Option<Ty<'_>> {
        self.by_path.get(path).map(|&id| Ty { m: self, id })
    }

    pub fn types(&self) -> impl Iterator<Item = Ty<'_>> + '_ {
        (0..self.paths.len()).map(move |i| Ty { m: self, id: TypeId(i as u32) })
    }

    fn node(&self, id: MemberId) -> &MemberNode {
        self.rev.snapshot.tree.member(id).expect("a member of this revision")
    }

    fn text(&self, id: dm_ir::SymbolId) -> &str {
        self.rev.snapshot.tree.symbols().text(id).unwrap_or("")
    }

    /// The file (repo-relative, `/` separated) and line of `site`; `None` for a site no source file holds.
    pub fn line(&self, site: Site) -> Option<(String, u32)> {
        let (path, line, _) = self.rev.debug_site_column(site.0 as usize)?;
        Some((self.rel(&path), line as u32))
    }

    /// Like [`Model::line`], with the column.
    pub fn line_column(&self, site: Site) -> Option<(String, u32, u32)> {
        let (path, line, column) = self.rev.debug_site_column(site.0 as usize)?;
        Some((self.rel(&path), line as u32, column as u32))
    }

    fn rel(&self, path: &Arc<str>) -> String {
        if let Some(r) = self.rels.lock().unwrap().get(path) {
            return r.to_string();
        }
        let p = Path::new(&**path);
        let abs = if p.is_absolute() { p.to_path_buf() } else { self.root.join(p) };
        let abs = std::fs::canonicalize(&abs).unwrap_or(abs);
        let r: Arc<str> = match abs.strip_prefix(&self.root_abs) {
            Ok(rel) => rel.to_string_lossy().replace('\\', "/").into(),
            Err(_) => path.replace('\\', "/").into(),
        };
        self.rels.lock().unwrap().insert(path.clone(), r.clone());
        r.to_string()
    }

    fn occurrence_site(&self, at: OccurrenceId) -> Option<Site> {
        self.rev.declaration_spans.get(at.0 as usize).map(|span| Site(span.start))
    }
}

/// A type of the semantic tree.
#[derive(Clone, Copy)]
pub struct Ty<'m> {
    m: &'m Model,
    pub id: TypeId,
}

impl<'m> Ty<'m> {
    pub fn path(&self) -> &'m str {
        &self.m.paths[self.id.index()]
    }

    pub fn parent(&self) -> Option<Ty<'m>> {
        self.m.rev.snapshot.tree.parent(self.id).map(|id| Ty { m: self.m, id })
    }

    pub fn synthetic(&self) -> bool {
        self.m.rev.snapshot.tree.type_node(self.id).is_some_and(|n| n.synthetic)
    }

    /// Where the type's first block is (`/obj/item/radio` as an item header); none for a type only implied by a member's path.
    pub fn site(&self) -> Option<Site> {
        self.m.type_sites.get(self.path()).copied()
    }

    /// The type's explicit parent (`parent_type = /x`) and where it is last assigned.
    pub fn explicit_parent(&self) -> Option<(Ty<'m>, Option<Site>)> {
        let node = self.m.rev.snapshot.tree.type_node(self.id)?;
        if !node.explicit_parent {
            return None;
        }
        Some((self.parent()?, self.m.parent_sites.get(self.path()).copied()))
    }

    /// This type's own members (declarations and overrides), in declaration order.
    pub fn members(&self) -> impl Iterator<Item = Member<'m>> + 'm {
        let m = self.m;
        m.own[self.id.index()].iter().map(move |&id| Member { m, id })
    }

    pub fn vars(&self) -> impl Iterator<Item = Member<'m>> + 'm {
        self.members().filter(|x| x.kind() == MemberKind::Var)
    }

    pub fn procs(&self) -> impl Iterator<Item = Member<'m>> + 'm {
        self.members().filter(|x| x.kind() != MemberKind::Var)
    }
}

/// A var, proc or verb definition (a declaration or an override) on one type.
#[derive(Clone, Copy)]
pub struct Member<'m> {
    m: &'m Model,
    pub id: MemberId,
}

impl<'m> Member<'m> {
    fn node(&self) -> &'m MemberNode {
        self.m.node(self.id)
    }

    pub fn name(&self) -> &'m str {
        self.m.text(self.node().name)
    }

    pub fn kind(&self) -> MemberKind {
        self.node().kind
    }

    pub fn owner(&self) -> Ty<'m> {
        Ty { m: self.m, id: self.node().owner }
    }

    pub fn declares(&self) -> bool {
        self.node().definition == DefinitionMode::Declare
    }

    /// The declared type path (`/obj/item`, `/list/mob` for a typed list), `""` when untyped or not a declaration.
    pub fn declared_type(&self) -> String {
        let meta = &self.node().metadata;
        let base = meta.declared_type.map(|t| self.m.text(t)).unwrap_or("");
        // `var/list/list/x`, `var/list/T/x[3]`: the semantic tree keeps the runtime type (`/list`) and at most one element type; the
        // declaration spells the nesting.
        if base == "/list" {
            if let Some(authored) = self.authored_list_type() {
                return authored;
            }
        }
        match meta.list_element_type.map(|t| self.m.text(t)) {
            Some(element) if !element.is_empty() => format!("{}{}", if base.is_empty() { "/list" } else { base }, element),
            _ => base.to_string(),
        }
    }

    /// The type path a `var/list/.../name` declaration spells (flags removed), when it starts with `list/`.
    fn authored_list_type(&self) -> Option<String> {
        let text = self.item_text()?;
        let header = text.lines().next()?;
        let header = match dm_syntax::top_level_assignment_index(header) {
            Some(i) => &header[..i],
            None => header,
        };
        let tail = header.rfind("var/").map_or(header, |at| &header[at + 4..]).trim();
        let parts: Vec<&str> = tail.split('/').collect();
        let (name, types) = parts.split_last()?;
        let mut types: Vec<&str> = types
            .iter()
            .copied()
            .filter(|p| !matches!(*p, "static" | "const" | "tmp" | "global" | "SpacemanDMM_private" | "SpacemanDMM_protected" | "SpacemanDMM_final"))
            .collect();
        // `var/list/L[10]`: the size suffix makes the declared type a list of the spelled type.
        if name.contains('[') && !types.is_empty() {
            types.insert(0, "list");
        }
        (types.first() == Some(&"list") && types.len() > 1).then(|| format!("/{}", types.join("/")))
    }

    /// The declaration flag bits (`DeclarationMeaning::flags`: 1 static, 2 const, 4 tmp, 8 global).
    pub fn flags(&self) -> u32 {
        self.node().metadata.flags
    }

    /// Parameter names, in order (procs and verbs).
    pub fn parameter_names(&self) -> Vec<&'m str> {
        match &self.node().metadata.procedure {
            Some(p) => {
                let mut names: Vec<&'m str> = p.signature.parameters.iter().map(|q| self.m.text(q.name)).collect();
                // `proc/f(a, ...)`: the variadic tail is spelled as a parameter.
                if p.signature.variadic {
                    names.push("...");
                }
                names
            }
            None => Vec::new(),
        }
    }

    /// Where the declaration is: a var's item; a proc's parameter list (its `(`), where dreammaker places a proc and which is the line
    /// of the name in a macro that writes the header over several lines.
    pub fn site(&self) -> Option<Site> {
        let start = self.m.occurrence_site(*self.m.occurrence.get(&self.id)?)?;
        if self.kind() == MemberKind::Var {
            return Some(start);
        }
        let text = self.item_text()?;
        let mut depth = 0usize;
        for token in dm_syntax::lex(text).tokens {
            match token.text.as_str() {
                "(" if depth == 0 => return Some(Site(start.0 + token.span.start as u32)),
                "(" => depth += 1,
                _ => {}
            }
        }
        Some(start)
    }

    /// The proc's typed body: none for a var, a builtin, or a body the compiler's parser rejected.
    pub fn body(&self) -> Option<&'m [dm_syntax::Statement]> {
        self.m.bodies().get(&self.id).map(|b| &b.parsed().statements[..])
    }

    /// The member's expanded header text (its declaration item, the body excluded).
    pub fn item_text(&self) -> Option<&'m str> {
        let at = *self.m.occurrence.get(&self.id)?;
        let span = self.m.rev.declaration_spans.get(at.0 as usize)?;
        self.m.rev.expanded.text.as_str().get(span.start as usize..span.end as usize)
    }
}

pub(crate) fn trace() -> bool {
    dq_hostio::var("DQ_ANALYZE_TRACE").is_ok() || dq_hostio::var("DQ_ANALYZE_PARSE_TRACE").is_ok()
}

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

/// The first type block of each path, walking the declaration items as dm-tree's adapter does: the owner a type item names carries to
/// its children and to the items after it (members take the block they are written in).
#[derive(Default)]
struct TypeSites {
    blocks: HashMap<Arc<str>, Site>,
    parents: HashMap<Arc<str>, Site>,
}

fn type_blocks<'a>(items: impl Iterator<Item = dm_tree::frontend::ItemView<'a>>, owner: &str, out: &mut TypeSites) {
    use dm_syntax::ItemKind;
    let mut containing = owner.to_owned();
    for item in items {
        let raw = item.header();
        let header = raw.trim();
        let at = item.header_span().start + (raw.len() - raw.trim_start().len());
        match item.kind() {
            ItemKind::Type => {
                let path = absolute(&containing, header);
                out.blocks.entry(Arc::from(path.as_str())).or_insert(Site(at as u32));
                // A bare relative word with no block declares the child type only: the items after it stay on the enclosing type.
                if header.starts_with('/') || item.children().next().is_some() {
                    containing = path.clone();
                }
                type_blocks(item.children(), &path, out);
            }
            ItemKind::Unknown | ItemKind::Statement => match dm_syntax::top_level_assignment_index(header) {
                None => type_blocks(item.children(), &containing, out),
                Some(index) => {
                    let target = header[..index].trim();
                    let owner = match target.rsplit_once('/') {
                        Some(("", name)) => ("/".to_owned(), name),
                        Some((prefix, name)) => (absolute(&containing, prefix), name),
                        None => (containing.clone(), target),
                    };
                    if owner.1 == "parent_type" {
                        out.parents.insert(Arc::from(owner.0.as_str()), Site(at as u32));
                    }
                }
            },
            _ => {}
        }
    }
}
