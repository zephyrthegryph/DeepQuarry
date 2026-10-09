//! Captured symbolic map planning. All input bytes are supplied by the caller;
//! queries perform no filesystem reads and assign no BYOND table IDs/defaults.
use dm_ir::map::{MapAssignment, MapAtom, MapBlock, MapRecord, MapTemplate, SymbolicMap};
use dm_ir::{SymbolTable, TypePath};
use dm_syntax::{Span, SpanToken, TokenKind};
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct CapturedMap {
    pub path: Arc<PathBuf>,
    pub include_occurrence: u32,
    pub source: Arc<str>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AssignmentOrigin {
    pub span: Span,
    pub value_span: Span,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AtomOrigin {
    pub span: Span,
    pub type_span: Span,
    pub assignments: Arc<[AssignmentOrigin]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TemplateOrigin {
    pub span: Span,
    pub key_span: Span,
    pub payload_span: Span,
    pub atoms: Arc<[AtomOrigin]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BlockOrigin {
    pub span: Span,
    pub cells_span: Span,
}
#[derive(Clone, Debug)]
pub struct MapPlan {
    pub captured: CapturedMap,
    pub source_identity: u128,
    pub semantic_identity: u128,
    pub model: Arc<SymbolicMap>,
    /// Only this map's spellings; no full project symbol-table copy per map.
    /// The caller collision-checks these extensions when composing its ledger.
    pub symbols: Arc<SymbolTable>,
    pub template_origins: Arc<[TemplateOrigin]>,
    pub block_origins: Arc<[BlockOrigin]>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DiagnosticKind {
    Syntax,
    UnsupportedModel,
    Internal,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MapDiagnostic {
    pub kind: DiagnosticKind,
    pub span: Span,
    pub message: String,
}
fn diagnostic(kind: DiagnosticKind, span: Span, message: impl Into<String>) -> MapDiagnostic {
    MapDiagnostic {
        kind,
        span,
        message: message.into(),
    }
}
fn origin(source: &str, part: &str) -> Span {
    let start = part.as_ptr() as usize - source.as_ptr() as usize;
    Span::new(start, start + part.len())
}
fn significant(source: &str, offset: usize) -> Result<Vec<SpanToken>, MapDiagnostic> {
    let lexed = dm_syntax::lex_spans(source);
    if let Some(error) = lexed.diagnostics.first() {
        return Err(diagnostic(
            DiagnosticKind::Syntax,
            Span::new(offset + error.span.start, offset + error.span.end),
            &error.message,
        ));
    }
    Ok(lexed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect())
}
/// Split using lexer tokens, so resource/string interpolation contents and
/// nested lists/modified types cannot masquerade as atom/assignment separators.
fn segments<'a>(
    source: &'a str,
    separator: &str,
    offset: usize,
) -> Result<Vec<&'a str>, MapDiagnostic> {
    let tokens = significant(source, offset)?;
    let mut nesting = Vec::new();
    let mut start = 0;
    let mut output = Vec::new();
    for token in tokens {
        let text = token.text(source);
        match text {
            "(" | "[" | "{" => nesting.push(text),
            ")" | "]" | "}" => {
                let expected = match text {
                    ")" => "(",
                    "]" => "[",
                    _ => "{",
                };
                if nesting.pop() != Some(expected) {
                    return Err(diagnostic(
                        DiagnosticKind::Syntax,
                        Span::new(offset + token.span.start, offset + token.span.end),
                        "unmatched map payload delimiter",
                    ));
                }
            }
            _ if text == separator && nesting.is_empty() => {
                output.push(&source[start..token.span.start]);
                start = token.span.end;
            }
            _ => {}
        }
    }
    if !nesting.is_empty() {
        return Err(diagnostic(
            DiagnosticKind::Syntax,
            Span::new(offset, offset + source.len()),
            "unterminated map payload delimiter",
        ));
    }
    output.push(&source[start..]);
    Ok(output)
}
fn intern(
    symbols: &mut SymbolTable,
    text: &str,
    span: Span,
) -> Result<dm_ir::SymbolId, MapDiagnostic> {
    symbols
        .intern(text)
        .map_err(|error| diagnostic(DiagnosticKind::Internal, span, error.to_string()))
}
fn assignment(
    source: &str,
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<(MapAssignment, AssignmentOrigin), MapDiagnostic> {
    let text = text.trim();
    let span = origin(source, text);
    let equal = dm_syntax::top_level_assignment_index(text).ok_or_else(|| {
        diagnostic(
            DiagnosticKind::UnsupportedModel,
            span,
            "unsupported map atom assignment",
        )
    })?;
    let name = text[..equal].trim();
    let name_tokens = significant(name, span.start)?;
    if name_tokens.len() != 1 || name_tokens[0].kind != TokenKind::Ident {
        return Err(diagnostic(
            DiagnosticKind::UnsupportedModel,
            span,
            "unsupported map field target",
        ));
    }
    let value_text = text[equal + 1..].trim();
    let value_span = origin(source, value_text);
    let value = crate::procedure::expression(value_text, symbols)
        .map_err(|message| diagnostic(DiagnosticKind::UnsupportedModel, value_span, message))?;
    Ok((
        MapAssignment {
            name: intern(symbols, name_tokens[0].text(name), span)?,
            value,
        },
        AssignmentOrigin { span, value_span },
    ))
}
fn atom(
    source: &str,
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<(MapAtom, AtomOrigin), MapDiagnostic> {
    let text = text.trim();
    let span = origin(source, text);
    let tokens = significant(text, span.start)?;
    let opener = tokens.iter().position(|token| token.text(text) == "{");
    let type_end = opener.map_or(text.len(), |index| tokens[index].span.start);
    let type_text = text[..type_end].trim();
    let type_span = origin(source, type_text);
    let type_tokens = significant(type_text, type_span.start)?;
    let normalized_type = type_tokens
        .iter()
        .map(|token| token.text(type_text))
        .collect::<String>();
    TypePath::parse(&normalized_type)
        .map_err(|message| diagnostic(DiagnosticKind::UnsupportedModel, type_span, message))?;
    if normalized_type != "/"
        && (type_tokens.len() % 2 != 0
            || type_tokens.iter().enumerate().any(|(index, token)| {
                if index % 2 == 0 {
                    token.text(type_text) != "/"
                } else {
                    token.kind != TokenKind::Ident
                }
            }))
    {
        return Err(diagnostic(
            DiagnosticKind::UnsupportedModel,
            type_span,
            "unsupported map atom type path",
        ));
    }
    let mut assignments = Vec::new();
    let mut assignment_origins = Vec::new();
    if let Some(open) = opener {
        let mut depth = 0;
        let mut close = None;
        for (index, token) in tokens.iter().enumerate().skip(open) {
            match token.text(text) {
                "{" => depth += 1,
                "}" => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(index);
                        break;
                    }
                }
                _ => {}
            }
        }
        let close = close.ok_or_else(|| {
            diagnostic(
                DiagnosticKind::Syntax,
                span,
                "unterminated map atom overrides",
            )
        })?;
        if close + 1 != tokens.len() {
            return Err(diagnostic(
                DiagnosticKind::UnsupportedModel,
                span,
                "unsupported text after map atom overrides",
            ));
        }
        let payload = &text[tokens[open].span.end..tokens[close].span.start];
        let parts = segments(payload, ";", origin(source, payload).start)?;
        for (index, part) in parts.iter().enumerate() {
            if significant(part, origin(source, part).start)?.is_empty() {
                if index + 1 != parts.len() {
                    return Err(diagnostic(
                        DiagnosticKind::Syntax,
                        origin(source, part),
                        "empty map assignment",
                    ));
                }
                continue;
            }
            let (value, provenance) = assignment(source, part, symbols)?;
            assignments.push(value);
            assignment_origins.push(provenance);
        }
    }
    Ok((
        MapAtom {
            type_path: intern(symbols, &normalized_type, type_span)?,
            initializer_present: opener.is_some(),
            assignments: assignments.into(),
        },
        AtomOrigin {
            span,
            type_span,
            assignments: assignment_origins.into(),
        },
    ))
}

fn complete_record_spans(
    source: &str,
    syntax: &dm_syntax::map::MapSyntax<'_>,
    tokens: &[SpanToken],
) -> Result<(Vec<Span>, Vec<Span>), MapDiagnostic> {
    let mut templates = Vec::new();
    for template in &syntax.templates {
        let key = tokens
            .get(tokens.partition_point(|token| token.span.end <= template.key_span.start))
            .filter(|token| {
                token.span.start <= template.key_span.start
                    && token.span.end >= template.key_span.end
            })
            .ok_or_else(|| {
                diagnostic(
                    DiagnosticKind::Internal,
                    template.key_span,
                    "map key has no lexical source",
                )
            })?;
        templates.push(Span::new(key.span.start, template.payload_span.end + 1));
    }
    let mut blocks = Vec::new();
    for block in &syntax.blocks {
        let index = tokens.partition_point(|token| token.span.end <= block.cells_span.start);
        let _cells = tokens
            .get(index)
            .filter(|token| {
                token.kind == TokenKind::String
                    && token.span.start <= block.cells_span.start
                    && token.span.end >= block.cells_span.end
            })
            .ok_or_else(|| {
                diagnostic(
                    DiagnosticKind::Internal,
                    block.cells_span,
                    "map cells have no lexical source",
                )
            })?;
        if index < 8 {
            return Err(diagnostic(
                DiagnosticKind::Internal,
                block.cells_span,
                "map block has no coordinate source",
            ));
        }
        blocks.push(Span::new(
            tokens[index - 8].span.start,
            tokens[index].span.end,
        ));
    }
    let mut spans: Vec<_> = templates.iter().chain(&blocks).copied().collect();
    spans.sort_by_key(|span| span.start);
    if spans.windows(2).any(|pair| pair[0].end > pair[1].start) {
        return Err(diagnostic(
            DiagnosticKind::UnsupportedModel,
            Span::new(0, source.len()),
            "overlapping map records",
        ));
    }
    let mut record = 0;
    for token in tokens {
        while record < spans.len() && token.span.start >= spans[record].end {
            record += 1;
        }
        if record == spans.len()
            || token.span.start < spans[record].start
            || token.span.end > spans[record].end
        {
            return Err(diagnostic(
                DiagnosticKind::UnsupportedModel,
                token.span,
                "unrecognized map record syntax",
            ));
        }
    }
    Ok((templates, blocks))
}

pub fn plan(captured: CapturedMap) -> Result<MapPlan, MapDiagnostic> {
    let source = captured.source.as_ref();
    let syntax = dm_syntax::map::parse_map(source)
        .map_err(|error| diagnostic(DiagnosticKind::Syntax, error.span, error.message))?;
    let tokens = significant(source, 0)?;
    let (template_spans, block_spans) = complete_record_spans(source, &syntax, &tokens)?;
    let mut symbols = SymbolTable::default();
    let mut templates = Vec::new();
    let mut template_origins = Vec::new();
    for (index, template) in syntax.templates.iter().enumerate() {
        let parts = segments(template.payload, ",", template.payload_span.start)?;
        let mut atoms = Vec::new();
        let mut origins = Vec::new();
        for (part_index, part) in parts.iter().enumerate() {
            if significant(part, origin(source, part).start)?.is_empty() {
                if part_index + 1 != parts.len() {
                    return Err(diagnostic(
                        DiagnosticKind::Syntax,
                        origin(source, part),
                        "empty map atom",
                    ));
                }
                continue;
            }
            let (value, provenance) = atom(source, part, &mut symbols)?;
            atoms.push(value);
            origins.push(provenance);
        }
        templates.push(MapTemplate {
            key: Arc::from(template.key),
            atoms: atoms.into(),
        });
        template_origins.push(TemplateOrigin {
            span: template_spans[index],
            key_span: template.key_span,
            payload_span: template.payload_span,
            atoms: origins.into(),
        });
    }
    let key_width = templates
        .first()
        .map(|template| template.key.len() as u64)
        .filter(|width| {
            templates
                .iter()
                .all(|template| template.key.len() as u64 == *width)
        });
    let blocks = syntax
        .blocks
        .iter()
        .map(|block| MapBlock {
            origin: block.axes.map(|coordinate| coordinate as u64),
            cells: Arc::from(block.cells),
        })
        .collect::<Vec<_>>();
    let block_origins = syntax
        .blocks
        .iter()
        .enumerate()
        .map(|(index, block)| BlockOrigin {
            span: block_spans[index],
            cells_span: block.cells_span,
        })
        .collect::<Vec<_>>();
    let records = syntax
        .records
        .iter()
        .map(|record| match *record {
            dm_syntax::map::MapRecord::Template(index) => MapRecord::Template(index),
            dm_syntax::map::MapRecord::Block(index) => MapRecord::Block(index),
        })
        .collect::<Vec<_>>();
    let model = SymbolicMap {
        templates: templates.into(),
        blocks: blocks.into(),
        records: records.into(),
        key_width,
    };
    let semantic_identity = xxhash_rust::xxh3::xxh3_128(&model.canonical_bytes());
    let source_identity = xxhash_rust::xxh3::xxh3_128(source.as_bytes());
    Ok(MapPlan {
        captured,
        source_identity,
        semantic_identity,
        model: Arc::new(model),
        symbols: Arc::new(symbols),
        template_origins: template_origins.into(),
        block_origins: block_origins.into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::SymbolId;
    fn input(source: &str) -> CapturedMap {
        CapturedMap {
            path: Arc::new(PathBuf::from("maps/probe.dmm")),
            include_occurrence: 3,
            source: Arc::from(source),
        }
    }
    #[test]
    fn empty_initializer_presence_is_semantic_not_invented() {
        let omitted = plan(input("\"a\"=(/obj)\n(1,1,1)={\"a\"}")).unwrap();
        let empty = plan(input("\"a\"=(/obj{})\n(1,1,1)={\"a\"}")).unwrap();
        assert!(!omitted.model.templates[0].atoms[0].initializer_present);
        assert!(empty.model.templates[0].atoms[0].initializer_present);
        assert!(empty.model.templates[0].atoms[0].assignments.is_empty());
        assert_ne!(omitted.semantic_identity, empty.semantic_identity);
    }
    #[test]
    fn authored_map_order_coordinates_assignments_and_sources_are_preserved() {
        let source = "\"z\"=(/obj/probe{value=list(1,2);value=3;message=\"text [call(\"a,b\")]\"},/turf,/area)\n(2,3,4)={\"\nz\n\"}\n\"a\"=(/turf,/area)\n(1,1,1)={\"a\"}";
        let plan = plan(input(source)).unwrap();
        assert_eq!(
            plan.model.records.as_ref(),
            &[
                MapRecord::Template(0),
                MapRecord::Block(0),
                MapRecord::Template(1),
                MapRecord::Block(1)
            ]
        );
        assert_eq!(plan.model.templates[0].key.as_ref(), "z");
        assert_eq!(plan.model.key_width, Some(1));
        assert_eq!(plan.model.blocks[0].origin, [2, 3, 4]);
        assert_eq!(plan.model.blocks[0].cells.as_ref(), "\nz\n");
        let atom = &plan.model.templates[0].atoms[0];
        assert_eq!(atom.type_path, SymbolId::of("/obj/probe"));
        assert_eq!(atom.assignments.len(), 3);
        assert_eq!(atom.assignments[0].name, atom.assignments[1].name);
        assert_eq!(atom.assignments[0].name, SymbolId::of("value"));
        let origin = &plan.template_origins[0].atoms[0].assignments[1];
        assert_eq!(&source[origin.value_span.range()], "3");
        assert_eq!(plan.captured.include_occurrence, 3);
    }
    #[test]
    fn comments_change_source_identity_without_changing_symbolic_meaning() {
        let first = plan(input("\"a\"=(/obj{value=1},/turf,/area)\n(1,1,1)={\"a\"}")).unwrap();
        let second = plan(input("// captured source\n\"a\" = ( /obj /* type */ { value /* field */ = 1 }, /turf, /area )\n(1,1,1)={\"a\"}")).unwrap();
        assert_eq!(first.semantic_identity, second.semantic_identity);
        assert_ne!(first.source_identity, second.source_identity);
        assert_eq!(
            second.model.templates[0].atoms[0].assignments[0].name,
            SymbolId::of("value")
        );
        assert!(second.symbols.text(SymbolId::of("/obj")).is_some());
        assert_ne!(
            first.template_origins[0].span,
            second.template_origins[0].span
        );
    }
    #[test]
    fn omitted_defaults_and_nonuniform_keys_are_not_filled_or_guessed() {
        let plan = plan(input("\"a\"=(/obj)\n\"bb\"=()\n(1,1,1)={\"a\"}")).unwrap();
        assert_eq!(plan.model.key_width, None);
        assert_eq!(plan.model.templates[0].atoms.len(), 1);
        assert!(plan.model.templates[0].atoms[0].assignments.is_empty());
        assert!(plan.model.templates[1].atoms.is_empty());
    }
    #[test]
    fn scanner_skipped_records_and_unrepresentable_targets_are_explicit() {
        for source in [
            "ignored\n\"a\"=(/turf)",
            "\"a\"=(/obj{value[1]=2})",
            "\"a\"=(/obj{value=1} garbage)",
        ] {
            assert_eq!(
                plan(input(source)).unwrap_err().kind,
                DiagnosticKind::UnsupportedModel,
                "{source}"
            );
        }
        assert_eq!(
            plan(input("\"a\"=(/obj{value=list(1,2]}"))
                .unwrap_err()
                .kind,
            DiagnosticKind::Syntax
        );
    }
}
