//! Prepared input packs use the same CAS and transactional metadata as builds.
//! Publish bytes before the mutable head; concurrent writers may publish either
//! fully verified revision. No database/Salsa IDs are serialized.
use crate::{input_proof::InputProof, prepared_project::*, ContentStore};
use dm_preprocess::{Diagnostic, Macro, PreprocessedProject, Unit};
use dm_syntax::Span;
use serde::{Deserialize, Serialize};
use sha2::{Digest,Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::PathBuf;
use std::sync::Arc;

const VERSION: u32 = 8;
const MAX_PACK: usize = 128 * 1024 * 1024;
const MAX_EXPANDED_BYTES: usize = 1024 * 1024 * 1024;
const MAX_MANIFEST: usize = 64 * 1024 * 1024;

#[derive(Serialize, Deserialize)]
struct Source {
    path: PathBuf,
    start: usize,
    end: usize,
    digest: [u8; 32],
    pack: Option<String>,
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
    source_pages: Vec<Option<String>>,
    origins: String,
    origin_count: usize,
    units: Vec<(usize, usize, usize, usize)>,
    unit_digests: Vec<[u8; 32]>,
    unit_digest_validity:Vec<bool>,
    unit_parents:Vec<Option<usize>>,
    semantic_identity:Option<Arc<dm_preprocess::SourceSemanticIdentity>>,
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

#[derive(Clone)]
pub(crate) struct SourceInventory {
    pages: Vec<Option<String>>,
    dirty: BTreeSet<usize>,
    expanded: BTreeSet<String>,
    origins: String,
}
impl SourceInventory {
    pub(crate) fn updated(&self,previous:&BTreeMap<PathBuf,PreparedSource>,current:&BTreeMap<PathBuf,PreparedSource>)->Self {
        let mut next=self.clone();
        for (path,source) in current {
            if previous.get(path).is_none_or(|old|old.digest!=source.digest || old.stamp!=source.stamp) {next.dirty.insert(source_bucket(path));}
        }
        for path in previous.keys().filter(|path|!current.contains_key(*path)) {next.dirty.insert(source_bucket(path));}
        next
    }
    pub(crate) fn resident_bytes(&self)->usize {
        self.pages.iter().map(|id|id.as_ref().map_or(0,String::capacity)+std::mem::size_of::<Option<String>>()).sum::<usize>()
            +self.expanded.iter().map(|digest|digest.capacity()+48).sum::<usize>()+self.dirty.len()*32+self.origins.capacity()+128
    }
}
pub(super) struct PublishedInputs {
    pub backings:BTreeMap<[u8;32],crate::PackedBlob>,
    pub inventory:SourceInventory,
}
fn source_bucket(path:&std::path::Path)->usize {
    // Authored filesystem identity belongs to this project-context cache only;
    // bucket membership never enters semantic compiler/output identity.
    Sha256::digest(path.as_os_str().as_encoded_bytes())[0] as usize
}
fn source_backing(source:&PreparedSource)->Option<crate::PackedBlob> {
    if !source.blob_published {return None;}
    let pack=if source.blob_packed {Some(source.blob.as_ref()?.file_name()?.to_str()?.to_owned())} else {None};
    Some(crate::PackedBlob {digest:source.digest,pack,start:source.blob_offset,len:source.content_len})
}

pub(super) fn save(store: &ContentStore, snapshot: &PreparedProject) -> io::Result<PublishedInputs> {
    let persist_started = std::time::Instant::now();
    let mut paths = BTreeMap::new();
    fn path_id(paths: &mut BTreeMap<PathBuf, usize>, path: &std::path::Path) -> usize {
        if let Some(id) = paths.get(path) { return *id; }
        let next=paths.len();paths.insert(path.to_path_buf(),next);next
    }
    let project = &snapshot.project;
    // Previously every body edit published expanded text plus every authored
    // source as one new CAS blob. Keep immutable expansion pieces and bounded
    // source groups so a changed generation writes only changed chunks.
    let inventory_started=std::time::Instant::now();
    let previous = if snapshot.source_inventory.is_some() {None} else {match load_manifest(store,&snapshot.context) {
        Ok(previous)=>previous,
        Err(error)=>{if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE prepared inventory miss: {error}");}None}
    }};
    trace_persistence("previous manifest inventory",inventory_started);
    let known:BTreeSet<_>=if let Some(inventory)=&snapshot.source_inventory {
        inventory.expanded.iter().cloned().chain(std::iter::once(inventory.origins.clone())).collect()
    } else {previous.as_ref().into_iter().flat_map(|manifest|manifest.pack.iter().map(|(digest,_)|digest.clone()).chain(std::iter::once(manifest.origins.clone()))).collect()};
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
    let expanded_started = std::time::Instant::now();
    let chunk_writes = dm_work::map_ordered(
        &missing_chunks,
        dm_work::WorkLimits::configured(),
        |piece| {
            // Resident immutable input is already charged to preparation. Only
            // lazy hydration allocates another decoded frame; CAS hashes/writes
            // borrowed bytes with bounded scratch storage.
            let hydration=if piece.text.len()==piece.content_len {0} else {piece.content_len.saturating_mul(2)};
            hydration.saturating_add(64*1024)
        },
        |piece| piece.content().and_then(|text|store.put_rebuildable("prepared-input-chunk-v2",text.as_bytes())),
    )
    .map_err(|error| io::Error::other(format!("expansion persistence work limits: {error:?}")))?;
    for write in chunk_writes {
        write?;
    }
    let mut scheduled_sources=BTreeSet::new();
    let missing:Vec<_>=snapshot.sources.values().filter(|source|!source.blob_published && scheduled_sources.insert(source.digest)).collect();
    trace_persistence("expanded CAS writes", expanded_started);
    let authored_started=std::time::Instant::now();
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE authored publication inventory: known={} requested={} bytes={} previous={}",snapshot.sources.len()-missing.len(),missing.len(),missing.iter().map(|source|source.content_len).sum::<usize>(),snapshot.source_inventory.is_some());}
    let mut backings:BTreeMap<_,_>=snapshot.sources.values().filter_map(source_backing).map(|backing|(backing.digest,backing)).collect();
    let mut groups:Vec<Vec<&PreparedSource>>=Vec::new();
    let mut group=Vec::new();let mut bytes=0usize;
    for source in missing {
        if !group.is_empty() && (bytes.saturating_add(source.content_len)>2*1024*1024 || group.len()>=512) {
            groups.push(std::mem::take(&mut group));bytes=0;
        }
        bytes=bytes.saturating_add(source.content_len);group.push(source);
    }
    if !group.is_empty() {groups.push(group);}
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE authored pack publication: {} bounded groups",groups.len());}
    let writes=dm_work::map_ordered(&groups,dm_work::WorkLimits::configured(),
        |group|group.iter().map(|source|if source.text.len()==source.content_len {0} else {source.content_len.saturating_mul(2)}).sum::<usize>().saturating_add(64*1024).saturating_add(group.len()*512),
        |group| {
            let contents=group.iter().map(|source|source.content()).collect::<io::Result<Vec<_>>>()?;
            let inputs:Vec<_>=group.iter().zip(&contents).map(|(source,text)|(source.digest,text.as_bytes())).collect();
            store.put_rebuildable_batch("prepared-source-v3",&inputs)
        }).map_err(|error|io::Error::other(format!("source pack work limits: {error:?}")))?;
    for write in writes {for backing in write? {backings.insert(backing.digest,backing);}}
    trace_persistence("authored CAS writes", authored_started);
    let manifest_started = std::time::Instant::now();
    let mut inventory=snapshot.source_inventory.as_ref().map(|inventory|inventory.as_ref().clone()).unwrap_or_else(||SourceInventory {
        pages:previous.as_ref().map_or_else(||vec![None;256],|manifest|manifest.source_pages.clone()),
        dirty:(0..256).collect(),expanded:BTreeSet::new(),origins:String::new(),
    });
    let mut buckets:BTreeMap<usize,Vec<Source>>=inventory.dirty.iter().map(|bucket|(*bucket,Vec::new())).collect();
    for (path,source) in snapshot.sources.iter() {
        let bucket=source_bucket(path);
        if let Some(rows)=buckets.get_mut(&bucket) {
            let backing=backings.get(&source.digest).ok_or_else(||io::Error::other("authored source backing missing after publication"))?;
            rows.push(Source {path:path.clone(),start:backing.start,end:backing.start+backing.len,digest:source.digest,pack:backing.pack.clone(),stamp:source.stamp.clone()});
        }
    }
    for (bucket,rows) in buckets {
        inventory.pages[bucket]=if rows.is_empty() {None} else {
            let bytes=encode_snapshot(&rows)?;
            if bytes.len()>4*1024*1024 || snapshot_decoded_size(&bytes)?>4*1024*1024 {return Err(io::Error::other("source inventory page exceeds limit"));}
            Some(store.put_rebuildable("prepared-source-inventory-v1",&bytes)?)
        };
    }
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE source inventory publication: {} dirty buckets",inventory.dirty.len());}
    inventory.dirty.clear();
    let origin_started=std::time::Instant::now();
    let map = snapshot.project.origin_map.clone().unwrap_or_else(||Arc::new(dm_preprocess::OriginMap::from_origins(project.origin_iter())));
    let origin_bytes=encode_snapshot(map.as_ref())?;
    let origins = format!("{:x}", Sha256::digest(&origin_bytes));
    if !known.contains(&origins) {store.put_rebuildable("prepared-input-chunk-v2", &origin_bytes)?;}
    trace_persistence("compact origin encoding and CAS", origin_started);
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
    inventory.expanded=pack.iter().map(|(digest,_)|digest.clone()).collect();
    inventory.origins=origins.clone();
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
        source_pages:inventory.pages.clone(),
        origins:origins.clone(),
        origin_count: project.origin_count(),
        units,
        unit_digests: project.unit_digests.clone(),
        unit_digest_validity:project.unit_digest_validity.clone(),
        unit_parents:project.unit_parents.clone(),
        semantic_identity:project.semantic_identity.clone(),
        dependencies,
        maps,
        skins,
        file_dirs,
        diagnostics: project.diagnostics.clone(),
        macros: project.final_macros.clone(),
        macro_names: snapshot.macro_names.as_ref().clone(),
        proof: snapshot.proof.clone(),
    };
    let encode_started=std::time::Instant::now();
    let bytes = encode_snapshot(&manifest)?;
    trace_persistence("manifest encoding", encode_started);
    if bytes.len() > MAX_MANIFEST {
        return Ok(PublishedInputs {backings,inventory});
    }
    let digest = store.put("prepared-input-manifest-v2", &bytes)?;
    let head = Head {
        version: VERSION,
        context: snapshot.context.clone(),
        manifest: digest,
    };
    let result = store
        .metadata
        .put_many(
            vec![(
                dm_store::Key::new("prepared-project-head-v2", &snapshot.context),
                serde_json::to_vec(&head).map_err(io::Error::other)?,
            )],
            None,
        )
        .map(|_| ());
    trace_persistence("origin and manifest publication", manifest_started);
    trace_persistence("total", persist_started);
    result.map(|()|PublishedInputs {backings,inventory})
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
    let manifest:Manifest = decode_snapshot(&store.get_bounded(
        "prepared-input-manifest-v2", &head.manifest, MAX_MANIFEST,
    )?)?;
    if manifest.source_pages.len()!=256 || manifest.source_pages.iter().flatten().any(|digest|digest.len()!=64 || !digest.bytes().all(|byte|byte.is_ascii_hexdigit())) {
        return Err(io::Error::other("invalid prepared source range metadata"));
    }
    Ok(Some(manifest))
}

fn valid_source_range(source:&Source)->bool {
    source.start<=source.end && source.end-source.start<=MAX_PACK
        && source.pack.as_ref().is_none_or(|digest|digest.len()==64 && digest.bytes().all(|byte|byte.is_ascii_hexdigit()))
        && (source.pack.is_some() || source.start==0)
        && (source.pack.is_none() || source.end<=2*1024*1024)
}

pub(super) fn load(store: &ContentStore, context: &str) -> io::Result<Option<PreparedProject>> {
    let Some(manifest) = load_manifest(store, context)? else {
        return Ok(None);
    };
    if manifest.version != VERSION
        || manifest.context != context
        || manifest.paths.len() > 64_000
        || manifest.origin_count > 4_000_000
        || manifest.units.len() > 128_000
        || manifest.units.len() != manifest.unit_digests.len()
        || manifest.units.len()!=manifest.unit_parents.len()
        || manifest.units.len()!=manifest.unit_digest_validity.len()
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
    for (bucket,page) in manifest.source_pages.iter().enumerate() {
        let Some(page)=page else {continue;};
        let bytes=store.get_bounded("prepared-source-inventory-v1",page,4*1024*1024)?;
        if snapshot_decoded_size(&bytes)?>4*1024*1024 {return Err(io::Error::other("source inventory page exceeds decoded limit"));}
        let rows:Vec<Source>=decode_snapshot(&bytes)?;
        if rows.len()>64_000 || sources.len()+rows.len()>64_000 {return Err(io::Error::other("too many authored inventory rows"));}
        for source in &rows {
        if source_bucket(&source.path)!=bucket {return Err(io::Error::other("source inventory bucket mismatch"));}
        if !valid_source_range(source) {return Err(io::Error::other("invalid source artifact range"));}
        let location=crate::PackedBlob {digest:source.digest,pack:source.pack.clone(),start:source.start,len:source.end-source.start};
        let blob=store.packed_blob_path("prepared-source-v3",&location);
        if !fs_metadata_has_range(&blob,source.end) {return Ok(None);}
        let key = source.path.clone();
        if sources
            .insert(
                key,
                PreparedSource {
                    text: Arc::from(""),
                    content_len: source.end-source.start,
                    blob: Some(blob),
                    blob_offset:source.start,
                    blob_packed:source.pack.is_some(),
                    blob_published:true,
                    digest: source.digest,
                    stamp: source.stamp.clone(),
                },
            )
            .is_some()
        {
            return Err(io::Error::other("duplicate prepared source"));
        }
    }
    }
    let origin_bytes =
        store.get_bounded("prepared-input-chunk-v2", &manifest.origins, MAX_MANIFEST)?;
    let origins:dm_preprocess::OriginMap=decode_snapshot(&origin_bytes)?;
    if !origins.validate() || origins.len()!=manifest.origin_count {
        return Err(io::Error::other("invalid prepared compact origin map"));
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
    let mut project = PreprocessedProject {
        text: String::new(),
        origins: Vec::new(),
        origin_map: Some(Arc::new(origins)),
        units,
        unit_digests: manifest.unit_digests,
        unit_digest_validity:manifest.unit_digest_validity,
        unit_parents:manifest.unit_parents,
        semantic_identity:manifest.semantic_identity,
        dependencies: resolve(manifest.dependencies)?
            .into_iter()
            .collect::<BTreeSet<_>>(),
        map_includes: resolve(manifest.maps)?,
        skin_includes: resolve(manifest.skins)?,
        file_dirs: resolve(manifest.file_dirs)?,
        diagnostics: manifest.diagnostics,
        final_macros: manifest.macros,
    };
    project.compact_origins();
    if !project.semantic_identity.as_ref().is_some_and(|identity|identity.validate(&project,expanded.len())) {
        return Err(io::Error::other("invalid prepared emission identity"));
    }
    let source_inventory=Some(Arc::new(SourceInventory {pages:manifest.source_pages.clone(),dirty:BTreeSet::new(),expanded:manifest.pack.iter().map(|(digest,_)|digest.clone()).collect(),origins:manifest.origins.clone()}));
    Ok(Some(PreparedProject {
        source_inventory,
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


fn trace_persistence(stage:&str,started:std::time::Instant) {
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE prepared persistence {stage}: {:.3}s",started.elapsed().as_secs_f64());}
}

fn encode_snapshot(value:&impl Serialize)->io::Result<Vec<u8>> {
    let bytes=rmp_serde::to_vec(value).map_err(io::Error::other)?;
    if bytes.len()>MAX_MANIFEST {return Err(io::Error::other("prepared snapshot exceeds decoded limit"));}
    Ok(lz4_flex::compress_prepend_size(&bytes))
}
fn decode_snapshot<T:serde::de::DeserializeOwned>(bytes:&[u8])->io::Result<T> {
    let size=bytes.get(..4).and_then(|prefix|prefix.try_into().ok()).map(u32::from_le_bytes)
        .ok_or_else(||io::Error::other("truncated prepared snapshot"))?;
    if size as usize>MAX_MANIFEST {return Err(io::Error::other("prepared snapshot exceeds decoded limit"));}
    let bytes=lz4_flex::decompress_size_prepended(bytes).map_err(io::Error::other)?;
    rmp_serde::from_slice(&bytes).map_err(io::Error::other)
}

fn fs_metadata_has_range(path:&std::path::Path,end:usize)->bool {std::fs::metadata(path).is_ok_and(|metadata|metadata.is_file() && metadata.len()>=end as u64)}

fn snapshot_decoded_size(bytes:&[u8])->io::Result<usize> {Ok(u32::from_le_bytes(bytes.get(..4).and_then(|prefix|prefix.try_into().ok()).ok_or_else(||io::Error::other("truncated inventory page"))?) as usize)}
