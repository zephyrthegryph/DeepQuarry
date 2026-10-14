//! Source-domain oracle from the pinned BYOND 516.1687 compile-only captures:
//! initializer-receiver-contexts-20261010-root-c,
//! user-proc-initializer-domains-20261010-root, and
//! user-proc-instance-overrides-20261010-root (under E:/dq-cache/dmb-native-v2).
//! This is the production lowering/diagnostic path, not daemon transport.
use super::*;

fn production(
    source: &'static str,
) -> Result<(), crate::initializer_diagnostics::InitializerLoweringError> {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("instance-default.dme"),
        &Source(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let (pinned, _scalar) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
    let host = startup.resolver(&frontend, &pinned).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi(&frontend, &engine, &host, None, 1).unwrap();
    assert!(
        abi.prepared.diagnostics.is_empty(),
        "{:?}",
        abi.prepared.diagnostics
    );
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&frontend, &abi.prepared).unwrap();
    let bodies = lower_frontend_with_statics(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
    );
    assert!(bodies.diagnostics.is_empty(), "{:?}", bodies.diagnostics);
    let ordinary = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: startup.plan().symbols.as_ref(),
    };
    let current = crate::startup::StartupEvaluator {
        ordinary: &ordinary,
        resolver: &host,
        symbols: startup.plan().symbols.as_ref(),
        resource_search_context: None,
    };
    let evaluator = crate::initializer_policy::EngineCapturedEvaluator {
        engine: &engine,
        evaluator: &current,
    };
    crate::initializer_lowering::lower_captured(&frontend, &startup, &evaluator, &host, None)
        .map(|_| ())
}

#[test]
fn captured_instance_user_calls_produce_current_source_errors_through_pinned_lowering() {
    for (source, line, message) in [
        ("/proc/receiver_amount()\n    return 7\n/datum/probe\n    var/amount = receiver_amount()\n", 4, "=: expected a constant expression"),
        ("/proc/receiver_amount()\n    return 7\n/datum/probe\n    var/amount = list(receiver_amount())\n", 4, "=: expected a constant expression"),
        ("/proc/receiver_amount()\n    return 7\n/datum/item\n/datum/probe\n    var/amount = new/datum/item(receiver_amount())\n", 5, "=: expected a constant expression"),
        ("/proc/receiver_amount()\n    return 7\n/datum/probe\n    var/amount = 1\n/datum/probe\n    amount = receiver_amount()\n", 6, ": expected a constant expression"),
        ("/proc/receiver_amount()\n    return 7\n/datum/probe\n    var/amount = 1\n/datum/probe/child\n    amount = receiver_amount()\n", 6, ": expected a constant expression"),
        ("// current shifted origin\n\n/proc/receiver_amount()\n    return 7\n/datum/probe\n    var/amount = receiver_amount()\n", 6, "=: expected a constant expression"),
    ] {
        let crate::initializer_diagnostics::InitializerLoweringError::Diagnostics(errors) = production(source).unwrap_err() else { panic!("expected certified source diagnostics") };
        assert_eq!(errors.len(), 1, "{errors:?}");
        assert_eq!(errors[0].kind, DiagnosticKind::SourceError, "source={source:?}; errors={errors:?}");
        assert_eq!(errors[0].origin.path.as_path(), Path::new("instance-default.dme"));
        assert_eq!(errors[0].origin.line, line);
        assert_eq!(errors[0].message, message);
    }
}

#[test]
fn captured_global_static_and_local_user_calls_remain_legal_through_pinned_lowering() {
    for source in [
        "/proc/receiver_amount()\n    return 7\nvar/global/amount = receiver_amount()\n",
        "/proc/receiver_amount()\n    return 7\n/proc/probe()\n    var/static/amount = receiver_amount()\n    return amount\n",
        "/proc/receiver_amount()\n    return 7\n/proc/probe()\n    var/amount = receiver_amount()\n    return amount\n",
    ] { production(source).unwrap(); }
}
