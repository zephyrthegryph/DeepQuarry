#!/usr/bin/env python3
"""Prints the four-phase report of a `server_phases` bench run as Markdown (code/tests/benchmarks/server_phases.dm).

  python tools/ci/bench_phases_report.py [run.json]      # default: the newest run under data/bench/runs holding the scenario
"""
import glob
import json
import os
import sys

ROWS = [
    ('Startup', ['startup_launch_to_ready_s', 'startup_init_s', 'startup_cpu_s', 'startup_peak_private_mb', 'settled_private_mb',
                 'settled_rust_heap_mb', 'settled_instances_total', 'startup_machine_cpu_pct']),
    ('Idle', ['log_world_state_us', 'log_timestamp_us', 'idle_tick_avg', 'idle_tick_p50', 'idle_tick_p95', 'idle_tick_p99', 'idle_tick_max', 'idle_overruns', 'idle_tps', 'idle_tidi_pct',
              'idle_dd_cpu_pct', 'idle_growth_mb_per_min', 'idle_private_mb', 'idle_machine_cpu_pct']),
    ('Explosion', ['explosion_settle_s', 'explosion_longest_stall_s', 'explosion_tick_max', 'explosion_overruns', 'explosion_tidi_pct',
                   'explosion_dd_cpu_pct', 'explosion_private_mb', 'explosion_machine_cpu_pct']),
    ('Post-explosion', ['post_recovery_s', 'post_tick_avg', 'post_tick_p95', 'post_tick_p99', 'post_overruns', 'post_tidi_pct', 'post_dd_cpu_pct',
                        'post_peak_private_mb', 'post_retained_mb', 'post_rust_retained_mb', 'before_instances_total', 'post_instances_total',
                        'post_gc_collected', 'post_hard_deletes', 'post_machine_cpu_pct']),
]


def main():
    paths = sys.argv[1:] or sorted(glob.glob('data/bench/runs/*.json'), key=os.path.getmtime, reverse=True)
    for path in paths:
        with open(path, encoding='utf-8') as f:
            run = json.load(f)
        metrics = run.get('summary', {}).get('server_phases')
        if metrics:
            break
    else:
        sys.exit('no run with server_phases')
    profiled = any(i.get('profiles') and any('profiler' in p for p in i['profiles']) for i in run['iterations'])
    print(f"### {run.get('label') or run.get('id')} ({run['map']})\n")
    print(f"{'PROFILED' if profiled else 'unprofiled'}; load {json.dumps(run['load'])}; failures {run['failures'] or 'none'}\n")
    print('| phase | metric | median | unit |\n|---|---|---|---|')
    for phase, names in ROWS:
        for name in names:
            if name in metrics:
                print(f"| {phase} | {name} | {metrics[name]['median']:.2f} | {metrics[name]['unit']} |")
    work = sorted(k for k in metrics if '_work_' in k)
    if work:
        print('\nLoad-independent work: ' + ', '.join(f"{k} {metrics[k]['median']:.0f}" for k in work))
    inits = sorted(((k[len('startup_init_ms_'):], v['median']) for k, v in metrics.items() if k.startswith('startup_init_ms_')), key=lambda r: -r[1])
    print('\nInit by system (s): ' + ', '.join(f'{k} {v / 1000:.1f}' for k, v in inits[:12]))
    detail = run['iterations'][-1]['scenarios']['server_phases'].get('details', {})
    profile = {k: v for k, v in (detail.get('explosion_profile') or {}).items() if k.startswith(('epoch_', 'last_'))}
    print('\nBlast: ' + json.dumps(detail.get('site')) + ' ' + json.dumps(profile))


if __name__ == '__main__':
    main()
