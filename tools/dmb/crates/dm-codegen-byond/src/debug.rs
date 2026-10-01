//! Procedure-local source anchors. Cached code contains no absolute source offset
//! or filename; the current compilation supplies provenance at link time.
use crate::{Instruction, Item as CodeItem, SimpleProc, Symbol, SymbolicProc, Table, Word};
use byond_dmb::bytecode::opcode;
use dm_syntax::{Item, Span};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RelativeStatementSpan {
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct StatementOrigin {
    /// Position in the original symbolic item sequence, including labels.
    pub code_item: usize,
    /// Byte span relative to the first lowered body's header start.
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedStatementOrigin {
    pub file: String,
    pub line: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DebugOriginError(pub String);

pub fn body_span_base(body: &[Item]) -> usize {
    body.first().map_or(0, |item| item.header_span.start)
}

/// Keep internal location changes observable while uniform upstream movement
/// preserves cached source anchors. Headers and AST shape are separately hashed.
pub fn relative_body_span_shape(body: &[Item]) -> Vec<[i64; 4]> {
    fn visit(items: &[Item], base: i64, output: &mut Vec<[i64; 4]>) {
        for item in items {
            output.push([
                item.header_span.start as i64 - base,
                item.header_span.end as i64 - base,
                item.span.start as i64 - base,
                item.span.end as i64 - base,
            ]);
            visit(&item.children, base, output);
        }
    }
    let mut output = Vec::new();
    visit(body, body_span_base(body) as i64, &mut output);
    output
}

pub(crate) fn relative_span(span: Span, base: usize) -> Option<(usize, usize)> {
    Some((span.start.checked_sub(base)?, span.end.checked_sub(base)?))
}

/// Locate the first matching symbolic reference in the original, uninstrumented
/// body. Default arguments preceding the first statement anchor remain unlocated
/// so the caller can explicitly map their authored header instead.
pub fn reference_origin(
    procedure: &SimpleProc,
    table: Table,
    key: &str,
) -> Option<RelativeStatementSpan> {
    let mut marks = procedure.statement_origins.iter().peekable();
    let mut current = None;
    for (index, item) in procedure.code.items.iter().enumerate() {
        while marks.peek().is_some_and(|mark| mark.code_item <= index) {
            let mark = marks.next()?;
            if mark.end < mark.start {
                return None;
            }
            current = Some(RelativeStatementSpan {
                start: mark.start,
                end: mark.end,
            });
        }
        if let CodeItem::Instruction(instruction) = item {
            let mut found = false;
            for operand in &instruction.operands {
                operand.for_each_reference(&mut |found_table, found_key| {
                    found |= found_table == table && found_key == key;
                });
            }
            if found {
                return current;
            }
        }
    }
    None
}

/// Instrument symbolic code before relocation, preserving branch labels. Resolve
/// offsets against the current body and preprocessor origins, never cached spans.
/// Each marked block sets both file and line, including cross-file jump targets.
/// Unknown origins remain uninstrumented; invalid supplied origins are errors.
pub fn with_statement_debug(
    procedure: &SimpleProc,
    mut resolve: impl FnMut(usize) -> Option<ResolvedStatementOrigin>,
) -> Result<SymbolicProc, DebugOriginError> {
    let mut result = SymbolicProc::default();
    let mut marks = procedure.statement_origins.iter().peekable();
    let mut previous = None;
    for (index, item) in procedure.code.items.iter().enumerate() {
        if let Some(mark) = marks.peek().filter(|mark| mark.code_item == index) {
            if previous.is_some_and(|previous| previous >= index)
                || mark.end < mark.start
                || !matches!(item, CodeItem::Instruction(_))
            {
                return Err(DebugOriginError(format!(
                    "invalid statement anchor at item {index}"
                )));
            }
            if let Some(origin) = resolve(mark.start) {
                if origin.file.is_empty() || origin.line == 0 {
                    return Err(DebugOriginError(format!(
                        "invalid source origin at item {index}"
                    )));
                }
                result.items.push(CodeItem::Instruction(Instruction {
                    opcode: opcode::DBG_FILE,
                    operands: vec![Word::Reference(Symbol::new(Table::String, origin.file))],
                }));
                result.items.push(CodeItem::Instruction(Instruction {
                    opcode: opcode::DBG_LINE,
                    operands: vec![Word::Immediate(origin.line)],
                }));
            }
            previous = Some(index);
            marks.next();
        }
        result.items.push(item.clone());
    }
    if marks.next().is_some() {
        return Err(DebugOriginError(
            "statement anchors must be ordered and inside the code body".into(),
        ));
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{compile_simple_proc, link_proc, Ledger};
    fn body(text: &str) -> Vec<Item> {
        dm_syntax::parse(text).items.remove(0).children
    }
    #[test]
    fn nested_errors_keep_their_exact_statement_anchor_in_both_lowering_paths() {
        let bindings = crate::LowerBindings {
            shared: Some(std::sync::Arc::new(Default::default())),
            ..Default::default()
        };
        for (source, failing) in [
            (
                "/proc/test()\n    var/value = 1\n    if(value)\n        return missing()\n",
                "return missing",
            ),
            (
                "/proc/test()\n    while(1)\n        not DM syntax ???\n",
                "not DM syntax",
            ),
        ] {
            let items = body(source);
            let errors = crate::compile_simple_proc_with_bindings(&items, &bindings).unwrap_err();
            assert_eq!(errors.len(), 1);
            assert_eq!(
                errors[0].statement_origin.unwrap().start,
                source.find(failing).unwrap() - body_span_base(&items)
            );
        }
    }
    #[test]
    fn missing_class_reference_uses_the_original_symbolic_statement_anchor() {
        let source = "/proc/test()\n    var/value = 1\n    return new /datum/missing\n";
        let items = body(source);
        let procedure = compile_simple_proc(&items).unwrap();
        let origin = reference_origin(&procedure, Table::Class, "/datum/missing").unwrap();
        assert_eq!(
            origin.start,
            source.find("return new").unwrap() - body_span_base(&items)
        );
        assert_eq!(
            reference_origin(&procedure, Table::Class, "/datum/unreferenced"),
            None
        );
    }
    #[test]
    fn source_anchors_rebase_but_internal_line_moves_change_shape() {
        let original = body("/proc/test()\n    var/list/items = list()\n    return items[3]\n");
        let shifted =
            body("// upstream\n\n/proc/test()\n    var/list/items = list()\n    return items[3]\n");
        let internal = body("/proc/test()\n    var/list/items = list()\n\n    return items[3]\n");
        assert_eq!(
            relative_body_span_shape(&original),
            relative_body_span_shape(&shifted)
        );
        assert_ne!(
            relative_body_span_shape(&original),
            relative_body_span_shape(&internal)
        );
        let first = compile_simple_proc(&original).unwrap();
        let second = compile_simple_proc(&shifted).unwrap();
        assert_eq!(first, second);
        assert!(first.statement_origins.len() >= 2);
        let mut ledger = Ledger::default();
        ledger
            .bind(Symbol::new(Table::String, "code/test.dm"), 12)
            .unwrap();
        let resolve = |offset| {
            Some(ResolvedStatementOrigin {
                file: "code/test.dm".into(),
                line: if offset == 0 { 2 } else { 3 },
            })
        };
        let linked = link_proc(&with_statement_debug(&first, resolve).unwrap(), &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let index = decoded
            .iter()
            .position(|item| item.opcode == opcode::LIST_GET)
            .unwrap();
        assert!(decoded[..index]
            .iter()
            .rev()
            .any(|item| item.opcode == opcode::DBG_LINE && item.operands == [3]));
    }
    #[test]
    fn branch_targets_enter_debug_markers_and_invalid_anchors_fail() {
        let source = body("/proc/test()\n    var/value = 1\n    while(value)\n        value = 0\n    return value\n");
        let procedure = compile_simple_proc(&source).unwrap();
        let instrumented = with_statement_debug(&procedure, |offset| {
            Some(ResolvedStatementOrigin {
                file: "code/test.dm".into(),
                line: offset as u32 + 1,
            })
        })
        .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(Symbol::new(Table::String, "code/test.dm"), 12)
            .unwrap();
        let linked = link_proc(&instrumented, &ledger).unwrap();
        for instruction in byond_dmb::bytecode::decode(&linked.words).unwrap() {
            if byond_dmb::bytecode::is_branch_opcode(instruction.opcode) {
                let destination = instruction.operands[0] as usize;
                assert_eq!(linked.words[destination], opcode::DBG_FILE);
            }
        }
        let mut corrupt = procedure.clone();
        corrupt.statement_origins[0].code_item = usize::MAX;
        assert!(with_statement_debug(&corrupt, |_| None).is_err());
    }
}
