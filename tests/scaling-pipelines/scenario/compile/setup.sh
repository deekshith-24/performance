# shellcheck source=/dev/null
source scenario/common/lib.sh

if [[ "${RUN_LOCUST:-false}" == "true" ]]; then
    if [[ "${INSTALL_RESULTS:-false}" != "true" ]]; then
        fatal "Compile Locust reads require INSTALL_RESULTS=true"
    fi
    export LOCUST_RUN_PHASE="${LOCUST_RUN_PHASE:-after-load}"
    export LOCUST_DURATION="${LOCUST_DURATION:-5m}"
    export LOCUST_USERS="${LOCUST_USERS:-250}"
    case "$LOCUST_RUN_PHASE" in
        after-load) ;;
        concurrent)
            export TEST_SCENARIO TEST_NAMESPACE
            python3 scenario/timebased-sign-pruner/concurrent-locust.py --validate
            ;;
        *) fatal "LOCUST_RUN_PHASE must be after-load or concurrent" ;;
    esac
fi

if [[ -z "${TOTAL_TIMEOUT:-}" ]]; then
    return 0
fi

if [[ ! "$TOTAL_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
    fatal "TOTAL_TIMEOUT must be a positive number of seconds"
fi
TEST_PARAMS="--wait-for-duration=${TOTAL_TIMEOUT}"

# Cluster setup disables downstream Chains before a scenario starts signing.
if [[ -n "${DEPLOYMENT_CHAINS_CONTROLLER_HA_REPLICAS:-}" ]] ||
   [[ "${DEPLOYMENT_TYPE:-downstream}" == "downstream" && "${INSTALL_RESULTS:-false}" == "true" ]]; then
    chains_setup_tekton_tekton_
    wait_for_ready_pods 600 openshift-pipelines app=tekton-chains-controller \
        "${DEPLOYMENT_CHAINS_CONTROLLER_HA_REPLICAS:-1}"
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

if [[ "${RUN_LOCUST:-false}" == "true" && "${LOCUST_RUN_PHASE:-}" == "concurrent" ]]; then
    start_concurrent_locust
fi
