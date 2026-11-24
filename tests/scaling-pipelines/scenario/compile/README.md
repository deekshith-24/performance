# Go compile pilot

Each PipelineRun checks out a pinned Helm revision, downloads its Go modules,
compiles the Helm CLI from source, runs selected unit tests, and packages the
binary. Four sequential TaskRuns share a fresh 8 GiB workspace. Compile and test
use the modules downloaded during checkout. The package stays in the workspace.

Use a test cluster with OpenShift Pipelines, a default storage class that supports
ReadWriteOnce claims, and access to the public source and dependency registries.
The compiler image is pinned. The compile step requests and uses at most two
vCPUs, with a 2 GiB memory request and 4 GiB limit. These are starting points for
the pilot.

From the repository root, on a cluster without a `benchmark` namespace:

```bash
TEST_SCENARIO=compile TEST_NAMESPACE=1 TEST_TOTAL=5 TEST_CONCURRENT=1 \
  TEST_PARAMS='' TEST_DO_CLEANUP=false bash ci-scripts/load-test.sh
```

Use the TaskRun timestamps to measure each stage. The compile step logs wall
time, user and system CPU time, and the step cgroup's memory peak when available.
The package step logs its size and checksum. The harness keeps the PipelineRuns,
TaskRuns, and their workspaces for inspection.

For a time-boxed capacity test on a dedicated benchmark cluster, use
`TOTAL_TIMEOUT=3600`, `TEST_NAMESPACE=5`, and `TEST_CONCURRENT=10` or `16`.
Each namespace replenishes completed runs up to its concurrency limit. With
`INSTALL_RESULTS=true`, set `COMPILE_PRUNER_MODE=event` (the default) for a
five-minute TTL or `COMPILE_PRUNER_MODE=soft` for a CronJob that keeps 30 runs per
resource every five minutes. Both modes allow in-flight runs to finish and wait
five more minutes before collecting the PostgreSQL snapshot.
With Chains HA configured, it prepares signing and waits for the Chains replicas
before starting load. Count successful completions within the test window
separately from completions after the cutoff.
