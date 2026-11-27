# shellcheck source=/dev/null
source scenario/common/lib.sh

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
