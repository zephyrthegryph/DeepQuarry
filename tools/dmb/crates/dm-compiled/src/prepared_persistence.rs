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

const VERSION: u32 = 4;
const MAX_PACK: usize = 128 * 1024 * 1024;
const MAX_EXPANDED_BYTES: usize = 1024 * 1024 * 1024;
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
    segment_lines: Vec<Vec<usize>>,
    segment_utf8: Vec<Vec<usize>>,
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
    let pack: Vec<_> = snapshot
        .expansion
        .segments
        .iter()
        .map(|piece| {
            let digest = piece
                .digest
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>();
            (digest, piece.content_len)
        })
        .collect();
    let mut scheduled = BTreeSet::new();
    let missing_chunks: Vec<_> = snapshot
        .expansion
        .segments
        .iter()
        .zip(&pack)
        .filter(|(_, (digest, _))| !known.contains(digest) && scheduled.insert(digest.clone()))
        .map(|(piece, _)| piece)
        .collect();
    let chunk_writes = dm_work::map_ordered(
        &missing_chunks,
        dm_work::WorkLimits::configured(),
        |piece| piece.content_len.saturating_add(4096),
        |piece| piece.content().and_then(|text|store.put_rebuildable("prepared-input-chunk-v2",text.as_bytes())),
    )
    .map_err(|error| io::Error::other(format!("expansion persistence work limits: {error:?}")))?;
    for write in chunk_writes {
        write?;
    }
    let known_sources: BTreeSet<_> = previous
        .as_ref()
        .into_iter()
        .flat_map(|manifest| manifest.sources.iter().map(|source| source.digest))
        .collect();
    let missing: Vec<_> = snapshot
        .sources
        .values()
        .filter(|source| !known_sources.contains(&source.digest))
        .collect();
    let writes = dm_work::map_ordered(
        &missing,
        dm_work::WorkLimits::configured(),
        |source| source.content_len.saturating_add(4096),
        |source| {
            source
                .content()
                .and_then(|text| store.put_rebuildable("prepared-source-v3", text.as_bytes()))
        },
    )
    .map_err(|error| io::Error::other(format!("source persistence work limits: {error:?}")))?;
    for write in writes {
        write?;
    }
    let mut sources = Vec::with_capacity(snapshot.sources.len());
    for (path, source) in snapshot.sources.iter() {
        sources.push(Source {
            path: path_id(&mut paths, path),
            start: 0,
            end: source.content_len,
            digest: source.digest,
            stamp: source.stamp.clone(),
        });
    }
    let mut origin_bytes = Vec::with_capacity(project.origins.len() * 5);
    for origin in &project.origins {
        write_varint(&mut origin_bytes, origin.output_line);
        write_varint(&mut origin_bytes, path_id(&mut paths, &origin.path));
        write_varint(&mut origin_bytes, origin.source_line);
    }
    let origins = format!("{:x}", Sha256::digest(&origin_bytes));
    if !known.contains(&origins) {
        store.put_rebuildable("prepared-input-chunk-v2", &origin_bytes)?;
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
        segment_lines:snapshot.expansion.segments.iter().map(|piece|piece.lines.to_vec()).collect(),
        segment_utf8:snapshot.expansion.segments.iter().map(|piece|piece.non_boundaries.to_vec()).collect(),
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
        .filter(|total| *total <= MAX_EXPANDED_BYTES)
        .ok_or_else(|| io::Error::other("prepared chunk pack exceeds limit"))?;
    if manifest.pack.len() > 16_384 {
        return Err(io::Error::other("too many prepared chunks"));
    }

    let mut position = 0;
    let mut expansion_segments = Vec::new();
    if manifest.segment_lines.len()!=manifest.pack.len() || manifest.segment_utf8.len()!=manifest.pack.len() {return Err(io::Error::other("invalid expanded segment indexes"));}
    for (index,(digest,len)) in manifest.pack.iter().enumerate() {
        if digest.len()!=64 || !digest.bytes().all(|byte|byte.is_ascii_hexdigit()) || position+len>manifest.expanded_end {return Err(io::Error::other("invalid expansion disk handle"));}
        let mut identity=[0u8;32];for (at,byte) in identity.iter_mut().enumerate() {*byte=u8::from_str_radix(&digest[at*2..at*2+2],16).map_err(io::Error::other)?;}
        let lines=&manifest.segment_lines[index];let utf8=&manifest.segment_utf8[index];
        if !lines.windows(2).all(|pair|pair[0]<pair[1]) || lines.iter().any(|at|*at>*len) || !utf8.windows(2).all(|pair|pair[0]<pair[1]) || utf8.iter().any(|at|*at>=*len) {return Err(io::Error::other("invalid expansion line/UTF8 index"));}
        expansion_segments.push(Arc::new(ExpandedSegment {text:Arc::from(""),content_len:*len,blob:Some(Arc::new(store.root.join("prepared-input-chunk-v2").join(&digest[..2]).join(digest))),digest:identity,lines:lines.clone().into(),non_boundaries:utf8.clone().into()}));
        position+=len;
    }
    let expansion = Arc::new(SegmentedExpansion {
        segments: expansion_segments,
        bytes: manifest.expanded_end,
    });
    if position != total || expansion.bytes > total {
        return Err(io::Error::other("invalid prepared expansion boundary"));
    }
    let expanded = expansion.source();
    let paths: Vec<Arc<PathBuf>> = manifest.paths.into_iter().map(Arc::new).collect();
    let path = |index: usize| {
        paths
            .get(index)
            .cloned()
            .ok_or_else(|| io::Error::other("invalid prepared path index"))
    };
    let mut sources = BTreeMap::new();
    for source in &manifest.sources {
        if source.start != 0 || source.end > MAX_PACK {
            return Err(io::Error::other("invalid source artifact length"));
        }
        let digest = source
            .digest
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let blob = store
            .root
            .join("prepared-source-v3")
            .join(&digest[..2])
            .join(&digest);
        if !blob.is_file() {
            return Ok(None);
        }
        let key = (*path(source.path)?).clone();
        if sources
            .insert(
                key,
                PreparedSource {
                    text: Arc::from(""),
                    content_len: source.end,
                    blob: Some(blob),
                    digest: source.digest,
                    stamp: source.stamp.clone(),
                },
            )
            .is_some()
        {
            return Err(io::Error::other("duplicate prepared source"));
        }
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
