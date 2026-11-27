//! The analysis view over dmbc's own front end (doc/rewrite/proposals/lean_unified.md, "Workstream 2a LINTS").
//!
//! [`Model`] holds one `dm_tree::frontend::FrontendRevision` (the compiler's semantic tree, declaration occurrences, typed bodies and
//! site map) and borrowed handles over it: [`Ty`], [`Member`]. Nothing is converted or copied: a declaration's site is the expanded
//! offset of its item (`ColdFrontend::declaration_spans`), mapped to a file and line only when asked; a body is the compiler's own
//! typed body (`dm_syntax::Statement`), parsed once per revision.
//!
//! Until the cutover the view is built beside the converted dreammaker tree (`DQ_ANALYZE_PARSE=dmbc`); [`parity`] compares the two
//! (`analyze sem model-parity`), the converted tree being the oracle for what every lint reads today.

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
    root: PathBuf,
    /// Type path text by `TypeId` (`/` for the root).
    paths: Vec<Arc<str>>,
    by_path: HashMap<Arc<str>, TypeId>,
    /// Each type's own members in declaration order (`SemanticTree::declarations`).
    own: Vec<Vec<MemberId>>,
    /// Each member's declaration occurrence.
    occurrence: HashMap<MemberId, OccurrenceId>,
    /// Each type's first declaration occurrence (types have no site of their own when only implied by a path).
    type_occurrence: HashMap<TypeId, OccurrenceId>,
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
        let mut type_occurrence = HashMap::new();
        // Emission order: the order the definitions take effect (include order), which is the order a proc's definitions override one another.
        let declarations = tree.declarations();
        for &at in rev.emission_order.iter() {
            let Some(target) = declarations.get(at.0 as usize) else { continue };
            match *target {
                Target::Member(id) => {
                    if let Some(member) = tree.member(id) {
                        if let Some(list) = own.get_mut(member.owner.index()) {
                            list.push(id);
                        }
                        occurrence.entry(id).or_insert(at);
                    }
                }
                Target::Type(id) => {
                    type_occurrence.entry(id).or_insert(at);
                }
            }
        }
        let root_abs = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
        let model = Model { rev, root: root.to_path_buf(), paths, by_path, own, occurrence, type_occurrence, rels: Default::default(), root_abs };
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

    /// Where the type is first declared (a type block or a path that names it), when it has a declaration of its own.
    pub fn site(&self) -> Option<Site> {
        self.m.occurrence_site(*self.m.type_occurrence.get(&self.id)?)
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
        match meta.list_element_type.map(|t| self.m.text(t)) {
            Some(element) if !element.is_empty() => format!("{}{}", if base.is_empty() { "/list" } else { base }, element),
            _ => base.to_string(),
        }
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

    /// The expanded offset of the declaration item.
    pub fn site(&self) -> Option<Site> {
        self.m.occurrence_site(*self.m.occurrence.get(&self.id)?)
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
