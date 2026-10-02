//! Prepared input packs use the same CAS and transactional metadata as builds.
//! Publish bytes before the mutable head; concurrent writers may publish either
//! fully verified revision. No database/Salsa IDs are serialized.
use crate::{input_proof::InputProof, prepared_project::*, ContentStore};
use dm_preprocess::{Diagnostic, Macro, Origin, PreprocessedProject, Unit};
use dm_syntax::Span;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::PathBuf;
use std::sync::Arc;

const VERSION: u32 = 1;
const MAX_PACK: usize = 128 * 1024 * 1024;
const MAX_MANIFEST: usize = 64 * 1024 * 1024;

#[derive(Serialize, Deserialize)]
struct Source {
    path: usize,
    start: usize,
    end: usize,
    digest: [u8; 32],
    stamp: Option<dm_host::file_stamp::FileStamp>,
}
#[derive(Serialize, Deserialize)]
struct Manifest {
    version: u32,
    context: String,
    pack: String,
    expanded_end: usize,
    project_digest: String,
    expanded_digest: String,
    revision: String,
    paths: Vec<PathBuf>,
    sources: Vec<Source>,
    origins: Vec<(usize, usize, usize)>,
    units: Vec<(usize, usize, usize, usize)>,
    unit_digests: Vec<[u8; 32]>,
    dependencies: Vec<usize>,
    maps: Vec<usize>,
    skins: Vec<usize>,
    file_dirs: Vec<usize>,
    diagnostics: Vec<Diagnostic>,
    macros: BTreeMap<String, Macro>,
    proof: Option<InputProof>,
}
#[derive(Serialize, Deserialize)]
struct Head {
    version: u32,
    context: String,
    manifest: String,
}

pub(super) fn save(store: &ContentStore, snapshot: &PreparedProject) -> io::Result<()> {
    let mut paths = BTreeMap::new();
    fn path_id(paths: &mut BTreeMap<PathBuf, usize>, path: &std::path::Path) -> usize {
        let next = paths.len();
        *paths.entry(path.to_path_buf()).or_insert(next)
    }
    let project = &snapshot.project;
    let mut parts = vec![project.text.as_bytes()];
    let mut end = project.text.len();
    let mut sources = Vec::with_capacity(snapshot.sources.len());
    for (path, source) in snapshot.sources.iter() {
        let start = end;
        end = end
            .checked_add(source.text.len())
            .ok_or_else(|| io::Error::other("prepared input size overflow"))?;
        if end > MAX_PACK {
            return Ok(());
        }
        parts.push(source.text.as_bytes());
        sources.push(Source {
            path: path_id(&mut paths, path),
            start,
            end,
            digest: source.digest,
            stamp: source.stamp.clone(),
        });
    }
    let origins = project
        .origins
        .iter()
        .map(|origin| {
            (
                origin.output_line,
                path_id(&mut paths, &origin.path),
                origin.source_line,
            )
        })
        .collect();
    let units = project
        .units
        .iter()
        .map(|unit| {
            (
                path_id(&mut paths, &unit.path),
                unit.output_span.start,
                unit.output_span.end,
                unit.source_lines,
            )
        })
        .collect();
    let dependencies = project
        .dependencies
        .iter()
        .map(|path| path_id(&mut paths, path))
        .collect();
    let maps = project
        .map_includes
        .iter()
        .map(|path| path_id(&mut paths, path))
        .collect();
    let skins = project
        .skin_includes
        .iter()
        .map(|path| path_id(&mut paths, path))
        .collect();
    let file_dirs = project
        .file_dirs
        .iter()
        .map(|path| path_id(&mut paths, path))
        .collect();
    let mut ordered_paths = vec![PathBuf::new(); paths.len()];
    for (path, index) in paths {
        ordered_paths[index] = path;
    }
    let pack = store.put_parts("prepared-input-pack-v1", &parts)?;
    let manifest = Manifest {
        version: VERSION,
        context: snapshot.context.clone(),
        pack,
        expanded_end: project.text.len(),
        project_digest: snapshot.project_digest.clone(),
        expanded_digest: snapshot.expanded_digest.clone(),
        revision: snapshot.revision.clone(),
        paths: ordered_paths,
        sources,
        origins,
        units,
        unit_digests: project.unit_digests.clone(),
        dependencies,
        maps,
        skins,
        file_dirs,
        diagnostics: project.diagnostics.clone(),
        macros: project.final_macros.clone(),
        proof: snapshot.proof.clone(),
    };
    let bytes = serde_json::to_vec(&manifest).map_err(io::Error::other)?;
    if bytes.len() > MAX_MANIFEST {
        return Ok(());
    }
    let digest = store.put("prepared-input-manifest-v1", &bytes)?;
    let head = Head {
        version: VERSION,
        context: snapshot.context.clone(),
        manifest: digest,
    };
    store
        .metadata
        .put_many(
            vec![(
                dm_store::Key::new("prepared-project-head-v1", &snapshot.context),
                serde_json::to_vec(&head).map_err(io::Error::other)?,
            )],
            None,
        )
        .map(|_| ())
}

pub(super) fn load(store: &ContentStore, context: &str) -> io::Result<Option<PreparedProject>> {
    let read = store.metadata.read_many(
        &[dm_store::Key::new("prepared-project-head-v1", context)],
        None,
    )?;
    let Some(bytes) = &read.values[0] else {
        return Ok(None);
    };
    let head: Head = serde_json::from_slice(bytes).map_err(io::Error::other)?;
    if head.version != VERSION || head.context != context {
        return Ok(None);
    }
    let manifest: Manifest = serde_json::from_slice(&store.get_bounded(
        "prepared-input-manifest-v1",
        &head.manifest,
        MAX_MANIFEST,
    )?)
    .map_err(io::Error::other)?;
    if manifest.version != VERSION
        || manifest.context != context
        || manifest.paths.len() > 64_000
        || manifest.sources.len() > 64_000
        || manifest.origins.len() > 4_000_000
        || manifest.units.len() > 128_000
        || manifest.units.len() != manifest.unit_digests.len()
    {
        return Ok(None);
    }
    let pack = store.get_bounded("prepared-input-pack-v1", &manifest.pack, MAX_PACK)?;
    let text = std::str::from_utf8(&pack).map_err(io::Error::other)?;
    let expanded = text
        .get(..manifest.expanded_end)
        .ok_or_else(|| io::Error::other("invalid prepared expansion boundary"))?;
    let paths: Vec<Arc<PathBuf>> = manifest.paths.into_iter().map(Arc::new).collect();
    let path = |index: usize| {
        paths
            .get(index)
            .cloned()
            .ok_or_else(|| io::Error::other("invalid prepared path index"))
    };
    let mut sources = BTreeMap::new();
    let mut cursor = manifest.expanded_end;
    for source in &manifest.sources {
        if source.start != cursor {
            return Err(io::Error::other("invalid prepared source order"));
        }
        cursor = source.end;
    }
    let loaded = dm_work::map_ordered(
        &manifest.sources,
        dm_work::WorkLimits::configured(),
        |source| {
            source
                .end
                .saturating_sub(source.start)
                .saturating_mul(2)
                .saturating_add(8192)
        },
        |source| {
            let content = text
                .get(source.start..source.end)
                .ok_or_else(|| io::Error::other("invalid prepared source boundary"))?;
            if <[u8; 32]>::from(sha2::Sha256::digest(content.as_bytes())) != source.digest {
                return Err(io::Error::other("prepared source digest mismatch"));
            }
            Ok((
                (*path(source.path)?).clone(),
                PreparedSource {
                    text: Arc::from(content),
                    digest: source.digest,
                    stamp: source.stamp.clone(),
                },
            ))
        },
    )
    .map_err(|error| match error {
        dm_work::WorkError::Panic { job, message } => {
            panic!("prepared input worker {job}: {message}")
        }
        other => io::Error::other(format!("prepared input work limits: {other:?}")),
    })?;
    for source in loaded {
        let (path, source) = source?;
        if sources.insert(path, source).is_some() {
            return Err(io::Error::other("duplicate prepared source"));
        }
    }
    if cursor != text.len() {
        return Err(io::Error::other("trailing prepared input bytes"));
    }
    let origins = manifest
        .origins
        .into_iter()
        .map(|(output_line, index, source_line)| {
            Ok(Origin {
                output_line,
                path: path(index)?,
                source_line,
            })
        })
        .collect::<io::Result<_>>()?;
    let units = manifest
        .units
        .into_iter()
        .map(|(index, start, end, source_lines)| {
            if start > end
                || end > expanded.len()
                || !expanded.is_char_boundary(start)
                || !expanded.is_char_boundary(end)
            {
                return Err(io::Error::other("invalid prepared unit span"));
            }
            Ok(Unit {
                path: (*path(index)?).clone(),
                output_span: Span::new(start, end),
                source_lines,
            })
        })
        .collect::<io::Result<_>>()?;
    let resolve = |indices: Vec<usize>| {
        indices
            .into_iter()
            .map(|index| path(index).map(|path| (*path).clone()))
            .collect::<io::Result<Vec<_>>>()
    };
    let project = PreprocessedProject {
        text: expanded.to_owned(),
        origins,
        units,
        unit_digests: manifest.unit_digests,
        dependencies: resolve(manifest.dependencies)?
            .into_iter()
            .collect::<BTreeSet<_>>(),
        map_includes: resolve(manifest.maps)?,
        skin_includes: resolve(manifest.skins)?,
        file_dirs: resolve(manifest.file_dirs)?,
        diagnostics: manifest.diagnostics,
        final_macros: manifest.macros,
    };
    Ok(Some(PreparedProject {
        project: Arc::new(project),
        sources: Arc::new(sources),
        project_digest: manifest.project_digest,
        expanded_digest: manifest.expanded_digest,
        revision: manifest.revision,
        context: context.to_owned(),
        proof: manifest.proof,
        changes: PreparationChanges::default(),
        stats: PreparationStats {
            disk_restored: true,
            ..Default::default()
        },
    }))
}
use sha2::Digest;
