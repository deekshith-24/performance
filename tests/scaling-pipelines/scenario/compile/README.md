# Go compile pilot

Each PipelineRun uses one fresh 8 GiB workspace and runs six tasks:

1. Check out a pinned Helm revision and download its Go modules.
2. Compile the Helm CLI from source.
3. Run `go vet` on the Helm CLI packages alongside the build.
4. Run selected unit tests once the build finishes.
5. Lint and render a sample chart with the built binary alongside the unit tests.
6. Package the binary after the checks pass and record its size and checksum.

The build and checks reuse the downloaded modules. The package and rendered
manifests stay in the workspace.

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

With Results enabled, `ci-scripts/collect-results.sh` includes Watcher workqueue
and API request metrics in `benchmark-tekton.json` and the raw monitoring CSVs.

For a time-boxed capacity test on a dedicated benchmark cluster, use
`TOTAL_TIMEOUT=3600`, `TEST_NAMESPACE=5`, and `TEST_CONCURRENT=10` or `16`.
Each namespace replenishes completed runs up to its concurrency limit. With
`INSTALL_RESULTS=true`, set `COMPILE_PRUNER_MODE=event` (the default) for a
five-minute TTL or `COMPILE_PRUNER_MODE=soft` for a CronJob that keeps 30 runs per
resource every five minutes. Both modes allow in-flight runs to finish and wait
five more minutes before collecting the PostgreSQL snapshot.
Timed downstream Results runs prepare Chains signing and wait for the configured
replica count before starting load. Count successful completions within the test window
separately from completions after the cutoff.
