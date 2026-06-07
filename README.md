# associazione-api-infra

Infrastructure-as-code for [associazione-api](https://github.com/DevilFlow92/associazione-api) —
Helm charts and Kustomize overlays for deploying the music association management backend on Kubernetes.

## Repository structure

```text
├── helm/
│   └── associazione-api/      # Helm chart (primary deployment method)
│       ├── Chart.yaml
│       ├── values.yaml        # Default values
│       ├── values-dev.yaml
│       ├── values-staging.yaml
│       └── values-prod.yaml
├── kustomize/
│   ├── base/                  # Base Kubernetes manifests
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── prod/
└── .github/
    └── workflows/
        ├── lint-helm.yaml     # Lint + validate on every PR
        └── release.yaml       # Package + GitHub Release on tag
```

## What this chart provides

| Resource | Purpose |
|---|---|
| `Deployment` | Runs the FastAPI application |
| `Service` | ClusterIP — internal traffic routing |
| `Ingress` | External access via nginx ingress controller |
| `ConfigMap` | Non-sensitive environment variables |
| `Secret` | DATABASE_URL and SECRET_KEY |
| `HorizontalPodAutoscaler` | CPU + memory autoscaling |
| `PodDisruptionBudget` | Minimum availability during node drain |
| `NetworkPolicy` | Restricts ingress/egress to known peers |
| `Job` (pre-install hook) | Runs Alembic migrations before deploy |
| `ServiceAccount` | Dedicated identity, no automount |

## Prerequisites

- Kubernetes 1.27+
- Helm 3.14+
- nginx ingress controller
- cert-manager (for TLS in staging/prod)

## Helm — quick start

### Install (dev)

```bash
helm install associazione-api helm/associazione-api \
  -f helm/associazione-api/values-dev.yaml \
  --set secret.databaseUrl="postgresql+asyncpg://user:pass@postgres:5432/associazione_db" \
  --set secret.secretKey="your-secret-key" \
  --namespace associazione-api-dev \
  --create-namespace
```

### Install (prod)

```bash
helm install associazione-api helm/associazione-api \
  -f helm/associazione-api/values-prod.yaml \
  --set secret.databaseUrl="postgresql+asyncpg://user:pass@postgres:5432/associazione_db" \
  --set secret.secretKey="your-secret-key" \
  --namespace associazione-api-prod \
  --create-namespace
```

### Upgrade

```bash
helm upgrade associazione-api helm/associazione-api \
  -f helm/associazione-api/values-prod.yaml \
  --set secret.databaseUrl="..." \
  --set secret.secretKey="..." \
  -n associazione-api-prod
```

### Uninstall

```bash
helm uninstall associazione-api -n associazione-api-prod
```

## Kustomize — quick start

```bash
# Preview rendered manifests
kubectl kustomize kustomize/overlays/dev

# Apply to cluster
kubectl apply -k kustomize/overlays/dev
kubectl apply -k kustomize/overlays/staging
kubectl apply -k kustomize/overlays/prod
```

## Environment differences

| Feature | dev | staging | prod |
|---|---|---|---|
| Replicas | 1 | 2 | 3 |
| HPA | ✗ | ✓ (2–4) | ✓ (3–10) |
| PodDisruptionBudget | ✗ | ✓ minAvailable=1 | ✓ minAvailable=2 |
| NetworkPolicy | ✗ | ✓ | ✓ |
| TLS | ✗ | ✓ | ✓ |
| Log level | DEBUG | INFO | WARNING |
| Resource limits | minimal | standard | production |

## Migration strategy

Alembic migrations run automatically as a Kubernetes `Job` via Helm pre-install/pre-upgrade hook.
The Job completes before the Deployment rolls out — zero manual intervention required.

```bash
# Check migration job status
kubectl get jobs -n associazione-api-prod -l app.kubernetes.io/component=migration

# View migration logs
kubectl logs -n associazione-api-prod \
  -l app.kubernetes.io/component=migration --tail=50
```

## CI/CD

| Workflow | Trigger | Steps |
|---|---|---|
| `lint-helm.yaml` | push / PR to main | helm lint × 4 envs → helm template → kubeval → kustomize build × 3 |
| `release.yaml` | push tag `v*.*.*` | version bump → helm package → GitHub Release with .tgz asset |

### Release a new version

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions packages the chart and creates a release automatically.

## Architectural decisions

**Why both Helm and Kustomize?**
Helm is the primary deployment method — it handles parameterization, hooks, and packaging.
Kustomize is included as a reference implementation showing the same multi-env pattern with pure YAML patching, without a templating engine.

**Secret management**
Secrets are passed at install time via `--set`. In production, integrate with
[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or
[External Secrets Operator](https://external-secrets.io) to avoid storing plaintext values in CI.

**readOnlyRootFilesystem**
The container filesystem is read-only. A writable `emptyDir` is mounted at `/tmp` for any temporary file needs.

**NetworkPolicy**
Enabled in staging and prod. Restricts inbound traffic to the nginx ingress controller namespace only,
and outbound to PostgreSQL + DNS. All other traffic is denied by default.

## Related repositories

- [associazione-api](https://github.com/DevilFlow92/associazione-api) — core backend (FastAPI + PostgreSQL)
- [associazione-api-toolkit](https://github.com/DevilFlow92/associazione-api-toolkit) — shared utilities