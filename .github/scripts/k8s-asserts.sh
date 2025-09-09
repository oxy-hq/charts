#!/usr/bin/env bash
set -euo pipefail

# This script asserts that the oxy-app release created expected resources.
# It expects the following environment variables optionally set:
# - NAMESPACE (default: default)
# - RELEASE_NAME (default: oxy-app)
# - APP_NAME (default: oxy-app)

NAMESPACE=${NAMESPACE:-default}
RELEASE_NAME=${RELEASE_NAME:-oxy-app}
APP_NAME=${APP_NAME:-oxy-app}

echo "Asserting resources for release='$RELEASE_NAME' app='$APP_NAME' namespace='$NAMESPACE'"

echo "Checking Service ${APP_NAME}-service exists..."
kubectl get svc ${APP_NAME}-service -n ${NAMESPACE}

echo "Checking headless Service ${APP_NAME}-headless (if enabled)..."
kubectl get svc ${APP_NAME}-headless -n ${NAMESPACE} || echo "headless service not present (ok if disabled)"

SS_NAME=${APP_NAME}
echo "Waiting for StatefulSet ${SS_NAME} to be ready..."
kubectl rollout status statefulset/${SS_NAME} -n ${NAMESPACE} --timeout=2m

echo "Checking pods for StatefulSet ${SS_NAME}..."
PODS=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o name)
if [ -z "$PODS" ]; then
  echo "No pods found for app=${APP_NAME}"
  exit 1
fi

for p in $PODS; do
  echo "Checking pod $p status..."
  kubectl wait --for=condition=ready -n ${NAMESPACE} $p --timeout=90s
done

echo "All checks passed."
