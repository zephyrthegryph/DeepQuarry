"""Per-lane timeline from the batch train's log, and the mean time of each gate phase.

    python3 tools/train/lane_times.py <train.log> [--since 2026-10-26T14:00:00Z] [--timings <dir of *.timings>]
    bash tools/dq_train.sh lanes [--since T]          (the same, on the train's own log and train-base/data/merge-gates)

For each lane episode (enqueue -> LANDED / dequeued; a bounce and a re-enqueue stay in one episode):
  waiting  = time queued while not part of a running cycle
  in-cycle = time inside cycles that included it (merge + gates + push)
  fixing   = time between a bounce and the next enqueue
  cyc/bnc  = cycles ridden / bounces
--timings: the mean seconds of every gate phase (gen, prepare, tests, ratchets, dreamchecker, analyze_tests, gates-wall, ...)
over the data/merge-gates/<sha>.timings files modified since --since.
"""
import argparse, glob, os, re, sys
from datetime import datetime, timezone

ap = argparse.ArgumentParser()
ap.add_argument("log")
ap.add_argument("since", nargs="?", default=None)
ap.add_argument("--since", dest="since_opt", default=None)
ap.add_argument("--timings", default=None)
args = ap.parse_args()
LOG = args.log
since = args.since_opt or args.since or "2026-10-26T14:00:00Z"
ts_re = re.compile(r'^(\S+Z) train\[\d+\]: (.*)$')

def t(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")

events = []
for line in open(LOG, encoding="utf-8", errors="replace"):
    m = ts_re.match(line.rstrip("\n"))
    if m and m.group(1) >= since:
        events.append((t(m.group(1)), m.group(2)))

open_ep = {}   # lane -> dict
done = []
cycle_start = None
cycle_lanes = []

def close(lane, when, outcome):
    ep = open_ep.pop(lane, None)
    if not ep:
        return
    if ep.get("in_cycle_since"):
        ep["cycle"] += (when - ep["in_cycle_since"]).total_seconds()
        ep["in_cycle_since"] = None
    ep["end"] = when
    ep["outcome"] = outcome
    total = (when - ep["start"]).total_seconds()
    if ep.get("bounced_at"):
        ep["fix"] += (when - ep["bounced_at"]).total_seconds()
    ep["wait"] = total - ep["cycle"] - ep["fix"]
    done.append(ep)

for when, msg in events:
    m = re.match(r'enqueued (\S+) tip (\S+) light=(\d)', msg)
    if m:
        lane = m.group(1)
        if lane in open_ep:  # re-enqueue of a new tip: keep the episode running
            ep = open_ep[lane]
            if ep.get("bounced_at"):
                ep["fix"] += (when - ep["bounced_at"]).total_seconds()
                ep["bounced_at"] = None
            continue
        open_ep[lane] = dict(lane=lane, start=when, cycle=0.0, cycles=0, in_cycle_since=None,
                             light=m.group(3) == "1", bounces=0, fix=0.0, bounced_at=None)
        continue
    m = re.search(r'chosen=\[([^\]]*)\]', msg)
    if m and msg.startswith("cycle:"):
        cycle_lanes = m.group(1).split()
        for lane in cycle_lanes:
            ep = open_ep.get(lane)
            if ep:
                ep["cycles"] += 1
                ep["in_cycle_since"] = when
        continue
    if msg.startswith("cycle done") or msg.startswith("nothing passed"):
        for lane in cycle_lanes:
            ep = open_ep.get(lane)
            if ep and ep["in_cycle_since"]:
                ep["cycle"] += (when - ep["in_cycle_since"]).total_seconds()
                ep["in_cycle_since"] = None
        cycle_lanes = []
        continue
    m = re.match(r'LANDED (\S+)', msg)
    if m:
        close(m.group(1), when, "landed")
        continue
    m = re.match(r'BOUNCED (\S+): (.{0,60})', msg)
    if m:
        lane = m.group(1)
        ep = open_ep.get(lane)
        if ep:
            ep["bounces"] += 1
            ep.setdefault("why", []).append(m.group(2).split(";")[0])
            # a bounce ends the train's hold; the lane's own fix time until re-enqueue counts as "fixing"
            if ep.get("in_cycle_since"):
                ep["cycle"] += (when - ep["in_cycle_since"]).total_seconds()
                ep["in_cycle_since"] = None
            ep["bounced_at"] = when
        continue
    m = re.match(r'dequeued (\S+)', msg)
    if m:
        close(m.group(1), when, "dequeued")

now = events[-1][0] if events else None
for lane, ep in list(open_ep.items()):
    close(lane, now, "QUEUED")

def fmt(s):
    s = int(s)
    return f"{s//3600}h{(s%3600)//60:02d}m" if s >= 3600 else f"{s//60}m{s%60:02d}s"

done.sort(key=lambda e: e["start"])
print(f"{'lane':34} {'outcome':8} {'total':>7} {'waiting':>7} {'in-cycle':>8} {'fixing':>7} {'cyc':>3} {'bnc':>3}")
tw = tc = tf = 0
for e in done:
    total = (e["end"] - e["start"]).total_seconds()
    tw += e["wait"]; tc += e["cycle"]; tf += e["fix"]
    print(f"{e['lane'][:34]:34} {e['outcome']:8} {fmt(total):>7} {fmt(e['wait']):>7} {fmt(e['cycle']):>8} {fmt(e['fix']):>7} {e['cycles']:>3} {e['bounces']:>3}"
          + (f"  ({'; '.join(e['why'])[:70]})" if e.get("why") else ""))
n = len(done)
if n:
    print(f"\n{n} lane episodes: mean waiting {fmt(tw/n)}, mean in-cycle {fmt(tc/n)}, mean fixing after bounce {fmt(tf/n)}; waiting share {100*tw/max(tw+tc+tf,1):.0f}%")


if args.timings:
    sums, counts = {}, {}
    cutoff = t(since).replace(tzinfo=timezone.utc).timestamp()
    files = [f for f in glob.glob(os.path.join(args.timings, "*.timings")) if os.path.getmtime(f) >= cutoff]
    for f in files:
        for line in open(f, encoding="utf-8", errors="replace"):
            m = re.match(r"^(\S+) (\d+)s", line)
            if m:
                sums[m.group(1)] = sums.get(m.group(1), 0) + int(m.group(2))
                counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    print(f"\ngate phases over {len(files)} gate run(s) since {since} (mean seconds, runs):")
    for k in sorted(sums, key=lambda k: -sums[k] / counts[k]):
        print(f"  {k:20} {sums[k] / counts[k]:7.0f}  ({counts[k]})")
