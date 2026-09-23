//! Scenarios the replay tool can rebuild, and recording helpers.
//!
//! A log names the scenario that recorded it. A scenario builds the same
//! domains and tasks, in the same order, lists their codecs, and gives a
//! driver that submits synthetic commands (for `vg-replay record`).
//! New sims register here as they move onto `vg-core` (gas, heat, power):
//! each adds an entry to [`SCENARIOS`].

use vg_core::cow::ChunkLayout;
use vg_core::frame::Task;
use vg_core::owner::{Applied, Domain};
use vg_core::replay::{Codec, DecodeError, DomainCodec, Reader, codec, encode_log, state_hashes};
use vg_core::rng::StreamId;
use vg_core::sim::{Sim, SimBuilder, SimConfig};

/// Submits frame `n`'s synthetic commands.
pub type Driver = Box<dyn FnMut(&mut Sim, u64)>;

/// A built scenario.
pub struct Built {
    pub builder: SimBuilder,
    pub codecs: Vec<Box<dyn DomainCodec>>,
    pub driver: Driver,
}

/// A scenario's constructor.
pub type Build = fn(SimConfig) -> Built;

/// Every scenario the tool knows.
pub const SCENARIOS: &[(&str, Build)] = &[("toy_heat", toy_heat)];

/// Looks a scenario up by name.
#[must_use]
pub fn scenario(name: &str) -> Option<Build> {
    SCENARIOS.iter().find(|(n, _)| *n == name).map(|(_, b)| *b)
}

/// Records `frames` driven frames of scenario `name` (seed `seed`), settles,
/// and returns the encoded log with final state hashes.
///
/// # Errors
/// On an unknown scenario or a pool build failure.
pub fn record(name: &str, seed: u64, frames: u64) -> Result<Vec<u8>, String> {
    let build = scenario(name).ok_or_else(|| format!("unknown scenario {name:?}"))?;
    let Built {
        builder,
        codecs,
        mut driver,
    } = build(SimConfig {
        seed,
        record: true,
        ..SimConfig::default()
    });
    let mut sim = builder.build().map_err(|e| e.to_string())?;
    let mut log = Vec::new();
    for f in 0..frames {
        sim.begin_tick();
        driver(&mut sim, f);
        sim.dispatch_frame();
        sim.wait_for_frame();
        log.extend(sim.take_log().into_iter().flat_map(|l| l.frames));
    }
    sim.settle();
    log.extend(sim.take_log().into_iter().flat_map(|l| l.frames));
    let hashes = state_hashes(&sim, &codecs);
    Ok(encode_log(name, seed, log.iter(), &codecs, &hashes))
}

/// The toy heat field from `vg-core`'s sim tests: 1D diffusion plus seeded
/// sparks. Tests the tool and serves as a template.
pub struct ToyHeat;

/// A toy heat command.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum HeatCmd {
    Add(f32),
    Remove(f32),
}

impl Codec for HeatCmd {
    fn encode(&self, out: &mut Vec<u8>) {
        let (tag, v) = match *self {
            HeatCmd::Add(v) => (0u8, v),
            HeatCmd::Remove(v) => (1u8, v),
        };
        tag.encode(out);
        v.encode(out);
    }
    fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        let tag = u8::decode(r)?;
        let v = f32::decode(r)?;
        match tag {
            0 => Ok(HeatCmd::Add(v)),
            1 => Ok(HeatCmd::Remove(v)),
            t => Err(DecodeError(format!("bad heat command {t}"))),
        }
    }
}

impl Domain for ToyHeat {
    type Value = f32;
    type Command = HeatCmd;
    const NAME: &'static str = "toy_heat";

    fn apply(value: &mut f32, cmd: &HeatCmd) -> Applied {
        match *cmd {
            HeatCmd::Add(e) => {
                *value += e;
                Applied::default()
            }
            HeatCmd::Remove(e) => {
                let taken = e.min(*value);
                *value -= taken;
                Applied {
                    shortfall: e - taken,
                }
            }
        }
    }
}

/// Cells in the toy field.
pub const TOY_CELLS: u32 = 256;

fn toy_heat(config: SimConfig) -> Built {
    let mut b = SimBuilder::new(config);
    let heat = b.add_domain::<ToyHeat>(ChunkLayout::linear_with_chunk(TOY_CELLS, 16));
    let state = heat.state();
    b.add_task(
        Task::new("diffuse", move |ctx| {
            let mut st = ctx.write(state);
            st.store.allocate_all();
            let old = st.store.snapshot();
            let layout = old.layout();
            st.store.par_for_each_chunk_mut(|chunk, cells| {
                for (i, cell) in cells.iter_mut().enumerate() {
                    let Some(index) = layout.index_of(chunk, i) else {
                        continue;
                    };
                    let here = old.get(index).unwrap_or_default();
                    let left = index
                        .checked_sub(1)
                        .and_then(|j| old.get(j))
                        .unwrap_or(here);
                    let right = old.get(index + 1).unwrap_or(here);
                    *cell = here + 0.1 * (left + right - 2.0 * here);
                }
            });
        })
        .writes(state.id()),
    );
    b.add_task(
        Task::new("spark", move |ctx| {
            let mut rng = ctx.rng(StreamId::named("spark"));
            let cell = u32::try_from(rng.next_u64() % u64::from(TOY_CELLS)).unwrap_or(0);
            if let Some(v) = ctx.write(state).store.get_mut(cell) {
                *v += 1.0;
            }
        })
        .writes(state.id())
        .every(3),
    );
    let driver: Driver = Box::new(move |sim, f| {
        let cell = u32::try_from((f * 37) % u64::from(TOY_CELLS)).unwrap_or(0);
        #[allow(clippy::cast_precision_loss)]
        let amount = (f % 5) as f32 + 0.5;
        let port = sim.port(heat);
        let _ = port.submit(cell, HeatCmd::Add(amount));
        if f % 4 == 3 {
            let _ = port.submit(cell, HeatCmd::Remove(2.0));
        }
    });
    Built {
        builder: b,
        codecs: vec![codec(heat)],
        driver,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vg_core::recorder::FlightRecorder;
    use vg_core::replay::{decode_log, verify};

    fn verify_bytes(bytes: &[u8]) -> vg_core::replay::Verdict {
        verify(bytes, |head| {
            let b = scenario(&head.scenario).ok_or("unknown")?(SimConfig::default());
            Ok((b.builder, b.codecs))
        })
        .unwrap()
    }

    #[test]
    fn recorded_log_replays_bit_for_bit() {
        let bytes = record("toy_heat", 11, 40).unwrap();
        let verdict = verify_bytes(&bytes);
        assert!(verdict.frames >= 40);
        assert_eq!(verdict.expected.len(), 1);
        assert!(verdict.ok(), "{verdict:?}");
    }

    #[test]
    fn tampered_log_mismatches() {
        let mut bytes = record("toy_heat", 11, 12).unwrap();
        // Flip a bit in the recorded hash (the last 8 bytes).
        let n = bytes.len();
        bytes[n - 1] ^= 1;
        assert!(!verify_bytes(&bytes).ok());
    }

    #[test]
    fn roundtrip_preserves_frames() {
        let bytes = record("toy_heat", 3, 8).unwrap();
        let b = toy_heat(SimConfig::default());
        let (head, log, hashes) = decode_log(&bytes, &b.codecs).unwrap();
        assert_eq!(head.scenario, "toy_heat");
        assert_eq!(head.seed, 3);
        assert_eq!(hashes.len(), 1);
        let again = encode_log("toy_heat", 3, log.frames.iter(), &b.codecs, &hashes);
        assert_eq!(again, bytes);
    }

    #[test]
    fn flight_recorder_ring_dumps_and_replays_while_complete() {
        let Built {
            builder,
            codecs,
            mut driver,
        } = toy_heat(SimConfig {
            seed: 5,
            record: true,
            ..SimConfig::default()
        });
        let mut sim = builder.build().unwrap();
        let mut rec = FlightRecorder::new(64, 5);
        for f in 0..10 {
            sim.begin_tick();
            driver(&mut sim, f);
            sim.dispatch_frame();
            sim.wait_for_frame();
            assert!(!rec.capture(&mut sim));
        }
        sim.settle();
        rec.capture(&mut sim);
        assert!(rec.complete());
        let text = rec.dump_text(&codecs);
        assert!(
            text.contains("toy_heat: #1 cell 0: Apply(Add(0.5))"),
            "{text}"
        );
        let bytes = rec.dump_log("toy_heat", &codecs, &state_hashes(&sim, &codecs));
        assert!(verify_bytes(&bytes).ok());

        let mut small = FlightRecorder::new(3, 5);
        for f in 0..6 {
            sim.begin_tick();
            driver(&mut sim, f);
            sim.dispatch_frame();
            sim.wait_for_frame();
            small.capture(&mut sim);
        }
        assert_eq!(small.len(), 3);
        assert!(!small.complete());
    }
}
