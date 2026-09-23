use byondapi::prelude::*;
use coarsetime::{Duration, Instant};
use eyre::Result;
use std::convert::TryFrom;

pub mod panic_guard;

type DeferredFunc = Box<dyn FnOnce() -> Result<()> + Send + Sync>;
type CallbackChannel = (flume::Sender<DeferredFunc>, flume::Receiver<DeferredFunc>);
pub type CallbackSender = flume::Sender<DeferredFunc>;
pub type CallbackReceiver = flume::Receiver<DeferredFunc>;

static CALLBACK_CHANNEL: std::sync::OnceLock<CallbackChannel> = std::sync::OnceLock::new();

pub fn clean_callbacks() {
	if let Some((_, rx)) = CALLBACK_CHANNEL.get() {
		rx.drain().for_each(std::mem::drop)
	};
}

fn with_callback_receiver<T>(f: impl Fn(&flume::Receiver<DeferredFunc>) -> T) -> T {
	f(&CALLBACK_CHANNEL.get_or_init(flume::unbounded).1)
}

/// This gives you a copy of the callback sender. Send to it with try_send or send, then later it'll be processed
/// if one of the process_callbacks functions is called for any reason.
pub fn byond_callback_sender() -> flume::Sender<DeferredFunc> {
	CALLBACK_CHANNEL.get_or_init(flume::unbounded).0.clone()
}

pub fn pending_callbacks() -> usize {
	CALLBACK_CHANNEL
		.get()
		.map_or(0, |(_, receiver)| receiver.len())
}

/// Reports a callback failure to DM's `/proc/byondapi_stack_trace`, best-effort.
///
/// This already runs from inside an error path, so it must never itself panic or
/// propagate a further error: if the string conversion or the global call fails, the
/// failure is logged with `tracing` and swallowed rather than unwinding into BYOND.
fn report_callback_error(e: eyre::Report) {
	let message = format!("{e:?}");
	match ByondValue::try_from(message.clone()) {
		Ok(error_string) => {
			if let Err(report_err) =
				byondapi::global_call::call_global_id(byond_string!("byondapi_stack_trace"), &[
					error_string,
				]) {
				tracing::error!(
					original_error = %message,
					report_error = %report_err,
					"failed to report callback error to byondapi_stack_trace"
				);
			}
		}
		Err(convert_err) => {
			tracing::error!(
				original_error = %message,
				convert_error = %convert_err,
				"failed to convert callback error into a ByondValue for reporting"
			);
		}
	}
}

/// Goes through every single outstanding callback and calls them.
fn process_callbacks() {
	with_callback_receiver(|receiver| {
		receiver
			.try_iter()
			.filter_map(|cb| cb().err())
			.for_each(report_callback_error)
	})
}

/// Goes through every single outstanding callback and calls them, until a given time limit is reached.
fn process_callbacks_for(duration: Duration) -> bool {
	let timer = Instant::now();
	with_callback_receiver(|receiver| {
		for callback in receiver.try_iter() {
			if let Err(e) = callback() {
				report_callback_error(e);
			}
			if timer.elapsed() >= duration {
				return true;
			}
		}
		false
	})
}

/// Goes through every single outstanding callback and calls them, until a given time limit in milliseconds is reached.
pub fn process_callbacks_for_millis(millis: u64) -> bool {
	process_callbacks_for(Duration::from_millis(millis))
}

/// This function is to be called from byond, preferably once a tick.
/// Calling with no arguments will process every outstanding callback.
/// Calling with one argument will process the callbacks until a given time limit is reached.
/// Time limit is in milliseconds.
/// This has to be manually hooked in the code, e.g.
/// ```ignore
/// // Illustrative only: `bind` and `ByondValue` come from the FFI crate's
/// // macro/byondapi context, which isn't available to a standalone doctest.
/// #[bind("/proc/process_atmos_callbacks")]
/// fn atmos_callback_handle(remaining: ByondValue) {
///     auxcallback::callback_processing_hook(remaining)
/// }
/// ```
pub fn callback_processing_hook(time_remaining: ByondValue) -> Result<ByondValue> {
	if time_remaining.is_num() {
		// `is_num()` just checked this, but the byondapi call can still fail (e.g. a
		// race with BYOND state), so handle it instead of unwrapping: a callback tick
		// is not worth crashing the DLL over.
		let limit = time_remaining
			.get_number()
			.map_err(|e| eyre::eyre!("callback_processing_hook: expected a number: {e}"))?
			as u64;
		Ok(process_callbacks_for_millis(limit).into())
	} else {
		process_callbacks();
		Ok(ByondValue::null())
	}
}
