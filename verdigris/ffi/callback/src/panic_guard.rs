//! The panic-catching core of every `#[auxmacros::bind]`/`#[auxmacros::bind_raw_args]`
//! function.
//!
//! Extracted out of the `auxmacros` proc macro (which, being `proc-macro = true`, can't
//! export ordinary runtime items) so the catch/convert logic is a single, unit-testable
//! function instead of duplicated inline codegen. Every crate with FFI binds (`vg-gas`,
//! `vg-ffi`) already depends on this crate for the callback channel, so the macro emits a
//! call to `::auxcallback::panic_guard::run_guarded` rather than inlining
//! `catch_unwind`.
use byondapi::value::ByondValue;

/// Runs `f`, converting a panic into an `Err` instead of unwinding across the
/// `extern "C"` boundary into BYOND (which would abort DreamDaemon). `context` is
/// prefixed onto both a caught panic's message and a returned `Err`, so the runtime
/// visible to DM (via `byondapi_stack_trace`) says which bind failed.
pub fn run_guarded<F>(context: &str, f: F) -> eyre::Result<ByondValue>
where
	F: FnOnce() -> eyre::Result<ByondValue>,
{
	// SAFETY (soundness, not memory safety): bind bodies commonly capture `&mut`
	// arguments (e.g. mutable `ByondValue` refs) that aren't `UnwindSafe` by the
	// conservative default, even though a panic mid-body leaves nothing for the
	// caller to observe through them afterward -- the whole point of this wrapper is
	// that the process doesn't continue running the caller's code across the unwind.
	// The bind's `Err` is converted to a DM runtime and the callback/arena state that
	// matters for correctness (gas cells, jobs, etc.) is behind its own panic-safe
	// invariants, audited separately.
	let result = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
		Ok(result) => result,
		Err(payload) => {
			let msg = payload
				.downcast_ref::<&str>()
				.map(|s| (*s).to_string())
				.or_else(|| payload.downcast_ref::<String>().cloned())
				.unwrap_or_else(|| "unknown panic".to_string());
			Err(eyre::eyre!("panic: {msg}"))
		}
	};
	result.map_err(|err| err.wrap_err(context.to_string()))
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn ok_result_passes_through() {
		let result = run_guarded("in test", || Ok(ByondValue::null()));
		assert!(result.is_ok());
	}

	#[test]
	fn err_result_is_wrapped_with_context() {
		let result = run_guarded("in test `foo`", || Err(eyre::eyre!("boom")));
		let message = format!("{:?}", result.unwrap_err());
		assert!(message.contains("in test `foo`"));
		assert!(message.contains("boom"));
	}

	#[test]
	fn panic_is_caught_and_returns_an_error_instead_of_unwinding() {
		// This is the property the bind macro relies on: a panicking bound function
		// must never unwind across the FFI boundary into BYOND. If this test ever
		// panics instead of returning an Err, the guard is broken.
		let result = run_guarded("in test `panics`", || {
			panic!("this should never reach BYOND")
		});
		assert!(result.is_err());
		let message = format!("{:?}", result.unwrap_err());
		assert!(message.contains("panic:"));
		assert!(message.contains("this should never reach BYOND"));
	}

	#[test]
	fn panic_with_string_payload_is_caught() {
		let result = run_guarded("in test `panics_string`", || {
			panic!("{}", "formatted panic".to_string())
		});
		assert!(result.is_err());
	}
}
