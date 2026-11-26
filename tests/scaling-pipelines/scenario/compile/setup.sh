compile_task_count="${COMPILE_TASK_COUNT:-4}"
case "$compile_task_count" in
    4|12) ;;
    *) fatal "COMPILE_TASK_COUNT must be 4 or 12" ;;
esac

# shellcheck source=/dev/null
source scenario/common/lib.sh
create_pipeline_from_j2_template pipeline.yaml.j2 "task_count=${compile_task_count}"

if [[ -z "${TOTAL_TIMEOUT:-}" ]]; then
    return 0
fi

if [[ ! "$TOTAL_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
    fatal "TOTAL_TIMEOUT must be a positive number of seconds"
fi
TEST_PARAMS="--wait-for-duration=${TOTAL_TIMEOUT}"

if [[ -n "${DEPLOYMENT_CHAINS_CONTROLLER_HA_REPLICAS:-}" ]]; then
    chains_setup_tekton_tekton_
    wait_for_ready_pods 600 openshift-pipelines app=tekton-chains-controller \
        "$DEPLOYMENT_CHAINS_CONTROLLER_HA_REPLICAS"
fi

if [[ "${INSTALL_RESULTS:-false}" == "true" ]]; then
    case "${COMPILE_PRUNER_MODE:-event}" in
        event)
            kubectl patch tektonconfig config --type=merge -p '{"spec":{"pruner":{"disabled":true},"tektonpruner":{"disabled":false,"global-config":{"enforcedConfigLevel":"global","ttlSecondsAfterFinished":300,"historyLimit":1000}}}}'
            kubectl -n openshift-pipelines wait --for=create deployment/tekton-pruner-controller --timeout=5m
            kubectl -n openshift-pipelines rollout status deployment/tekton-pruner-controller --timeout=5m
            ;;
        soft)
            kubectl patch tektonconfig config --type=merge -p '{"spec":{"tektonpruner":{"disabled":true}}}'
            PRUNER_KEEP=30 PRUNER_SCHEDULE='*/5 * * * *' PRUNE_PER_RESOURCE=true pruner_start
            ;;
        *)
            fatal "COMPILE_PRUNER_MODE must be event or soft"
            ;;
    esac
fi
