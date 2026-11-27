# "timebased-sign-pruner" scenario

This scenario maintains the configured PipelineRun concurrency across benchmark
namespaces to exercise Pipelines, Chains, pruning, and Tekton Results. It does not
pace PipelineRuns to a fixed hourly arrival rate. Locust tests GetRecord,
ListRecords, and GetLog after ingestion by default, or repeatedly during ingestion
when concurrent mode is enabled. ListRecords reads the default first page; it
does not scan every record in the database.

## Execution Modes

This scenario supports two execution modes:

1. **Count-based mode**: Use `TEST_TOTAL` to run for a specific number of PipelineRuns (no time limit)
2. **Time-based mode**: Use `TOTAL_TIMEOUT` to run for a specific duration (ignores TEST_TOTAL)

**Note**: If both are set, `TOTAL_TIMEOUT` takes precedence (time-based mode). This handles the default `TEST_TOTAL=100` from `load-test.sh` gracefully.

### Examples

**Count-based execution:**
```bash
export TEST_TOTAL="1000"
# Scenario will create 1000 PipelineRuns
```

**Time-based execution:**
```bash
export TOTAL_TIMEOUT="7200"  # 2 hours
# Scenario will run for 2 hours
```

The following environment variables are available for controlling execution:
- **TEST_TOTAL**: Total number of PipelineRuns to execute (count-based mode, Default: 100 from load-test.sh)
- **TOTAL_TIMEOUT**: Total time for test execution in seconds (time-based mode, no default - must be explicitly set)
- **CHAINS_WAIT_TIME**: Wait period before enabling chains (Default: 600 = 10 mins)
- **PRUNER_WAIT_TIME**: Wait period before enabling pruner (Default: 600 = 10 mins)
- **TEST_PRUNER_ENABLED**: Set to `false` to keep the Kubernetes pruner disabled throughout the test (Default: `true`).
- **PRUNER_KEEP**: How many PipelineRuns/TaskRuns to retain (Default: 3)
- **PRUNER_SCHEDULE**: Cron schedule for the pruner (Default: `* * * * *`)
- **PRUNE_PER_RESOURCE**: Retain counts per PipelineRun/TaskRun resource (Default: true)

Soft-pruner Citi jobs use `PRUNER_KEEP=30`, `PRUNER_SCHEDULE=*/5 * * * *`, `PRUNER_WAIT_TIME=0`.

The following environment variables are available for controlling the PR/TR payload size and log outputs:
- **TEST_BIGBANG_MULTI_STEP__TASK_COUNT**: Total number of tasks per Pipeline (Default: 5 tasks)
- **TEST_BIGBANG_MULTI_STEP__STEP_COUNT**: Total number of steps per Task (Default: 10 steps)
- **TEST_BIGBANG_MULTI_STEP__LINE_COUNT**: Total number of unique output log lines per step (Default: 15 lines)
- **TEST_BIGBANG_MULTI_STEP__LOG_BYTES_PER_STEP**: Exact stdout bytes per step, including newlines (Default: `0`, preserving the existing line-count workload). A positive value replaces `LINE_COUNT` with runtime log generation, so larger logs do not enlarge the Task script. These repetitive synthetic logs compress well and do not model production log entropy or storage cost.

For a heavier synthetic workload, keep deployment tuning and pruning fixed.
Choose concurrency to fit the cluster's available pod slots: the upper bound on
active TaskRun pods is namespaces × concurrent PipelineRuns per namespace ×
parallel tasks per PipelineRun. Leave headroom for system pods and pod turnover.
For example:

```bash
export TEST_BIGBANG_MULTI_STEP__TASK_COUNT=32
export TEST_BIGBANG_MULTI_STEP__STEP_COUNT=3
export TEST_BIGBANG_MULTI_STEP__LOG_BYTES_PER_STEP=1048576
export TEST_NAMESPACE=5
export TEST_CONCURRENT=5
```

This produces 96 MiB of application stdout per successful PipelineRun, excluding
collector metadata, with up to 800 active TaskRun pods. Keep task/step counts and
concurrency fixed when subsequently comparing log-volume levels.
Start with a short run before a full benchmark; task count increases pod demand,
and more steps add containers to each TaskRun pod. This is a capacity experiment,
not a reproduction of Citi's production workload. Keep reporting achieved PLR/h
and TR/h, persistence, read latency/errors, collector byte rates, and resource use.

PostgreSQL collection includes pod CPU/memory/I/O/restarts and PVC usage/capacity
over time, where the cluster exposes those metrics. Collection also records final
database size and `results`/`records` table and index sizes under
`results.ResultsDB.queries`. Physical database sizes include PostgreSQL overhead;
they are not serialized object sizes. Final SQL snapshots alone do not measure
database growth rates.

The following environment variables are available to set Locust Test parameters:
- **LOCUST_USERS**: Total number of users to spawn (Default: 100)
- **LOCUST_SPAWN_RATE**: Number of users to spawn every second (Default: 10)
- **LOCUST_DURATION**: Total duration for locust testing (Default: 15m)
- **LOCUST_WORKERS**: Number of Locust worker pods (Default: 5)
- **LOCUST_EXTRA_CMD**: Additional Locust Command-line parameters.

This scenario **supports** multi-namespace testing through *TEST_NAMESPACE* env variable.

### Results finalizer diagnostics

Set `TEST_CAPTURE_FINALIZERS=true` before running `ci-scripts/load-test.sh` to
capture finalizer/storage transitions in `benchmark-output.json`. It is disabled
by default and does not change pruning or Results configuration.

Each tracked run then includes the full finalizer names in `finalizers_observed`,
the Results finalizers in `results_finalizers`, `results_finalizer_ever_observed`,
and a `finalizer_history` of changes. History entries record the observation time,
resource version, finalizers, `results.tekton.dev/stored`, deletion timestamp and
deletion event. The existing `finalizers` field continues to describe Chains only.

These are transitions seen by the benchmark observer, not a Kubernetes audit
trail. An unobserved Results finalizer does not prove that it was never attached.

### Authenticated Results API tests

Export `DEPLOYMENT_RESULTS_API_AUTH_DISABLE=false` for **both**
`ci-scripts/setup-cluster.sh` and `ci-scripts/load-test.sh`. Setup enables Results
API authentication and grants the `locust-operator:default` service account
read-only access to Results, records, and logs across namespaces. The Locust
operator uses this account for test pods; keep this namespace dedicated to the
benchmark. No bearer token is written to environment variables, ConfigMaps, or
artifacts. Locust reads its projected service-account token for each request so
rotation is respected.

Watcher authentication already uses its own service-account token. This switch
enables API enforcement, including Kubernetes TokenReview and SubjectAccessReview
calls. API QPS/burst tuning therefore exercises that client.
Leaving the switch unset preserves the previous setup behavior; `true` disables
API authentication explicitly. Reads run after ingestion by default; the concurrent
mode below runs them while PipelineRuns are being created.

### Repeated reads during ingestion

Concurrent mode cycles **GetRecord -> ListRecords -> GetLog**, one workload at a
time, while the normal pipeline benchmark continues. Set these variables for
`ci-scripts/load-test.sh` (in addition to the usual deployment/workload settings):

```bash
export RUN_LOCUST=true
export LOCUST_RUN_PHASE=concurrent
export LOCUST_DURATION=5m
export LOCUST_START_DELAY=300
export LOCUST_STOP_BEFORE_END=600
export TOTAL_TIMEOUT=3600
export LOCUST_USERS=25
export LOCUST_SPAWN_RATE=5
export LOCUST_WORKERS=5
```

The coordinator waits for a PipelineRun in `benchmark` (or `benchmark1` for a
multi-namespace test), then waits until the five-minute warm-up has elapsed from
its creation. It repeatedly launches fresh Locust tests, each with five minutes
of configured runtime. The 25 users are **total across all five workers**, and
each master waits for all configured workers. Pod startup and the user ramp are
not steady-state read time; the user ramp is included in Locust's runtime.

Reads must finish before minute 50, leaving at least ten minutes of ingestion
without Locust. Before starting another iteration the coordinator reserves its
full duration, 300 seconds for startup, and 60 seconds for cleanup. Therefore the
last read can finish earlier than minute 50, and the final cycle can contain
fewer than three scenarios. Startup/runtime timeouts are recorded as incomplete
iterations; they are not silently treated as successful short runs. Configuration
validation requires room for at least one complete three-scenario cycle.

Do not set `LOCUST_SCENARIO`; all three workloads are selected automatically.
To leave five minutes at the end instead, set `LOCUST_STOP_BEFORE_END=300`.
`LOCUST_WAIT_TIME` still controls the separate **post-ingestion** settling wait.
Concurrent mode skips the usual three quiet-period read tests.

Each iteration has its own log under `locust-concurrent/`. The summary
`locust-concurrent.json` retains its scenario, timestamps, request/failure counts,
throughput, latency statistics (including percentiles when present), and status.
`locust-test.log` also contains all iterations in sequence. Collection copies these
artifacts and stores the full summary as `results.ResultsAPIConcurrent`; it does
not overwrite earlier iterations with the last result for each endpoint.

Read errors remain in the results and the cycle continues. Tierdown reports a
failed test after the settling wait if any iteration failed, was incomplete, or
a scenario never ran. An ingestion exit or coordinator interruption stops the
active read test and cleans up its resources. Tierdown also checks that every
read window was bracketed by observed PipelineRun creation timestamps and ended
before the read cutoff, with at least one PipelineRun created within the window.
Each iteration records that creation count and the longest gap between creations
(including the window boundaries). This does not assert uninterrupted ingestion.
Compare per-iteration results with the pipeline/control-plane telemetry
for the same timestamps; these are sequential read workloads, not a mixed read
workload running all three endpoints simultaneously.

Measured metadata requests use explicit 10-second connect and 30-second read timeouts;
log requests use 30-second connect and 60-second read timeouts. A timeout remains
a failed request. The master waits up to ten seconds for worker reports after
ramp-up; the coordinator requires a report confirming the configured user count.
Completed-window measurements are retained even when that validation fails.
Transient Kubernetes API errors while discovering the first PipelineRun are
retried within the existing five-minute startup deadline.

Between iterations, cleanup retries deletions and verifies that the LocustTest,
ConfigMap and matching pods are absent, within the existing 60-second cleanup
budget. A timed-out deletion can recover if absence is subsequently verified;
recovered errors are retained in `cleanup_recovered_errors`. Unverifiable deletion
or remaining resources still fail the run and stop further read windows. Read
request failures and latency statistics are unchanged.

### Diagnosing log-read failures

Set `LOKI_QUERIER_REPLICAS=2` for `ci-scripts/setup-cluster.sh` to test two Loki
queriers. The default is one. Setup writes the replica count to the LokiStack
and waits for the requested deployment and ready pods when scaling above one.
`load-test.sh` reuses the installed settings; exporting this variable only for
the load script does not change the stack.

For the 1 MiB-per-TaskRun logging workload, the next capacity experiment uses
`LOKI_QUERIER_REPLICAS=4`, `LOKI_INGESTION_RATE_MB=32` and
`LOKI_INGESTION_BURST_MB=64` during setup. The ingestion settings apply only to
the `application` tenant, in the LokiStack API's MB units. Both ingestion values
must be supplied together as positive integers; leaving them empty preserves
the operator defaults. These allowances provide headroom above the observed
4 MiB/s rejection threshold, including log-envelope overhead. They do not
guarantee that the ingesters or queries can sustain the requested load. Record
CPU, memory, throttling and log failures when comparing with the earlier runs.
The workload, user count, Results timeout and Loki query timeout are unchanged.

Post-ingestion reads validate Locust's final summary, exit code, failed requests,
duration and reported user count. All three endpoints still run if one fails;
the test then fails and collection retains the failed endpoint's statistics.

When several Loki stacks use the same S3 bucket, setup adds the local OpenShift
cluster ID to Results' log queries using `LOGGING_PLUGIN_STATIC_LABELS`. The
collector indexes `openshift.cluster_id` as the `openshift_cluster_id` stream
label. Setup reads the ID automatically from `ClusterVersion/version` and applies
the query filter through the Tekton operator's Results API deployment options.
This works for local and Prow setup without additional environment variables or
AWS permissions. The original bucket and credentials are reused.

After updating an existing stack, verify using newly emitted logs: historical
streams without the cluster-ID label will not match the scoped query. This
narrows query selection, while storage, indexes, and compaction remain shared;
it does not establish independent storage isolation or prove a timeout fix.
The legacy 1.15 direct-S3 setup and upstream installation are unchanged.

`fetch-log` emits one `RESULTS_LOG_DIAGNOSTIC` JSON pool record per worker at
startup, and at most 50 failure samples per worker per window. Samples include
UTC request times, the log ID, elapsed milliseconds, HTTP status, response size,
and up to 1,024 characters of sanitized response text. Request headers are not
recorded. Common credential forms are redacted; CI artifact censoring still
applies. Every request continues to use the `/log` statistics name, and every
failure is counted even after sampling stops. Pools are selected independently
by each worker and rebuilt for each window.

Workers relay these bounded samples to the master as they happen, using Locust's
existing distributed connection. The master logs each sample with its worker ID
into the streamed per-iteration log, so normal operator deletion of worker pods
does not remove the captured evidence. Samples also remain in worker logs while
those pods exist. Relay failures are logged once per worker and do not suppress
HTTP failures; a broken distributed connection can still leave diagnostic gaps.

Concurrent master-log streams reconnect up to twice after an error without
restarting the read test. Reconnection replays retained master logs, so raw logs
can contain duplicate lines. Final metrics are still parsed from the final
shutdown summary. Exhausted retries preserve the failure and still attempt
cleanup; they do not make an incomplete window pass.

`collect-results.sh` takes one final Results API/Loki diagnostic snapshot before
monitoring installation and database dumps, with a 90-second collection budget.
Per-request failure samples are retained in the streamed master logs during each
window; full pod-log collection does not run between read windows.

The final snapshot has `results-loki-pod-logs/`, the compatible combined
`results-api-logs.txt` and `results-api-logs.json`, and
`results-log-diagnostics.json`. The JSON API summary preserves whole messages,
including embedded braces, plus pod/container identity. The diagnostic manifest
records collected streams, unavailable streams, pod images, resource settings,
restart counts and termination reasons, and selected LokiStack settings. Logs
are limited to the latest 10,000 lines per container since the requested start;
previous-container logs are attempted for restarted containers. Rotation, pod
deletion and collection deadlines can leave gaps, which the manifest makes
visible. Collection errors do not change the benchmark's pass/fail result.

Monitoring adds Loki component CPU, working-set memory, CPU throttling, restarts,
query-range latency and 5xx rates, plus total frontend queue depth, the worst
frontend's mean/p95 queue wait, and summed connected querier clients. This stack
uses frontend-managed queues. Inactive tenant queue series may disappear;
missing metrics remain unavailable rather than becoming zero. Confirm
the actual scrape labels and available metrics on the next cluster before
interpreting those series. Workload settings, pruning and service timeouts are
unchanged.

Run the concurrent cleanup regression tests without cluster access:

```bash
python3 tools/test_concurrent_locust_cleanup.py
```
