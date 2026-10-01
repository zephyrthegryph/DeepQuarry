# RSC timestamps: native static evidence

The named RSC record stores two unsigned 32-bit timestamps. The reader/writer preserves both exactly. Fresh Dream Maker 516.1687 compilation writes current Unix time in the first and the source file modification time in the second. The translator now uses those values when creating new entries; existing archives retain their original timestamps on read/write.

## Loaded record layout

Native archive parser1023f6e0 stores timestamp at resource-record+0x24 (1023f727) and source_timestamp at+0x28 (1023f735). Kind, CRC, size and filename are independent fields. Parser1023f590 retains these records in the resource CRC tree.

## First timestamp: resource cache age

Routine1023dfb0 obtains Unix time through IAT103a653c, verified `_time64`. At1023e047 it subtracts record+0x24. Entries younger than172800seconds return without rewriting. Older entries are checked/read through1023e310; successful checks set+0x24 to current time at1023e06f and rewrite metadata through1023fc30.

This is a runtime path: resource manager10247b63 calls it before CRC lookup, and multiple VM operations call it. The manager ignores its return in the inspected path, so this observation does not prove absent payloads or a gameplay failure from zero timestamps.

Cache pruning1023c9e0 also obtains current time and calculates age cutoffs. It compares+0x24 at1023cbf3/1023cbfb. Unpinned entries older than the selected cutoff are tombstoned through1023f8b0 at1023cc1f. The routine is reachable from resource manager initialization10247d6d when the configured age field is enabled. A record flag at+0x3c suppresses deletion for pinned entries. This establishes cache lifecycle use rather than authoring-only metadata.

## Second timestamp: source freshness

Resource import/find routine1023e0f0 compares supplied source modification time against record+0x28 at1023e22f, and supplied size against+0x2c at1023e234. A change sends the operation through resource reconstruction. This is the compiler/file-cache freshness contract.

## Scope of the conclusion

Zero timestamps retain CRC identity, filenames and payload bytes but alter cache-age/freshness decisions. Current static evidence does not prove a missing-resource gameplay failure. New entries now use emission Unix time and source modification time. Paired tests verify the latter exactly and bound creation time around emission. Creation timestamps necessarily differ across independent compilations and remain separate from payload/order parity checks. No DreamDaemon was executed for this audit.

## Native positive timestamp conversion probes

Fresh native emission accepts filesystem mtime4294967419 as source_timestamp123 and mtime4294967296 as0. Positive values wrap modulo2^32 rather than clamp. Normalmtime1700000123 and signedmaximum2147483647 are unchanged. Installed Windows native compiler rejects mtime0,-1,1,2147483648 and pre1900 as cannot find file; this is a file-date discovery limitation, not a rule that serialized0 is invalid. The portable resource_timestamps fixture and integration test use explicitly set filesystem dates.
