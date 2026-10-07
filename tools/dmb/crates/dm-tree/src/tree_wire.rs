//! Neutral whole-tree DTO. Current inputs authorize replay; source origins never
//! enter this record. Derived indexes are reconstructed, not deserialized.
use crate::{frontend::EngineSeed, *};
use serde::{Deserialize, Serialize};
const MAX_NODES: usize = 1_000_000;
#[derive(Serialize, Deserialize)]
struct TypeRow {
    path: SymbolId,
    parent: Option<u32>,
    explicit: bool,
    synthetic: bool,
}
#[derive(Serialize, Deserialize)]
struct MemberRow {
    definition: DefinitionMode,
    owner: u32,
    name: SymbolId,
    kind: MemberKind,
    content: u128,
    previous: Option<u32>,
}
#[derive(Serialize, Deserialize)]
enum TargetRow {
    Type(u32),
    Member(u32),
}
#[derive(Serialize, Deserialize)]
struct Record {
    identity: u128,
    symbols: Vec<(SymbolId, String)>,
    types: Vec<TypeRow>,
    members: Vec<MemberRow>,
    targets: Vec<TargetRow>,
}
fn invalid() -> String {
    "invalid resolved-tree record".into()
}
fn merged(
    source: &[Skeleton],
    seed: Option<&EngineSeed>,
) -> (Vec<Skeleton>, Option<EngineHierarchy>) {
    let authored: HashMap<_, _> = source
        .iter()
        .filter_map(|row| match row {
            Skeleton::Type {
                path,
                explicit_parent: Some(parent),
            } => Some((*path, *parent)),
            _ => None,
        })
        .collect();
    let hierarchy = seed.map(|seed| {
        let mut h = seed.hierarchy.clone();
        for (path, parent) in &mut h.parents {
            if let Some(authored) = authored.get(path) {
                *parent = Some(*authored);
            }
        }
        h
    });
    let mut all = hierarchy.as_ref().map_or_else(Vec::new, |h| {
        h.parents
            .iter()
            .map(|(path, parent)| Skeleton::Type {
                path: *path,
                explicit_parent: *parent,
            })
            .collect()
    });
    all.extend_from_slice(source);
    (all, hierarchy)
}
pub(super) fn encode(
    tree: &SemanticTree,
    _source: &[Skeleton],
    _seed: Option<&EngineSeed>,
    size: &mut usize,
) -> Result<Vec<Vec<u8>>, String> {
    let symbols = tree.symbols.ordered();
    let mut output = Vec::new();
    *size = 0;
    append(
        ChunkView::Header {
            identity: tree.identity,
            counts: [
                symbols.len(),
                tree.types.len(),
                tree.members.len(),
                tree.declaration_targets.len(),
            ],
        },
        &mut output,
        size,
    )?;
    // Metadata comes from the current exact-key-authorized source, not this DTO.
    // Only one neutral row batch is materialized at a time. Strings remain
    // borrowed from the immutable tree dictionary throughout serialization.
    for rows in symbols.chunks(1024) {
        append(ChunkView::Symbols(rows), &mut output, size)?;
    }
    for rows in tree.types.chunks(1024) {
        let rows: Vec<_> = rows
            .iter()
            .map(|node| TypeRow {
                path: node.path,
                parent: node.parent.map(|id| id.0),
                explicit: node.explicit_parent,
                synthetic: node.synthetic,
            })
            .collect();
        append(ChunkView::Types(&rows), &mut output, size)?;
    }
    for rows in tree.members.chunks(1024) {
        let rows: Vec<_> = rows
            .iter()
            .map(|node| MemberRow {
                definition: node.definition,
                owner: node.owner.0,
                name: node.name,
                kind: node.kind,
                content: node.content,
                previous: node.previous.map(|id| id.0),
            })
            .collect();
        append(ChunkView::Members(&rows), &mut output, size)?;
    }
    for rows in tree.declaration_targets.chunks(1024) {
        let rows: Vec<_> = rows
            .iter()
            .map(|target| match target {
                Target::Type(id) => TargetRow::Type(id.0),
                Target::Member(id) => TargetRow::Member(id.0),
            })
            .collect();
        append(ChunkView::Targets(&rows), &mut output, size)?;
    }
    Ok(output)
}
const CHUNK_BYTES: usize = 8 * 1024 * 1024;
const STREAM_BYTES: usize = 256 * 1024 * 1024;
const MAX_CHUNKS: usize = 4096;
#[derive(Serialize, Deserialize)]
enum Chunk {
    Header { identity: u128, counts: [usize; 4] },
    Symbols(Vec<(SymbolId, String)>),
    Types(Vec<TypeRow>),
    Members(Vec<MemberRow>),
    Targets(Vec<TargetRow>),
}
// The variants and field order exactly mirror Chunk; borrowing changes ownership,
// not the wire representation. The decoder always issues owned neutral records.
#[derive(Clone, Copy, Serialize)]
enum ChunkView<'a> {
    Header { identity: u128, counts: [usize; 4] },
    Symbols(&'a [(SymbolId, &'a str)]),
    Types(&'a [TypeRow]),
    Members(&'a [MemberRow]),
    Targets(&'a [TargetRow]),
}
fn append(
    value: ChunkView<'_>,
    output: &mut Vec<Vec<u8>>,
    total: &mut usize,
) -> Result<(), String> {
    if output.len() >= MAX_CHUNKS || *total >= STREAM_BYTES {
        return Err("tree chunk stream exceeds bound".into());
    }
    let limit = CHUNK_BYTES.min(STREAM_BYTES - *total);
    match dm_wire::encode_bounded(3, &value, limit) {
        Ok(bytes) => {
            *total += bytes.len();
            output.push(bytes);
            Ok(())
        }
        Err(error) => {
            macro_rules! split {
                ($rows:expr,$variant:ident) => {{
                    let rows = $rows;
                    if rows.len() <= 1 {
                        return Err(error);
                    }
                    let (left, right) = rows.split_at(rows.len() / 2);
                    append(ChunkView::$variant(left), output, total)?;
                    append(ChunkView::$variant(right), output, total)
                }};
            }
            match value {
                ChunkView::Header { .. } => Err(error),
                ChunkView::Symbols(rows) => split!(rows, Symbols),
                ChunkView::Types(rows) => split!(rows, Types),
                ChunkView::Members(rows) => split!(rows, Members),
                ChunkView::Targets(rows) => split!(rows, Targets),
            }
        }
    }
}
fn decode(chunks: &[Vec<u8>]) -> Result<Record, String> {
    if chunks.is_empty()
        || chunks.len() > MAX_CHUNKS
        || chunks.iter().any(|c| c.len() > CHUNK_BYTES)
        || chunks.iter().map(Vec::len).sum::<usize>() > STREAM_BYTES
    {
        return Err(invalid());
    }
    let mut record = Record {
        identity: 0,
        symbols: Vec::new(),
        types: Vec::new(),
        members: Vec::new(),
        targets: Vec::new(),
    };
    let mut expected = None;
    let mut section = 0;
    for (ordinal, bytes) in chunks.iter().enumerate() {
        let chunk: Chunk = dm_wire::decode(3, bytes, CHUNK_BYTES)?;
        let next = match chunk {
            Chunk::Header { identity, counts } if ordinal == 0 => {
                if counts.iter().any(|n| *n > MAX_NODES) {
                    return Err(invalid());
                }
                record.identity = identity;
                expected = Some(counts);
                0
            }
            Chunk::Symbols(rows) if !rows.is_empty() => {
                record.symbols.extend(rows);
                1
            }
            Chunk::Types(rows) if !rows.is_empty() => {
                record.types.extend(rows);
                2
            }
            Chunk::Members(rows) if !rows.is_empty() => {
                record.members.extend(rows);
                3
            }
            Chunk::Targets(rows) if !rows.is_empty() => {
                record.targets.extend(rows);
                4
            }
            _ => return Err(invalid()),
        };
        if next < section
            || ordinal > 0 && next == 0
            || record.symbols.len() > MAX_NODES
            || record.types.len() > MAX_NODES
            || record.members.len() > MAX_NODES
            || record.targets.len() > MAX_NODES
        {
            return Err(invalid());
        }
        section = next;
    }
    if expected
        != Some([
            record.symbols.len(),
            record.types.len(),
            record.members.len(),
            record.targets.len(),
        ])
    {
        return Err(invalid());
    }
    if record.types.is_empty()
        || record.types.len() > MAX_NODES
        || record.members.len() > MAX_NODES
        || record.targets.len() > MAX_NODES
        || record.symbols.len() > MAX_NODES
    {
        return Err(invalid());
    }
    let mut symbols = HashSet::new();
    for (id, text) in &record.symbols {
        if text.len() > dm_wire::MAX_BYTES || SymbolId::of(text) != *id || !symbols.insert(*id) {
            return Err(invalid());
        }
    }
    let mut paths = HashSet::new();
    for row in &record.types {
        if !symbols.contains(&row.path)
            || !paths.insert(row.path)
            || row.parent.is_some_and(|p| p as usize >= record.types.len())
        {
            return Err(invalid());
        }
    }
    for row in &record.members {
        if row.owner as usize >= record.types.len()
            || !symbols.contains(&row.name)
            || row
                .previous
                .is_some_and(|p| p as usize >= record.members.len())
        {
            return Err(invalid());
        }
    }
    for target in &record.targets {
        if match target {
            TargetRow::Type(i) => *i as usize >= record.types.len(),
            TargetRow::Member(i) => *i as usize >= record.members.len(),
        } {
            return Err(invalid());
        }
    }
    acyclic(record.types.iter().map(|row| row.parent).collect())?;
    acyclic(record.members.iter().map(|row| row.previous).collect())?;
    Ok(record)
}
fn acyclic(parents: Vec<Option<u32>>) -> Result<(), String> {
    let mut colors = vec![0u8; parents.len()];
    for start in 0..parents.len() {
        let mut chain = Vec::new();
        let mut cursor = Some(start as u32);
        while let Some(id) = cursor {
            match colors[id as usize] {
                2 => break,
                1 => return Err(invalid()),
                _ => {}
            }
            colors[id as usize] = 1;
            chain.push(id);
            cursor = parents[id as usize];
        }
        for id in chain {
            colors[id as usize] = 2;
        }
    }
    Ok(())
}
pub(super) fn validate(bytes: &[Vec<u8>]) -> Result<(), String> {
    decode(bytes).map(|_| ())
}
fn ensure(
    path: SymbolId,
    symbols: &mut SymbolTable,
    paths: &mut Vec<SymbolId>,
    seen: &mut HashSet<SymbolId>,
) -> Result<(), String> {
    if seen.contains(&path) {
        return Ok(());
    }
    let text = symbols.text(path).ok_or_else(invalid)?.to_owned();
    if text.len() > 4096 {
        return Err(invalid());
    }
    let parsed = dm_ir::TypePath::parse(&text).map_err(|_| invalid())?;
    if let Some(parent) = parsed.parent() {
        let id = symbols.intern(parent.as_str()).map_err(|_| invalid())?;
        ensure(id, symbols, paths, seen)?;
    }
    seen.insert(path);
    paths.push(path);
    Ok(())
}
pub(super) fn replay(
    bytes: &[Vec<u8>],
    adapted: &AdaptedDeclarations,
    seed: Option<&EngineSeed>,
) -> Result<SemanticTree, String> {
    let record = decode(bytes)?;
    if record.targets.len() != adapted.skeletons.len() {
        return Err(invalid());
    }
    let (all, hierarchy) = merged(&adapted.skeletons, seed);
    let mut symbols = adapted.symbols.clone();
    let root = SymbolId::of("/");
    symbols.intern("/").map_err(|_| invalid())?;
    let mut expected_paths = Vec::new();
    let mut seen = HashSet::new();
    ensure(root, &mut symbols, &mut expected_paths, &mut seen)?;
    for row in &all {
        let path = match row {
            Skeleton::Type { path, .. } => *path,
            Skeleton::Member { owner, .. } => *owner,
        };
        ensure(path, &mut symbols, &mut expected_paths, &mut seen)?;
    }
    if expected_paths.len() != record.types.len()
        || expected_paths
            .iter()
            .zip(&record.types)
            .any(|(path, row)| *path != row.path)
    {
        return Err(invalid());
    }
    let spellings: Vec<_> = symbols
        .ordered()
        .into_iter()
        .map(|(id, text)| (id, text.to_owned()))
        .collect();
    if spellings != record.symbols {
        return Err(invalid());
    }
    let mut explicit = HashMap::new();
    let mut declared = HashSet::new();
    for row in &all {
        if let Skeleton::Type {
            path,
            explicit_parent,
        } = row
        {
            declared.insert(*path);
            if let Some(parent) = explicit_parent {
                if explicit
                    .insert(*path, *parent)
                    .is_some_and(|p| p != *parent)
                {
                    return Err(invalid());
                }
            }
        }
    }
    let by_path: HashMap<_, _> = expected_paths
        .iter()
        .enumerate()
        .map(|(i, path)| (*path, TypeId(i as u32)))
        .collect();
    let mut types = Vec::new();
    for row in &record.types {
        let parent = if let Some(parent) = explicit.get(&row.path) {
            Some(*by_path.get(parent).ok_or_else(invalid)?)
        } else {
            dm_ir::TypePath::parse(symbols.text(row.path).ok_or_else(invalid)?)
                .map_err(|_| invalid())?
                .parent()
                .map(|parent| {
                    let lexical = SymbolId::of(parent.as_str());
                    let datum = SymbolId::of("/datum");
                    if lexical == root && row.path != datum && by_path.contains_key(&datum) {
                        by_path[&datum]
                    } else {
                        by_path[&lexical]
                    }
                })
        };
        if parent.map(|id| id.0) != row.parent
            || row.explicit != explicit.contains_key(&row.path)
            || row.synthetic == declared.contains(&row.path)
        {
            return Err(invalid());
        }
        types.push(TypeNode {
            path: row.path,
            parent,
            explicit_parent: row.explicit,
            synthetic: row.synthetic,
            members: Arc::from([]),
        });
    }
    let fields = seed.map_or(&[][..], |s| s.fields.as_ref());
    let intrinsics = seed.map_or(&[][..], |s| s.intrinsics.as_ref());
    let mut tree = SemanticTree {
        symbols: Arc::new(symbols),
        types: types.into(),
        members: Arc::from([]),
        by_path,
        direct: HashMap::new(),
        declaration_targets: Arc::from([]),
        identity: crate::declaration_identity(&all, fields),
        inventory: resolver::ResolverInventory::default(),
        intrinsic_fields: Arc::new(
            fields
                .iter()
                .map(|f| ((f.owner, f.name), f.clone()))
                .collect(),
        ),
    };
    let callable = callable_namespace::collect(&all, intrinsics).map_err(|_| invalid())?;
    let mut targets = Vec::new();
    let mut members = Vec::new();
    let mut originals = Vec::new();
    let mut groups: HashMap<_, Vec<MemberId>> = HashMap::new();
    let mut owned = vec![Vec::new(); tree.types.len()];
    for source in &adapted.skeletons {
        match source {
            Skeleton::Type { path, .. } => {
                targets.push(Target::Type(*tree.by_path.get(path).ok_or_else(invalid)?))
            }
            Skeleton::Member {
                owner,
                name,
                kind,
                mode,
                metadata,
                content,
            } => {
                let id = MemberId(members.len() as u32);
                let row = record.members.get(id.index()).ok_or_else(invalid)?;
                let owner = tree.by_path[owner];
                let kind = callable_namespace::effective_kind(
                    &tree, owner, *name, *kind, *mode, root, &callable,
                );
                if row.owner != owner.0
                    || row.name != *name
                    || row.kind != kind
                    || row.definition != *mode
                    || row.content != *content
                {
                    return Err(invalid());
                }
                members.push(MemberNode {
                    definition: *mode,
                    owner,
                    name: *name,
                    kind,
                    metadata: Arc::new(metadata.clone()),
                    content: *content,
                    previous: row.previous.map(MemberId),
                });
                originals.push(metadata.clone());
                groups.entry((owner, *name, kind)).or_default().push(id);
                owned[owner.index()].push(id);
                targets.push(Target::Member(id));
            }
        }
    }
    if members.len() != record.members.len() {
        return Err(invalid());
    }
    let mut expected_previous = vec![None; members.len()];
    for (group, ids) in groups {
        let mut formals = ids
            .iter()
            .filter(|id| members[id.index()].definition == DefinitionMode::Declare);
        let formal = formals.next().copied();
        if formals.next().is_some() {
            return Err(invalid());
        }
        let chain: Vec<_> = formal
            .into_iter()
            .chain(ids.into_iter().filter(|id| Some(*id) != formal))
            .collect();
        for pair in chain.windows(2) {
            expected_previous[pair[1].index()] = Some(pair[0]);
        }
        if let Some(last) = chain.last() {
            tree.direct.insert(group, *last);
        }
    }
    for (i, node) in members.iter().enumerate() {
        if expected_previous[i].is_none() {
            let mut parent = tree.parent(node.owner);
            while let Some(owner) = parent {
                if tree.types[owner.index()].path == root {
                    break;
                }
                if let Some(id) = tree.direct.get(&(owner, node.name, node.kind)) {
                    expected_previous[i] = Some(*id);
                    break;
                }
                parent = tree.parent(owner);
            }
        }
        if node.previous != expected_previous[i] {
            return Err(invalid());
        }
        callable_namespace::validate_explicit(&tree, node, node.definition, root, &callable)
            .map_err(|_| invalid())?;
    }
    let mut complete = vec![false; members.len()];
    for start in 0..members.len() {
        let mut pending = Vec::new();
        let mut current = Some(start);
        while let Some(i) = current {
            if complete[i] {
                break;
            }
            pending.push(i);
            current = members[i].previous.map(MemberId::index);
        }
        for i in pending.into_iter().rev() {
            let node = &members[i];
            let mut expected = originals[i].clone();
            if node.kind == MemberKind::Var && node.definition == DefinitionMode::Override {
                if let Some(previous) = node.previous {
                    let inherited = &members[previous.index()].metadata;
                    expected.inherited_opaque = inherited.inherited_opaque.clone();
                    expected.declared_type = inherited.declared_type;
                    expected.list_element_type = inherited.list_element_type;
                    expected.flags = inherited.flags;
                    expected.array = inherited.array.clone();
                    expected.declared_initializer = inherited.declared_initializer.clone();
                } else {
                    let mut current = Some(node.owner);
                    while let Some(owner) = current {
                        if let Some(field) = tree
                            .intrinsic_fields
                            .get(&(tree.types[owner.index()].path, node.name))
                        {
                            expected.inherited_opaque = Some(field.clone());
                            expected.declared_type = match field.declared_type {
                                dm_ir::DeclaredTypeKnowledge::Known(path) => Some(path),
                                _ => None,
                            };
                            break;
                        }
                        current = tree.parent(owner);
                    }
                }
            }
            if node.definition == DefinitionMode::Override
                && node.previous.is_none()
                && expected.inherited_opaque.is_none()
            {
                return Err(invalid());
            }
            members[i].metadata = Arc::new(expected);
            complete[i] = true;
        }
    }
    for (expected, stored) in targets.iter().zip(&record.targets) {
        if !match (expected, stored) {
            (Target::Type(a), TargetRow::Type(b)) => a.0 == *b,
            (Target::Member(a), TargetRow::Member(b)) => a.0 == *b,
            _ => false,
        } {
            return Err(invalid());
        }
    }
    for (node, ids) in Arc::make_mut(&mut tree.types).iter_mut().zip(owned) {
        node.members = ids.into();
    }
    tree.members = members.into();
    tree.declaration_targets = targets.into();
    tree.rebuild_inventory();
    if let Some(seed) = seed {
        tree = tree
            .with_engine_intrinsics(hierarchy.ok_or_else(invalid)?, seed.intrinsics.to_vec())
            .map_err(|_| invalid())?;
    }
    if tree.identity != record.identity {
        return Err(invalid());
    }
    Ok(tree)
}
