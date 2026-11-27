//! The analysis view over dmbc's own front end (doc/rewrite/proposals/lean_unified.md, "Workstream 2a LINTS").
//!
//! [`Model`] holds one `dm_tree::frontend::FrontendRevision` (the compiler's semantic tree, declaration occurrences, typed bodies and
//! site map) and borrowed handles over it: [`Ty`], [`Member`]. Nothing is converted or copied: a declaration's site is the expanded
//! offset of its item (`ColdFrontend::declaration_spans`), mapped to a file and line only when asked; a body is the compiler's own
//! typed body (`dm_syntax::Statement`), parsed once per revision.
//!
//! The view was proven against the converted dreammaker tree it replaced (`analyze sem model-parity`, removed with the converter): every
//! type, parent, declaration, site, initializer, folded constant, proc resolution and all 120472 body walks identical
//! (doc/rewrite/proposals/lean_unified.md, 2a).

pub mod builtins;
pub mod consts;
pub mod procs;
pub mod reads;
mod reuse;
pub mod profile;
pub mod expr;
pub mod walk;

/// The view's maps hash with foldhash: their keys are ids, offsets and type paths the model owns, never untrusted input.
type HashMap<K, V> = std::collections::HashMap<K, V, foldhash::fast::FixedState>;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use dm_tree::frontend::{ColdFrontend, FrontendRevision};
use dm_ir::TypeId;
use dm_tree::{DefinitionMode, MemberId, MemberKind, MemberNode, OccurrenceId, Target};

/// Shards of the site cache (a power of two): the walks ask from every core at once.
const SITE_SHARDS: usize = 64;

/// An expanded-arena offset: where a declaration or a body node starts. [`Model::line`] maps it to its file and line.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Site(pub u32);

/// The front end's declarations, typed bodies and sites, indexed for analysis.
pub struct Model {
    /// Each body block read as statements (`walk::stmts`), by its address: the walks read the same blocks over and over. Declared first so
    /// it is dropped before the bodies it borrows from (see [`Model::stmts`]).
    blocks: Vec<std::sync::RwLock<HashMap<(usize, usize), Arc<Block<'static>>>>>,
    rev: FrontendRevision,
    /// Each declaration occurrence's stable identity (`dm_tree::frontend::declaration_keys`), built when a recording first asks.
    keys: std::sync::OnceLock<Vec<Option<dm_tree::frontend::DeclarationKey>>>,
    /// Each var's initializer, parsed from its declaration item, with the expanded offset its spans are relative to.
    initializers: std::sync::OnceLock<HashMap<MemberId, (Arc<dm_syntax::Expr>, usize)>>,
    /// Each var's folded constant (`consts::fold_all`), built when first asked.
    folded: std::sync::OnceLock<consts::Folded>,
    /// Each proc's typed body (the compiler's own parse, once per revision), by member.
    bodies: std::sync::OnceLock<HashMap<MemberId, reuse::Body>>,
    root: PathBuf,
    /// Type path text by `TypeId` (`/` for the root).
    paths: Vec<Arc<str>>,
    by_path: HashMap<Arc<str>, TypeId>,
    /// Each type's own members in declaration order (`SemanticTree::declarations`).
    own: Vec<Vec<MemberId>>,
    /// Each type's own members by (name, is a var), in the order of `own`.
    named: HashMap<(TypeId, dm_ir::SymbolId, bool), Vec<MemberId>>,
    /// Each member's declaration occurrence.
    occurrence: HashMap<MemberId, OccurrenceId>,
    /// Each type's first type block (`/obj/item/radio` as an item header), in the order the declaration items come.
    type_sites: HashMap<Arc<str>, Site>,
    /// Each type's last `parent_type = /x` assignment (the semantic tree holds the parent, not the assignment).
    parent_sites: HashMap<Arc<str>, Site>,
    /// Each (type, var name)'s nearest declaration, once asked.
    declarations: Vec<std::sync::RwLock<HashMap<(TypeId, dm_ir::SymbolId), Option<consts::VarDeclaration>>>>,
    /// Each proc's site (its parameter list), found once.
    proc_sites: Vec<std::sync::RwLock<HashMap<MemberId, Option<Site>>>>,
    /// Every site asked about so far: its file, line and column.
    sites: Vec<std::sync::RwLock<HashMap<u32, Option<Loc>>>>,
    /// The files sites are in, interned: a [`Loc`] names one by index, so a lookup copies three numbers and shares no reference count
    /// between the walks' threads.
    loc_files: std::sync::RwLock<(Vec<Arc<str>>, HashMap<Arc<str>, u32>)>,
    /// This model's identity among the models of the process (never 0), for the per-thread site cache.
    id: u64,
    /// Each own member's node and name, by member index: the tree's accessors go through a chunked arena and a symbol table that a
    /// retained session layers revision over revision, and the walks ask for a member's name and kind millions of times.
    minfo: Vec<Option<(&'static MemberNode, &'static str)>>,
    /// Each proc's parameters, parsed from its header when first asked.
    params: Vec<std::sync::RwLock<HashMap<MemberId, Arc<Vec<Param>>>>>,
    /// The repo-relative spelling of each path the site map names: every included file's resolved when the model is made (the site
    /// lookups of parallel walks then only read it), any other path once when first asked.
    rels: std::sync::RwLock<HashMap<Arc<str>, Arc<str>>>,
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
        let mut occurrence = HashMap::default();
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
            list.sort_by_cached_key(|id| start(id));
            // Stable: move each proc's declaration before the definitions of the same name that precede it (before the first one placed
            // so far). A linked list with each name's first node, so a type with thousands of members places them in linear time.
            if list.iter().any(|id| declares(id)) {
                let n = list.len();
                let mut next: Vec<usize> = vec![usize::MAX; n];
                let mut prev: Vec<usize> = vec![usize::MAX; n];
                let (mut head, mut tail) = (usize::MAX, usize::MAX);
                let mut first_of: HashMap<(dm_ir::SymbolId, MemberKind), usize> = HashMap::default();
                for (i, &id) in list.iter().enumerate() {
                    let name = tree.member(id).map(|m| (m.name, m.kind));
                    let before = if declares(&id) { name.and_then(|k| first_of.get(&k).copied()) } else { None };
                    match before {
                        Some(b) => {
                            // Insert node i before node b.
                            let p = prev[b];
                            next[i] = b;
                            prev[i] = p;
                            prev[b] = i;
                            if p == usize::MAX {
                                head = i;
                            } else {
                                next[p] = i;
                            }
                        }
                        None => {
                            prev[i] = tail;
                            if tail == usize::MAX {
                                head = i;
                            } else {
                                next[tail] = i;
                            }
                            tail = i;
                        }
                    }
                    if let Some(k) = name {
                        // The first placed node of the name: a node inserted before it takes its place.
                        match first_of.get(&k).copied() {
                            Some(f) if before != Some(f) => {}
                            _ => {
                                first_of.insert(k, i);
                            }
                        }
                    }
                }
                let mut placed: Vec<MemberId> = Vec::with_capacity(n);
                let mut at = head;
                while at != usize::MAX {
                    placed.push(list[at]);
                    at = next[at];
                }
                *list = placed;
            }
        }
        let t_members = started.elapsed();
        // Keyed by the name's symbol (`SymbolId::of` hashes the text, so a lookup by name allocates nothing).
        let mut named: HashMap<(TypeId, dm_ir::SymbolId, bool), Vec<MemberId>> = HashMap::default();
        for (i, list) in own.iter().enumerate() {
            for &id in list {
                if let Some(m) = tree.member(id) {
                    // The member's symbol is the hash of its spelling (`SymbolId::of`): the key a lookup by name computes.
                    let name = m.name;
                    named.entry((TypeId(i as u32), name, m.kind == MemberKind::Var)).or_default().push(id);
                }
            }
        }
        let t_named = started.elapsed();
        let root_abs = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
        let mut sites = TypeSites::default();
        for chunk in rev.syntax.chunks().iter() {
            type_blocks(chunk.items(), "/", &mut sites);
        }
        let t_sites = started.elapsed();
        let max_id = own.iter().flatten().map(|id| id.index()).max().map_or(0, |m| m + 1);
        let mut minfo: Vec<Option<(&'static MemberNode, &'static str)>> = vec![None; max_id];
        for &id in own.iter().flatten() {
            if let Some(m) = tree.member(id) {
                let name = symbols.text(m.name).unwrap_or("");
                // SAFETY: both borrow from the revision's semantic tree and symbol table, which the model owns (`rev`, an `Arc`) and never
                // changes; the references are handed out only with the model's borrow (`Model::node`, `Member::name`).
                minfo[id.index()] = Some(unsafe { (std::mem::transmute::<&MemberNode, &'static MemberNode>(m), std::mem::transmute::<&str, &'static str>(name)) });
            }
        }
        let model = Model {
            minfo,
            blocks: (0..SITE_SHARDS).map(|_| Default::default()).collect(),
            bodies: std::sync::OnceLock::new(),
            initializers: std::sync::OnceLock::new(),
            keys: std::sync::OnceLock::new(),
            params: (0..SITE_SHARDS).map(|_| Default::default()).collect(),
            sites: (0..SITE_SHARDS).map(|_| Default::default()).collect(),
            loc_files: Default::default(),
            id: NEXT_MODEL.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            proc_sites: (0..SITE_SHARDS).map(|_| Default::default()).collect(),
            declarations: (0..SITE_SHARDS).map(|_| Default::default()).collect(),
            folded: std::sync::OnceLock::new(),
            rev,
            root: root.to_path_buf(),
            paths,
            by_path,
            own,
            named,
            occurrence,
            type_sites: sites.blocks,
            parent_sites: sites.parents,
            rels: Default::default(),
            root_abs,
        };
        model.file_paths();
        if trace() {
            eprintln!(
                "analyze: model view: {} types, {} members, {} bodies in {:.1?} (members {:.1?}, names {:.1?}, type sites {:.1?}, files {:.1?})",
                model.paths.len(),
                model.occurrence.len(),
                model.rev.bodies.len(),
                started.elapsed(),
                t_members,
                t_named - t_members,
                t_sites - t_named,
                started.elapsed() - t_sites
            );
        }
        model
    }

    fn bodies(&self) -> &HashMap<MemberId, reuse::Body> {
        self.bodies.get_or_init(|| {
            use rayon::prelude::*;
            let started = std::time::Instant::now();
            let arena = dm_tree::frontend::BodyArena::new_typed(&self.rev, |_| true);
            let text = self.rev.expanded.text.as_str();
            // The previous model's bodies: a body whose text is unchanged is taken (moved when it moved) instead of parsed.
            let kept = reuse::kept();
            let verify = reuse::verify();
            let parse = |o: &dm_tree::frontend::BodyOccurrence| arena.take_parsed(o).ok().and_then(|b| b.shared_statement_body()).map(reuse::Body::Parsed);
            let made: Vec<(MemberId, Option<(u128, usize)>, Option<reuse::Body>, bool)> = self
                .rev
                .bodies
                .par_iter()
                .map(|o| {
                    let key = reuse::key(text, o.expanded_span.start, o.expanded_span.end);
                    if let Some((k, start)) = key {
                        if let Some(b) = reuse::take(&kept, k, start) {
                            if verify {
                                let fresh = parse(o);
                                if fresh.as_ref().map(|f| f.statements()) != Some(b.statements()) {
                                    eprintln!("analyze: model view: a reused body differs from its parse (member {:?}, at {})", o.member, start);
                                }
                            }
                            return (o.member, key, Some(b), true);
                        }
                    }
                    (o.member, key, parse(o), false)
                })
                .collect();
            drop(kept);
            let reused = made.iter().filter(|m| m.3).count();
            let mut next: HashMap<u128, (reuse::Body, usize)> = HashMap::default();
            let mut map: HashMap<MemberId, reuse::Body> = HashMap::default();
            for (m, key, b, _) in made {
                let Some(b) = b else { continue };
                if let Some((k, start)) = key {
                    next.insert(k, (b.clone(), start));
                }
                map.insert(m, b);
            }
            reuse::keep(next.into_iter().collect());
            if trace() {
                eprintln!(
                    "analyze: model view: {} typed bodies ({} kept from the previous model) in {:.1?} (process cpu {} ms)",
                    map.len(),
                    reused,
                    started.elapsed(),
                    crate::util::cpu_ms()
                );
            }
            map
        })
    }

    fn initializers(&self) -> &HashMap<MemberId, (Arc<dm_syntax::Expr>, usize)> {
        self.initializers.get_or_init(|| {
            use rayon::prelude::*;
            let started = std::time::Instant::now();
            let vars: Vec<MemberId> = self.own.iter().flatten().copied().filter(|id| self.node(*id).kind == MemberKind::Var).collect();
            // The previous model's values, by the item's text: an unchanged declaration is not parsed again.
            let kept = reuse::kept_values();
            let verify = reuse::verify();
            let parsed: Vec<(MemberId, Option<(u128, Arc<dm_syntax::Expr>, usize, usize)>, bool)> = vars
                .par_iter()
                .map(|&id| {
                    let member = Member { m: self, id };
                    let Some(start) = member.item_start() else { return (id, None, false) };
                    let key = member.item_text().map(reuse::text_key);
                    if let Some(k) = key {
                        if let Some((e, rel)) = kept.get(&k) {
                            if verify && member.parse_initializer().map(|(f, b)| (f, b - start)) != Some(((**e).clone(), *rel)) {
                                eprintln!("analyze: model view: a reused initializer differs from its parse (member {:?})", id);
                            }
                            return (id, Some((k, e.clone(), *rel, start)), true);
                        }
                    }
                    let made = member.parse_initializer().map(|(e, base)| (key.unwrap_or(0), Arc::new(e), base - start, start));
                    (id, made, false)
                })
                .collect();
            drop(kept);
            let reused = parsed.iter().filter(|p| p.2).count();
            let mut next = std::collections::HashMap::new();
            let mut map: HashMap<MemberId, (Arc<dm_syntax::Expr>, usize)> = HashMap::default();
            for (id, made, _) in parsed {
                let Some((k, e, rel, start)) = made else { continue };
                if k != 0 {
                    next.insert(k, (e.clone(), rel));
                }
                map.insert(id, (e, start + rel));
            }
            reuse::keep_values(next);
            if trace() {
                eprintln!(
                    "analyze: model view: {} var initializers ({} kept from the previous model) in {:.1?} (process cpu {} ms)",
                    map.len(),
                    reused,
                    started.elapsed(),
                    crate::util::cpu_ms()
                );
            }
            map
        })
    }

    /// Builds the typed bodies, the var initializers and the folded constants now, on every core. They are built once per model and
    /// read from inside parallel walks: a lazy build there runs on the one thread that got there first while every other worker waits on
    /// it, so the model builds them up front.
    pub fn prewarm(&self) {
        rayon::join(|| self.bodies().len(), || self.initializers().len());
        self.folded();
    }

    /// Every var's folded constant.
    pub fn folded(&self) -> &consts::Folded {
        // Every var's folded value reads every initializer it reaches.
        reads::note(|| reads::Read::Everything);
        self.folded.get_or_init(|| {
            let started = std::time::Instant::now();
            let f = consts::fold_all(self);
            if trace() {
                eprintln!("analyze: model view: {} vars folded in {:.1?} (process cpu {} ms)", f.values.len(), started.elapsed(), crate::util::cpu_ms());
            }
            f
        })
    }

    /// Every source file of the revision (repo-relative), in include order, each once.
    pub fn file_paths(&self) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for o in self.rev.plan.occurrences.iter() {
            let rel = self.rel(&o.semantic_path);
            if seen.insert(rel.clone()) {
                out.push(rel);
            }
        }
        out
    }

    pub fn frontend(&self) -> &ColdFrontend {
        &self.rev
    }

    pub fn ty(&self, path: &str) -> Option<Ty<'_>> {
        self.by_path.get(path).map(|&id| Ty { m: self, id })
    }

    pub fn types(&self) -> impl Iterator<Item = Ty<'_>> + '_ {
        reads::note(|| reads::Read::Everything);
        (0..self.paths.len()).map(move |i| Ty { m: self, id: TypeId(i as u32) })
    }

    fn node(&self, id: MemberId) -> &MemberNode {
        match self.minfo.get(id.index()) {
            Some(Some((node, _))) => node,
            _ => self.rev.snapshot.tree.member(id).expect("a member of this revision"),
        }
    }

    fn member_name(&self, id: MemberId) -> &str {
        match self.minfo.get(id.index()) {
            Some(Some((_, name))) => name,
            _ => self.text(self.node(id).name),
        }
    }

    fn text(&self, id: dm_ir::SymbolId) -> &str {
        self.rev.snapshot.tree.symbols().text(id).unwrap_or("")
    }

    /// The file (repo-relative, `/` separated) and line of `site`; `None` for a site no source file holds.
    pub fn line(&self, site: Site) -> Option<(String, u32)> {
        self.located(site).map(|l| (self.loc_file(l).to_string(), l.line))
    }

    /// Only the line of `site` (no file name allocated).
    pub fn line_no(&self, site: Site) -> Option<u32> {
        self.located(site).map(|l| l.line)
    }

    /// The file of `site`, shared.
    pub fn file_arc(&self, site: Site) -> Option<Arc<str>> {
        self.located(site).map(|l| self.loc_file(l))
    }

    /// Like [`Model::line`], with the column.
    pub fn line_column(&self, site: Site) -> Option<(String, u32, u32)> {
        self.located(site).map(|l| (self.loc_file(l).to_string(), l.line, l.col))
    }

    /// `block` read as statements ([`walk::stmts`]), remembered by its address.
    ///
    /// `block` must be part of a body of this model (a proc's [`Member::body`] or a block nested in one): the remembered statements borrow
    /// from it, and the model keeps every body alive (and unmoved: each is an `Arc`) for as long as the remembered statements exist.
    pub fn stmts<'m>(&'m self, block: &'m [dm_syntax::Statement]) -> Arc<Block<'m>> {
        let key = (block.as_ptr() as usize, block.len());
        let shard = &self.blocks[key.0.wrapping_mul(0x9E37_79B9) >> 26 & (SITE_SHARDS - 1)];
        if let Some(hit) = shard.read().unwrap_or_else(|e| e.into_inner()).get(&key) {
            return hit.clone();
        }
        let stmts: Vec<walk::StmtAt<'m>> = walk::stmts(block);
        let lines = stmts.iter().map(|st| self.line_no(st.site).unwrap_or(0)).collect();
        let read = Block { stmts, lines };
        // SAFETY: `read` borrows from `block`, which (the contract above) lives in a body this model owns and outlives the cache: `blocks`
        // is dropped first, and the statements are handed out with the model's borrow (`'m`), never longer.
        let stored: Arc<Block<'static>> = Arc::new(unsafe { std::mem::transmute::<Block<'m>, Block<'static>>(read) });
        shard.write().unwrap_or_else(|e| e.into_inner()).insert(key, stored.clone());
        stored
    }

    /// `find`'s answer for (type, name), remembered.
    pub(crate) fn remembered_declaration(&self, ty: TypeId, name: &str, find: impl FnOnce() -> Option<consts::VarDeclaration>) -> Option<consts::VarDeclaration> {
        let key = (ty, dm_ir::SymbolId::of(name));
        let shard = &self.declarations[(ty.0 as usize ^ name.len()).wrapping_mul(0x9E37_79B9) >> 26 & (SITE_SHARDS - 1)];
        if let Some(hit) = shard.read().unwrap_or_else(|e| e.into_inner()).get(&key) {
            return hit.clone();
        }
        let found = find();
        shard.write().unwrap_or_else(|e| e.into_inner()).insert(key, found.clone());
        found
    }

    /// A site's file, line and column, remembered: the walks ask about the same terms many times.
    fn located(&self, site: Site) -> Option<Loc> {
        profile::count(profile::SITE_HIT);
        // A small direct-mapped cache per thread in front of the shared one: the walks ask the same sites again and again, and a
        // lookup here takes no lock and touches no line another thread writes.
        thread_local! {
            static NEAR: std::cell::RefCell<Vec<(u64, u32, Option<Loc>)>> = const { std::cell::RefCell::new(Vec::new()) };
        }
        let slot = (site.0 as usize).wrapping_mul(0x9E37_79B9) >> 16 & (NEAR_SLOTS - 1);
        let near = NEAR.with(|n| {
            let n = n.borrow();
            n.get(slot).and_then(|&(m, s, l)| (m == self.id && s == site.0).then_some(l))
        });
        if let Some(l) = near {
            return l;
        }
        let found = self.located_shared(site);
        NEAR.with(|n| {
            let mut n = n.borrow_mut();
            if n.is_empty() {
                n.resize(NEAR_SLOTS, (0, 0, None));
            }
            n[slot] = (self.id, site.0, found);
        });
        found
    }

    fn located_shared(&self, site: Site) -> Option<Loc> {
        let shard = &self.sites[(site.0 as usize).wrapping_mul(0x9E37_79B9) >> 26 & (SITE_SHARDS - 1)];
        if let Some(hit) = shard.read().unwrap_or_else(|e| e.into_inner()).get(&site.0) {
            return *hit;
        }
        profile::count(profile::SITE_MISS);
        let found = self.rev.debug_site_column(site.0 as usize).map(|(path, line, column)| Loc { file: self.intern_file(&path), line: line as u32, col: column as u32 });
        shard.write().unwrap_or_else(|e| e.into_inner()).insert(site.0, found);
        found
    }

    /// The index of `path`'s repo-relative spelling in [`Model::loc_files`].
    fn intern_file(&self, path: &Arc<str>) -> u32 {
        let rel = self.rel_arc(path);
        if let Some(&i) = self.loc_files.read().unwrap_or_else(|e| e.into_inner()).1.get(&rel) {
            return i;
        }
        let mut files = self.loc_files.write().unwrap_or_else(|e| e.into_inner());
        if let Some(&i) = files.1.get(&rel) {
            return i;
        }
        let i = files.0.len() as u32;
        files.0.push(rel.clone());
        files.1.insert(rel, i);
        i
    }

    fn loc_file(&self, l: Loc) -> Arc<str> {
        self.loc_files.read().unwrap_or_else(|e| e.into_inner()).0[l.file as usize].clone()
    }

    fn rel_arc(&self, path: &Arc<str>) -> Arc<str> {
        if let Some(r) = self.rels.read().unwrap_or_else(|e| e.into_inner()).get(path) {
            return r.clone();
        }
        let r: Arc<str> = self.rel(path).into();
        r
    }

    fn rel(&self, path: &Arc<str>) -> String {
        if let Some(r) = self.rels.read().unwrap_or_else(|e| e.into_inner()).get(path) {
            return r.to_string();
        }
        let p = Path::new(&**path);
        let abs = if p.is_absolute() { p.to_path_buf() } else { self.root.join(p) };
        // A path already under the root needs no file system call (a canonicalize is milliseconds on Windows, and the model resolves
        // every included file); anything else is canonicalized as before.
        let abs = match abs.strip_prefix(&self.root_abs).or_else(|_| abs.strip_prefix(&self.root)) {
            Ok(rel) if !rel.components().any(|c| matches!(c, std::path::Component::ParentDir | std::path::Component::CurDir)) => self.root_abs.join(rel),
            _ => std::fs::canonicalize(&abs).unwrap_or(abs),
        };
        let r: Arc<str> = match abs.strip_prefix(&self.root_abs) {
            Ok(rel) => rel.to_string_lossy().replace('\\', "/").into(),
            Err(_) => path.replace('\\', "/").into(),
        };
        self.rels.write().unwrap_or_else(|e| e.into_inner()).insert(path.clone(), r.clone());
        r.to_string()
    }

    fn occurrence_site(&self, at: OccurrenceId) -> Option<Site> {
        self.rev.declaration_spans.get(at.0 as usize).map(|span| Site(span.start))
    }
}

/// Slots of the per-thread site cache ([`Model::located`]).
const NEAR_SLOTS: usize = 1 << 16;

static NEXT_MODEL: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

/// Where a site is: its file (an index into the model's interned files), line and column.
#[derive(Clone, Copy)]
struct Loc {
    file: u32,
    line: u32,
    col: u32,
}

/// A body block read as statements ([`Model::stmts`]), with each statement's line (0 for none), looked up once per block.
pub struct Block<'a> {
    pub stmts: Vec<walk::StmtAt<'a>>,
    pub lines: Vec<u32>,
}

/// A type of the semantic tree.
#[derive(Clone, Copy)]
pub struct Ty<'m> {
    m: &'m Model,
    pub id: TypeId,
}

impl<'m> Ty<'m> {
    pub(crate) fn m_ref(&self) -> &'m Model {
        self.m
    }

    pub fn path(&self) -> &'m str {
        &self.m.paths[self.id.index()]
    }

    pub fn parent(&self) -> Option<Ty<'m>> {
        reads::note(|| reads::Read::Parents(Arc::from(self.path())));
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
        reads::note(|| reads::Read::Everything);
        let m = self.m;
        m.own[self.id.index()].iter().map(move |&id| Member { m, id })
    }

    pub fn vars(&self) -> impl Iterator<Item = Member<'m>> + 'm {
        self.members().filter(|x| x.kind() == MemberKind::Var)
    }

    pub fn procs(&self) -> impl Iterator<Item = Member<'m>> + 'm {
        self.members().filter(|x| x.kind() != MemberKind::Var)
    }

    /// This type's own definitions of the var `name`, in order.
    pub fn own_vars_named(&self, name: &str) -> impl Iterator<Item = Member<'m>> + 'm {
        reads::note(|| reads::Read::Lookup { owner: Arc::from(self.path()), name: Arc::from(name), kind: reads::LookupKind::Var });
        let m = self.m;
        m.named.get(&(self.id, dm_ir::SymbolId::of(name), true)).into_iter().flatten().map(move |&id| Member { m, id })
    }

    /// The ids of this type's own definitions of the proc `name`, in override order.
    pub(crate) fn own_proc_ids(&self, name: &str) -> &'m [MemberId] {
        reads::note(|| reads::Read::Lookup { owner: Arc::from(self.path()), name: Arc::from(name), kind: reads::LookupKind::Proc });
        self.m.named.get(&(self.id, dm_ir::SymbolId::of(name), false)).map_or(&[], |v| &v[..])
    }

    pub(crate) fn member(&self, id: MemberId) -> Member<'m> {
        Member { m: self.m, id }
    }

    /// This type's own definitions of the proc `name`, in override order.
    pub fn own_procs_named(&self, name: &str) -> impl Iterator<Item = Member<'m>> + 'm {
        reads::note(|| reads::Read::Lookup { owner: Arc::from(self.path()), name: Arc::from(name), kind: reads::LookupKind::Proc });
        let m = self.m;
        m.named.get(&(self.id, dm_ir::SymbolId::of(name), false)).into_iter().flatten().map(move |&id| Member { m, id })
    }

    /// `self` is `other` or one of its subtypes.
    pub fn is_subtype_of(&self, other: &Ty<'_>) -> bool {
        let mut cur = Some(*self);
        while let Some(t) = cur {
            if t.id == other.id {
                return true;
            }
            cur = t.parent();
        }
        false
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
        self.m.member_name(self.id)
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
        self.note_declaration();
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
        self.note_declaration();
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
        reads::note(|| self.key().map_or(reads::Read::Everything, reads::Read::Site));
        let start = self.m.occurrence_site(*self.m.occurrence.get(&self.id)?)?;
        if self.kind() == MemberKind::Var {
            return Some(start);
        }
        let shard = &self.m.proc_sites[(self.id.0 as usize).wrapping_mul(0x9E37_79B9) >> 26 & (SITE_SHARDS - 1)];
        if let Some(hit) = shard.read().unwrap_or_else(|e| e.into_inner()).get(&self.id) {
            return *hit;
        }
        let found = self.paren_site(start);
        shard.write().unwrap_or_else(|e| e.into_inner()).insert(self.id, found);
        found
    }

    /// A proc's parameter list `(`: the first `(` of its item. Before it a header holds only its path, so a plain scan finds it; a quote
    /// or a comment before any `(` (never in a header the compiler accepted, kept for safety) sends it to the lexer.
    fn paren_site(&self, start: Site) -> Option<Site> {
        let text = self.item_text()?;
        let bytes = text.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            match bytes[i] {
                b'(' => return Some(Site(start.0 + i as u32)),
                b'"' | b'\'' | b'{' => break,
                b'/' if matches!(bytes.get(i + 1), Some(b'/') | Some(b'*')) => break,
                _ => {}
            }
            i += 1;
        }
        if i == bytes.len() {
            return Some(start);
        }
        for token in dm_syntax::lex(text).tokens {
            if token.text == "(" {
                return Some(Site(start.0 + token.span.start as u32));
            }
        }
        Some(start)
    }

    /// This definition's stable identity (the front end delta's key), for a read receipt.
    pub fn key(&self) -> Option<dm_tree::frontend::DeclarationKey> {
        let at = *self.m.occurrence.get(&self.id)?;
        self.m.keys.get_or_init(|| dm_tree::frontend::declaration_keys(&self.m.rev)).get(at.0 as usize)?.clone()
    }

    fn note_declaration(&self) {
        reads::note(|| self.key().map_or(reads::Read::Everything, reads::Read::Declaration));
    }

    /// The proc's typed body: none for a var, a builtin, or a body the compiler's parser rejected.
    pub fn body(&self) -> Option<&'m [dm_syntax::Statement]> {
        reads::note(|| self.key().map_or(reads::Read::Everything, reads::Read::Body));
        self.m.bodies().get(&self.id).map(|b| b.statements())
    }

    /// Whether the var is given a value: an initializer, or a size (`var/L[3]`, which starts as `new /list(3)`).
    pub fn has_value(&self) -> bool {
        self.initializer().is_some() || self.sized_list()
    }

    /// `var/L[3]` with no value written: a list of that size.
    pub fn sized_list(&self) -> bool {
        if self.kind() != MemberKind::Var || self.initializer().is_some() {
            return false;
        }
        let Some(text) = self.item_text() else { return false };
        let header = text.lines().next().unwrap_or("");
        let header = match dm_syntax::top_level_assignment_index(header) {
            Some(i) => &header[..i],
            None => header,
        };
        // A written size: `[3]` (or `[2][][3]`), not only `[]`.
        let name = header.rsplit('/').next().unwrap_or(header);
        !walk::declaration(name, None).suffix_args.is_empty()
    }

    /// A var's initializer as written (`= value`), parsed by the compiler's expression parser; none without a value.
    pub fn initializer(&self) -> Option<&'m dm_syntax::Expr> {
        self.note_declaration();
        self.m.initializers().get(&self.id).map(|(e, _)| expr::specified(&**e).0)
    }

    /// The initializer with the expanded offset its spans are relative to (add it to a node's span for a [`Site`]).
    pub fn initializer_at(&self) -> Option<(&'m dm_syntax::Expr, usize)> {
        self.note_declaration();
        self.m.initializers().get(&self.id).map(|(e, base)| (expr::specified(&**e).0, *base))
    }

    /// The parameters (procs and verbs), as the header spells them.
    pub fn parameters(&self) -> Arc<Vec<Param>> {
        self.note_declaration();
        let shard = &self.m.params[(self.id.0 as usize).wrapping_mul(0x9E37_79B9) >> 26 & (SITE_SHARDS - 1)];
        if let Some(p) = shard.read().unwrap_or_else(|e| e.into_inner()).get(&self.id) {
            return p.clone();
        }
        let p = Arc::new(self.parse_parameters());
        shard.write().unwrap_or_else(|e| e.into_inner()).insert(self.id, p.clone());
        p
    }

    fn parse_parameters(&self) -> Vec<Param> {
        let mut out = Vec::new();
        let Some(procedure) = self.node().metadata.procedure.as_ref() else { return out };
        let (Some(at), Some(text)) = (self.m.occurrence.get(&self.id), self.item_text()) else { return out };
        let start = self.m.rev.declaration_spans[at.0 as usize].start as usize;
        let Some((before, arguments, _)) = signature_parts(text) else { return out };
        let base = start + before.len() + 1;
        for p in procedure.signature.parameters.iter() {
            let (s, e) = (p.relative_span.start as usize, p.relative_span.end as usize);
            if let Some(t) = arguments.get(s..e) {
                out.push(Param::parse(t, base + s));
            }
        }
        if procedure.signature.variadic {
            out.push(Param { name: "...".into(), type_path: Vec::new(), value: None, as_types: None, in_list: None, site: Site(base as u32) });
        }
        out
    }

    /// `proc/f() as text|num`: the input types the header's return clause names (none for a type path or no clause).
    pub fn return_input_types(&self) -> Option<Vec<String>> {
        let text = self.item_text()?;
        let (_, _, after) = signature_parts(text)?;
        let after = after.lines().next().unwrap_or("");
        let rest = after.trim().strip_prefix("as")?.trim();
        (!rest.is_empty() && !rest.starts_with('/')).then(|| rest.split('|').map(|t| t.trim().to_owned()).filter(|t| !t.is_empty()).collect())
    }

    /// `proc/f() as /obj/item`: the return type path the header names.
    pub fn return_type_path(&self) -> Option<Vec<String>> {
        let text = self.item_text()?;
        let (_, _, after) = signature_parts(text)?;
        let after = after.lines().next().unwrap_or("");
        let rest = after.trim().strip_prefix("as")?.trim();
        rest.starts_with('/').then(|| rest.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect())
    }

    fn parse_initializer(&self) -> Option<(dm_syntax::Expr, usize)> {
        let at = *self.m.occurrence.get(&self.id)?;
        let span = self.m.rev.declaration_spans.get(at.0 as usize)?;
        let text = self.m.rev.expanded.text.as_str().get(span.start as usize..span.end as usize)?;
        let eq = dm_syntax::top_level_assignment_index(text)?;
        let rest = &text[eq + 1..];
        let lead = rest.len() - rest.trim_start().len();
        let value = rest.trim();
        let base = span.start as usize + eq + 1 + lead;
        let parsed = dm_syntax::parse_expression(value);
        match parsed.expr {
            Some(e) if parsed.diagnostics.is_empty() => Some((e, base)),
            _ => {
                // A value followed by more lines of the item: the first line alone.
                let first = value.lines().next()?.trim_end();
                let parsed = dm_syntax::parse_expression(first);
                parsed.expr.filter(|_| parsed.diagnostics.is_empty()).map(|e| (e, base))
            }
        }
    }

    /// Where the member's declaration item starts in the expanded text.
    fn item_start(&self) -> Option<usize> {
        let at = *self.m.occurrence.get(&self.id)?;
        self.m.rev.declaration_spans.get(at.0 as usize).map(|s| s.start as usize)
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

/// `(before, arguments, after)` of a proc header: the first top-level parenthesis group. The header's first line is read first (an item's
/// text holds its whole body).
fn signature_parts(header: &str) -> Option<(&str, &str, &str)> {
    if let Some(line_end) = header.find('\n') {
        if let Some(parts) = signature_parts_in(&header[..line_end]) {
            let (before, arguments, _) = parts;
            let after_start = before.len() + 1 + arguments.len() + 1;
            return Some((before, arguments, &header[after_start..]));
        }
    }
    signature_parts_in(header)
}

fn signature_parts_in(header: &str) -> Option<(&str, &str, &str)> {
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

/// One parameter as its declaration spells it (`var/mob/user = null`, `atom/A as obj in view()`).
#[derive(Clone, Debug)]
pub struct Param {
    pub name: String,
    /// The declared type path segments, flags removed; a size suffix puts `list` first.
    pub type_path: Vec<String>,
    /// The default value as written (with its specifiers), with the expanded offset its spans are relative to.
    pub value: Option<(dm_syntax::Expr, usize)>,
    /// `as obj|mob`, from the default or the declaration.
    pub as_types: Option<Vec<String>>,
    /// `in L`, from the default or the declaration, with its offset.
    pub in_list: Option<(dm_syntax::Expr, usize)>,
    pub site: Site,
}

impl Param {
    /// `/mob`, empty when untyped.
    pub fn declared(&self) -> String {
        if self.type_path.is_empty() {
            String::new()
        } else {
            format!("/{}", self.type_path.join("/"))
        }
    }

    /// The default value without its specifiers.
    pub fn default(&self) -> Option<&dm_syntax::Expr> {
        self.value.as_ref().map(|(e, _)| expr::specified(e).0)
    }

    fn parse(text: &str, at: usize) -> Param {
        let (declaration, default) = match dm_syntax::top_level_assignment_index(text) {
            Some(index) => {
                let rest = &text[index + 1..];
                let lead = rest.len() - rest.trim_start().len();
                (text[..index].trim(), Some((rest.trim(), at + index + 1 + lead)))
            }
            None => (text.trim(), None),
        };
        let mut in_list = None;
        if let Some(index) = declaration.find(" in ") {
            let rest = &declaration[index + 4..];
            let lead = rest.len() - rest.trim_start().len();
            let parsed = dm_syntax::parse_expression(rest.trim());
            in_list = parsed.expr.filter(|_| parsed.diagnostics.is_empty()).map(|e| (e, at + index + 4 + lead));
        }
        let declaration = declaration.split(" in ").next().unwrap_or(declaration);
        let mut as_types = declaration.split_once(" as ").map(|(_, t)| t.split('|').map(|x| x.trim().to_owned()).collect::<Vec<_>>());
        let declaration = declaration.split(" as ").next().unwrap_or(declaration).trim();
        let suffixed = declaration.contains('[');
        let declaration = declaration.split('[').next().unwrap_or(declaration).trim();
        let declaration = declaration.strip_prefix("var/").unwrap_or(declaration);
        let pieces: Vec<&str> = declaration.split('/').filter(|p| !p.is_empty()).collect();
        let name = pieces.last().copied().unwrap_or("").to_owned();
        let flags = ["static", "global", "const", "tmp", "SpacemanDMM_private", "SpacemanDMM_protected", "SpacemanDMM_final"];
        let mut type_path: Vec<String> =
            pieces[..pieces.len().saturating_sub(1)].iter().filter(|p| !flags.contains(*p)).map(|p| p.to_string()).collect();
        if suffixed {
            type_path.insert(0, "list".to_owned());
        }
        let value = default.and_then(|(t, a)| {
            let parsed = dm_syntax::parse_expression(t);
            parsed.expr.filter(|_| parsed.diagnostics.is_empty()).map(|e| (e, a))
        });
        if let Some((e, a)) = &value {
            let (_, types, list) = expr::specified(e);
            if let Some(t) = types {
                as_types = Some(t.to_vec());
            }
            if let Some(l) = list {
                in_list = Some((l.clone(), *a));
            }
        }
        Param { name, type_path, value, as_types, in_list, site: Site(at as u32) }
    }
}
