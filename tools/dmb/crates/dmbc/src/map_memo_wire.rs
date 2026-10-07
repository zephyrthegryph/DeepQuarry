//! Private versioned S5 DTOs. Arena IDs, resolver pointers and wire table IDs
//! cannot be represented here. Cache checksums precede these structural checks.
use super::*;
use crate::map_projection::{AtomOrigin, GridRun, Instance, InstanceKind, PlacedObject};
use dm_ir::map::{MapAssignment, MapAtom, MapBlock, MapRecord, MapTemplate, SymbolicMap};
use dm_ir::{ExpressionToken, ResolveQuery, SymbolId, SymbolTable, SymbolicExpression};
use dm_syntax::{Span, TokenKind};
use dm_tree::maps::{AssignmentOrigin, BlockOrigin, TemplateOrigin};
use serde::{Deserialize, Serialize};

type Bounds = [usize; 2];
const MAGIC: &[u8; 8] = b"DMBCMAP2";
/// The exact binary key is framed once, rather than serialized as JSON numbers.
/// Both syntax and geometry DTOs use this envelope; stage/version chooses type.
fn encode(key: &[u8], payload: &impl Serialize) -> Option<Vec<u8>> {
    let json = dm_wire::encode(1, payload).ok()?;
    let capacity = 16usize.checked_add(key.len())?.checked_add(json.len())?;
    let mut bytes = Vec::with_capacity(capacity);
    bytes.extend_from_slice(MAGIC);
    bytes.extend_from_slice(&(key.len() as u64).to_le_bytes());
    bytes.extend_from_slice(key);
    bytes.extend_from_slice(&json);
    Some(bytes)
}
fn envelope(bytes: &[u8]) -> Option<(&[u8], &[u8])> {
    if bytes.get(..8)? != MAGIC {
        return None;
    }
    let length = usize::try_from(u64::from_le_bytes(bytes.get(8..16)?.try_into().ok()?)).ok()?;
    let end = 16usize.checked_add(length)?;
    Some((bytes.get(16..end)?, bytes.get(end..)?))
}
#[derive(Serialize, Deserialize)]
struct Assignment {
    name: SymbolId,
    tokens: Vec<(u8, SymbolId, Bounds)>,
    span: Bounds,
    value: Bounds,
}
#[derive(Serialize, Deserialize)]
struct Atom {
    path: SymbolId,
    initializer: bool,
    span: Bounds,
    type_span: Bounds,
    assignments: Vec<Assignment>,
}
#[derive(Serialize, Deserialize)]
struct Template {
    key: String,
    span: Bounds,
    key_span: Bounds,
    payload: Bounds,
    atoms: Vec<Atom>,
}
#[derive(Serialize, Deserialize)]
struct Block {
    origin: [u64; 3],
    cells: String,
    span: Bounds,
    cells_span: Bounds,
}
#[derive(Serialize, Deserialize)]
struct Parse {
    version: u32,
    source: String,
    semantic: u128,
    symbols: Vec<(SymbolId, String)>,
    templates: Vec<Template>,
    blocks: Vec<Block>,
    records: Vec<(u8, usize)>,
    key_width: Option<u64>,
}
fn bounds(span: Span) -> Bounds {
    [span.start, span.end]
}
fn span(value: Bounds, source: &str) -> Option<Span> {
    source.get(value[0]..value[1])?;
    Some(Span::new(value[0], value[1]))
}
fn token_kind(kind: TokenKind) -> u8 {
    match kind {
        TokenKind::Ident => 0,
        TokenKind::Number => 1,
        TokenKind::String => 2,
        TokenKind::Resource => 3,
        TokenKind::Interpolation => 4,
        TokenKind::Operator => 5,
        TokenKind::Punctuation => 6,
        TokenKind::Whitespace => 7,
        TokenKind::Newline => 8,
        TokenKind::Comment => 9,
        TokenKind::Unknown => 10,
    }
}
fn kind(value: u8) -> Option<TokenKind> {
    Some(match value {
        0 => TokenKind::Ident,
        1 => TokenKind::Number,
        2 => TokenKind::String,
        3 => TokenKind::Resource,
        4 => TokenKind::Interpolation,
        5 => TokenKind::Operator,
        6 => TokenKind::Punctuation,
        _ => return None,
    })
}
fn invalid() -> String {
    "invalid symbolic map memo payload".to_owned()
}
pub(super) fn encode_parse(key: &[u8], plan: &MapPlan) -> Option<Vec<u8>> {
    let templates = plan
        .model
        .templates
        .iter()
        .zip(plan.template_origins.iter())
        .map(|(template, origin)| Template {
            key: template.key.to_string(),
            span: bounds(origin.span),
            key_span: bounds(origin.key_span),
            payload: bounds(origin.payload_span),
            atoms: template
                .atoms
                .iter()
                .zip(origin.atoms.iter())
                .map(|(atom, origin)| Atom {
                    path: atom.type_path,
                    initializer: atom.initializer_present,
                    span: bounds(origin.span),
                    type_span: bounds(origin.type_span),
                    assignments: atom
                        .assignments
                        .iter()
                        .zip(origin.assignments.iter())
                        .map(|(assignment, origin)| Assignment {
                            name: assignment.name,
                            span: bounds(origin.span),
                            value: bounds(origin.value_span),
                            tokens: assignment
                                .value
                                .tokens
                                .iter()
                                .map(|token| {
                                    (
                                        token_kind(token.kind),
                                        token.text,
                                        bounds(token.relative_span),
                                    )
                                })
                                .collect(),
                        })
                        .collect(),
                })
                .collect(),
        })
        .collect();
    let blocks = plan
        .model
        .blocks
        .iter()
        .zip(plan.block_origins.iter())
        .map(|(block, origin)| Block {
            origin: block.origin,
            cells: block.cells.to_string(),
            span: bounds(origin.span),
            cells_span: bounds(origin.cells_span),
        })
        .collect();
    let payload = Parse {
        version: 1,
        source: plan.captured.source.to_string(),
        semantic: plan.semantic_identity,
        symbols: plan
            .symbols
            .ordered()
            .into_iter()
            .map(|(id, text)| (id, text.to_owned()))
            .collect(),
        templates,
        blocks,
        records: plan
            .model
            .records
            .iter()
            .map(|record| match *record {
                MapRecord::Template(index) => (0, index),
                MapRecord::Block(index) => (1, index),
            })
            .collect(),
        key_width: plan.model.key_width,
    };
    encode(key, &payload)
}
fn parsed(payload: Parse, captured: CapturedMap) -> Option<MapPlan> {
    if payload.version != 1 || payload.source.as_str() != captured.source.as_ref() {
        return None;
    }
    let mut symbols = SymbolTable::default();
    for (id, text) in payload.symbols {
        if SymbolId::of(&text) != id || symbols.intern(&text).ok()? != id {
            return None;
        }
    }
    let mut templates = Vec::new();
    let mut template_origins = Vec::new();
    for template in payload.templates {
        let mut atoms = Vec::new();
        let mut atom_origins = Vec::new();
        for atom in template.atoms {
            let path = atom.path;
            dm_ir::TypePath::parse(symbols.text(path)?).ok()?;
            let mut assignments = Vec::new();
            let mut assignment_origins = Vec::new();
            for assignment in atom.assignments {
                let value_span = span(assignment.value, &captured.source)?;
                let text = captured.source.get(value_span.range())?;
                let name = assignment.name;
                symbols.text(name)?;
                let mut tokens = Vec::new();
                let mut end = 0;
                for (tag, id, relative) in assignment.tokens {
                    let relative_span = span(relative, text)?;
                    let token_text = text.get(relative_span.range())?;
                    let token_id = id;
                    if relative_span.start < end || symbols.text(token_id)? != token_text {
                        return None;
                    }
                    let kind = kind(tag)?;
                    end = relative_span.end;
                    tokens.push(ExpressionToken {
                        kind,
                        text: token_id,
                        relative_span,
                    });
                }
                if tokens.is_empty() {
                    return None;
                }
                assignments.push(MapAssignment {
                    name,
                    value: SymbolicExpression {
                        tokens: tokens.into(),
                    },
                });
                assignment_origins.push(AssignmentOrigin {
                    span: span(assignment.span, &captured.source)?,
                    value_span,
                });
            }
            if !atom.initializer && !assignments.is_empty() {
                return None;
            }
            atoms.push(MapAtom {
                type_path: path,
                initializer_present: atom.initializer,
                assignments: assignments.into(),
            });
            atom_origins.push(dm_tree::maps::AtomOrigin {
                span: span(atom.span, &captured.source)?,
                type_span: span(atom.type_span, &captured.source)?,
                assignments: assignment_origins.into(),
            });
        }
        templates.push(MapTemplate {
            key: template.key.into(),
            atoms: atoms.into(),
        });
        template_origins.push(TemplateOrigin {
            span: span(template.span, &captured.source)?,
            key_span: span(template.key_span, &captured.source)?,
            payload_span: span(template.payload, &captured.source)?,
            atoms: atom_origins.into(),
        });
    }
    let mut blocks = Vec::new();
    let mut block_origins = Vec::new();
    for block in payload.blocks {
        if block.origin.contains(&0) {
            return None;
        }
        blocks.push(MapBlock {
            origin: block.origin,
            cells: block.cells.into(),
        });
        block_origins.push(BlockOrigin {
            span: span(block.span, &captured.source)?,
            cells_span: span(block.cells_span, &captured.source)?,
        });
    }
    let mut records = Vec::new();
    let mut seen_templates = std::collections::BTreeSet::new();
    let mut seen_blocks = std::collections::BTreeSet::new();
    for (tag, index) in payload.records {
        records.push(match tag {
            0 if index < templates.len() && seen_templates.insert(index) => {
                MapRecord::Template(index)
            }
            1 if index < blocks.len() && seen_blocks.insert(index) => MapRecord::Block(index),
            _ => return None,
        });
    }
    if seen_templates.len() != templates.len() || seen_blocks.len() != blocks.len() {
        return None;
    }
    let key_width = templates
        .first()
        .map(|template| template.key.len() as u64)
        .filter(|width| {
            templates
                .iter()
                .all(|template| template.key.len() as u64 == *width)
        });
    if key_width != payload.key_width {
        return None;
    }
    let model = SymbolicMap {
        templates: templates.into(),
        blocks: blocks.into(),
        records: records.into(),
        key_width,
    };
    if xxhash_rust::xxh3::xxh3_128(&model.canonical_bytes()) != payload.semantic {
        return None;
    }
    Some(MapPlan {
        source_identity: xxhash_rust::xxh3::xxh3_128(captured.source.as_bytes()),
        semantic_identity: payload.semantic,
        captured,
        model: Arc::new(model),
        symbols: Arc::new(symbols),
        template_origins: template_origins.into(),
        block_origins: block_origins.into(),
    })
}
pub(super) fn validate_parse(bytes: &[u8]) -> Result<(), String> {
    let (_, json) = envelope(bytes).ok_or_else(invalid)?;
    let payload: Parse = dm_wire::decode(1, json, 32 * 1024 * 1024)?;
    let captured = CapturedMap {
        path: Arc::new(std::path::PathBuf::new()),
        include_occurrence: 0,
        source: Arc::from(payload.source.as_str()),
    };
    parsed(payload, captured).ok_or_else(invalid).map(|_| ())
}
pub(super) fn admit_parse(
    bytes: &[u8],
    key: &[u8],
    captured: CapturedMap,
) -> Result<Option<MapPlan>, String> {
    let (stored, json) = envelope(bytes).ok_or_else(invalid)?;
    let payload: Parse = dm_wire::decode(1, json, 32 * 1024 * 1024)?;
    if stored == key && payload.source.as_str() == captured.source.as_ref() {
        return parsed(payload, captured).ok_or_else(invalid).map(Some);
    }
    // A hash collision/current-source mismatch is a miss, but the old record
    // still needs structural validation before cache.get can admit its segment.
    let original = CapturedMap {
        path: Arc::new(std::path::PathBuf::new()),
        include_occurrence: 0,
        source: Arc::from(payload.source.as_str()),
    };
    parsed(payload, original).ok_or_else(invalid).map(|_| None)
}
#[derive(Serialize, Deserialize)]
struct Geometry {
    version: u32,
    reads: Vec<(ResolveQuery, Vec<u8>)>,
    dimensions: [u16; 3],
    instances: Vec<(u8, SymbolId, Option<[usize; 3]>)>,
    grid: Vec<(usize, usize, u8)>,
    objects: Vec<(u16, usize)>,
}
fn instance_kind(value: u8) -> Option<InstanceKind> {
    Some(match value {
        0 => InstanceKind::Mob,
        1 => InstanceKind::Object,
        2 => InstanceKind::Turf,
        3 => InstanceKind::Area,
        _ => return None,
    })
}
fn instance_tag(value: InstanceKind) -> u8 {
    match value {
        InstanceKind::Mob => 0,
        InstanceKind::Object => 1,
        InstanceKind::Turf => 2,
        InstanceKind::Area => 3,
    }
}
pub(super) fn encode_geometry(
    key: &[u8],
    projection: &Projection,
    reads: &[ResolverRead],
) -> Option<Vec<u8>> {
    encode(
        key,
        &Geometry {
            version: 1,
            reads: reads
                .iter()
                .map(|read| (read.query, read.answer.canonical_bytes()))
                .collect(),
            dimensions: projection.dimensions,
            instances: projection
                .instances
                .iter()
                .map(|instance| {
                    (
                        instance_tag(instance.kind),
                        instance.atom.type_path,
                        instance
                            .origin
                            .map(|origin| [origin.map, origin.template, origin.atom]),
                    )
                })
                .collect(),
            grid: projection
                .grid
                .iter()
                .map(|run| (run.turf, run.area, run.copies))
                .collect(),
            objects: projection
                .objects
                .iter()
                .map(|object| (object.offset, object.instance))
                .collect(),
        },
    )
}
fn check_geometry(payload: &Geometry) -> Result<(), String> {
    if payload.version != 1 || payload.dimensions.contains(&0) || payload.instances.len() < 2 {
        return Err(invalid());
    }
    for (tag, _, _) in &payload.instances {
        instance_kind(*tag).ok_or_else(invalid)?;
    }
    let extent = payload
        .dimensions
        .iter()
        .map(|value| u64::from(*value))
        .product::<u64>();
    let mut count = 0u64;
    for (turf, area, copies) in &payload.grid {
        if *copies == 0
            || payload.instances.get(*turf).map(|instance| instance.0) != Some(2)
            || payload.instances.get(*area).map(|instance| instance.0) != Some(3)
        {
            return Err(invalid());
        }
        count = count.checked_add(u64::from(*copies)).ok_or_else(invalid)?;
    }
    if count != extent {
        return Err(invalid());
    }
    let mut position = 0u64;
    for (offset, instance) in &payload.objects {
        position = position
            .checked_add(u64::from(*offset))
            .ok_or_else(invalid)?;
        if position >= extent
            || !matches!(
                payload.instances.get(*instance).map(|instance| instance.0),
                Some(0 | 1)
            )
        {
            return Err(invalid());
        }
    }
    Ok(())
}
pub(super) fn validate_geometry(bytes: &[u8]) -> Result<(), String> {
    let (_, json) = envelope(bytes).ok_or_else(invalid)?;
    let payload: Geometry = dm_wire::decode(1, json, 32 * 1024 * 1024)?;
    check_geometry(&payload)
}
pub(super) fn admit_geometry<R: Resolver>(
    bytes: &[u8],
    key: &[u8],
    maps: &[MapPlan],
    defaults: WorldDefaults,
    host: &R,
) -> Result<Option<(Projection, Vec<ResolverRead>)>, String> {
    let (stored, json) = envelope(bytes).ok_or_else(invalid)?;
    let payload: Geometry = dm_wire::decode(1, json, 32 * 1024 * 1024)?;
    check_geometry(&payload)?;
    if stored != key {
        return Ok(None);
    }
    Ok(replay_geometry(payload, maps, defaults, host))
}
fn replay_geometry<R: Resolver>(
    payload: Geometry,
    maps: &[MapPlan],
    defaults: WorldDefaults,
    host: &R,
) -> Option<(Projection, Vec<ResolverRead>)> {
    let mut reads = Vec::new();
    for (query, expected) in payload.reads {
        // Only the geometry classifier domain is admitted to this schema.
        if !matches!(query, ResolveQuery::Type(_) | ResolveQuery::Ancestry(_)) {
            return None;
        }
        let answer = host.resolve(query);
        if answer.canonical_bytes() != expected {
            return None;
        }
        reads.push(ResolverRead {
            domain: query.domain(),
            query,
            answer,
        });
    }
    let mut instances = Vec::new();
    for (index, (tag, path, origin)) in payload.instances.into_iter().enumerate() {
        let (atom, origin) = match origin {
            Some([map, template, atom]) => {
                let model = maps
                    .get(map)?
                    .model
                    .templates
                    .get(template)?
                    .atoms
                    .get(atom)?
                    .clone();
                if model.type_path != path {
                    return None;
                }
                (
                    model,
                    Some(AtomOrigin {
                        map,
                        template,
                        atom,
                    }),
                )
            }
            None => {
                if (index, tag, path) != (0, 2, defaults.turf)
                    && (index, tag, path) != (1, 3, defaults.area)
                {
                    return None;
                }
                (
                    MapAtom {
                        type_path: path,
                        initializer_present: false,
                        assignments: Arc::from([]),
                    },
                    None,
                )
            }
        };
        // Every issued kind must be backed by fresh validated classification
        // reads, even if an externally altered record deleted its read ledger.
        let type_read = reads
            .iter()
            .find(|read| read.query == ResolveQuery::Type(atom.type_path))?;
        if !matches!(&type_read.answer,dm_ir::ResolvedMeaning::Symbol(actual) if *actual==atom.type_path)
        {
            return None;
        }
        let ancestry = reads
            .iter()
            .find(|read| read.query == ResolveQuery::Ancestry(atom.type_path))?;
        let dm_ir::ResolvedMeaning::Symbols(chain) = &ancestry.answer else {
            return None;
        };
        let expected = std::iter::once(atom.type_path)
            .chain(chain.iter().copied())
            .find_map(|owner| {
                [("/turf", 2), ("/area", 3), ("/obj", 1), ("/mob", 0)]
                    .into_iter()
                    .find_map(|(name, kind)| (owner == SymbolId::of(name)).then_some(kind))
            })?;
        if expected != tag {
            return None;
        }
        instances.push(Instance {
            kind: instance_kind(tag)?,
            atom,
            origin,
        });
    }
    Some((
        Projection {
            dimensions: payload.dimensions,
            instances: instances.into(),
            grid: payload
                .grid
                .into_iter()
                .map(|(turf, area, copies)| GridRun { turf, area, copies })
                .collect::<Vec<_>>()
                .into(),
            objects: payload
                .objects
                .into_iter()
                .map(|(offset, instance)| PlacedObject { offset, instance })
                .collect::<Vec<_>>()
                .into(),
        },
        reads,
    ))
}
