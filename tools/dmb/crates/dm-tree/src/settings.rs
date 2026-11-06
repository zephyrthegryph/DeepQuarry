//! Ordered, unevaluated procedure settings with compact structural context.
use dm_ir::{ProcedureSettingNode, SymbolTable};
use dm_syntax::{Item, Span};
use std::sync::Arc;

fn keyword(header: &str, word: &str) -> bool {
    header.trim_start().strip_prefix(word).is_some_and(|tail| {
        tail.is_empty() || tail.starts_with(char::is_whitespace) || tail.starts_with('(')
    })
}
fn has_setting(item: &Item) -> bool {
    keyword(&item.header, "set") || item.children.iter().any(has_setting)
}
/// Remove executable leaves while retaining every setting ancestor. Else is a
/// sibling in the indentation AST: retain its whole chain if any branch has a
/// setting, including empty antecedent branches needed to express negation.
pub fn compact_setting_items(items: Vec<Item>) -> Vec<Item> {
    let mut input = items.into_iter().peekable();
    let mut result = Vec::new();
    while let Some(item) = input.next() {
        if keyword(&item.header, "if") {
            let mut chain = vec![item];
            while input
                .peek()
                .is_some_and(|item| keyword(&item.header, "else"))
            {
                chain.push(input.next().unwrap());
            }
            if chain.iter().any(has_setting) {
                for mut item in chain {
                    item.children = compact_setting_items(item.children);
                    result.push(item);
                }
            }
        } else if has_setting(&item) {
            let mut item = item;
            item.children = compact_setting_items(item.children);
            result.push(item);
        }
    }
    result
}

/// Shared lexical admission for setting leaves in either AST representation.
pub fn is_setting_header(header: &str) -> bool {
    keyword(header, "set")
}

/// Remove lexical setting leaves, preserving every executable container and
/// runtime guard, including guards whose blocks become empty.
pub fn strip_setting_items(items: Vec<Item>) -> Vec<Item> {
    items
        .into_iter()
        .filter_map(|mut item| {
            if is_setting_header(&item.header) {
                return None;
            }
            item.children = strip_setting_items(item.children);
            Some(item)
        })
        .collect()
}

/// Settings are proc-wide lexical declarations, even under runtime control
/// flow. Visit every body in encounter order without evaluating its guards.
/// Executable containers are preserved separately by strip_setting_items.
pub fn extract_settings(
    items: &[Item],
    symbols: &mut SymbolTable,
) -> Result<Arc<[ProcedureSettingNode]>, String> {
    let mut result = Vec::new();
    fn walk(
        items: &[Item],
        symbols: &mut SymbolTable,
        result: &mut Vec<ProcedureSettingNode>,
    ) -> Result<(), String> {
        for item in items {
            if append_setting(&item.header, !item.children.is_empty(), symbols, result)? {
                continue;
            }
            walk(&item.children, symbols, result)?;
        }
        Ok(())
    }
    walk(items, symbols, &mut result)?;
    Ok(result.into())
}
fn append_setting(
    header: &str,
    has_children: bool,
    symbols: &mut SymbolTable,
    result: &mut Vec<ProcedureSettingNode>,
) -> Result<bool, String> {
    if !keyword(header, "set") {
        return Ok(false);
    }
    if has_children {
        return Err("setting has nested children".into());
    }
    result.push(ProcedureSettingNode::Setting(
        super::procedure::parse_setting(header.trim(), symbols)?,
    ));
    Ok(true)
}
/// The same lexical setting producer over current source-backed node views.
pub fn extract_settings_view(
    body: crate::frontend::ItemView<'_>,
    symbols: &mut SymbolTable,
) -> Result<Arc<[ProcedureSettingNode]>, String> {
    fn walk(
        item: crate::frontend::ItemView<'_>,
        symbols: &mut SymbolTable,
        result: &mut Vec<ProcedureSettingNode>,
    ) -> Result<(), String> {
        if !append_setting(item.header(), item.children().len() != 0, symbols, result)? {
            for child in item.children() {
                walk(child, symbols, result)?;
            }
        }
        Ok(())
    }
    let mut result = Vec::new();
    for child in body.children() {
        walk(child, symbols, &mut result)?;
    }
    Ok(result.into())
}

/// Source-only spans remain outside canonical setting-node identities.
pub(crate) fn setting_spans(items: &[Item], output: &mut Vec<Span>) {
    for item in items {
        output.push(item.header_span);
        setting_spans(&item.children, output);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn runtime_guards_and_spawn_do_not_condition_proc_settings() {
        let mut ast = dm_syntax::parse("/proc/p()\n    if (target_radio)\n        return 1\n    else\n        if (prob(scan_ticks * 10))\n            spawn(0)\n                set background = 1\n                return 2\n    set waitfor = 0\n");
        assert!(ast.diagnostics.is_empty());
        let body = std::mem::take(&mut ast.items[0].children);
        let mut symbols = SymbolTable::default();
        let nodes = extract_settings(&body, &mut symbols).unwrap();
        assert_eq!(nodes.len(), 2);
        assert!(nodes
            .iter()
            .all(|n| matches!(n, ProcedureSettingNode::Setting(_))));
        assert_eq!(
            nodes,
            extract_settings(&compact_setting_items(body.clone()), &mut symbols).unwrap()
        );
        let executable = strip_setting_items(body);
        assert_eq!(executable.len(), 2);
        let spawn = &executable[1].children[0].children[0];
        assert_eq!(spawn.header, "spawn(0)");
        assert_eq!(spawn.children.len(), 1);
        assert_eq!(spawn.children[0].header, "return 2");
    }
    #[test]
    fn lexical_order_includes_all_branches_and_unreachable_settings() {
        let ast = dm_syntax::parse("/proc/p()\n    if (0)\n        set waitfor = 0\n    else\n        set waitfor = 1\n    while (runtime_value)\n        set background = 1\n");
        let mut symbols = SymbolTable::default();
        let nodes = extract_settings(&ast.items[0].children, &mut symbols).unwrap();
        assert_eq!(nodes.len(), 3);
        let expected = dm_syntax::parse(
            "/proc/p()\n    set waitfor = 0\n    set waitfor = 1\n    set background = 1\n",
        );
        assert_eq!(
            nodes,
            extract_settings(&expected.items[0].children, &mut symbols).unwrap()
        );
    }
    #[test]
    fn stripping_settings_keeps_empty_executable_guards() {
        let ast = dm_syntax::parse("/proc/p()\n    if (prob(10))\n        set background = 1\n    else\n        set waitfor = 0\n");
        let executable = strip_setting_items(ast.items[0].children.clone());
        assert_eq!(executable.len(), 2);
        assert_eq!(executable[0].header, "if (prob(10))");
        assert!(executable.iter().all(|item| item.children.is_empty()));
    }
}

/// SAME existing encounter-order setting extraction over issued original headers.
/// No executable body or Expr parser is entered by this metadata/footprint pass.
pub(crate) fn extract_settings_original(
    items: &[Item],
    symbols: &mut SymbolTable,
    headers: &crate::procedure::OriginalProcedureHeaders,
    offset: usize,
) -> Result<(Arc<[ProcedureSettingNode]>, crate::procedure::adapter_rows::AdapterRows<crate::procedure::header_input::SettingFootprint>), String> {
    let (nodes, footprints) = extract_settings_original_rows(items, symbols, headers, offset)?;
    Ok((nodes.into_shared(), footprints))
}

pub(crate) fn extract_settings_original_rows(
    items: &[Item],
    symbols: &mut SymbolTable,
    headers: &crate::procedure::OriginalProcedureHeaders,
    offset: usize,
) -> Result<
    (
        crate::procedure::adapter_rows::AdapterRows<ProcedureSettingNode>,
        crate::procedure::adapter_rows::AdapterRows<crate::procedure::header_input::SettingFootprint>,
    ),
    String,
> {
    extract_settings_original_rows_using(items, symbols, headers, offset,
        &mut |headers, header, offset, symbols| headers.parse_setting_original(header, offset, symbols),
        &mut |nodes, footprints| {
            nodes.reserve_compatibility().map_err(|_| "setting metadata capacity refused")?;
            footprints.reserve_compatibility().map_err(|_| "setting footprint capacity refused")?;
            Ok(())
        })
}

pub(crate) fn extract_settings_original_rows_using<E: From<String> + From<&'static str>>(
    items: &[Item],
    symbols: &mut SymbolTable,
    headers: &crate::procedure::OriginalProcedureHeaders,
    offset: usize,
    parse: &mut impl FnMut(&crate::procedure::OriginalProcedureHeaders, dm_syntax::Span, usize, &mut SymbolTable)
        -> Result<crate::procedure::ParsedSetting, E>,
    reserve: &mut impl FnMut(
        &mut crate::procedure::adapter_rows::AdapterRows<ProcedureSettingNode>,
        &mut crate::procedure::adapter_rows::AdapterRows<crate::procedure::header_input::SettingFootprint>,
    ) -> Result<(), E>,
) -> Result<
    (
        crate::procedure::adapter_rows::AdapterRows<ProcedureSettingNode>,
        crate::procedure::adapter_rows::AdapterRows<crate::procedure::header_input::SettingFootprint>,
    ),
    E,
> {
    fn walk<E: From<String> + From<&'static str>>(
        items: &[Item],
        symbols: &mut SymbolTable,
        headers: &crate::procedure::OriginalProcedureHeaders,
        offset: usize,
        nodes: &mut crate::procedure::adapter_rows::AdapterRows<ProcedureSettingNode>,
        footprints: &mut crate::procedure::adapter_rows::AdapterRows<crate::procedure::header_input::SettingFootprint>,
        parse: &mut impl FnMut(&crate::procedure::OriginalProcedureHeaders, dm_syntax::Span, usize, &mut SymbolTable)
            -> Result<crate::procedure::ParsedSetting, E>,
        reserve: &mut impl FnMut(
            &mut crate::procedure::adapter_rows::AdapterRows<ProcedureSettingNode>,
            &mut crate::procedure::adapter_rows::AdapterRows<crate::procedure::header_input::SettingFootprint>,
        ) -> Result<(), E>,
    ) -> Result<(), E> {
        for item in items {
            if keyword(&item.header, "set") {
                if !item.children.is_empty() {
                    return Err("setting has nested children".into());
                }
                let parsed = parse(headers, item.header_span, offset, symbols)?;
                let start = item
                    .header_span
                    .start
                    .checked_sub(offset)
                    .ok_or("setting before original chunk")?;
                let header = dm_syntax::Span::new(
                    start,
                    item.header_span
                        .end
                        .checked_sub(offset)
                        .ok_or("setting end before original chunk")?,
                );
                let value = dm_syntax::Span::new(
                    start
                        .checked_add(parsed.value_span.start)
                        .ok_or("setting RHS start overflow")?,
                    start
                        .checked_add(parsed.value_span.end)
                        .ok_or("setting RHS end overflow")?,
                );
                reserve(nodes, footprints)?;
                footprints.push_reserved(crate::procedure::header_input::SettingFootprint {
                    header,
                    value,
                    ordinal: nodes.len(),
                });
                nodes.push_reserved(ProcedureSettingNode::Setting(parsed.setting));
            } else {
                walk(&item.children, symbols, headers, offset, nodes, footprints, parse, reserve)?;
            }
        }
        Ok(())
    }
    let mut nodes = crate::procedure::adapter_rows::AdapterRows::default();
    let mut footprints = crate::procedure::adapter_rows::AdapterRows::default();
    walk(items, symbols, headers, offset, &mut nodes, &mut footprints, parse, reserve)?;
    Ok((nodes, footprints))
}
