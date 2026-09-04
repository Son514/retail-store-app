#!/usr/bin/env bash
# ============================================================================
# allow-my-ip.sh
#
# Opens up the EKS cluster's public API endpoint to your current public IP.
#
# The EKS control-plane endpoint is locked down to a CIDR allow-list in
# terraform/environments/shared.tfvars. When your home/VPN IP changes you get
# locked out of kubectl until it is updated. This script detects your current
# public IP, updates the allow-list, and applies just the cluster change so
# access is restored — even if kubectl is currently blocked (the cluster-only
# -target apply talks to the AWS EKS *service* API, not the cluster API).
#
# Usage:
#   ./scripts/allow-my-ip.sh                 # detect IP + apply cluster change
#   ./scripts/allow-my-ip.sh --dry-run       # show what would change, apply nothing
#   ./scripts/allow-my-ip.sh --full-apply    # cluster change, then full terraform apply
#   ./scripts/allow-my-ip.sh --cidr 1.2.3.4  # override the detected IP
#   ./scripts/allow-my-ip.sh --yes           # skip the confirmation prompt
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EKS_DIR="$REPO_ROOT/terraform/environments/eks"
TFVARS="$EKS_DIR/terraform.tfvars"          # symlink -> ../shared.tfvars
REGION="${AWS_REGION:-ap-southeast-1}"
CLUSTER_NAME="retail-store"
CLUSTER_RESOURCE="module.eks.aws_eks_cluster.this"

DRY_RUN=0
FULL_APPLY=0
AUTO_YES=0
CIDR_OVERRIDE=""

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1; shift ;;
    --full-apply) FULL_APPLY=1; shift ;;
    --yes)       AUTO_YES=1; shift ;;
    --cidr)      CIDR_OVERRIDE="$2"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *)           echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

ts() { date '+[%H:%M:%S]'; }

# ---------------------------------------------------------------------------
# Detect current public IP
# ---------------------------------------------------------------------------
if [[ -n "$CIDR_OVERRIDE" ]]; then
  CURRENT_IP="$CIDR_OVERRIDE"
else
  CURRENT_IP="$(curl -sf https://checkip.amazonaws.com 2>/dev/null || echo '')"
  [[ -z "$CURRENT_IP" ]] && { echo "Could not detect public IP. Pass --cidr explicitly." >&2; exit 1; }
fi

case "$CURRENT_IP" in
  */*) CURRENT_CIDR="$CURRENT_IP" ;;   # already a CIDR
  *)   CURRENT_CIDR="$CURRENT_IP/32" ;; # plain IP -> /32
esac

[[ -f "$TFVARS" ]] || { echo "Missing $TFVARS (run the setup in shared.tfvars header first)." >&2; exit 1; }

# ---------------------------------------------------------------------------
# Read the current CIDR from the vars file (last match wins)
# ---------------------------------------------------------------------------
CURRENT_VALUE="$(grep -Eo 'cluster_endpoint_public_access_cidrs[[:space:]]*=[[:space:]]*\[[^]]*\]' "$TFVARS" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | tail -1 || true)"

echo "$(ts) Your public IP : $CURRENT_CIDR"
echo "$(ts) Cluster allows : ${CURRENT_VALUE:-<none>}"

if [[ "$CURRENT_CIDR" == "$CURRENT_VALUE" ]]; then
  echo "$(ts) Already up to date — nothing to do."
  exit 0
fi

if [[ -z "$CURRENT_VALUE" ]]; then
  echo "Could not find cluster_endpoint_public_access_cidrs in $TFVARS." >&2
  exit 1
fi

echo "$(ts) Will replace   : $CURRENT_VALUE -> $CURRENT_CIDR"
[[ "$DRY_RUN" == 1 ]] && { echo "$(ts) Dry run — no changes applied."; exit 0; }

if [[ "$AUTO_YES" != 1 ]]; then
  read -rp "$(ts) Apply this change? [y/N] " -n 1 ans; echo
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# ---------------------------------------------------------------------------
# Update the vars file in place (preserves surrounding formatting/comments)
# ---------------------------------------------------------------------------
python3 - "$TFVARS" "$CURRENT_CIDR" <<'PY'
import re, sys
path, new_cidr = sys.argv[1], sys.argv[2]
pat = re.compile(r'(cluster_endpoint_public_access_cidrs\s*=\s*\[)"[^"]*"(\])', re.M)
with open(path) as f:
    txt = f.read()
new, n = pat.subn(lambda m: m.group(1) + f'"{new_cidr}"' + m.group(2), txt)
if n == 0:
    sys.exit(f"pattern not found in {path}")
with open(path, "w") as f:
    f.write(new)
PY

echo "$(ts) Updated $TFVARS"

# ---------------------------------------------------------------------------
# Apply — cluster-only first (this is what re-opens access, works while locked out)
# ---------------------------------------------------------------------------
cd "$EKS_DIR"
echo "$(ts) terraform init..."
terraform init -input=false -no-color >/dev/null 2>&1 || terraform init -input=false

echo "$(ts) Applying cluster endpoint change (targeted)..."
terraform apply -target="$CLUSTER_RESOURCE" -auto-approve -no-color

# ---------------------------------------------------------------------------
# Full apply / plan (optional)
# ---------------------------------------------------------------------------
if [[ "$FULL_APPLY" == 1 ]]; then
  echo "$(ts) Running full terraform apply..."
  terraform apply -auto-approve -no-color
else
  echo "$(ts) Verifying no other drift (plan)..."
  terraform plan -no-color 2>&1 | tail -3
fi

# ---------------------------------------------------------------------------
# Refresh kubeconfig + verify access
# ---------------------------------------------------------------------------
echo "$(ts) Refreshing kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

echo "$(ts) Verifying kubectl..."
if timeout 30 kubectl get nodes >/dev/null 2>&1; then
  echo "$(ts) kubectl access restored."
  kubectl get nodes
else
  echo "$(ts) WARNING: kubectl still unreachable. Re-run this script or check the CIDR in"
  echo "$(ts)         $TFVARS"
  exit 1
fi
