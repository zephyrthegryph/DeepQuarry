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
#[test]
fn body_code_owner_reuses_unchanged_chunks_with_current_shifted_origins() {
    let mut state = RetainedSemanticTree::default();
    let old = build(
        &mut state,
        "/proc/p(value = 1)\n    return value\n/proc/q()\n    return 2\n",
    );
    let shifted = build(
        &mut state,
        "\n/proc/p(value = 1)\n    return value\n/proc/q()\n    return 3\n",
    );
    let a = old.body_code(&old.bodies[0]).unwrap();
    let b = shifted.body_code(&shifted.bodies[0]).unwrap();
    assert!(Arc::ptr_eq(a.identity(), b.identity()));
    assert_eq!(a.termination(), b.termination());
    assert_ne!(a.occurrence().source.line, b.occurrence().source.line);
    let fresh = build(
        &mut RetainedSemanticTree::default(),
        "\n/proc/p(value = 1)\n    return value\n/proc/q()\n    return 3\n",
    );
    assert_eq!(
        b.termination(),
        fresh.body_code(&fresh.bodies[0]).unwrap().termination()
    );
    let changed = build(
        &mut state,
        "\n/proc/p(value = 9)\n    return value\n/proc/q()\n    return 3\n",
    );
    assert!(!Arc::ptr_eq(
        b.identity(),
        changed.body_code(&changed.bodies[0]).unwrap().identity()
    ));
    let mut foreign = shifted.clone();
    foreign.bodies = Arc::from(foreign.bodies.to_vec());
    assert!(foreign.body_code(&foreign.bodies[0]).is_err());
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
