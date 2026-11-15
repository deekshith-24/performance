source scenario/common/lib.sh

# Locust test configurations
LOCUST_HOST="https://tekton-results-api-service.openshift-pipelines.svc.cluster.local:8080"
LOCUST_USERS=${LOCUST_USERS:-100}
LOCUST_SPAWN_RATE=${LOCUST_SPAWN_RATE:-10}
LOCUST_DURATION="${LOCUST_DURATION:-15m}"
LOCUST_WORKERS=${LOCUST_WORKERS:-5}
LOCUST_EXTRA_CMD="${LOCUST_EXTRA_CMD:-}"
LOCUST_WAIT_TIME=${LOCUST_WAIT_TIME:-600} # [Default: 10 mins]

if [ "${LOCUST_RUN_PHASE:-after-load}" == concurrent ]; then
    # Preserve failed read results, but still allow the usual post-load settling time.
    concurrent_locust_status=0
    wait "$CONCURRENT_LOCUST_PID" || concurrent_locust_status=$?
    CONCURRENT_LOCUST_PID=""
    python3 "scenario/$TEST_SCENARIO/concurrent-locust.py" --verify-overlap || concurrent_locust_status=$?
    trap - EXIT
    if [ -n "$CONCURRENT_LOCUST_PREVIOUS_EXIT_TRAP" ]; then
        eval "$CONCURRENT_LOCUST_PREVIOUS_EXIT_TRAP"
    fi
    wait_for_timeout "$LOCUST_WAIT_TIME" "allow final Results and log ingestion to settle"
fi

if [ "${LOCUST_RUN_PHASE:-after-load}" == after-load ]; then
    # Existing quiet-period tests; concurrent mode has already cycled all three.
    wait_for_timeout "$LOCUST_WAIT_TIME" "start Locust test"
    after_load_locust_status=0
    for locust_scenario in fetch-log fetch-record fetch-all-records; do
        # Retain all three measurements even when an earlier endpoint fails.
        run_locust "$locust_scenario" "$LOCUST_HOST" "$LOCUST_USERS" "$LOCUST_SPAWN_RATE" \
            "$LOCUST_DURATION" "$LOCUST_WORKERS" "$LOCUST_EXTRA_CMD" || after_load_locust_status=$?
    done
fi

# Update test end time
set_ended_now

if [ "${concurrent_locust_status:-0}" -ne 0 ]; then
    fatal "Concurrent Locust failed; inspect locust-concurrent.json and per-iteration logs"
fi
if [ "${after_load_locust_status:-0}" -ne 0 ]; then
    fatal "Post-ingestion Locust failed; inspect locust-test.log"
fi
