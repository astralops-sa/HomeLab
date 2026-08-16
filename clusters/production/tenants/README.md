# Tenants

Each subfolder here becomes one ArgoCD Application, auto-discovered by the
`tenants` ApplicationSet (`clusters/production/appsets/tenants/tenants-appset.yaml`).

To onboard a tenant, add `clusters/production/tenants/<name>/` containing a
Capsule `Tenant` custom resource (and any other namespace-scoped manifests
that tenant needs). It will show up in ArgoCD as an Application named
`tenant-<name>` on the next sync — no other file needs to change.
