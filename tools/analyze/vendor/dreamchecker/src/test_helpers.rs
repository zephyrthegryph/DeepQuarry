use dm::Context;
use std::borrow::Cow;

use crate::{run_inner, run_parallel_batched};

pub const NO_ERRORS: &[(u32, u16, &str)] = &[];

/// Parses and checks `buffer` serially, then again with the parallel pass (one body per batch, three threads), and requires the two
/// diagnostic lists to be identical; returns the serial context.
pub fn parse_a_file_for_test<S: Into<Cow<'static, str>>>(buffer: S) -> Context {
    let buffer: Cow<'static, str> = buffer.into();
    let serial = parse_and_check(buffer.clone(), |c, t| run_inner(c, t, false));
    let parallel = parse_and_check(buffer, |c, t| run_parallel_batched(c, t, false, 3, 1));
    let render = |c: &Context| c.errors().iter().map(|e| format!("{e:?}")).collect::<Vec<_>>();
    assert_eq!(render(&serial), render(&parallel), "the parallel pass must give the serial diagnostics");
    serial
}

fn parse_and_check(buffer: Cow<'static, str>, check: impl Fn(&Context, &dm::objtree::ObjectTree)) -> Context {
    let context = Context::default();

    let pp = dm::preprocessor::Preprocessor::from_buffer(&context, "unit_tests.rs".into(), buffer);

    let indents = dm::indents::IndentProcessor::new(&context, pp);

    let mut parser = dm::parser::Parser::new(&context, indents);
    parser.enable_procs();
    let tree = parser.parse_object_tree();

    check(&context, &tree);

    context
}

pub fn check_errors_match<S: Into<Cow<'static, str>>>(buffer: S, errorlist: &[(u32, u16, &str)]) {
    let context = parse_a_file_for_test(buffer);
    let errors = context.errors();
    let mut iter = errors.iter();
    for (line, column, desc) in errorlist {
        let nexterror = iter.next().unwrap();
        if nexterror.location().line != *line
            || nexterror.location().column != *column
            || nexterror.description() != *desc
        {
            panic!(
                "possible feature regression in dreamchecker:\nexpected error: {}:{}:{}\nfound error:    {}:{}:{}",
                *line,
                *column,
                *desc,
                nexterror.location().line,
                nexterror.location().column,
                nexterror.description()
            );
        }
    }
    if iter.next().is_some() {
        panic!("found more errors than was expected");
    }
}
