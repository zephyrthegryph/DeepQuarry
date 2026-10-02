-- Server metrics, events and test/benchmark history, written by GLOB.metrics_service
-- (code/modules/metrics/) and tools/admin-viewer/ingest.ts, read by tools/admin-viewer.
-- Rounds are the existing `round` table (SSdbcore); round_id here refers to round.id.

-- One row per metric name. category/subcategory drive the viewer's breakdowns
-- (e.g. mc / Air / cost_ms, lane / machine / backlog, players / online).
CREATE TABLE IF NOT EXISTS `metric_key` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(128) NOT NULL,
  `category` VARCHAR(32) NOT NULL,
  `subcategory` VARCHAR(64) NOT NULL DEFAULT '',
  `unit` VARCHAR(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Raw samples (every metrics_sample_interval). Pruned after metrics_retention_days;
-- metric_round keeps the per-round summary forever.
CREATE TABLE IF NOT EXISTS `metric_sample` (
  `round_id` INT(11) NOT NULL,
  `key_id` INT(11) NOT NULL,
  `t` INT(11) NOT NULL COMMENT 'seconds since round initialize',
  `ts` DATETIME NOT NULL,
  `value` DOUBLE NOT NULL,
  PRIMARY KEY (`round_id`, `key_id`, `t`),
  KEY `ts` (`ts`),
  KEY `round_ts` (`round_id`, `ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Per-round distribution of each metric, written at round end (and at shutdown).
CREATE TABLE IF NOT EXISTS `metric_round` (
  `round_id` INT(11) NOT NULL,
  `key_id` INT(11) NOT NULL,
  `n` INT(11) NOT NULL,
  `mean` DOUBLE NOT NULL,
  `min` DOUBLE NOT NULL,
  `p50` DOUBLE NOT NULL,
  `p95` DOUBLE NOT NULL,
  `p99` DOUBLE NOT NULL,
  `max` DOUBLE NOT NULL,
  PRIMARY KEY (`round_id`, `key_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Things that happened: runtimes, tick overruns, tickets, admin verbs, round start/end.
-- signature groups repeats (a runtime's file:line:message hash, a ticket id, a verb type).
CREATE TABLE IF NOT EXISTS `metric_event` (
  `id` BIGINT(20) NOT NULL AUTO_INCREMENT,
  `round_id` INT(11) NOT NULL,
  `t` INT(11) NOT NULL,
  `ts` DATETIME NOT NULL,
  `kind` VARCHAR(32) NOT NULL,
  `category` VARCHAR(64) NOT NULL DEFAULT '',
  `signature` VARCHAR(64) NOT NULL DEFAULT '',
  `ckey` VARCHAR(32) NOT NULL DEFAULT '',
  `message` VARCHAR(512) NOT NULL DEFAULT '',
  `payload` TEXT NULL,
  PRIMARY KEY (`id`),
  KEY `kind_ts` (`kind`, `ts`),
  KEY `round_kind` (`round_id`, `kind`),
  KEY `signature` (`kind`, `signature`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Unit-test and benchmark history (data/test-runs, data/bench/runs), loaded by ingest.ts.
CREATE TABLE IF NOT EXISTS `test_run` (
  `id` VARCHAR(96) NOT NULL,
  `ts` DATETIME NOT NULL,
  `commit_hash` VARCHAR(40) NOT NULL DEFAULT '',
  `branch` VARCHAR(128) NOT NULL DEFAULT '',
  `label` VARCHAR(64) NOT NULL DEFAULT '',
  `host` VARCHAR(64) NOT NULL DEFAULT '',
  `clean` TINYINT(1) NOT NULL DEFAULT 0,
  `duration_s` DOUBLE NOT NULL DEFAULT 0,
  `passed` INT(11) NOT NULL DEFAULT 0,
  `failed` INT(11) NOT NULL DEFAULT 0,
  `skipped` INT(11) NOT NULL DEFAULT 0,
  `focused` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `ts` (`ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `test_result` (
  `run_id` VARCHAR(96) NOT NULL,
  `test` VARCHAR(160) NOT NULL,
  `status` TINYINT(4) NOT NULL COMMENT '0 pass, 1 fail, 2 skip',
  `duration_s` DOUBLE NOT NULL DEFAULT 0,
  `runtimes` INT(11) NOT NULL DEFAULT 0,
  `message` VARCHAR(512) NOT NULL DEFAULT '',
  PRIMARY KEY (`run_id`, `test`),
  KEY `test` (`test`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `bench_run` (
  `id` VARCHAR(96) NOT NULL,
  `ts` DATETIME NOT NULL,
  `commit_hash` VARCHAR(40) NOT NULL DEFAULT '',
  `branch` VARCHAR(128) NOT NULL DEFAULT '',
  `label` VARCHAR(64) NOT NULL DEFAULT '',
  `host` VARCHAR(64) NOT NULL DEFAULT '',
  `map` VARCHAR(64) NOT NULL DEFAULT '',
  `iterations` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `ts` (`ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- One value per (run, metric): the median over the run's measured iterations.
CREATE TABLE IF NOT EXISTS `bench_metric` (
  `run_id` VARCHAR(96) NOT NULL,
  `name` VARCHAR(128) NOT NULL,
  `category` VARCHAR(32) NOT NULL,
  `value` DOUBLE NOT NULL,
  `unit` VARCHAR(16) NOT NULL DEFAULT '',
  `better` VARCHAR(8) NOT NULL DEFAULT 'none' COMMENT 'lower, higher or none',
  PRIMARY KEY (`run_id`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
