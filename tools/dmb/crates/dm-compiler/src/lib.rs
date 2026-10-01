//! Incremental DM front-end queries. This crate owns Salsa state; syntax,
//! semantics, and IR remain usable without Salsa by other tools.

use dm_preprocess::{PreprocessedProject, SourceProvider};
use dm_semantics::DeclarationIndex;
use dm_syntax::{AstFile, Lexed};
use salsa::Setter as _;
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub mod frontend;
pub mod lower_cache;
pub mod maps;
mod proc_parse_cache;
mod semantic_queries;
mod source_debug;
pub use maps::{load_map_set, load_map_set_from_paths, MapSet};

pub const TARGET_VERSION: u32 = 516;
pub const TARGET_BUILD: u32 = 1687;

/// Recover authored lexical diagnostics after a failed structural parse. This
/// error-only pass is chunk bounded and adds no scan to successful builds.
pub fn authored_syntax_errors(project: &PreprocessedProject, project_root: &Path) -> Vec<String> {
    let origins = source_debug::SourceDebugIndex::new(project, project_root);
    let mut errors = Vec::new();
    dm_syntax::for_each_source_chunk(&project.text, 1024 * 1024, |source, base| {
        if errors.len() >= 64 { return; }
        for error in dm_syntax::lex_spans(source).diagnostics {
            if errors.len() >= 64 { break; }
            if let Some((file, line)) = origins.resolve(base + error.span.start) {
                errors.push(format!("{file}:{line}: error: {}", error.message));
            }
        }
    });
    errors
}

/// Native compiler macros must be present even in configurations with no
/// user-supplied defines. They also select version compatibility branches.
pub fn target_defines(mut defines: BTreeMap<String, String>) -> BTreeMap<String, String> {
    defines
        .entry("DM_VERSION".into())
        .or_insert_with(|| TARGET_VERSION.to_string());
    defines
        .entry("DM_BUILD".into())
        .or_insert_with(|| TARGET_BUILD.to_string());
    defines
}

#[salsa::db]
pub trait Db: salsa::Database {}

#[salsa::db]
#[derive(Clone, Default)]
pub struct Database {
    storage: salsa::Storage<Self>,
}

#[salsa::db]
impl salsa::Database for Database {}

#[salsa::db]
impl Db for Database {}

#[salsa::input]
pub struct SourceFile {
    pub path: PathBuf,
    #[returns(deref)]
    pub text: String,
}

/// A portable input snapshot for project-level preprocessing. This coarse
/// input is the first integration step; later include-occurrence queries can
/// narrow invalidation without changing the syntax/preprocessor crates.
#[salsa::input]
pub struct ProjectSnapshot {
    pub root: PathBuf,
    #[returns(ref)]
    pub sources: BTreeMap<PathBuf, String>,
    #[returns(ref)]
    pub defines: BTreeMap<String, String>,
}

/// Live project graph. File input handles remain stable across edits; the
/// manifest map changes only when an include is added or removed.
#[salsa::input]
pub struct ProjectRoot {
    pub root: PathBuf,
    #[returns(ref)]
    pub files: BTreeMap<PathBuf, SourceFile>,
    #[returns(ref)]
    pub defines: BTreeMap<String, String>,
}

struct LiveProvider<'a> {
    db: &'a dyn Db,
    files: &'a BTreeMap<PathBuf, SourceFile>,
}

impl SourceProvider for LiveProvider<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        let source = self
            .files
            .get(path)
            .ok_or_else(|| format!("not in project source set: {}", path.display()))?;
        Ok(source.text(self.db).to_owned())
    }
}

#[salsa::tracked]
pub fn preprocess_live(db: &dyn Db, project: ProjectRoot) -> PreprocessedProject {
    dm_preprocess::preprocess_project(
        project.root(db),
        &LiveProvider {
            db,
            files: project.files(db),
        },
        project.defines(db),
    )
}

#[salsa::tracked]
pub fn parse_live(db: &dyn Db, project: ProjectRoot) -> AstFile {
    dm_syntax::parse(&preprocess_live(db, project).text)
}

#[salsa::tracked(no_eq)]
pub fn index_live(db: &dyn Db, project: ProjectRoot) -> Result<DeclarationIndex, Vec<String>> {
    let declarations = declarations::lower_declarations(parse_live(db, project))?;
    DeclarationIndex::build(declarations).map_err(|errors| {
        errors
            .into_iter()
            .map(|error| format!("{error:?}"))
            .collect()
    })
}

struct SnapshotProvider<'a>(&'a BTreeMap<PathBuf, String>);

impl SourceProvider for SnapshotProvider<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0
            .get(path)
            .cloned()
            .ok_or_else(|| format!("not in project input snapshot: {}", path.display()))
    }
}

#[salsa::tracked]
pub fn preprocess_snapshot(db: &dyn Db, snapshot: ProjectSnapshot) -> PreprocessedProject {
    dm_preprocess::preprocess_project(
        snapshot.root(db),
        &SnapshotProvider(snapshot.sources(db)),
        snapshot.defines(db),
    )
}

#[salsa::tracked]
pub fn parse_project(db: &dyn Db, snapshot: ProjectSnapshot) -> AstFile {
    dm_syntax::parse(&preprocess_snapshot(db, snapshot).text)
}

/// The first semantic bridge handles declaration shapes it can identify
/// unambiguously. Unknown forms are reported rather than misindexed.
#[salsa::tracked(no_eq)]
pub fn index_project(
    db: &dyn Db,
    snapshot: ProjectSnapshot,
) -> Result<DeclarationIndex, Vec<String>> {
    let ast = parse_project(db, snapshot);
    let declarations = declarations::lower_declarations(ast)?;
    DeclarationIndex::build(declarations).map_err(|errors| {
        errors
            .into_iter()
            .map(|error| format!("{error:?}"))
            .collect()
    })
}

pub mod bootstrap;
pub mod incremental;
pub use bootstrap::{audit_initializers, InitializerAudit};
pub mod declarations;

/// Index an already parsed expansion without preprocessing or parsing it again.
pub fn index_ast(ast: &AstFile) -> Result<DeclarationIndex, Vec<String>> {
    let declarations = declarations::lower_declarations(ast)?;
    DeclarationIndex::build(declarations).map_err(|errors| {
        errors
            .into_iter()
            .map(|error| format!("{error:?}"))
            .collect()
    })
}

/// Bound whole-project diagnostic parsing in both the CLI and daemon.
pub fn check_source_size(size: usize, limit: usize) -> Result<(), String> {
    if size > limit {
        return Err(format!(
            "preprocessed project is {size} bytes, above the check limit of {limit}; set DM_CHECK_MAX_SOURCE_BYTES to raise it"
        ));
    }
    Ok(())
}

pub fn check_source_limit() -> usize {
    std::env::var("DM_CHECK_MAX_SOURCE_BYTES")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(16 * 1024 * 1024)
}

#[salsa::tracked]
pub fn lex_source(db: &dyn Db, source: SourceFile) -> Lexed {
    dm_syntax::lex(source.text(db))
}

#[salsa::tracked]
pub fn parse_source(db: &dyn Db, source: SourceFile) -> AstFile {
    dm_syntax::parse(source.text(db))
}

/// One Salsa database per worktree/build configuration. The registry keeps
/// input identity stable through edits, which is necessary for reuse.
#[derive(Default)]
pub struct CompilerSession {
    db: Database,
    files: BTreeMap<PathBuf, SourceFile>,
}

/// Mutable project view used by editor/daemon sessions. It keeps one Salsa
/// input identity while source contents change. A later include-occurrence
/// query can replace the coarse `sources` field without changing callers.
pub struct ProjectSession {
    db: Database,
    project: ProjectRoot,
    preprocess_cache: RefCell<dm_preprocess::PreprocessCache>,
    preprocessed: RefCell<Option<PreprocessedProject>>,
    cache_path: Option<PathBuf>,
    outline_session: RefCell<frontend::OutlineSession>,
}

impl ProjectSession {
    pub fn new(
        root: PathBuf,
        sources: BTreeMap<PathBuf, String>,
        defines: BTreeMap<String, String>,
    ) -> Self {
        let defines = target_defines(defines);
        let db = Database::default();
        let files = sources
            .into_iter()
            .map(|(path, text)| (path.clone(), SourceFile::new(&db, path, text)))
            .collect();
        let project = ProjectRoot::new(&db, root, files, defines);
        Self {
            db,
            project,
            preprocess_cache: RefCell::new(dm_preprocess::PreprocessCache::default()),
            preprocessed: RefCell::new(None),
            cache_path: None,
            outline_session: RefCell::new(frontend::OutlineSession::default()),
        }
    }

    pub fn from_disk(root: PathBuf, defines: BTreeMap<String, String>) -> Self {
        let defines = target_defines(defines);
        struct CollectingFiles(RefCell<BTreeMap<PathBuf, String>>);
        impl SourceProvider for CollectingFiles {
            fn read(&self, path: &Path) -> Result<String, String> {
                let text = dm_preprocess::read_source_file(path)
                    .map_err(|error| format!("{}: {error}", path.display()))?;
                self.0.borrow_mut().insert(path.to_path_buf(), text.clone());
                Ok(text)
            }
        }
        let files = CollectingFiles(RefCell::new(BTreeMap::new()));
        let cache_path = preprocess_cache_path(&root);
        let mut cache = dm_preprocess::PreprocessCache::load_incremental(&cache_path);
        let preprocessed =
            dm_preprocess::preprocess_project_cached(&root, &files, &defines, &mut cache);
        if cache.misses > 0 {
            let _ = cache.save_incremental(&cache_path);
        }
        let mut session = Self::new(root, files.0.into_inner(), defines);
        session.cache_path = Some(cache_path);
        *session.outline_session.borrow_mut() = frontend::OutlineSession::new(Some(
            lower_cache::project_cache_root(session.project.root(&session.db)),
        ));
        *session.preprocess_cache.borrow_mut() = cache;
        *session.preprocessed.borrow_mut() = Some(preprocessed);
        session
    }

    pub fn update_source(&mut self, path: PathBuf, text: String) -> bool {
        if let Some(source) = self.project.files(&self.db).get(&path).copied() {
            if source.text(&self.db) == text {
                return false;
            }
            source.set_text(&mut self.db).to(text);
            self.preprocessed.get_mut().take();
            return true;
        }
        let source = SourceFile::new(&self.db, path.clone(), text);
        let mut files = self.project.files(&self.db).clone();
        files.insert(path, source);
        self.project.set_files(&mut self.db).to(files);
        self.preprocessed.get_mut().take();
        true
    }

    pub fn remove_source(&mut self, path: &Path) -> bool {
        if !self.project.files(&self.db).contains_key(path) {
            return false;
        }
        let mut files = self.project.files(&self.db).clone();
        files.remove(path);
        self.project.set_files(&mut self.db).to(files);
        self.preprocessed.get_mut().take();
        true
    }

    pub fn set_defines(&mut self, defines: BTreeMap<String, String>) -> bool {
        let defines = target_defines(defines);
        if self.project.defines(&self.db) == &defines {
            return false;
        }
        self.project.set_defines(&mut self.db).to(defines);
        self.preprocessed.get_mut().take();
        true
    }

    pub fn preprocess(&self) -> &PreprocessedProject {
        preprocess_live(&self.db, self.project)
    }

    /// Size of the already preprocessed disk snapshot, when one is available.
    pub fn preprocessed_byte_len(&self) -> Option<usize> {
        self.preprocessed
            .borrow()
            .as_ref()
            .map(|project| project.text.len())
    }

    /// Reuse complete leaf-include expansions across changed-file builds.
    /// Each reuse checks the source and incoming macro environment exactly.
    pub fn preprocess_incremental(&self) -> PreprocessedProject {
        if let Some(preprocessed) = self.preprocessed.borrow().as_ref() {
            return preprocessed.clone();
        }
        let misses_before = self.preprocess_cache.borrow().misses;
        let preprocessed = dm_preprocess::preprocess_project_cached(
            self.project.root(&self.db),
            &LiveProvider {
                db: &self.db,
                files: self.project.files(&self.db),
            },
            self.project.defines(&self.db),
            &mut self.preprocess_cache.borrow_mut(),
        );
        if let Some(path) = &self.cache_path {
            let mut cache = self.preprocess_cache.borrow_mut();
            if cache.misses > misses_before {
                let _ = cache.save_incremental(path);
            }
        }
        *self.preprocessed.borrow_mut() = Some(preprocessed.clone());
        preprocessed
    }

    pub fn preprocess_cache_stats(&self) -> (usize, usize) {
        let cache = self.preprocess_cache.borrow();
        (cache.hits, cache.misses)
    }

    /// Reuse syntax identities across edits without retaining procedure token
    /// trees. Declaration changes still invalidate the semantic linking guard.
    pub fn source_outline(&self) -> Result<incremental::SourceOutline, String> {
        let preprocessed = self.preprocess_incremental();
        if !preprocessed.diagnostics.is_empty() {
            return Err(format!(
                "preprocessing diagnostics: {:?}",
                preprocessed.diagnostics
            ));
        }
        self.outline_session.borrow_mut().update(&preprocessed)
    }

    pub fn outline_cache_stats(&self) -> frontend::OutlineStats {
        self.outline_session.borrow().stats()
    }

    pub fn parse(&self) -> &AstFile {
        parse_live(&self.db, self.project)
    }

    pub fn index(&self) -> &Result<DeclarationIndex, Vec<String>> {
        index_live(&self.db, self.project)
    }
}

/// The cache is local to the codebase and safe to share across processes or
/// worktrees because each entry checks exact source and macro inputs.
pub fn preprocess_cache_path(project: &Path) -> PathBuf {
    let absolute = std::fs::canonicalize(project).unwrap_or_else(|_| {
        if project.is_absolute() {
            project.to_path_buf()
        } else {
            std::env::current_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .join(project)
        }
    });
    let directory = absolute.parent().unwrap_or_else(|| Path::new("."));
    let prefix = std::process::Command::new("git")
        .args(["rev-parse", "--show-prefix"])
        .current_dir(directory)
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .unwrap_or_default();
    let name = absolute.file_name().unwrap_or_default().to_string_lossy();
    let identity = format!("{}{}", prefix.trim(), name)
        .replace('\\', "/")
        .to_ascii_lowercase();
    let digest = format!("{:x}", Sha256::digest(identity.as_bytes()));
    lower_cache::project_cache_root(&absolute)
        .join("preprocess-v3")
        .join(format!("{digest}.json"))
}

impl CompilerSession {
    pub fn update_file(&mut self, path: PathBuf, text: String) -> bool {
        if let Some(source) = self.files.get(&path).copied() {
            if source.text(&self.db) == text {
                return false;
            }
            source.set_text(&mut self.db).to(text);
        } else {
            let source = SourceFile::new(&self.db, path.clone(), text);
            self.files.insert(path, source);
        }
        true
    }

    pub fn remove_file(&mut self, path: &PathBuf) -> bool {
        // Salsa inputs are retained by a database; dropping the registry entry
        // makes the file unreachable to project queries in future revisions.
        self.files.remove(path).is_some()
    }

    pub fn parse(&self, path: &PathBuf) -> Option<&AstFile> {
        self.files
            .get(path)
            .copied()
            .map(|file| parse_source(&self.db, file))
    }

    pub fn lex(&self, path: &PathBuf) -> Option<&Lexed> {
        self.files
            .get(path)
            .copied()
            .map(|file| lex_source(&self.db, file))
    }

    pub fn database(&self) -> &Database {
        &self.db
    }
}

/// Collects the include closure once from disk and freezes exact contents for
/// a query revision. The caller must refresh this snapshot after file events.
pub fn project_snapshot_from_disk(
    db: &Database,
    root: PathBuf,
    defines: BTreeMap<String, String>,
) -> ProjectSnapshot {
    let discovery = dm_preprocess::preprocess_project(&root, &dm_preprocess::FileSystem, &defines);
    let sources = discovery
        .dependencies
        .iter()
        .filter_map(|path| {
            dm_preprocess::read_source_file(path)
                .ok()
                .map(|text| (path.clone(), text))
        })
        .collect();
    ProjectSnapshot::new(db, root, sources, defines)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lexical_failure_is_reported_at_authored_include_location() {
        let root = std::env::current_dir().unwrap().join("diagnostic-fixture");
        let project = PreprocessedProject {
            text: "/proc/broken()\n    return \"unterminated\n".into(),
            origins: vec![
                dm_preprocess::Origin { output_line: 1, path: root.join("code/broken.dm").into(), source_line: 17 },
                dm_preprocess::Origin { output_line: 2, path: root.join("code/broken.dm").into(), source_line: 18 },
            ],
            ..Default::default()
        };
        let errors = authored_syntax_errors(&project, &root);
        assert!(!errors.is_empty());
        assert!(errors.iter().all(|error| error.starts_with("code/broken.dm:18: error:")), "{errors:?}");
    }

    #[test]
    fn unchanged_content_keeps_revision_stable_and_edit_updates_parse() {
        let mut session = CompilerSession::default();
        let file = PathBuf::from("unit.dm");
        assert!(session.update_file(file.clone(), "/obj/item\n".into()));
        let initial = session.parse(&file).unwrap().clone();
        assert!(!session.update_file(file.clone(), "/obj/item\n".into()));
        assert_eq!(&initial, session.parse(&file).unwrap());
        assert!(session.update_file(file.clone(), "/obj/tool\n".into()));
        assert_ne!(&initial, session.parse(&file).unwrap());
    }

    #[test]
    fn distinct_files_have_distinct_query_keys() {
        let mut session = CompilerSession::default();
        let a = PathBuf::from("a.dm");
        let b = PathBuf::from("b.dm");
        session.update_file(a.clone(), "/obj/a\n".into());
        session.update_file(b.clone(), "/obj/b\n".into());
        let before = session.parse(&b).unwrap().clone();
        session.update_file(a, "/obj/new_a\n".into());
        assert_eq!(&before, session.parse(&b).unwrap());
    }

    #[test]
    fn project_query_tracks_macro_change() {
        let db = Database::default();
        let root = PathBuf::from("fixture.dme");
        let file = PathBuf::from("part.dm");
        let sources = BTreeMap::from([
            (
                root.clone(),
                "#define KIND obj\n#include \"part.dm\"\n".into(),
            ),
            (file.clone(), "/KIND/example\n".into()),
        ]);
        let snapshot = ProjectSnapshot::new(&db, root, sources, BTreeMap::new());
        assert!(preprocess_snapshot(&db, snapshot)
            .text
            .contains("/obj/example"));
        assert!(!parse_project(&db, snapshot).items.is_empty());
        assert!(index_project(&db, snapshot).is_ok());
    }

    #[test]
    fn project_session_edits_restore_diagnostics() {
        let root = PathBuf::from("fixture.dme");
        let file = PathBuf::from("part.dm");
        let mut session = ProjectSession::new(
            root.clone(),
            BTreeMap::from([
                (root, "#include \"part.dm\"\n".into()),
                (file.clone(), "/obj/example\n".into()),
            ]),
            BTreeMap::new(),
        );
        assert!(session.preprocess().diagnostics.is_empty());
        session.remove_source(&file);
        assert!(!session.preprocess().diagnostics.is_empty());
        session.update_source(file, "/obj/example\n".into());
        assert!(session.preprocess().diagnostics.is_empty());
    }

    #[test]
    fn project_outline_reuses_syntax_and_invalidates_macro_dependents() {
        let root = PathBuf::from("fixture.dme");
        let file = PathBuf::from("part.dm");
        let mut session = ProjectSession::new(
            root.clone(),
            BTreeMap::from([
                (
                    root.clone(),
                    "#define VALUE 1\n#include \"part.dm\"\n".into(),
                ),
                (file, "/proc/example()\n\treturn VALUE\n".into()),
            ]),
            BTreeMap::new(),
        );
        let first = session.source_outline().unwrap();
        let repeated = session.source_outline().unwrap();
        assert_eq!(first.abi_digest, repeated.abi_digest);
        assert_eq!(session.outline_cache_stats().parsed_chunks, 0);
        assert!(session.outline_cache_stats().memory_hits > 0);
        session.update_source(root, "#define VALUE 2\n#include \"part.dm\"\n".into());
        let changed = session.source_outline().unwrap();
        assert_eq!(changed.abi_digest, first.abi_digest);
        assert_ne!(
            changed.procedures.values().next().unwrap().digest,
            first.procedures.values().next().unwrap().digest
        );
        assert!(changed
            .procedures
            .values()
            .next()
            .unwrap()
            .source
            .contains("return 2"));
    }

    #[test]
    fn incremental_project_reuses_unedited_includes() {
        let root = PathBuf::from("fixture.dme");
        let a = PathBuf::from("a.dm");
        let b = PathBuf::from("b.dm");
        let mut session = ProjectSession::new(
            root.clone(),
            BTreeMap::from([
                (root, "#include \"a.dm\"\n#include \"b.dm\"\n".into()),
                (a, "/obj/a\n".into()),
                (b.clone(), "/obj/b\n".into()),
            ]),
            BTreeMap::new(),
        );
        let first = session.preprocess_incremental();
        assert_eq!(session.preprocess_cache_stats(), (0, 2));
        assert_eq!(session.preprocess_incremental(), first);
        assert_eq!(session.preprocess_cache_stats(), (0, 2));
        session.update_source(b, "/obj/new_b\n".into());
        let changed = session.preprocess_incremental();
        assert!(changed.text.contains("/obj/new_b"));
        assert_eq!(session.preprocess_cache_stats(), (1, 3));
    }

    #[test]
    fn fixture_dme_uses_project_cache_directory() {
        let project =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/simple.dme");
        let cache = preprocess_cache_path(&project);
        assert!(cache.starts_with(lower_cache::project_cache_root(&project).join("preprocess-v3")));
        assert_eq!(
            cache.extension().and_then(|extension| extension.to_str()),
            Some("json")
        );
        let relative = Path::new("../../fixtures/native_compiler/simple.dme");
        assert_eq!(cache, preprocess_cache_path(relative));
        assert_eq!(
            lower_cache::project_cache_root(&project),
            lower_cache::project_cache_root(relative)
        );
    }

    #[test]
    fn preprocess_cache_is_shared_per_dme_across_git_worktrees() {
        use std::process::Command;
        use std::sync::atomic::{AtomicU64, Ordering};
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let temp = std::env::temp_dir().join(format!(
            "dm-preprocess-worktree-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let primary = temp.join("primary");
        let secondary = temp.join("secondary");
        std::fs::create_dir_all(&primary).unwrap();
        let git = |args: &[&str]| {
            let status = Command::new("git")
                .current_dir(&primary)
                .args(args)
                .status()
                .unwrap();
            assert!(status.success(), "git {args:?}");
        };
        git(&["init", "-q"]);
        std::fs::write(primary.join("game.dme"), "#include \"leaf.dm\"\n").unwrap();
        std::fs::write(primary.join("fixture.dme"), "#include \"leaf.dm\"\n").unwrap();
        std::fs::write(primary.join("leaf.dm"), "/obj/test\n").unwrap();
        git(&["add", "."]);
        git(&[
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "-qm",
            "initial",
        ]);
        git(&[
            "worktree",
            "add",
            "--quiet",
            "--detach",
            secondary.to_str().unwrap(),
            "HEAD",
        ]);

        let game = preprocess_cache_path(&primary.join("game.dme"));
        let other_worktree = preprocess_cache_path(&secondary.join("game.dme"));
        let fixture = preprocess_cache_path(&primary.join("fixture.dme"));
        assert_eq!(game, other_worktree);
        assert_ne!(game, fixture);
        std::fs::create_dir_all(game.parent().unwrap()).unwrap();
        std::fs::write(&game, b"game cache").unwrap();
        std::fs::write(&fixture, b"fixture cache").unwrap();
        assert_eq!(std::fs::read(&game).unwrap(), b"game cache");
        std::fs::remove_dir_all(&temp).unwrap();
    }

    #[test]
    fn second_disk_session_reuses_persisted_include() {
        let project =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/simple.dme");
        let first = ProjectSession::from_disk(project.clone(), BTreeMap::new());
        let expected = first.preprocess_incremental();
        let second = ProjectSession::from_disk(project, BTreeMap::new());
        assert_eq!(second.preprocess_incremental(), expected);
        assert!(second.preprocess_cache_stats().0 >= 1);
    }
}

/// Variable selector words and nullable string fields reserve these string IDs.
pub(crate) fn native_reserved_string_id(id: u32) -> bool {
    (0xffcd..=0xfff1).contains(&id) || id == 0xffff
}

/// Object table widths are a property of the final image, including maps.
pub(crate) fn promote_object_ids(dmb: &mut byond_dmb::dmb::Dmb) {
    if [
        dmb.classes.len(),
        dmb.mobs.len(),
        dmb.strings.len(),
        dmb.lists.len(),
        dmb.procs.len(),
        dmb.variables.len(),
        dmb.proc_references.len(),
        dmb.instances.len(),
        dmb.map_objects.len(),
        dmb.resources.len(),
    ]
    .into_iter()
    .any(|count| count > u16::MAX as usize)
    {
        dmb.header.flags |= 0x4000_0000;
    }
}

pub(crate) fn reserve_class_sentinel(dmb: &mut byond_dmb::dmb::Dmb) {
    if dmb.classes.len() == 0xffff {
        dmb.classes.push(byond_dmb::dmb::Class {
            initial_ids: [0xffff; 6],
            direction: 2,
            interface: 1,
            extended_interface: None,
            text: 0xffff,
            maptext: 0xffff,
            maptext_geometry: [0; 4],
            suffix: 0xffff,
            flags: 0,
            lists_and_procs: [0xffff; 6],
            layer_bits: (-1.0f32).to_bits(),
            transform_flag: 0,
            transform: None,
            color_matrix_flag: 0,
            color_matrix: None,
            overrides: 0xffff,
        });
    }
}
pub(crate) fn reserve_proc_sentinel(dmb: &mut byond_dmb::dmb::Dmb) {
    if dmb.procs.len() == 0xffff {
        dmb.procs.push(byond_dmb::dmb::Proc {
            strings: [0xffff; 4],
            source_parameter: 255,
            source_kind: 0,
            flags: 4,
            extended_flags: None,
            code_locals_args: [0xffff; 3],
        });
    }
}
