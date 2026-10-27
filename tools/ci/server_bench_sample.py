#!/usr/bin/env python3
"""Live-server sampler for benchmarking a running DreamDaemon world (doc/rewrite/server_bench_20261027.md).

  python tools/ci/server_bench_sample.py sample --port 1337 --pid <dd pid> --out <dir> [--phase-file <f>] [--seconds N]
  python tools/ci/server_bench_sample.py summary --out <dir>
  python tools/ci/server_bench_sample.py topic --port 1337 "kmsystems&reset=1"

`sample` polls the world's localhost diagnostic probes (code/game/world.dm): `kmticks` every 10 s (every tick's usage and
maptick from the flight recorder, which holds the last 30 s at 40 fps), `mcdiag` every 60 s, and the process memory of
DreamDaemon plus the machine load every 30 s. Rows carry the phase named in --phase-file, so one sampler covers a whole
run while the phase changes. Files written in --out: ticks.csv, proc.jsonl, mcdiag.jsonl. `summary` prints per-phase tick
statistics and the memory trend. Requires psutil.
"""
import argparse
import csv
import json
import os
import socket
import struct
import sys
import time

import psutil

LOAD_NAMES = ('dreamdaemon.exe', 'dd.exe', 'dmbc.exe', 'dm.exe', 'dreammaker.exe', 'cargo.exe', 'rustc.exe')


def topic(port, query, timeout=10.0):
    """One BYOND world/Topic call; returns the reply text (or a float as text)."""
    body = b'\x00' * 5 + ('?' + query).encode('utf-8') + b'\x00'
    packet = b'\x00\x83' + struct.pack('>H', len(body)) + body
    with socket.create_connection(('127.0.0.1', port), timeout=timeout) as s:
        s.sendall(packet)
        head = b''
        while len(head) < 4:
            chunk = s.recv(4 - len(head))
            if not chunk:
                raise ConnectionError('closed before header')
            head += chunk
        size = struct.unpack('>H', head[2:4])[0]
        data = b''
        while len(data) < size:
            chunk = s.recv(size - len(data))
            if not chunk:
                break
            data += chunk
    kind, payload = data[:1], data[1:]
    if kind == b'\x2a':
        return str(struct.unpack('<f', payload[:4])[0])
    return payload.rstrip(b'\x00').decode('utf-8', 'replace')


def phase_of(path):
    if not path:
        return ''
    try:
        with open(path, encoding='utf-8') as f:
            return f.read().strip()
    except OSError:
        return ''


def machine_load(own_pid):
    counts = {}
    for p in psutil.process_iter(['name', 'pid']):
        name = (p.info['name'] or '').lower()
        if name in LOAD_NAMES and p.info['pid'] != own_pid:
            counts[name] = counts.get(name, 0) + 1
    vm = psutil.virtual_memory()
    return {'cpu_pct': psutil.cpu_percent(interval=None), 'free_gb': round(vm.available / 2**30, 2), 'others': counts}


def sample(args):
    os.makedirs(args.out, exist_ok=True)
    proc = psutil.Process(args.pid)
    proc.cpu_percent(None)
    psutil.cpu_percent(None)
    ticks_path = os.path.join(args.out, 'ticks.csv')
    new_file = not os.path.exists(ticks_path)
    ticks_file = open(ticks_path, 'a', newline='', encoding='utf-8')
    writer = csv.writer(ticks_file)
    if new_file:
        writer.writerow(['wall', 'phase', 'tick', 'usage', 'maptick', 'players', 'state'])
    last_tick = 0
    next_proc = next_diag = 0.0
    end = time.time() + args.seconds if args.seconds else None
    while end is None or time.time() < end:
        now = time.time()
        phase = phase_of(args.phase_file)
        if not psutil.pid_exists(args.pid):
            print('world process gone', file=sys.stderr)
            return 1
        try:
            reply = json.loads(topic(args.port, f'kmticks&since={last_tick}'))
            for t, u, m in zip(reply['ticks'], reply['usage'], reply['maptick']):
                writer.writerow([round(now, 1), phase, t, u, m, reply['players'], reply['state']])
            if reply['ticks']:
                last_tick = reply['ticks'][-1]
            ticks_file.flush()
        except Exception as error:  # a busy or rebooting world: note it and keep going
            print(f'{time.strftime("%H:%M:%S")} kmticks failed: {error}', file=sys.stderr)
        if now >= next_proc:
            next_proc = now + 30
            try:
                mem = proc.memory_info()
                row = {'wall': round(now, 1), 'phase': phase, 'rss_mb': round(mem.rss / 2**20, 1),
                       'private_mb': round(getattr(mem, 'private', mem.vms) / 2**20, 1),
                       'cpu_pct': proc.cpu_percent(None), 'threads': proc.num_threads(), 'load': machine_load(args.pid)}
                with open(os.path.join(args.out, 'proc.jsonl'), 'a', encoding='utf-8') as f:
                    f.write(json.dumps(row) + '\n')
            except psutil.Error as error:
                print(f'process read failed: {error}', file=sys.stderr)
        if now >= next_diag:
            next_diag = now + 60
            try:
                diag = json.loads(topic(args.port, 'mcdiag'))
                diag.update({'wall': round(now, 1), 'phase': phase})
                with open(os.path.join(args.out, 'mcdiag.jsonl'), 'a', encoding='utf-8') as f:
                    f.write(json.dumps(diag) + '\n')
            except Exception as error:
                print(f'{time.strftime("%H:%M:%S")} mcdiag failed: {error}', file=sys.stderr)
        time.sleep(max(0.0, 10 - (time.time() - now)))
    return 0


def percentile(sorted_values, p):
    if not sorted_values:
        return 0
    return sorted_values[min(len(sorted_values) - 1, max(0, int(round(p * len(sorted_values) + 0.5)) - 1))]


def summary(args):
    by_phase = {}
    with open(os.path.join(args.out, 'ticks.csv'), encoding='utf-8') as f:
        for row in csv.DictReader(f):
            entry = by_phase.setdefault(row['phase'], {'usage': [], 'maptick': [], 'first': float(row['wall']), 'last': 0.0})
            entry['usage'].append(float(row['usage']))
            entry['maptick'].append(float(row['maptick']))
            entry['last'] = float(row['wall'])
    print('phase | ticks | span_min | mean | p50 | p95 | p99 | max | overruns(>100%) | maptick mean | maptick p99')
    for phase, e in by_phase.items():
        u = sorted(e['usage'])
        m = sorted(e['maptick'])
        over = sum(1 for v in u if v > 100)
        print(f"{phase or '-'} | {len(u)} | {round((e['last'] - e['first']) / 60, 1)} | {sum(u) / len(u):.1f} | {percentile(u, .5)} | "
              f"{percentile(u, .95)} | {percentile(u, .99)} | {u[-1]} | {over} | {sum(m) / len(m):.2f} | {percentile(m, .99)}")
    path = os.path.join(args.out, 'proc.jsonl')
    if os.path.exists(path):
        rows = [json.loads(line) for line in open(path, encoding='utf-8') if line.strip()]
        print('\nphase | samples | rss first | rss last | rss max | private last | cpu mean % | machine cpu mean % | other procs')
        phases = {}
        for r in rows:
            phases.setdefault(r['phase'], []).append(r)
        for phase, rs in phases.items():
            others = {}
            for r in rs:
                for k, v in r['load']['others'].items():
                    others[k] = max(others.get(k, 0), v)
            print(f"{phase or '-'} | {len(rs)} | {rs[0]['rss_mb']} | {rs[-1]['rss_mb']} | {max(r['rss_mb'] for r in rs)} | "
                  f"{rs[-1]['private_mb']} | {sum(r['cpu_pct'] for r in rs) / len(rs):.1f} | "
                  f"{sum(r['load']['cpu_pct'] for r in rs) / len(rs):.1f} | {others}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('sample')
    s.add_argument('--port', type=int, default=1337)
    s.add_argument('--pid', type=int, required=True)
    s.add_argument('--out', required=True)
    s.add_argument('--phase-file')
    s.add_argument('--seconds', type=float, default=0)
    m = sub.add_parser('summary')
    m.add_argument('--out', required=True)
    t = sub.add_parser('topic')
    t.add_argument('--port', type=int, default=1337)
    t.add_argument('query')
    args = parser.parse_args()
    if args.cmd == 'sample':
        return sample(args)
    if args.cmd == 'summary':
        return summary(args)
    print(topic(args.port, args.query))
    return 0


if __name__ == '__main__':
    sys.exit(main())
