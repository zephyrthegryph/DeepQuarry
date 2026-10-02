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

const VERSION: u32 = 2;
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
    pack: Vec<(String, usize)>,
    expanded_end: usize,
    project_digest: String,
    expanded_digest: String,
    revision: String,
    paths: Vec<PathBuf>,
    sources: Vec<Source>,
    origins: String,
    origin_count: usize,
    units: Vec<(usize, usize, usize, usize)>,
    unit_digests: Vec<[u8; 32]>,
    dependencies: Vec<usize>,
    maps: Vec<usize>,
    skins: Vec<usize>,
    file_dirs: Vec<usize>,
    diagnostics: Vec<Diagnostic>,
    macros: BTreeMap<String, Macro>,
    macro_names: BTreeSet<String>,
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
    // Previously every body edit published expanded text plus every authored
    // source as one new CAS blob. Keep immutable expansion pieces and bounded
    // source groups so a changed generation writes only changed chunks.
    let previous = load_manifest(store, &snapshot.context).ok().flatten();
    let known: BTreeSet<_> = previous
        .as_ref()
        .into_iter()
        .flat_map(|manifest| {
            manifest
                .pack
                .iter()
                .map(|(digest, _)| digest.clone())
                .chain(std::iter::once(manifest.origins.clone()))
        })
        .collect();
    let mut pack = Vec::new();
    for piece in &snapshot.expansion.segments {
        let digest = format!("{:x}", Sha256::digest(piece.text.as_bytes()));
        if !known.contains(&digest) {
            store.put("prepared-input-chunk-v2", piece.text.as_bytes())?;
        }
        pack.push((digest, piece.text.len()));
    }
    let mut parts = Vec::new();
    let mut source_group_bytes = 0;
    let mut end = snapshot.expansion.bytes;
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
        source_group_bytes += source.text.len();
        if source_group_bytes >= 1024 * 1024 {
            publish_group(store, &mut pack, &mut parts, &known)?;
            source_group_bytes = 0;
        }
        sources.push(Source {
            path: path_id(&mut paths, path),
            start,
            end,
            digest: source.digest,
            stamp: source.stamp.clone(),
        });
    }
    publish_group(store, &mut pack, &mut parts, &known)?;
    let mut origin_bytes = Vec::with_capacity(project.origins.len() * 5);
    for origin in &project.origins {
        write_varint(&mut origin_bytes, origin.output_line);
        write_varint(&mut origin_bytes, path_id(&mut paths, &origin.path));
        write_varint(&mut origin_bytes, origin.source_line);
    }
    let origins = format!("{:x}", Sha256::digest(&origin_bytes));
    if !known.contains(&origins) {
        store.put("prepared-input-chunk-v2", &origin_bytes)?;
    }
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
    let manifest = Manifest {
        version: VERSION,
        context: snapshot.context.clone(),
        pack,
        expanded_end: snapshot.expansion.bytes,
        project_digest: snapshot.project_digest.clone(),
        expanded_digest: snapshot.expanded_digest.clone(),
        revision: snapshot.revision.clone(),
        paths: ordered_paths,
        sources,
        origins,
        origin_count: project.origins.len(),
        units,
        unit_digests: project.unit_digests.clone(),
        dependencies,
        maps,
        skins,
        file_dirs,
        diagnostics: project.diagnostics.clone(),
        macros: project.final_macros.clone(),
        macro_names: snapshot.macro_names.as_ref().clone(),
        proof: snapshot.proof.clone(),
    };
    let bytes = serde_json::to_vec(&manifest).map_err(io::Error::other)?;
    if bytes.len() > MAX_MANIFEST {
        return Ok(());
    }
    let digest = store.put("prepared-input-manifest-v2", &bytes)?;
    let head = Head {
        version: VERSION,
        context: snapshot.context.clone(),
        manifest: digest,
    };
    store
        .metadata
        .put_many(
            vec![(
                dm_store::Key::new("prepared-project-head-v2", &snapshot.context),
                serde_json::to_vec(&head).map_err(io::Error::other)?,
            )],
            None,
        )
        .map(|_| ())
}

fn load_manifest(store: &ContentStore, context: &str) -> io::Result<Option<Manifest>> {
    let read = store.metadata.read_many(
        &[dm_store::Key::new("prepared-project-head-v2", context)],
        None,
    )?;
    let Some(bytes) = &read.values[0] else {
        return Ok(None);
    };
    let head: Head = serde_json::from_slice(bytes).map_err(io::Error::other)?;
    if head.version != VERSION || head.context != context {
        return Ok(None);
    }
    let manifest = serde_json::from_slice(&store.get_bounded(
        "prepared-input-manifest-v2",
        &head.manifest,
        MAX_MANIFEST,
    )?)
    .map_err(io::Error::other)?;
    Ok(Some(manifest))
}

pub(super) fn load(store: &ContentStore, context: &str) -> io::Result<Option<PreparedProject>> {
    let Some(manifest) = load_manifest(store, context)? else {
        return Ok(None);
    };
    if manifest.version != VERSION
        || manifest.context != context
        || manifest.paths.len() > 64_000
        || manifest.sources.len() > 64_000
        || manifest.origin_count > 4_000_000
        || manifest.units.len() > 128_000
        || manifest.units.len() != manifest.unit_digests.len()
    {
        return Ok(None);
    }
    let total = manifest
        .pack
        .iter()
        .try_fold(0usize, |total, (_, len)| total.checked_add(*len))
        .filter(|total| *total <= MAX_PACK)
        .ok_or_else(|| io::Error::other("prepared chunk pack exceeds limit"))?;
    if manifest.pack.len() > 16_384 {
        return Err(io::Error::other("too many prepared chunks"));
    }
    let mut pack = Vec::with_capacity(total.saturating_sub(manifest.expanded_end));
    let mut position = 0;
    let mut expansion_segments = Vec::new();
    for (digest, len) in &manifest.pack {
        let bytes = store.get_bounded("prepared-input-chunk-v2", digest, *len)?;
        if bytes.len() != *len {
            return Err(io::Error::other("prepared chunk length mismatch"));
        }
        if position < manifest.expanded_end {
            if position + bytes.len() > manifest.expanded_end {
                return Err(io::Error::other(
                    "prepared chunk crosses expansion boundary",
                ));
            }
            let text = std::str::from_utf8(&bytes).map_err(io::Error::other)?;
            expansion_segments.push(Arc::new(ExpandedSegment {
                text: Arc::from(text),
                digest: Sha256::digest(&bytes).into(),
                lines: text.match_indices('\n').map(|(at, _)| at+1).collect::<Vec<_>>().into(),
            }));
        } else { pack.extend_from_slice(&bytes); }
        position += bytes.len();
    }
    let expansion = Arc::new(SegmentedExpansion {
        segments: expansion_segments,
        bytes: manifest.expanded_end,
    });
    let text = std::str::from_utf8(&pack).map_err(io::Error::other)?;
    if position != total || expansion.bytes > total { return Err(io::Error::other("invalid prepared expansion boundary")); }
    let expanded = expansion.source();
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
                .get(source.start.checked_sub(manifest.expanded_end).ok_or_else(|| io::Error::other("invalid prepared source start"))?..source.end.checked_sub(manifest.expanded_end).ok_or_else(|| io::Error::other("invalid prepared source end"))?)
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
    if cursor != text.len()+manifest.expanded_end {
        return Err(io::Error::other("trailing prepared input bytes"));
    }
    let origin_bytes =
        store.get_bounded("prepared-input-chunk-v2", &manifest.origins, MAX_MANIFEST)?;
    let mut reader = origin_bytes.as_slice();
    let mut origins = Vec::with_capacity(manifest.origin_count);
    for _ in 0..manifest.origin_count {
        origins.push(Origin {
            output_line: read_varint(&mut reader)?,
            path: path(read_varint(&mut reader)?)?,
            source_line: read_varint(&mut reader)?,
        });
    }
    if !reader.is_empty() {
        return Err(io::Error::other("trailing prepared origin bytes"));
    }
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
        text: String::new(),
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
        macro_names: Arc::new(manifest.macro_names),
        expansion,
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
use sha2::{Digest, Sha256};

fn publish_group(
    store: &ContentStore,
    pack: &mut Vec<(String, usize)>,
    parts: &mut Vec<&[u8]>,
    known: &BTreeSet<String>,
) -> io::Result<()> {
    if parts.is_empty() {
        return Ok(());
    }
    let mut hash = Sha256::new();
    let mut bytes = 0;
    for part in parts.iter() {
        hash.update(part);
        bytes += part.len();
    }
    let digest = format!("{:x}", hash.finalize());
    if !known.contains(&digest) {
        store.put_parts("prepared-input-chunk-v2", parts)?;
    }
    pack.push((digest, bytes));
    parts.clear();
    Ok(())
}
fn write_varint(bytes: &mut Vec<u8>, mut value: usize) {
    while value >= 128 {
        bytes.push((value as u8 & 127) | 128);
        value >>= 7;
    }
    bytes.push(value as u8);
}
fn read_varint(bytes: &mut &[u8]) -> io::Result<usize> {
    let mut value = 0usize;
    for shift in (0..usize::BITS).step_by(7) {
        let (&byte, rest) = bytes
            .split_first()
            .ok_or_else(|| io::Error::other("truncated origin varint"))?;
        *bytes = rest;
        let part = usize::from(byte & 127);
        if part > (usize::MAX >> shift) {
            return Err(io::Error::other("origin varint overflow"));
        }
        value |= part << shift;
        if byte & 128 == 0 {
            return Ok(value);
        }
    }
    Err(io::Error::other("origin varint overflow"))
}
