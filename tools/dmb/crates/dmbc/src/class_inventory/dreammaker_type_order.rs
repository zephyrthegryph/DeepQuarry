//! DreamMaker's class table order (observable through `typesof()`), measured against DreamMaker
//! 516.1687 (`fixtures/native_compiler/null_defaults` and the probes in the tests below).
//!
//! Types form a tree by path, emitted in postorder (children before their path parent):
//! - The path roots that predate the newer builtins (`/datum`, `/atom`, `/mob`, `/obj`, `/image`,
//!   `/mutable_appearance`, `/turf`, `/area`, `/client`) come first when source names them or a
//!   path below them, in the order source first names them; the ones source never names follow
//!   in template order; the newer builtin roots (`/alist` ... `/particles`) always follow in
//!   template order.
//! - Below an older root, children source names come first, in the order it first names them,
//!   then the others in template order. Below a newer root, the builtin children come first in
//!   template order, then the source children.
//! - Last come: `/mob` itself when source names it (its subtypes stay in place), the
//!   `/mutable_appearance` subtree when source names it, and every source type whose parent is
//!   not its path parent (`parent_type`), with its subtree, in the order source first names them.
use dm_ir::{SymbolId, SymbolTable};
use std::collections::{HashMap, HashSet};

const OLDER_ROOTS: [&str; 9] = [
    "/datum",
    "/atom",
    "/mob",
    "/obj",
    "/image",
    "/mutable_appearance",
    "/turf",
    "/area",
    "/client",
];

fn path_parent(path: &str) -> &str {
    match path.rfind('/') {
        Some(0) | None => "/",
        Some(at) => &path[..at],
    }
}

/// `engine`: engine types in template order. `touches`: every path a declaration block names,
/// first encounter first. `source`: the source types with their parent.
pub(crate) fn order(
    engine: &[SymbolId],
    touches: &[SymbolId],
    source: &[(SymbolId, Option<SymbolId>)],
    symbols: &SymbolTable,
) -> Result<Vec<SymbolId>, String> {
    let text = |id: SymbolId| -> Result<&str, String> {
        symbols
            .text(id)
            .ok_or_else(|| format!("type spelling missing for {id:?}"))
    };
    let root = SymbolId::of("/");
    let template: HashMap<SymbolId, usize> =
        engine.iter().enumerate().map(|(index, &id)| (id, index)).collect();
    let mut nodes: HashSet<SymbolId> = engine.iter().copied().collect();
    nodes.extend(source.iter().map(|(path, _)| *path));
    // First touch of every node: a named path touches its ancestors first.
    let mut touch: HashMap<SymbolId, usize> = HashMap::new();
    let mut clock = 0usize;
    for &path in touches {
        let mut chain = Vec::new();
        let mut at = text(path)?;
        while at != "/" {
            chain.push(SymbolId::of(at));
            at = path_parent(at);
        }
        for id in chain.into_iter().rev() {
            if nodes.contains(&id) && !touch.contains_key(&id) {
                touch.insert(id, clock);
                clock += 1;
            }
        }
    }
    // Source types the touches missed are named in source order.
    for &(path, _) in source {
        touch.entry(path).or_insert_with(|| {
            clock += 1;
            clock
        });
    }
    let mut children: HashMap<SymbolId, Vec<SymbolId>> = HashMap::new();
    for &node in &nodes {
        // The nearest path ancestor that is itself a type (a path segment no source declares
        // is not a table row).
        let mut at = path_parent(text(node)?);
        while at != "/" && !nodes.contains(&SymbolId::of(at)) {
            at = path_parent(at);
        }
        children.entry(SymbolId::of(at)).or_default().push(node);
    }
    let root_of = |node: SymbolId| -> Result<SymbolId, String> {
        let path = text(node)?;
        let end = path[1..].find('/').map_or(path.len(), |at| at + 1);
        Ok(SymbolId::of(&path[..end]))
    };
    let older: HashSet<SymbolId> = OLDER_ROOTS.iter().map(|path| SymbolId::of(path)).collect();
    let is_engine = |node: &SymbolId| template.contains_key(node);
    for (&parent, list) in children.iter_mut() {
        let older_family = parent == root || older.contains(&root_of(parent)?);
        list.sort_by_key(|node| {
            let engine_rank = template.get(node).copied().unwrap_or(usize::MAX);
            let touched = touch.get(node).copied();
            if parent == root {
                // Touched older roots, untouched older roots, newer roots.
                match (older.contains(node), touched) {
                    (true, Some(at)) => (0, at, 0),
                    (true, None) => (1, engine_rank, 0),
                    (false, _) if is_engine(node) => (2, engine_rank, 0),
                    (false, at) => (3, at.unwrap_or(usize::MAX), 0),
                }
            } else if older_family {
                match touched {
                    Some(at) => (0, at, 0),
                    None => (1, engine_rank, 0),
                }
            } else if is_engine(node) {
                (0, engine_rank, 0)
            } else {
                (1, touched.unwrap_or(usize::MAX), 0)
            }
        });
    }
    // Late subtrees and nodes.
    let parents: HashMap<SymbolId, Option<SymbolId>> = source.iter().copied().collect();
    let datum = SymbolId::of("/datum");
    let mut late_subtrees: Vec<SymbolId> = Vec::new();
    for &(path, parent) in source {
        let lexical = path_parent(text(path)?);
        let expected = if lexical == "/" { Some(datum) } else { Some(SymbolId::of(lexical)) };
        if parent != expected {
            late_subtrees.push(path);
        }
    }
    late_subtrees.sort_by_key(|path| touch.get(path).copied().unwrap_or(usize::MAX));
    let mutable = SymbolId::of("/mutable_appearance");
    if touch.contains_key(&mutable) && nodes.contains(&mutable) {
        late_subtrees.insert(0, mutable);
    }
    let mob = SymbolId::of("/mob");
    let late_mob = touch.contains_key(&mob) && nodes.contains(&mob);
    let late: HashSet<SymbolId> = late_subtrees.iter().copied().collect();
    let _ = parents;
    fn emit(
        node: SymbolId,
        children: &HashMap<SymbolId, Vec<SymbolId>>,
        late: &HashSet<SymbolId>,
        skip_self: Option<SymbolId>,
        emitted: &mut HashSet<SymbolId>,
        out: &mut Vec<SymbolId>,
    ) {
        for &child in children.get(&node).into_iter().flatten() {
            if !late.contains(&child) {
                emit(child, children, late, skip_self, emitted, out);
            }
        }
        if Some(node) != skip_self && emitted.insert(node) {
            out.push(node);
        }
    }
    let mut out = Vec::with_capacity(nodes.len());
    let mut emitted = HashSet::with_capacity(nodes.len());
    for &top in children.get(&root).into_iter().flatten() {
        if !late.contains(&top) {
            emit(top, &children, &late, late_mob.then_some(mob), &mut emitted, &mut out);
        }
    }
    if late_mob && emitted.insert(mob) {
        out.push(mob);
    }
    // A late subtree inside another late subtree is emitted with the outer one.
    for &subtree in &late_subtrees {
        emit(subtree, &children, &HashSet::new(), None, &mut emitted, &mut out);
    }
    if out.len() != nodes.len() {
        return Err(format!(
            "type order covers {} of {} types",
            out.len(),
            nodes.len()
        ));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    const ENGINE: [&str; 24] = [
        "/datum",
        "/atom/movable",
        "/atom",
        "/mob",
        "/obj",
        "/image",
        "/mutable_appearance",
        "/turf",
        "/area",
        "/client",
        "/alist",
        "/pixloc",
        "/vector",
        "/callee",
        "/sound",
        "/icon",
        "/matrix",
        "/database/query",
        "/database",
        "/exception",
        "/regex",
        "/dm_filter",
        "/generator",
        "/particles",
    ];
    /// `decls`: (path, Some(parent) when parent_type is assigned), in source order. Returns the
    /// order with the untouched engine tail cut after `take` entries.
    fn run(decls: &[(&str, Option<&str>)], take: usize) -> Vec<String> {
        let mut symbols = SymbolTable::default();
        let mut intern = |text: &str| {
            symbols.intern(text).unwrap();
            SymbolId::of(text)
        };
        let engine: Vec<_> = ENGINE.iter().map(|path| intern(path)).collect();
        let mut touches = Vec::new();
        let mut source = Vec::new();
        for &(path, parent) in decls {
            // Undeclared path segments are allocated as source types, as the compiler does.
            let mut at = path_parent(path);
            let mut implied = Vec::new();
            while at != "/" {
                implied.push(at);
                at = path_parent(at);
            }
            for segment in implied.into_iter().rev() {
                let id = intern(segment);
                if !engine.contains(&id) && !source.iter().any(|(known, _)| *known == id) {
                    let lexical = path_parent(segment);
                    let parent = intern(if lexical == "/" { "/datum" } else { lexical });
                    source.push((id, Some(parent)));
                }
            }
            let id = intern(path);
            touches.push(id);
            if !engine.contains(&id) && !source.iter().any(|(known, _)| *known == id) {
                let lexical = path_parent(path);
                let parent = parent
                    .map(|parent| intern(parent))
                    .unwrap_or_else(|| intern(if lexical == "/" { "/datum" } else { lexical }));
                source.push((id, Some(parent)));
            }
        }
        // Source parents listed after their use are still source types.
        let order = order(&engine, &touches, &source, &symbols).unwrap();
        order
            .into_iter()
            .take(take)
            .map(|id| symbols.text(id).unwrap().to_string())
            .collect()
    }
    fn expect(decls: &[(&str, Option<&str>)], expected: &[&str]) {
        assert_eq!(run(decls, expected.len()), expected, "{decls:?}");
    }
    #[test]
    fn matches_dreammaker_516_type_tables() {
        // fixtures/native_compiler/null_defaults
        expect(
            &[("/obj/a", None), ("/obj/b", None), ("/obj/c", None), ("/obj/d", None), ("/obj/g", None), ("/image/h", None)],
            &["/obj/a", "/obj/b", "/obj/c", "/obj/d", "/obj/g", "/obj", "/image/h", "/image", "/datum", "/atom/movable", "/atom", "/mob", "/mutable_appearance"],
        );
        expect(
            &[("/mob/b", None), ("/obj/a", None), ("/datum/z", None)],
            &["/mob/b", "/obj/a", "/obj", "/datum/z", "/datum", "/atom/movable", "/atom", "/image"],
        );
        expect(
            &[("/obj/a/x", None), ("/obj/b", None)],
            &["/obj/a/x", "/obj/a", "/obj/b", "/obj", "/datum", "/atom/movable", "/atom", "/mob"],
        );
        expect(
            &[("/atom", None), ("/obj/a", None)],
            &["/atom/movable", "/atom", "/obj/a", "/obj", "/datum", "/mob", "/image"],
        );
        expect(
            &[("/obj/a/b/c", None), ("/obj/a", None), ("/turf/x", None), ("/obj/z", None)],
            &["/obj/a/b/c", "/obj/a/b", "/obj/a", "/obj/z", "/obj", "/turf/x", "/turf", "/datum"],
        );
        expect(
            &[("/database/query/q", None), ("/atom/movable/m", None)],
            &["/atom/movable/m", "/atom/movable", "/atom", "/datum", "/mob", "/obj", "/image", "/mutable_appearance", "/turf", "/area", "/client", "/alist", "/pixloc", "/vector", "/callee", "/sound", "/icon", "/matrix", "/database/query/q", "/database/query", "/database"],
        );
        expect(
            &[("/database/d", None), ("/obj/a", None)],
            &["/obj/a", "/obj", "/datum", "/atom/movable", "/atom", "/mob", "/image", "/mutable_appearance", "/turf", "/area", "/client", "/alist", "/pixloc", "/vector", "/callee", "/sound", "/icon", "/matrix", "/database/query", "/database/d", "/database"],
        );
        expect(
            &[("/atom/x", None), ("/atom/movable/m", None)],
            &["/atom/x", "/atom/movable/m", "/atom/movable", "/atom", "/datum", "/mob", "/obj"],
        );
        expect(
            &[("/image/i", None), ("/turf/t", None), ("/obj", None)],
            &["/image/i", "/image", "/turf/t", "/turf", "/obj", "/datum", "/atom/movable", "/atom", "/mob", "/mutable_appearance", "/area"],
        );
        let all = run(&[("/obj/a", None), ("/mutable_appearance/m", None)], 26);
        assert_eq!(&all[..2], ["/obj/a", "/obj"]);
        assert_eq!(&all[24..], ["/mutable_appearance/m", "/mutable_appearance"]);
        let all = run(&[("/mob/m", None), ("/obj/a", Some("/datum")), ("/obj/b", Some("/datum")), ("/turf/t", None)], 28);
        assert_eq!(&all[..5], ["/mob/m", "/obj", "/turf/t", "/turf", "/datum"]);
        assert_eq!(&all[25..], ["/mob", "/obj/a", "/obj/b"]);
        let all = run(&[("/obj/a", None), ("/obj/a/b", Some("/obj")), ("/obj/c", None)], 27);
        assert_eq!(&all[..3], ["/obj/a", "/obj/c", "/obj"]);
        assert_eq!(&all[26..], ["/obj/a/b"]);
        // A reparented type inside a reparented type's subtree is listed once, with the outer.
        let all = run(&[("/obj/a", Some("/datum")), ("/obj/a/b", Some("/mob"))], 30);
        assert_eq!(all.len(), 26);
        assert_eq!(&all[24..], ["/obj/a/b", "/obj/a"]);
    }
}
