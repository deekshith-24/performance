if [[ "${INSTALL_RESULTS:-false}" != "true" ]] ||
   [[ -z "${TOTAL_TIMEOUT:-}" && "${RUN_LOCUST:-false}" != "true" ]]; then
    return 0
fi

compile_locust_status=0
if [[ "${RUN_LOCUST:-false}" == "true" && "$LOCUST_RUN_PHASE" == "concurrent" ]]; then
    finish_concurrent_locust || compile_locust_status=$?
fi

# In-flight runs can use the remainder of their 20-minute pipeline timeout.
# The resulting PostgreSQL snapshot includes completions after load cutoff.
info "Waiting for the remaining compile PipelineRuns to finish"
compile_drain_deadline=$((SECONDS + 1200))
while true; do
    compile_active=$(kubectl get pipelineruns -A -l tekton.dev/pipeline=compile-go -o json | jq '
        [.items[] | select(.metadata.namespace | test("^benchmark[0-9]*$"))
         | select(all(.status.conditions[]?; .type != "Succeeded" or .status == "Unknown"))]
        | length')
    if [[ "$compile_active" == "0" ]]; then
        break
    fi
    if (( SECONDS >= compile_drain_deadline )); then
        fatal "Timed out waiting for ${compile_active} compile PipelineRun(s) to finish"
    fi
    sleep 15
done

info "Waiting five minutes for pruning and Results storage"
sleep 300

if [[ "${RUN_LOCUST:-false}" == "true" && "$LOCUST_RUN_PHASE" == "after-load" ]]; then
    : > locust-test.log
    : > locust-after-load.jsonl
    for compile_read in fetch-record fetch-all-records fetch-log; do
        printf '\n# %s\n' "$compile_read" >> locust-test.log
        if (run_locust "$compile_read" \
            "${LOCUST_HOST:-https://tekton-results-api-service.openshift-pipelines.svc.cluster.local:8080}" \
            "$LOCUST_USERS" "${LOCUST_SPAWN_RATE:-10}" "$LOCUST_DURATION" \
            "${LOCUST_WORKERS:-5}" "${LOCUST_EXTRA_CMD:-} --expect-workers=${LOCUST_WORKERS:-5}"); then
            continue
        fi
        compile_locust_status=1
        # A startup failure can occur before the log parser records an outcome.
        if ! jq -es --arg scenario "$compile_read" 'any(.[]; .scenario == $scenario)' \
            locust-after-load.jsonl >/dev/null; then
            jq -cn --arg scenario "$compile_read" \
                '{scenario: $scenario, status: "failed", error: "Locust exited before recording a summary"}' \
                >> locust-after-load.jsonl
        fi
        cleanup_locust "$compile_read" || fatal "Could not clean up $compile_read before the next Locust run"
    done
    if [[ "$compile_locust_status" -ne 0 ]]; then
        fatal "Post-ingestion Locust failed. Inspect locust-after-load.jsonl and locust-test.log"
    fi
fi

if [[ "$compile_locust_status" -ne 0 ]]; then
    fatal "Concurrent Locust failed. Inspect locust-concurrent.json and per-iteration logs"
fi
