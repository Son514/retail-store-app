#!/usr/bin/env bash
# ============================================================================
# test-spot-interruption.sh
#
# Simulates an EC2 Spot Instance Interruption Warning via SQS and watches
# Karpenter's response in real time: node cordoned, pods drained, PDBs
# respected.
#
# Usage:
#   ./scripts/test-spot-interruption.sh                  # auto-detect node
#   ./scripts/test-spot-interruption.sh --instance-id i-0abc123
#   QUEUE_NAME=custom-queue ./scripts/test-spot-interruption.sh
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
QUEUE_NAME="${QUEUE_NAME:-retail-store-karpenter}"
REGION="${AWS_REGION:-ap-southeast-1}"
NAMESPACE="${NAMESPACE:-production}"
INTERVAL="${INTERVAL:-5}"          # watch refresh interval (seconds)
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "692797214517")"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
INSTANCE_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-id) INSTANCE_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ts()  { date '+[%H:%M:%S]'; }
log() { echo "$(ts) $*"; }

separator() {
  echo "$(ts) ────────────────────────────────────────────────────────────────"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
command -v aws >/dev/null || { log "ERROR: aws CLI not found"; exit 1; }
command -v kubectl >/dev/null || { log "ERROR: kubectl not found"; exit 1; }
command -v jq >/dev/null || { log "ERROR: jq not found (required for node tracking)"; exit 1; }

# Get queue URL
QUEUE_URL=$(aws sqs get-queue-url \
  --queue-name "$QUEUE_NAME" \
  --region "$REGION" \
  --query 'QueueUrl' --output text 2>/dev/null) || {
  log "ERROR: Could not get queue URL for '$QUEUE_NAME'"
  log "       Is the Karpenter module applied? (terraform apply)"
  exit 1
}
log "Queue: $QUEUE_URL"

# Auto-detect spot node if not specified
if [[ -z "$INSTANCE_ID" ]]; then
  PROVIDER_ID=$(kubectl get nodes -l karpenter.sh/capacity-type=spot \
    -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null) || {
    log "ERROR: No Karpenter spot nodes found"
    log "       Ensure the NodePool and spot instances are running"
    exit 1
  }
  INSTANCE_ID=$(echo "$PROVIDER_ID" | awk -F'/' '{print $NF}')
  log "Auto-detected spot instance: $INSTANCE_ID"
fi

NODE_NAME=$(kubectl get nodes -o json | \
  jq -r ".items[] | select(.spec.providerID | endswith(\"$INSTANCE_ID\")) | .metadata.name" 2>/dev/null) || true

log "Target node: ${NODE_NAME:-unknown}"
separator

# ---------------------------------------------------------------------------
# Send interruption event
# ---------------------------------------------------------------------------
log "Sending EC2 Spot Instance Interruption Warning..."

EVENT_BODY=$(cat <<EOF
{
  "version": "0",
  "id": "$(uuidgen 2>/dev/null || echo "test-$(date +%s)")",
  "detail-type": "EC2 Spot Instance Interruption Warning",
  "source": "aws.ec2",
  "account": "$ACCOUNT_ID",
  "region": "$REGION",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "resources": ["arn:aws:ec2:$REGION:$ACCOUNT_ID:instance/$INSTANCE_ID"],
  "detail": {
    "instance-action": "terminate",
    "instance-id": "$INSTANCE_ID"
  }
}
EOF
)

aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body "$EVENT_BODY" \
  --region "$REGION" \
  --output text >/dev/null

log "Event sent. Watching Karpenter response... (Ctrl+C to stop)"
separator

# ---------------------------------------------------------------------------
# Watch loop
# ---------------------------------------------------------------------------
NODE_GONE=0

cleanup() {
  echo ""
  log "Watch stopped."
  exit 0
}
trap cleanup SIGINT SIGTERM

while true; do
  echo ""

  # -- Nodes ---------------------------------------------------------------
  log "NODES:"
  kubectl get nodes \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,CAPACITY:.metadata.labels.karpenter\.sh/capacity-type' \
    --no-headers 2>/dev/null | while IFS= read -r line; do
    echo "  $line"
  done

  # -- Pods ----------------------------------------------------------------
  log "PODS ($NAMESPACE):"
  kubectl get pods -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,NODE:.spec.nodeName' \
    --no-headers 2>/dev/null | while IFS= read -r line; do
    echo "  $line"
  done

  # -- PDBs ----------------------------------------------------------------
  log "PDBs ($NAMESPACE):"
  kubectl get pdb -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,MIN-AVAILABLE:.spec.minAvailable,MAX-UNAVAIL:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed,CURRENT:.status.currentHealthy,DESIRED:.status.desiredHealthy' \
    --no-headers 2>/dev/null | while IFS= read -r line; do
    echo "  $line"
  done

  # -- Events (recent Karpenter/draining) ----------------------------------
  log "RECENT EVENTS:"
  kubectl get events -n "$NAMESPACE" \
    --sort-by='.lastTimestamp' \
    --field-selector reason=Draining 2>/dev/null | tail -5 | while IFS= read -r line; do
    echo "  $line"
  done || true

  # -- Check if node is gone -----------------------------------------------
  if [[ -n "$NODE_NAME" ]]; then
    if ! kubectl get node "$NODE_NAME" &>/dev/null; then
      separator
      log "Node $NODE_NAME ($INSTANCE_ID) has been terminated."
      log "Test complete. Karpenter handled the interruption."
      exit 0
    fi

    # Check node status
    NODE_STATUS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || echo "")
    if [[ "$NODE_STATUS" == "true" ]]; then
      log "  → Node is CORDONED (SchedulingDisabled)"
    fi

    # Check pod count on node
    POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$NODE_NAME" --no-headers 2>/dev/null | wc -l)
    if [[ "$POD_COUNT" -eq 0 ]]; then
      log "  → All pods drained from node"
    else
      log "  → $POD_COUNT pods remaining on node"
    fi
  fi

  sleep "$INTERVAL"
done
