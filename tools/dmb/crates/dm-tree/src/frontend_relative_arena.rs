//! Compact coordinates into the producer-owned exact source, with wide fallback.
use dm_syntax::{Item, ItemKind, Span};
use std::sync::Arc;
#[derive(Clone, Copy, Debug)]
pub(super) struct Node {
    kind: ItemKind,
    indent: u32,
    span: [u32; 2],
    header_span: [u32; 2],
    text: [u32; 2],
    children: [u32; 2],
}
#[derive(Debug)]
pub(super) enum Arena {
    Compact {
        source: dm_preprocess::SourceText,
        nodes: Vec<Node>,
        roots: usize,
        owned: Vec<Box<str>>,
    },
    Wide(Arc<[Item]>),
}
impl Arena {
    pub(super) fn capture(items: Vec<Item>, source: impl Into<dm_preprocess::SourceText>) -> Self {
        let source = source.into();
        fn fits(items: &[Item]) -> bool {
            items.iter().all(|item| {
                item.indent <= u32::MAX as usize
                    && [
                        item.span.start,
                        item.span.end,
                        item.header_span.start,
                        item.header_span.end,
                    ]
                    .into_iter()
                    .all(|v| v <= u32::MAX as usize)
                    && fits(&item.children)
            })
        }
        fn count(items: &[Item]) -> Option<usize> {
            items
                .iter()
                .try_fold(items.len(), |n, item| n.checked_add(count(&item.children)?))
        }
        if source.len() >= u32::MAX as usize
            || !fits(&items)
            || count(&items).is_none_or(|n| n >= u32::MAX as usize)
        {
            return Self::Wide(items.into());
        }
        let roots = items.len();
        let mut nodes = Vec::with_capacity(count(&items).unwrap());
        let mut owned = Vec::new();
        fn append(
            items: Vec<Item>,
            source: &str,
            nodes: &mut Vec<Node>,
            owned: &mut Vec<Box<str>>,
        ) -> [u32; 2] {
            let start = nodes.len();
            for item in &items {
                let span = item.header_span;
                let text = if item.header.is_empty() {
                    [0, 0]
                } else if source.get(span.range()) == Some(item.header.as_str()) {
                    [span.start as u32, span.end as u32]
                } else {
                    let index = owned.len();
                    owned.push(item.header.clone().into_boxed_str());
                    [u32::MAX, index as u32]
                };
                nodes.push(Node {
                    kind: item.kind,
                    indent: item.indent as u32,
                    span: [item.span.start as u32, item.span.end as u32],
                    header_span: [span.start as u32, span.end as u32],
                    text,
                    children: [0, 0],
                });
            }
            let end = nodes.len();
            for (index, item) in items.into_iter().enumerate() {
                nodes[start + index].children = append(item.children, source, nodes, owned);
            }
            [start as u32, end as u32]
        }
        append(items, &source, &mut nodes, &mut owned);
        Self::Compact {
            source,
            nodes,
            roots,
            owned,
        }
    }
    pub(super) fn roots(&self) -> Nodes<'_> {
        match self {
            Self::Compact { roots, .. } => Nodes::Compact {
                arena: self,
                front: 0,
                back: *roots,
            },
            Self::Wide(items) => Nodes::Wide(items.iter()),
        }
    }
    pub(super) fn wide_items(&self) -> Option<&Arc<[Item]>> {
        match self {
            Self::Wide(items) => Some(items),
            Self::Compact { .. } => None,
        }
    }
    pub(super) fn source(&self) -> Option<&dm_preprocess::SourceText> {
        match self {
            Self::Compact { source, .. } => Some(source),
            Self::Wide(_) => None,
        }
    }
    pub(super) fn visit_storage(&self, mut buffer: impl FnMut(usize, usize, usize)) {
        match self {
            Self::Compact { nodes, owned, .. } => {
                buffer(
                    nodes.as_ptr() as usize,
                    nodes.len() * std::mem::size_of::<Node>(),
                    nodes.capacity() * std::mem::size_of::<Node>(),
                );
                buffer(
                    owned.as_ptr() as usize,
                    owned.len() * std::mem::size_of::<Box<str>>(),
                    owned.capacity() * std::mem::size_of::<Box<str>>(),
                );
                for text in owned {
                    buffer(text.as_ptr() as usize, text.len(), text.len());
                }
            }
            Self::Wide(items) => {
                buffer(
                    items.as_ptr() as usize,
                    std::mem::size_of_val(items.as_ref()),
                    std::mem::size_of_val(items.as_ref()),
                );
                fn visit(items: &[Item], f: &mut impl FnMut(usize, usize, usize)) {
                    for item in items {
                        f(
                            item.header.as_ptr() as usize,
                            item.header.len(),
                            item.header.capacity(),
                        );
                        f(
                            item.children.as_ptr() as usize,
                            item.children.len() * std::mem::size_of::<Item>(),
                            item.children.capacity() * std::mem::size_of::<Item>(),
                        );
                        visit(&item.children, f);
                    }
                }
                visit(items, &mut buffer);
            }
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub(super) enum Ref<'a> {
    Compact(&'a Arena, usize),
    Wide(&'a Item),
}
impl Ref<'_> {
    pub(super) fn same(self, other: Self) -> bool {
        match (self, other) {
            (Self::Compact(a, i), Self::Compact(b, j)) => std::ptr::eq(a, b) && i == j,
            (Self::Wide(a), Self::Wide(b)) => std::ptr::eq(a, b),
            _ => false,
        }
    }
    fn node(self) -> Option<Node> {
        match self {
            Self::Compact(Arena::Compact { nodes, .. }, i) => Some(nodes[i]),
            _ => None,
        }
    }
    pub(super) fn kind(self) -> ItemKind {
        self.node().map_or_else(
            || match self {
                Self::Wide(item) => item.kind,
                _ => unreachable!(),
            },
            |n| n.kind,
        )
    }
    pub(super) fn indent(self) -> usize {
        self.node().map_or_else(
            || match self {
                Self::Wide(item) => item.indent,
                _ => unreachable!(),
            },
            |n| n.indent as usize,
        )
    }
    pub(super) fn span(self) -> Span {
        self.node().map_or_else(
            || match self {
                Self::Wide(item) => item.span,
                _ => unreachable!(),
            },
            |n| Span::new(n.span[0] as usize, n.span[1] as usize),
        )
    }
    pub(super) fn header_span(self) -> Span {
        self.node().map_or_else(
            || match self {
                Self::Wide(item) => item.header_span,
                _ => unreachable!(),
            },
            |n| Span::new(n.header_span[0] as usize, n.header_span[1] as usize),
        )
    }
}
impl<'a> Ref<'a> {
    pub(super) fn header(self) -> &'a str {
        match self {
            Self::Wide(item) => &item.header,
            Self::Compact(
                Arena::Compact {
                    source,
                    nodes,
                    owned,
                    ..
                },
                i,
            ) => {
                let t = nodes[i].text;
                if t[0] == u32::MAX {
                    &owned[t[1] as usize]
                } else {
                    &source[t[0] as usize..t[1] as usize]
                }
            }
            _ => unreachable!(),
        }
    }
    pub(super) fn children(self) -> Nodes<'a> {
        match self {
            Self::Wide(item) => Nodes::Wide(item.children.iter()),
            Self::Compact(arena @ Arena::Compact { nodes, .. }, i) => {
                let range = nodes[i].children;
                Nodes::Compact {
                    arena,
                    front: range[0] as usize,
                    back: range[1] as usize,
                }
            }
            _ => unreachable!(),
        }
    }
}
pub(super) enum Nodes<'a> {
    Compact {
        arena: &'a Arena,
        front: usize,
        back: usize,
    },
    Wide(std::slice::Iter<'a, Item>),
}
impl<'a> Iterator for Nodes<'a> {
    type Item = Ref<'a>;
    fn nth(&mut self, n: usize) -> Option<Self::Item> {
        match self {
            Self::Compact { arena, front, back } => {
                if n >= *back - *front {
                    *front = *back;
                    return None;
                }
                *front += n;
                let index = *front;
                *front += 1;
                Some(Ref::Compact(arena, index))
            }
            Self::Wide(items) => items.nth(n).map(Ref::Wide),
        }
    }
    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Self::Compact { arena, front, back } => {
                if *front == *back {
                    return None;
                }
                let i = *front;
                *front += 1;
                Some(Ref::Compact(arena, i))
            }
            Self::Wide(items) => items.next().map(Ref::Wide),
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let n = self.len();
        (n, Some(n))
    }
}
impl DoubleEndedIterator for Nodes<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        match self {
            Self::Compact { arena, front, back } => {
                if *front == *back {
                    return None;
                }
                *back -= 1;
                Some(Ref::Compact(arena, *back))
            }
            Self::Wide(items) => items.next_back().map(Ref::Wide),
        }
    }
}
impl ExactSizeIterator for Nodes<'_> {
    fn len(&self) -> usize {
        match self {
            Self::Compact { front, back, .. } => back - front,
            Self::Wide(items) => items.len(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compact_nodes_borrow_headers_and_keep_recursive_order_with_smaller_slots() {
        let source: Arc<str> = Arc::from(
            "/datum/a\n    var/x = 1\n    proc/run()\n        if(x)\n            set waitfor = 0\n",
        );
        let parsed = dm_syntax::parse_declaration_skeleton(&source).items;
        let arena = Arena::capture(parsed.clone(), Arc::clone(&source));
        let Arena::Compact { nodes, owned, .. } = &arena else {
            panic!("small exact syntax must compact")
        };
        assert!(owned.is_empty());
        assert!(std::mem::size_of::<Node>() < std::mem::size_of::<Item>());
        assert!(std::mem::size_of::<Node>() <= 48);
        fn check(node: Ref<'_>, expected: &Item, source: &str) {
            assert_eq!(node.header(), expected.header);
            assert_eq!(node.span(), expected.span);
            assert_eq!(node.header_span(), expected.header_span);
            assert_eq!(node.indent(), expected.indent);
            assert_eq!(node.children().len(), expected.children.len());
            if !expected.header.is_empty() {
                assert!(std::ptr::eq(
                    node.header().as_ptr(),
                    source[expected.header_span.range()].as_ptr()
                ));
            }
            for (child, old) in node.children().zip(&expected.children) {
                check(child, old, source);
            }
        }
        assert_eq!(nodes.len(), {
            fn count(items: &[Item]) -> usize {
                items.len()
                    + items
                        .iter()
                        .map(|item| count(&item.children))
                        .sum::<usize>()
            }
            count(&parsed)
        });
        for (node, old) in arena.roots().zip(&parsed) {
            check(node, old, &source);
        }
        let root = arena.roots().next().unwrap();
        assert_eq!(
            root.children().next_back().unwrap().header(),
            parsed[0].children.last().unwrap().header
        );
        assert!(Arc::ptr_eq(
            arena.source().unwrap().full_original_owner().unwrap(),
            &source
        ));
    }
    #[test]
    fn transformed_headers_and_wide_coordinates_preserve_owned_spelling() {
        let source: Arc<str> = Arc::from("relative\n");
        let item = Item {
            kind: ItemKind::Type,
            header: "/qualified/relative".into(),
            span: Span::new(0, 8),
            header_span: Span::new(0, 8),
            indent: 0,
            children: vec![],
        };
        let arena = Arena::capture(vec![item.clone()], Arc::clone(&source));
        assert_eq!(arena.roots().next().unwrap().header(), item.header);
        assert_eq!(
            arena.roots().next().unwrap().header_span(),
            item.header_span
        );
        let wide = Item {
            indent: usize::MAX,
            ..item
        };
        let arena = Arena::capture(vec![wide.clone()], source);
        assert!(matches!(arena, Arena::Wide(_)));
        assert_eq!(arena.roots().next().unwrap().indent(), wide.indent);
        assert_eq!(arena.roots().next().unwrap().header(), wide.header);
    }
}
