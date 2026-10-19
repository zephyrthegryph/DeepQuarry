#!/usr/bin/env python3
"""Cost-balanced look-pin shards (tools/dq_focused_test.sh).

  dq_look_shard.py partition <types.txt> <n> <costs.tsv> <out-prefix>   writes <out-prefix>.<i>.txt for i in 0..n-1, prints n used
  dq_look_shard.py record <costs.tsv> <tests.log>...                     folds the per-type seconds of finished look worlds into costs.tsv

A look world probes one type at a time and logs "look pin: making <type>"; the gap to the next line is that type's cost. Round-robin by
index (sweep_owns) put several of the slowest mobs (a long space worm head is about 170 s; most objects are 0.05 s) in one world, so the
pins took as long as the unluckiest world. Partitioning by measured cost (longest first, onto the least loaded world) evens the worlds.
Which world probes a type does not change its rows: every unit starts from a reset block and a reseeded RNG.
"""
import collections
import datetime
import os
import re
import sys

LINE = re.compile(r'^\[(\d+-\d+-\d+ \d+:\d+:\d+\.\d+)\] look pin: making (\S+)')
DEFAULT_MOB = 1.3
DEFAULT_OTHER = 0.05


def read_costs(path):
    costs = {}
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                parts = line.rstrip('\n').split('\t')
                if len(parts) == 2:
                    try:
                        costs[parts[0]] = float(parts[1])
                    except ValueError:
                        pass
    except OSError:
        pass
    return costs


def default_cost(t):
    return DEFAULT_MOB if t.startswith('/mob') else DEFAULT_OTHER


def partition(types_path, n, costs_path, prefix):
    with open(types_path, encoding='utf-8') as f:
        types = [line.split('\t')[0].strip() for line in f if line.strip()]
    n = max(1, min(n, len(types))) if types else 1
    costs = read_costs(costs_path)
    load = [0.0] * n
    shards = [[] for _ in range(n)]
    for t in sorted(types, key=lambda t: -costs.get(t, default_cost(t))):
        i = min(range(n), key=load.__getitem__)
        shards[i].append(t)
        load[i] += costs.get(t, default_cost(t))
    for i, shard in enumerate(shards):
        with open(f'{prefix}.{i}.txt', 'w', encoding='utf-8', newline='\n') as f:
            for t in sorted(shard):
                f.write(t + '\n')
    print(n)
    sys.stderr.write('look shards: ' + ', '.join(f'{len(s)} types ~{l:.0f}s' for s, l in zip(shards, load)) + '\n')


def record(costs_path, logs):
    costs = read_costs(costs_path)
    seen = collections.defaultdict(float)
    for log in logs:
        try:
            lines = open(log, encoding='utf-8', errors='replace').read().splitlines()
        except OSError:
            continue
        events = []
        for line in lines:
            m = LINE.match(line)
            if m:
                events.append((datetime.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S.%f'), m.group(2)))
        for (t0, ty), (t1, _) in zip(events, events[1:]):
            gap = (t1 - t0).total_seconds()
            if 0 <= gap < 900:
                seen[ty] += gap
    if not seen:
        return
    costs.update(seen)
    tmp = f'{costs_path}.{os.getpid()}.tmp'
    os.makedirs(os.path.dirname(costs_path) or '.', exist_ok=True)
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        for t in sorted(costs):
            f.write(f'{t}\t{costs[t]:.3f}\n')
    os.replace(tmp, costs_path)


if __name__ == '__main__':
    if len(sys.argv) >= 6 and sys.argv[1] == 'partition':
        partition(sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5])
    elif len(sys.argv) >= 3 and sys.argv[1] == 'record':
        record(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
