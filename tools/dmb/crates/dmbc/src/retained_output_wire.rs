//! The source half of a retained output as stored data (see `crate::variant_spill`).
//!
//! What a patch compares or reads of the retained build is kept: the body roster with its digests, the rows' source lines, the
//! unit link footprints, the non-text input record, the archive identity, the warnings and the answer-table version. What only a
//! build of this process holds is not: the expanded program text (so a restored output cannot admit a numeric default edit) and
//! each unit's symbolic record (a patch compares only its footprint). Restoring never fabricates a proof: every comparison a
//! patch makes against the retained build is made against the stored values exactly as against the live ones.
use super::*;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize)]
struct BodyParts {
    digest: u128,
    text: u128,
    guarded: bool,
    path: u32,
    file: u32,
    line: u64,
    lines: u64,
}

#[derive(Serialize, Deserialize)]
struct UnitParts {
    owner: dm_ir::SymbolId,
    name: dm_ir::SymbolId,
    verb: bool,
    occurrence: u32,
    footprint: Vec<(u8, u128)>,
    modified: bool,
}

#[derive(Serialize, Deserialize)]
struct WarningParts {
    source_ordinal: u64,
    code: dm_ir::WarningCode,
    name: Option<String>,
    path: String,
    line: Option<u64>,
}

/// A retained output's source half, in stored form.
#[derive(Serialize, Deserialize)]
pub(crate) struct BaseParts {
    text_key: u128,
    positions: u128,
    tree_identity: u128,
    /// Semantic paths and files, interned: bodies and rows name them by position.
    paths: Vec<String>,
    files: Vec<PathBuf>,
    bodies: Vec<BodyParts>,
    skeleton: Vec<(u32, u64)>,
    body_rows: Vec<(u64, Vec<(u32, u64)>)>,
    units: Vec<UnitParts>,
    inputs: crate::input_snapshot::InputSnapshot,
    archive: crate::publish::ResourceIdentity,
    prefix: Vec<WarningParts>,
    unit_warnings: Vec<(dm_ir::SymbolId, dm_ir::SymbolId, bool, u32, Vec<WarningParts>)>,
    answers: Option<u128>,
    answers_context: Option<u128>,
    facts: Option<crate::query_db::AnswerFacts>,
}

fn unit_key(identity: UnitIdentity) -> (dm_ir::SymbolId, dm_ir::SymbolId, bool, u32) {
    (
        identity.owner,
        identity.name,
        matches!(identity.namespace, crate::lowering::Namespace::Verb),
        identity.occurrence,
    )
}
fn identity_of(owner: dm_ir::SymbolId, name: dm_ir::SymbolId, verb: bool, occurrence: u32) -> UnitIdentity {
    UnitIdentity {
        owner,
        name,
        namespace: if verb {
            crate::lowering::Namespace::Verb
        } else {
            crate::lowering::Namespace::Proc
        },
        occurrence,
    }
}

fn warning_parts(warning: &InitializerWarning) -> WarningParts {
    WarningParts {
        source_ordinal: warning.source_ordinal as u64,
        code: warning.code,
        name: warning.name.clone(),
        path: warning.location.semantic_path.to_string(),
        line: warning.location.line.map(|line| line as u64),
    }
}
fn warning_of(parts: WarningParts) -> InitializerWarning {
    InitializerWarning {
        source_ordinal: parts.source_ordinal as usize,
        code: parts.code,
        name: parts.name,
        location: crate::initializer_policy::warnings::WarningLocation {
            semantic_path: Arc::from(parts.path),
            line: parts.line.map(|line| line as usize),
        },
    }
}

/// Positions in `names` by value, in first-seen order.
struct Interner<T: Clone + Eq + std::hash::Hash> {
    at: HashMap<T, u32>,
    items: Vec<T>,
}
impl<T: Clone + Eq + std::hash::Hash> Interner<T> {
    fn new() -> Self {
        Self {
            at: HashMap::new(),
            items: Vec::new(),
        }
    }
    fn id(&mut self, item: &T) -> u32 {
        if let Some(&id) = self.at.get(item) {
            return id;
        }
        let id = self.items.len() as u32;
        self.at.insert(item.clone(), id);
        self.items.push(item.clone());
        id
    }
}

impl OutputBase {
    /// The stored form of this output's source half. `None` when something cannot be stored (a layout of a restored output is
    /// stored as it is; a unit footprint part with a name this build does not know is refused).
    pub(crate) fn to_parts(&self, workers: usize) -> Option<BaseParts> {
        let shape = &self.shape;
        let mut paths: Interner<Arc<str>> = Interner::new();
        let mut files: Interner<Arc<PathBuf>> = Interner::new();
        let bodies: Vec<BodyParts> = shape
            .bodies
            .iter()
            .map(|body| BodyParts {
                digest: body.digest,
                text: body.text,
                guarded: body.guarded,
                path: paths.id(&body.path),
                file: files.id(&body.file),
                line: body.line as u64,
                lines: body.lines as u64,
            })
            .collect();
        let rows = shape.layout.rows();
        let mut row_ids = |rows: &[(Arc<str>, usize)]| -> Vec<(u32, u64)> {
            rows.iter().map(|(path, line)| (paths.id(path), *line as u64)).collect()
        };
        let skeleton = row_ids(&rows.skeleton);
        let mut body_rows: Vec<(u64, Vec<(u32, u64)>)> = rows
            .bodies
            .iter()
            .map(|(which, rows)| (*which as u64, row_ids(rows)))
            .collect();
        body_rows.sort_unstable_by_key(|(which, _)| *which);
        // Footprints of units a build of this process holds are computed now (the live records hold what they need).
        let pool = rayon::ThreadPoolBuilder::new().num_threads(workers.max(1)).build().ok()?;
        let entries: Vec<(&UnitIdentity, &UnitBase)> = self.units.iter().collect();
        let units: Option<Vec<UnitParts>> = pool.install(|| {
            use rayon::prelude::*;
            entries
                .par_iter()
                .with_min_len(512)
                .map(|(identity, unit)| {
                    let footprint: Option<Vec<(u8, u128)>> = unit
                        .footprint()
                        .into_iter()
                        .map(|(name, digest)| {
                            crate::symbolic::FOOTPRINT_NAMES
                                .iter()
                                .position(|known| *known == name)
                                .map(|at| (at as u8, digest))
                        })
                        .collect();
                    let (owner, name, verb, occurrence) = unit_key(**identity);
                    Some(UnitParts {
                        owner,
                        name,
                        verb,
                        occurrence,
                        footprint: footprint?,
                        modified: unit.modified(),
                    })
                })
                .collect()
        });
        Some(BaseParts {
            text_key: shape.text_key,
            positions: shape.positions,
            tree_identity: shape.tree_identity,
            paths: paths.items.iter().map(|path| path.to_string()).collect(),
            files: files.items.iter().map(|file| file.as_ref().clone()).collect(),
            bodies,
            skeleton,
            body_rows,
            units: units?,
            inputs: (*self.inputs).clone(),
            archive: self.archive,
            prefix: self.warnings.prefix.iter().map(warning_parts).collect(),
            unit_warnings: self
                .warnings
                .units
                .iter()
                .map(|(identity, warnings)| {
                    let (owner, name, verb, occurrence) = unit_key(*identity);
                    (owner, name, verb, occurrence, warnings.iter().map(warning_parts).collect())
                })
                .collect(),
            answers: self.answers,
            answers_context: self.answers_context,
            facts: self.facts.as_deref().cloned(),
        })
    }

    /// The output a stored source half describes, for the image whose digest is `dmb_hash`. The answer marks are not stored:
    /// an output restored from disk is admitted on an equal answer-table version or not at all.
    pub(crate) fn from_parts(parts: BaseParts, dmb_hash: u128) -> Option<Self> {
        let paths: Vec<Arc<str>> = parts.paths.iter().map(|path| Arc::from(path.as_str())).collect();
        let files: Vec<Arc<PathBuf>> = parts.files.into_iter().map(Arc::new).collect();
        let path = |id: u32| paths.get(id as usize).cloned();
        let bodies = parts
            .bodies
            .iter()
            .map(|body| {
                Some(BodyShape {
                    digest: body.digest,
                    text: body.text,
                    guarded: body.guarded,
                    path: path(body.path)?,
                    file: Arc::clone(files.get(body.file as usize)?),
                    line: usize::try_from(body.line).ok()?,
                    lines: usize::try_from(body.lines).ok()?,
                })
            })
            .collect::<Option<Vec<_>>>()?;
        let row_lines = |rows: &[(u32, u64)]| -> Option<Vec<(Arc<str>, usize)>> {
            rows.iter()
                .map(|(id, line)| Some((path(*id)?, usize::try_from(*line).ok()?)))
                .collect()
        };
        let rows = RowLines {
            skeleton: row_lines(&parts.skeleton)?,
            bodies: parts
                .body_rows
                .iter()
                .map(|(which, rows)| Some((usize::try_from(*which).ok()?, row_lines(rows)?)))
                .collect::<Option<HashMap<_, _>>>()?,
        };
        if rows.bodies.keys().any(|which| *which >= bodies.len()) {
            return None;
        }
        let shape = SourceShape {
            text_key: parts.text_key,
            positions: parts.positions,
            bodies,
            layout: Layout::Rows(rows),
            tree_identity: parts.tree_identity,
        };
        let mut units = BTreeMap::new();
        for unit in parts.units {
            let footprint = unit
                .footprint
                .iter()
                .map(|(at, digest)| Some((*crate::symbolic::FOOTPRINT_NAMES.get(*at as usize)?, *digest)))
                .collect::<Option<Vec<_>>>()?;
            let identity = identity_of(unit.owner, unit.name, unit.verb, unit.occurrence);
            let digest = UnitDigest {
                footprint,
                modified: unit.modified,
            };
            if units.insert(identity, UnitBase::Digest(digest)).is_some() {
                return None;
            }
        }
        let warnings = OutputWarnings {
            prefix: parts.prefix.into_iter().map(warning_of).collect(),
            units: parts
                .unit_warnings
                .into_iter()
                .map(|(owner, name, verb, occurrence, warnings)| {
                    (
                        identity_of(owner, name, verb, occurrence),
                        warnings.into_iter().map(warning_of).collect(),
                    )
                })
                .collect(),
        };
        // Facts that do not hash to the stored version and context are not this output's: it is then admitted on an equal
        // answer-table version or not at all.
        let facts = parts
            .facts
            .filter(|facts| Some(facts.version()) == parts.answers && Some(facts.context()) == parts.answers_context)
            .map(Arc::new);
        Some(Self {
            shape: Arc::new(shape),
            units: Arc::new(units),
            inputs: Arc::new(parts.inputs),
            archive: parts.archive,
            warnings: Arc::new(warnings),
            answers: parts.answers,
            answers_context: parts.answers_context,
            marks: None,
            facts,
            restored: true,
            dmb_hash,
        })
    }
}
