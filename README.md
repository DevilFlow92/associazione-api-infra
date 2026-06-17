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
| `ConfigMap` | Non-sensitive environment variables (app + auth: JWT/session config) |
| `Secret` | DATABASE_URL, SECRET_KEY, JWT_SECRET_KEY, MIGRATION_DATABASE_URL, BOOTSTRAP_ADMIN_PASSWORD |
| `HorizontalPodAutoscaler` | CPU + memory autoscaling |
| `PodDisruptionBudget` | Minimum availability during node drain |
| `NetworkPolicy` | Restricts ingress/egress to known peers |
| `Job` (pre-install hook) | Runs Alembic migrations before deploy |
| `PersistentVolumeClaim` | Upload storage (prod only, controlled by `uploads.persistent`) |
| `ServiceAccount` | Dedicated identity, no automount |

## Container image

The application image is built from `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` — the official uv base image. Key implications for the chart:

- `runAsNonRoot` is `false` (uv base image runs as uid 0 by default)
- `readOnlyRootFilesystem` is `true` — the chart mounts three writable volumes:
  - `/tmp` — general temporary files
  - `/root/.cache` — uv package cache (written at runtime)
  - `/app/uploads` — uploaded PDF files (emptyDir in dev, PVC in prod)

## Upload storage

Uploaded files are written to `/app/uploads` inside the container. The chart supports two modes, controlled by `uploads.persistent`:

| Mode | `uploads.persistent` | Backend | Data survives pod restart |
|---|---|---|---|
| Dev | `false` (default) | `emptyDir` | ✗ |
| Prod | `true` | `PersistentVolumeClaim` | ✓ |

In production, configure `uploads.size` and optionally `uploads.storageClass` in `values-prod.yaml`.

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
  --set secret.databaseUrl="postgresql+asyncpg://app_rw:pass@postgres:5432/associazione_db" \
  --set secret.migrationDatabaseUrl="postgresql+asyncpg://associazione:pass@postgres:5432/associazione_db" \
  --set secret.secretKey="your-secret-key" \
  --set secret.jwtSecretKey="your-jwt-signing-key" \
  --set secret.bootstrapAdminPassword="your-admin-password" \
  --namespace associazione-api-dev \
  --create-namespace
```

### Install (prod)

```bash
helm install associazione-api helm/associazione-api \
  -f helm/associazione-api/values-prod.yaml \
  --set secret.databaseUrl="postgresql+asyncpg://app_rw:pass@postgres:5432/associazione_db" \
  --set secret.migrationDatabaseUrl="postgresql+asyncpg://associazione:pass@postgres:5432/associazione_db" \
  --set secret.secretKey="your-secret-key" \
  --set secret.jwtSecretKey="your-jwt-signing-key" \
  --set secret.bootstrapAdminPassword="your-admin-password" \
  --namespace associazione-api-prod \
  --create-namespace
```

> **DB roles (least privilege).** At runtime the app uses a DML-only role
> (`app_rw`) via `databaseUrl`. Alembic migrations need DDL, so the migration
> Job uses the schema owner via `migrationDatabaseUrl`. If `migrationDatabaseUrl`
> is left empty the Job falls back to `databaseUrl` — only correct if that role
> can run DDL. `bootstrapAdminPassword` seeds the initial superuser created by
> the auth/RBAC migration on first deploy.

### Upgrade

```bash
helm upgrade associazione-api helm/associazione-api \
  -f helm/associazione-api/values-prod.yaml \
  --set secret.databaseUrl="..." \
  --set secret.migrationDatabaseUrl="..." \
  --set secret.secretKey="..." \
  --set secret.jwtSecretKey="..." \
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
| Upload storage | emptyDir | emptyDir | PVC 10Gi |
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
The container filesystem is read-only. Three `emptyDir` volumes are mounted for writable paths: `/tmp`, `/root/.cache` (uv), and `/app/uploads`.

**NetworkPolicy**
Enabled in staging and prod. Restricts inbound traffic to the nginx ingress controller namespace only,
and outbound to PostgreSQL + DNS. All other traffic is denied by default.

## Related repositories

- [associazione-api](https://github.com/DevilFlow92/associazione-api) — core backend (FastAPI + PostgreSQL)
- [associazione-api-toolkit](https://github.com/DevilFlow92/associazione-api-toolkit) — shared utilities
- **associazione-api-infra** — ← you are here