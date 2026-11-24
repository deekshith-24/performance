if [[ -z "${TOTAL_TIMEOUT:-}" || "${INSTALL_RESULTS:-false}" != "true" ]]; then
    return 0
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

info "Waiting five minutes for pruning and Results storage before collection"
sleep 300
