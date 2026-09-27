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

/// Commands per [`Batch`] chunk. A queue grows by whole chunks of this
/// many commands, so it never asks the allocator for one large block: in
/// DreamDaemon's 32-bit address space a doubling `Vec` of big commands
/// (a gas `Put` is 144 bytes) failed for want of 9 MB of contiguous space.
pub const BATCH_CHUNK: usize = 1024;

/// A run of commands in sequence order, stored as fixed-size chunks.
#[derive(Clone, Debug, PartialEq)]
pub struct Batch<O> {
    chunks: Vec<Vec<Sequenced<O>>>,
    len: usize,
}

impl<O> Default for Batch<O> {
    fn default() -> Self {
        Self::new()
    }
}

impl<O> Batch<O> {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            chunks: Vec::new(),
            len: 0,
        }
    }

    /// A batch holding `commands`, in order.
    #[must_use]
    pub fn from_vec(commands: Vec<Sequenced<O>>) -> Self {
        let mut batch = Self::new();
        for c in commands {
            batch.push(c);
        }
        batch
    }

    pub fn push(&mut self, command: Sequenced<O>) {
        match self.chunks.last_mut() {
            Some(chunk) if chunk.len() < BATCH_CHUNK => chunk.push(command),
            _ => {
                let mut chunk = Vec::with_capacity(BATCH_CHUNK);
                chunk.push(command);
                self.chunks.push(chunk);
            }
        }
        self.len += 1;
    }

    /// Moves every command of `other` to the end of this batch.
    pub fn append(&mut self, other: &mut Self) {
        self.len += other.len;
        other.len = 0;
        self.chunks.append(&mut other.chunks);
    }

    #[must_use]
    pub fn last(&self) -> Option<&Sequenced<O>> {
        self.chunks.last().and_then(|c| c.last())
    }

    #[must_use]
    pub const fn len(&self) -> usize {
        self.len
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// The commands, in order.
    pub fn iter(&self) -> impl Iterator<Item = &Sequenced<O>> {
        self.chunks.iter().flatten()
    }

    /// Takes every command out, in order, leaving the batch empty.
    pub fn drain(&mut self) -> impl Iterator<Item = Sequenced<O>> {
        self.len = 0;
        std::mem::take(&mut self.chunks).into_iter().flatten()
    }

    /// Heap bytes the batch holds (chunk capacities).
    #[must_use]
    pub fn capacity_bytes(&self) -> usize {
        self.chunks.iter().map(Vec::capacity).sum::<usize>() * size_of::<Sequenced<O>>()
            + self.chunks.capacity() * size_of::<Vec<Sequenced<O>>>()
    }
}

impl<O: Clone> Batch<O> {
    /// The commands as one `Vec` (the flight recorder's format).
    #[must_use]
    pub fn to_vec(&self) -> Vec<Sequenced<O>> {
        self.iter().cloned().collect()
    }
}

/// The main-thread side of an owner's command queue.
#[derive(Debug)]
pub struct CommandBuffer<O> {
    next: u64,
    pending: Batch<O>,
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
            pending: Batch::new(),
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
    pub const fn len(&self) -> usize {
        self.pending.len()
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }

    /// Heap bytes the queue holds (its capacity, not just its length).
    #[must_use]
    pub fn capacity_bytes(&self) -> usize {
        self.pending.capacity_bytes()
    }

    /// Swaps the queue out, leaving an empty one.
    pub fn take(&mut self) -> Batch<O> {
        std::mem::take(&mut self.pending)
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
        assert_eq!(batch.len(), 2);
        assert_eq!(buf.issue(), Seq(3));
        assert_eq!(buf.last_issued(), Seq(3));
    }

    #[test]
    fn batches_grow_by_chunks_and_keep_order() {
        let mut buf = CommandBuffer::<Op<u8, u8>>::new();
        let n = BATCH_CHUNK * 2 + 5;
        for i in 0..n {
            buf.push(u32::try_from(i).unwrap(), Op::Take);
        }
        let mut batch = buf.take();
        assert_eq!(batch.len(), n);
        assert_eq!(batch.chunks.len(), 3);
        assert!(batch.chunks.iter().all(|c| c.capacity() == BATCH_CHUNK));
        let mut more = Batch::from_vec(vec![Sequenced {
            seq: Seq(9999),
            target: 0,
            op: Op::Put(1),
        }]);
        batch.append(&mut more);
        assert!(more.is_empty());
        let seqs: Vec<u64> = batch.drain().map(|c| c.seq.0).collect();
        assert_eq!(seqs.len(), n + 1);
        assert!(seqs[..n].windows(2).all(|w| w[0] + 1 == w[1]));
        assert_eq!(seqs[n], 9999);
        assert!(batch.is_empty());
    }
}
