//! The order DreamMaker runs the global initializers in.
//!
//! DreamMaker numbers a variable when it allocates it and runs `<global-init>` in ascending number. The numbering
//! follows a walk of the type tree, and a variable that cannot be resolved yet is allocated on a later walk. Measured
//! against DreamMaker 516.1687 (the probes are the tests of `startup_allocation_order_tests`, and the production
//! dme reproduces exactly):
//!
//! * **The tree.** A node is a path. Its members are the ledger events whose owner is that path (a block header, a
//!   `var`, a procedure, a `parent_type` assignment). The walk sorts a node's members and its child subtrees together:
//!   a member by its event number, a child subtree by the smallest event number inside it. So a parent's own members
//!   land among its children, wherever its source puts them.
//! * **Members.** Every `proc/` declaration of a node is one member, at the first one's position (verbs likewise,
//!   separately). A later declaration joins it; an override or a `var` is a member of its own.
//! * **Passes.** The first pass walks the tree without its late subtrees and allocates every initializer whose
//!   references already resolve; the others wait. Each further pass walks the whole tree (late subtrees included, in
//!   their place) and allocates what resolves by then, until nothing waits.
//! * **Late subtrees.** A node whose `parent_type` names a type that does not exist yet at the assignment (or is itself
//!   late), together with everything below it, is not walked by the first pass.
//! * **References.** A type resolves once its whole subtree has been walked (a type no source names resolves from the
//!   second pass on); a procedure path, once the procedure's member was walked; another initializer's variable, once
//!   that initializer is allocated; a call of a global procedure, once any global procedure was walked; `world`, from
//!   the second pass on. The declared type of a variable that has an initializer is a reference of that initializer.
//!
//! The function is pure: its inputs are the ledger events and, for each initializer, its references.
use dm_ir::{SymbolId, SymbolTable};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum EventKind {
    Type,
    Namespace,
    Field,
    Procedure,
    Parent,
}

/// One allocation-ledger event, reduced to what orders the walk.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct OrderEvent {
    pub kind: EventKind,
    pub owner: SymbolId,
    /// The field or procedure name; unused by the other kinds.
    pub name: SymbolId,
    /// A procedure declared with `proc/` or `verb/`.
    pub formal: bool,
    pub verb: bool,
    /// The `parent_type` value of a `Parent` event, when it names a path.
    pub target: Option<SymbolId>,
}

/// What an initializer needs before DreamMaker allocates it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Ref {
    /// A type path (also the declared type of the variable, and the owner for `type::name`).
    Type(SymbolId),
    /// A procedure named by a path or `nameof`; the owner is searched up its ancestry.
    Procedure { owner: SymbolId, name: SymbolId },
    /// A variable named in the expression: a static of the same procedure, a static of the owner's ancestry or a
    /// global.
    Ident(SymbolId),
    /// A call of a name that may be a global procedure.
    Call(SymbolId),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct OrderWrite {
    /// The event the initializer belongs to: the procedure of a procedure static, the field of a shared variable.
    pub event: u32,
    pub procedure_static: bool,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub refs: Vec<Ref>,
    pub world: bool,
}

const NONE: u32 = u32::MAX;

struct Item {
    key: u32,
    events: Vec<u32>,
}

struct Node {
    parent: usize,
    items: Vec<Item>,
    children: Vec<usize>,
    sub: u32,
    late: bool,
}

enum Op {
    Enter(usize),
    Item(usize, usize),
    Leave(usize),
}

fn path_parent(path: &str) -> &str {
    match path.rfind('/') {
        Some(0) | None => "/",
        Some(at) => &path[..at],
    }
}

struct Tree {
    nodes: Vec<Node>,
    by_path: HashMap<SymbolId, usize>,
}

impl Tree {
    fn ensure(&mut self, path: &str) -> usize {
        let id = SymbolId::of(path);
        if let Some(&node) = self.by_path.get(&id) {
            return node;
        }
        let parent = self.ensure(path_parent(path));
        let node = self.nodes.len();
        self.nodes.push(Node {
            parent,
            items: Vec::new(),
            children: Vec::new(),
            sub: NONE,
            late: false,
        });
        self.nodes[parent].children.push(node);
        self.by_path.insert(id, node);
        node
    }
    fn node(&self, path: SymbolId) -> Option<usize> {
        self.by_path.get(&path).copied()
    }
    fn in_late(&self, mut node: usize) -> bool {
        while node != 0 {
            if self.nodes[node].late {
                return true;
            }
            node = self.nodes[node].parent;
        }
        false
    }
}

/// The initializers in the order DreamMaker runs them (indices into `writes`).
pub(crate) fn order(
    events: &[OrderEvent],
    writes: &[OrderWrite],
    symbols: &SymbolTable,
) -> Vec<u32> {
    let text = |id: SymbolId| symbols.text(id).unwrap_or("/");
    let mut tree = Tree {
        nodes: vec![Node {
            parent: 0,
            items: Vec::new(),
            children: Vec::new(),
            sub: NONE,
            late: false,
        }],
        by_path: HashMap::new(),
    };
    tree.by_path.insert(SymbolId::of("/"), 0);

    // Members. The node of an event is its owner's.
    let mut event_node = Vec::with_capacity(events.len());
    let mut groups: HashMap<(usize, bool), usize> = HashMap::new();
    for (index, event) in events.iter().enumerate() {
        let node = tree.ensure(text(event.owner));
        event_node.push(node);
        let index = index as u32;
        if event.kind == EventKind::Procedure && event.formal {
            let slot = *groups.entry((node, event.verb)).or_insert_with(|| {
                tree.nodes[node].items.push(Item {
                    key: index,
                    events: Vec::new(),
                });
                tree.nodes[node].items.len() - 1
            });
            tree.nodes[node].items[slot].events.push(index);
        } else {
            tree.nodes[node].items.push(Item {
                key: index,
                events: vec![index],
            });
        }
    }
    // A node's key is the smallest event number inside it. Parents are created before their children, so one backward
    // pass folds every node into its parent.
    for node in 0..tree.nodes.len() {
        let own = tree.nodes[node]
            .items
            .iter()
            .map(|item| item.key)
            .min()
            .unwrap_or(NONE);
        tree.nodes[node].sub = own;
    }
    for node in (1..tree.nodes.len()).rev() {
        let parent = tree.nodes[node].parent;
        let key = tree.nodes[node].sub;
        tree.nodes[parent].sub = tree.nodes[parent].sub.min(key);
    }

    // Late subtrees: `parent_type` that names a type not yet there, or one that is late itself.
    for (index, event) in events.iter().enumerate() {
        if event.kind != EventKind::Parent {
            continue;
        }
        let Some(target) = event.target else { continue };
        let owner_path = text(event.owner);
        let target_path = text(target);
        if target_path == path_parent(owner_path)
            || owner_path
                .strip_prefix(target_path)
                .is_some_and(|rest| rest.starts_with('/'))
        {
            continue;
        }
        let owner = event_node[index];
        let late = match tree.node(target) {
            None => true,
            Some(node) => tree.nodes[node].sub as usize > index || tree.in_late(node),
        };
        if late {
            tree.nodes[owner].late = true;
        }
    }

    // The walk, once: members and child subtrees by key.
    let mut tape = Vec::new();
    let mut leave_of = vec![0usize; tree.nodes.len()];
    fn walk(tree: &mut Tree, node: usize, tape: &mut Vec<Op>, leave_of: &mut [usize]) {
        let mut entries: Vec<(u32, bool, usize)> = Vec::new();
        for (index, item) in tree.nodes[node].items.iter().enumerate() {
            entries.push((item.key, false, index));
        }
        let children = tree.nodes[node].children.clone();
        for child in children {
            let key = tree.nodes[child].sub;
            entries.push((key, true, child));
        }
        entries.sort_by_key(|entry| (entry.0, entry.1));
        tape.push(Op::Enter(node));
        for (_, is_child, index) in entries {
            if is_child {
                walk(tree, index, tape, leave_of);
            } else {
                tape.push(Op::Item(node, index));
            }
        }
        leave_of[node] = tape.len();
        tape.push(Op::Leave(node));
    }
    walk(&mut tree, 0, &mut tape, &mut leave_of);

    // Lookup tables.
    let mut proc_events: HashMap<(usize, SymbolId), Vec<u32>> = HashMap::new();
    let mut root_fields: HashMap<SymbolId, Vec<u32>> = HashMap::new();
    for (index, event) in events.iter().enumerate() {
        let node = event_node[index];
        match event.kind {
            EventKind::Procedure => proc_events
                .entry((node, event.name))
                .or_default()
                .push(index as u32),
            EventKind::Field if node == 0 => root_fields
                .entry(event.name)
                .or_default()
                .push(index as u32),
            _ => {}
        }
    }
    let mut writes_at: HashMap<u32, Vec<usize>> = HashMap::new();
    let mut static_by: HashMap<(u32, SymbolId), usize> = HashMap::new();
    let mut shared_by: HashMap<(usize, SymbolId), usize> = HashMap::new();
    for (index, write) in writes.iter().enumerate() {
        writes_at.entry(write.event).or_default().push(index);
        if write.procedure_static {
            static_by.entry((write.event, write.name)).or_insert(index);
        } else if let Some(node) = tree.node(write.owner) {
            shared_by.entry((node, write.name)).or_insert(index);
        }
    }

    let mut allocated = vec![false; writes.len()];
    let mut processed = vec![false; events.len()];
    let mut finished = vec![false; tree.nodes.len()];
    let mut root_procedure_seen = false;
    let mut out: Vec<u32> = Vec::with_capacity(writes.len());
    let mut remaining = writes.len();

    for pass in 1..=8u32 {
        let mut position = 0usize;
        while position < tape.len() && remaining > 0 {
            match tape[position] {
                Op::Enter(node) => {
                    if pass == 1 && tree.nodes[node].late {
                        position = leave_of[node] + 1;
                        continue;
                    }
                }
                Op::Leave(node) => finished[node] = true,
                Op::Item(node, item) => {
                    for slot in 0..tree.nodes[node].items[item].events.len() {
                        let event = tree.nodes[node].items[item].events[slot];
                        if let Some(here) = writes_at.get(&event) {
                            for &write in here {
                                if allocated[write] {
                                    continue;
                                }
                                let env = Env {
                                    tree: &tree,
                                    finished: &finished,
                                    processed: &processed,
                                    allocated: &allocated,
                                    proc_events: &proc_events,
                                    root_fields: &root_fields,
                                    writes_at: &writes_at,
                                    static_by: &static_by,
                                    shared_by: &shared_by,
                                    root_procedure_seen,
                                };
                                if resolves(&writes[write], write, pass, &env) {
                                    allocated[write] = true;
                                    remaining -= 1;
                                    out.push(write as u32);
                                }
                            }
                        }
                        // The member counts as walked only after its own initializers were tried: a procedure's
                        // static that names the procedure itself does not resolve yet.
                        processed[event as usize] = true;
                        if node == 0 && events[event as usize].kind == EventKind::Procedure {
                            root_procedure_seen = true;
                        }
                    }
                }
            }
            position += 1;
        }
        if remaining == 0 {
            break;
        }
    }
    if remaining > 0 {
        // Not reachable for a program DreamMaker accepts (a reference cycle): keep source order for the rest.
        for (write, done) in allocated.iter().enumerate() {
            if !done {
                out.push(write as u32);
            }
        }
    }
    out
}

struct Env<'a> {
    tree: &'a Tree,
    finished: &'a [bool],
    processed: &'a [bool],
    allocated: &'a [bool],
    proc_events: &'a HashMap<(usize, SymbolId), Vec<u32>>,
    root_fields: &'a HashMap<SymbolId, Vec<u32>>,
    writes_at: &'a HashMap<u32, Vec<usize>>,
    static_by: &'a HashMap<(u32, SymbolId), usize>,
    shared_by: &'a HashMap<(usize, SymbolId), usize>,
    root_procedure_seen: bool,
}

fn event_done(env: &Env<'_>, event: u32) -> bool {
    env.processed[event as usize]
        && env
            .writes_at
            .get(&event)
            .map_or(true, |here| here.iter().all(|&write| env.allocated[write]))
}

fn resolves(write: &OrderWrite, this: usize, pass: u32, env: &Env<'_>) -> bool {
    if write.world && pass < 2 {
        return false;
    }
    let owner = env.tree.node(write.owner);
    for reference in &write.refs {
        match reference {
            Ref::Type(path) => match env.tree.node(*path) {
                Some(node) => {
                    if !env.finished[node] {
                        return false;
                    }
                }
                None => {
                    if pass < 2 {
                        return false;
                    }
                }
            },
            Ref::Procedure { owner: from, name } => {
                let mut node = env.tree.node(*from).unwrap_or(0);
                let mut found = false;
                loop {
                    if env.proc_events.get(&(node, *name)).is_some_and(|events| {
                        events.iter().any(|&event| env.processed[event as usize])
                    }) {
                        found = true;
                        break;
                    }
                    if node == 0 {
                        break;
                    }
                    node = env.tree.nodes[node].parent;
                }
                if !found {
                    return false;
                }
            }
            Ref::Ident(name) => {
                if write.procedure_static {
                    if let Some(&other) = env.static_by.get(&(write.event, *name)) {
                        if other != this {
                            if !env.allocated[other] {
                                return false;
                            }
                            continue;
                        }
                    }
                }
                let mut hit = None;
                let mut node = owner;
                while let Some(current) = node {
                    if current == 0 {
                        break;
                    }
                    if let Some(&other) = env.shared_by.get(&(current, *name)) {
                        if other != this {
                            hit = Some(other);
                        }
                        break;
                    }
                    node = Some(env.tree.nodes[current].parent);
                }
                if let Some(other) = hit {
                    if !env.allocated[other] {
                        return false;
                    }
                    continue;
                }
                if let Some(events) = env.root_fields.get(name) {
                    if !events.iter().any(|&event| event_done(env, event)) {
                        return false;
                    }
                }
            }
            Ref::Call(name) => {
                if env.proc_events.contains_key(&(0, *name)) && !env.root_procedure_seen {
                    return false;
                }
            }
        }
    }
    true
}
