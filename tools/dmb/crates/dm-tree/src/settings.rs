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

/// Remove lexical setting leaves, preserving every executable container and
/// runtime guard, including guards whose blocks become empty.
pub fn strip_setting_items(items: Vec<Item>) -> Vec<Item> {
    items
        .into_iter()
        .filter_map(|mut item| {
            if keyword(&item.header, "set") {
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
    for item in items {
        if keyword(&item.header, "set") {
            if !item.children.is_empty() {
                return Err("setting has nested children".into());
            }
            result.push(ProcedureSettingNode::Setting(
                super::procedure::parse_setting(item.header.trim(), symbols)?,
            ));
        } else {
            result.extend(extract_settings(&item.children, symbols)?.iter().cloned());
        }
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
