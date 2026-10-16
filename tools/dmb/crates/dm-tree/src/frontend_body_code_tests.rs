use super::*;
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(state: &mut RetainedSemanticTree, text: &'static str) -> ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("body-code.dme"),
        &Source(text),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(state),
    )
    .unwrap()
}
struct Chunks {
    p: &'static str,
    q: &'static str,
}
impl dm_preprocess::SourceProvider for Chunks {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.file_name().and_then(|name| name.to_str()) {
            Some("p.dm") => Ok(self.p.into()),
            Some("q.dm") => Ok(self.q.into()),
            _ => Ok("#include \"q.dm\"\n#include \"p.dm\"\n".into()),
        }
    }
}
fn chunks(state: &mut RetainedSemanticTree, p: &'static str, q: &'static str) -> ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("body-code.dme"),
        &Chunks { p, q },
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(state),
    )
    .unwrap()
}
fn p_body(front: &ColdFrontend) -> &BodyOccurrence {
    front
        .bodies
        .iter()
        .find(|body| {
            front.snapshot.tree.member(body.member).unwrap().name == dm_ir::SymbolId::of("p")
        })
        .unwrap()
}
/// Include text whose last declaration closes a chunk, so the chunk of the include that follows
/// starts at its own first declaration. The chunker is content defined: a declaration ends a
/// chunk when the hash of its header line has its low four bits clear (or after 32 declarations).
/// Editing this text therefore never touches the following chunk, which only moves.
fn q_chunk(prefix: &str, last: u32) -> &'static str {
    let closes_chunk = |header: &str| {
        header
            .bytes()
            .fold(0xcbf29ce484222325u64, |hash, byte| {
                (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3)
            })
            & 15
            == 0
    };
    let tail = (0..)
        .map(|index| format!("/proc/q_tail{index}()"))
        .find(|header| closes_chunk(header))
        .unwrap();
    Box::leak(format!("{prefix}/proc/q()\n    return {last}\n{tail}\n    return {last}\n").into_boxed_str())
}
#[test]
fn body_code_owner_reuses_unchanged_chunks_with_current_shifted_origins() {
    let mut state = RetainedSemanticTree::default();
    // A changed sibling within the SAME source chunk conservatively remints
    // tokens. The producer's real reuse unit is an exact declaration chunk.
    let old = chunks(
        &mut state,
        "/proc/p(value = 1)\n    return value\n",
        q_chunk("", 2),
    );
    let shifted = chunks(
        &mut state,
        "/proc/p(value = 1)\n    return value\n",
        q_chunk("// shifted preceding include\n\n", 333),
    );
    let a = old.body_code(p_body(&old)).unwrap();
    let b = shifted.body_code(p_body(&shifted)).unwrap();
    assert!(Arc::ptr_eq(a.identity(), b.identity()));
    assert_eq!(a.termination(), b.termination());
    assert_ne!(
        a.occurrence().expanded_span.start,
        b.occurrence().expanded_span.start
    );
    let fresh = chunks(
        &mut RetainedSemanticTree::default(),
        "/proc/p(value = 1)\n    return value\n",
        q_chunk("// shifted preceding include\n\n", 333),
    );
    assert_eq!(b.occurrence().source, p_body(&fresh).source);
    assert_eq!(
        b.termination(),
        fresh.body_code(p_body(&fresh)).unwrap().termination()
    );
    let changed = chunks(
        &mut state,
        "/proc/p(value = 9)\n    return value\n",
        q_chunk("// shifted preceding include\n\n", 333),
    );
    assert!(!Arc::ptr_eq(
        b.identity(),
        changed.body_code(p_body(&changed)).unwrap().identity()
    ));
    let mut foreign = shifted.clone();
    foreign.bodies = Arc::from(foreign.bodies.to_vec());
    assert!(foreign.body_code(p_body(&foreign)).is_err());
}
#[test]
fn current_body_code_boundary_distinguishes_eof_and_following_declaration() {
    let mut state = RetainedSemanticTree::default();
    let eof = build(&mut state, "/proc/p()\n    return 1\n");
    let following = build(
        &mut state,
        "/proc/p()\n    return 1\n/proc/q()\n    return 2\n",
    );
    let a = eof.body_code(&eof.bodies[0]).unwrap();
    let b = following.body_code(&following.bodies[0]).unwrap();
    assert_eq!(a.termination(), dm_syntax::BodyTermination::ExhaustedInput);
    assert_eq!(
        b.termination(),
        dm_syntax::BodyTermination::DeclarationBoundary
    );
    assert_ne!(a.termination(), b.termination());
    for front in [&eof, &following] {
        for body in front.bodies.iter() {
            assert_eq!(
                front.body_code(body).unwrap().termination(),
                front.body_input(body).unwrap().termination()
            );
        }
    }
}
