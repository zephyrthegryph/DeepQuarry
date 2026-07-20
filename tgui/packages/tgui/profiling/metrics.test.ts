import { describe, expect, test } from 'bun:test';
import { summarizeLatestStartup, summarizeProfiler } from './metrics';

describe('TGUI profiler metrics', () => {
  test('reports stationary cursor and hit-target instability separately', () => {
    const summary = summarizeProfiler({
      actions: [],
      commits: [],
      frames: [],
      updates: [],
      cursors: [
        {
          at: 1,
          x: 4,
          y: 4,
          cursor: 'pointer',
          target: 'div.Button',
          stationary: false,
        },
        {
          at: 2,
          x: 4,
          y: 4,
          cursor: 'default',
          target: 'div.Button',
          stationary: true,
        },
        {
          at: 3,
          x: 4,
          y: 4,
          cursor: 'pointer',
          target: 'div.Button__content',
          stationary: true,
        },
      ],
    });
    expect(summary.stationaryCursorChanges).toBe(2);
    expect(summary.stationaryTargetChanges).toBe(1);
  });

  test('computes test and live distributions identically', () => {
    const summary = summarizeProfiler({
      actions: [],
      cursors: [],
      updates: [],
      commits: [1, 2, 3, 4].map((actualDuration) => ({
        interfaceName: 'benchmark',
        phase: 'update' as const,
        actualDuration,
        baseDuration: actualDuration,
        startTime: 0,
        commitTime: actualDuration,
      })),
      frames: [10, 16, 55].map((duration) => ({ at: duration, duration })),
    });
    expect(summary.commitAverage).toBe(2.5);
    expect(summary.commitP95).toBe(4);
    expect(summary.longFrames).toBe(1);
  });

  test('summarizes explicit startup stages', () => {
    const startup = summarizeLatestStartup([
      { at: 10, stage: 'document_ready' },
      { at: 100, stage: 'backend_received', interfaceName: 'PowerMonitor' },
      { at: 120, stage: 'chunk_load_started', interfaceName: 'PowerMonitor' },
      { at: 170, stage: 'chunk_load_finished', interfaceName: 'PowerMonitor' },
      { at: 220, stage: 'content_committed', interfaceName: 'PowerMonitor' },
      { at: 240, stage: 'first_paint', interfaceName: 'PowerMonitor' },
      { at: 260, stage: 'window_revealed', interfaceName: 'PowerMonitor' },
    ]);
    expect(startup).toEqual({
      interfaceName: 'PowerMonitor',
      backendToChunk: 20,
      chunkLoad: 50,
      backendToCommit: 120,
      commitToPaint: 20,
      backendToReveal: 160,
      documentToReveal: 250,
    });
  });
});
