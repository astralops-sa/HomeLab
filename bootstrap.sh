#!/usr/bin/env bash
#
# Bootstraps a single-node k3s cluster and hands control over to ArgoCD.
#
# What it does:
#   1. installs k3s (default networking: flannel + traefik + servicelb)
#   2. installs helm (if missing)
#   3. helm-installs ArgoCD once, using the same values this repo will use
#      going forward, so the ArgoCD Application that manages ArgoCD itself
#      converges to a no-op diff
#   4. applies the single root Application (app-of-apps) that then takes
#      over syncing everything else, including ArgoCD, from this repo
#
# After this runs, do NOT `helm upgrade` anything by hand. Edit the repo
# and let ArgoCD reconcile.

set -euo pipefail

# ---- config -----------------------------------------------------------
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="10.3.3"   # argo-cd helm chart version, bump as needed
# -------------------------------------------------------------------------

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$1"; }

# ---- 1. install k3s -----------------------------------------------------
if ! command -v k3s >/dev/null 2>&1; then
  log "Installing k3s"
  
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 
else
  log "k3s already installed, skipping"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p "${HOME}/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "${HOME}/.kube/config"
sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"
export KUBECONFIG="${HOME}/.kube/config"

log "Waiting for node to be Ready"
kubectl wait --for=condition=Ready node --all --timeout=180s

# ---- 2. install helm ------------------------------------------------------
if ! command -v helm >/dev/null 2>&1; then
  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  log "Helm already installed, skipping"
fi

# ---- 3. install ArgoCD via Helm -----------------------------------------
log "Installing ArgoCD (chart v${ARGOCD_CHART_VERSION})"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NAMESPACE}" \
  --version "${ARGOCD_CHART_VERSION}" \
  --values clusters/production/values/argocd-values.yaml \
  --wait --timeout 10m

log "Waiting for ArgoCD server to be ready"
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deploy/argocd-server --timeout=180s

# ---- 4. apply the root app-of-apps ---------------------------------------
log "Applying root Application"
kubectl apply -f  bootstrap/root-app.yaml

log "Done"
echo "ArgoCD will now sync clusters/production/apps/* and manage the cluster from there."
echo
echo "Initial admin password:"
kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo || \
  echo "  (secret not found — admin password may already be rotated, or check 'argocd-secret')"
echo
echo "Port-forward to reach the UI:"
echo "  kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443"
