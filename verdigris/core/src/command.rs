//! Sequence-numbered command buffers (`rust_core.md` §3.2).
//!
//! DM writes to a worker-owned entity become commands appended to its
//! owner's buffer on the main thread: amortised O(1), no locks (the buffer
//! is plain main-thread data). At each frame boundary the buffer is swapped
//! out whole and moved into the frame, which applies it in sequence order.
//!
//! Commands carry absolute amounts computed on the main thread (§3.2), so
//! the result DM saw is the result the worker applies.

/// A command sequence number, per owner. `Seq(0)` means "none yet"; the
/// first command is `Seq(1)`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Seq(pub u64);

/// What a command does to its target cell. `Put` and `Take` are generic
/// (registration and ownership transfer, §3.1); `Apply` is the domain's own
/// command.
#[derive(Clone, Debug, PartialEq)]
pub enum Op<V, C> {
    /// Set the cell to this value (register it, or transfer it in).
    Put(V),
    /// Reset the cell to its default (unregister it, or transfer it out).
    Take,
    /// A domain command.
    Apply(C),
}

/// A command with its sequence number and target cell.
#[derive(Clone, Debug, PartialEq)]
pub struct Sequenced<O> {
    pub seq: Seq,
    pub target: u32,
    pub op: O,
}

/// The main-thread side of an owner's command queue.
#[derive(Debug)]
pub struct CommandBuffer<O> {
    next: u64,
    pending: Vec<Sequenced<O>>,
}

impl<O> Default for CommandBuffer<O> {
    fn default() -> Self {
        Self::new()
    }
}

impl<O> CommandBuffer<O> {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            next: 1,
            pending: Vec::new(),
        }
    }

    /// Issues the next sequence number without queueing anything (used by
    /// the main-thread fallback, §3.11, which applies writes directly).
    pub fn issue(&mut self) -> Seq {
        let seq = Seq(self.next);
        self.next += 1;
        seq
    }

    /// Appends a command and returns its sequence number.
    pub fn push(&mut self, target: u32, op: O) -> Seq {
        let seq = self.issue();
        self.pending.push(Sequenced { seq, target, op });
        seq
    }

    /// Appends a command and returns its sequence number and a reference to
    /// it (so the caller can apply the same command to its overlay).
    pub fn push_ref(&mut self, target: u32, op: O) -> (Seq, &O) {
        let seq = self.push(target, op);
        (seq, &self.pending.last().expect("just pushed").op)
    }

    /// The last sequence number issued (`Seq(0)` if none).
    #[must_use]
    pub const fn last_issued(&self) -> Seq {
        Seq(self.next - 1)
    }

    /// Commands queued since the last [`take`](Self::take).
    #[must_use]
    pub fn len(&self) -> usize {
        self.pending.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }

    /// Swaps the queue out, leaving an empty one with the same capacity
    /// class (so steady-state submission does not reallocate).
    pub fn take(&mut self) -> Vec<Sequenced<O>> {
        let capacity = self.pending.len();
        std::mem::replace(&mut self.pending, Vec::with_capacity(capacity))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_in_order_and_swaps_out() {
        let mut buf = CommandBuffer::<Op<u8, u8>>::new();
        assert_eq!(buf.last_issued(), Seq(0));
        assert_eq!(buf.push(3, Op::Take), Seq(1));
        assert_eq!(buf.push(4, Op::Put(1)), Seq(2));
        let batch = buf.take();
        assert!(buf.is_empty());
        assert_eq!(batch.iter().map(|c| c.seq.0).collect::<Vec<_>>(), [1, 2]);
        assert_eq!(buf.issue(), Seq(3));
        assert_eq!(buf.last_issued(), Seq(3));
    }
}
