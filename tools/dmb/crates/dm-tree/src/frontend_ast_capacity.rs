//! Trim declaration arena slack before issuing immutable analysis snapshots.
use dm_syntax::{AstFile, Item};

pub(super) fn compact(syntax: &mut AstFile) {
    if syntax.items.capacity() > syntax.items.len() {
        syntax.items.shrink_to_fit();
    }
    // Explicit traversal preserves the parser's supported nesting without an
    // additional recursive call stack. Only owned allocation capacity changes.
    let mut pending: Vec<&mut Item> = syntax.items.iter_mut().collect();
    while let Some(item) = pending.pop() {
        if item.header.capacity() > item.header.len() {
            item.header.shrink_to_fit();
        }
        if item.children.capacity() > item.children.len() {
            item.children.shrink_to_fit();
        }
        pending.extend(item.children.iter_mut());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_syntax::{parse, ItemKind, Span};

    #[test]
    fn compact_nested_declarations_preserves_analysis_and_source_spans() {
        let mut syntax = parse("/datum/sample\n    var/value = 7\n    proc/callback(argument = 4)\n        return argument\n");
        assert!(syntax.diagnostics.is_empty());
        let expected = syntax.clone();
        syntax.items.reserve(64);
        let root = &mut syntax.items[0];
        root.header.reserve(4096);
        root.children.reserve(64);
        root.children[0].header.reserve(4096);
        root.children[1].children.reserve(64);
        compact(&mut syntax);
        assert_eq!(syntax, expected);
        assert_eq!(syntax.items.capacity(), syntax.items.len());
        assert_eq!(
            syntax.items[0].header.capacity(),
            syntax.items[0].header.len()
        );
        assert_eq!(
            syntax.items[0].children.capacity(),
            syntax.items[0].children.len()
        );
        assert_eq!(
            syntax.items[0].children[1].children.capacity(),
            syntax.items[0].children[1].children.len()
        );
    }

    #[test]
    fn compaction_preserves_empty_children_and_all_item_fields() {
        let mut header = String::with_capacity(1024);
        header.push_str("var/example");
        let item = Item {
            kind: ItemKind::Var,
            header,
            span: Span::new(10, 34),
            header_span: Span::new(10, 21),
            indent: 17,
            children: Vec::with_capacity(32),
        };
        let expected = item.clone();
        let mut syntax = AstFile {
            items: vec![item],
            ..AstFile::default()
        };
        compact(&mut syntax);
        assert_eq!(syntax.items[0], expected);
        assert_eq!(syntax.items[0].children.capacity(), 0);
    }
}
