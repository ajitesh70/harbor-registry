# harbor-registry

Production deployment of [Harbor](https://goharbor.io) (container registry) on EKS, wrapping the
official [goharbor/harbor-helm](https://github.com/goharbor/harbor-helm) chart the way
[OT-CONTAINER-KIT/helm-charts](https://github.com/OT-CONTAINER-KIT/helm-charts/tree/harbor/charts/harbor)
does: a thin wrapper `Chart.yaml` depending on the upstream chart, with a values file tuned for
external-service, HA-capable, no-owned-domain production use.

## Architecture

```
GitHub Actions (OIDC, no long-lived AWS keys)
  └─ terraform/main  → VPC, EKS (1 managed node group), RDS Postgres, ElastiCache Redis, S3, IRSA
  └─ helm/harbor      → Harbor components on EKS, talking to the above instead of in-cluster DB/Redis/PVC storage
```

- **No NAT Gateway.** Nodes sit in public subnets with a locked-down security group instead of a
  private subnet + NAT (~$35/mo saved). RDS/ElastiCache live in the same subnets but
  `publicly_accessible=false` / SG-restricted to the cluster's security group only.
- **External stateful services.** Postgres (RDS) and Redis (ElastiCache) instead of the chart's
  bundled internal StatefulSets — makes `core`/`jobservice`/`registry` stateless and horizontally
  scalable. Registry blob/chart storage is S3, not a PVC, for the same reason.
- **No owned domain.** TLS uses Harbor's own self-signed CA (`expose.tls.certSource: auto`)
  rather than a Let's Encrypt/ACM cert bound to a hostname. Harbor is exposed via a Kubernetes
  `Service type=LoadBalancer` (AWS NLB), reachable at the NLB's own AWS-assigned hostname. See
  "Trusting the registry CA" below. Swapping in a real domain later is a values change
  (`expose.type: ingress` + cert-manager/ACM), not a redesign.
- **IRSA everywhere secrets/permissions are needed**: the Harbor pods' ServiceAccount assumes an
  IAM role scoped to just the registry S3 bucket; nothing uses static AWS keys.
- **Secrets never touch git.** RDS password is AWS-managed (`manage_master_user_password`), the
  Redis auth token and Harbor admin password are Terraform-generated and land directly in
  Kubernetes Secrets / Secrets Manager. The CD workflow reads them at deploy time and masks them
  in logs.

## One-time bootstrap (run locally, not by CI)

CI can't authenticate to AWS until the OIDC trust role exists, so this part has to run once with
your own AWS credentials:

```
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply -var="github_repo=<owner>/<repo>"
```

This creates the Terraform state backend (S3 + DynamoDB) and a GitHub Actions OIDC deploy role
scoped to `ec2`, `eks`, `rds`, `elasticache`, `s3`, `secretsmanager`, `logs`, and IAM
resources prefixed `harbor-registry-*` — not account-admin.

Take the `deploy_role_arn` output and set it as a repository variable named `AWS_ROLE_ARN`
(Settings → Secrets and variables → Actions → Variables). `.github/workflows/cd.yml` uses it both
to assume the AWS role and as `terraform/main`'s `deploy_role_arn` input (the role that gets an
EKS access entry so CI can `kubectl`/`helm` after creating the cluster).

## Ongoing deploys

Push to `main` → `.github/workflows/cd.yml`:
1. `terraform apply` in `terraform/main` (EKS, RDS, ElastiCache, S3, IRSA).
2. `helm upgrade --install` the Harbor chart (pass 1, to create the Service/NLB).
3. Poll for the NLB hostname, then `helm upgrade` again (pass 2) with `externalURL` set correctly
   — unavoidable two-pass dance since the hostname doesn't exist until the Service does.

`.github/workflows/ci.yml` runs on PRs: `terraform fmt/validate` for both stacks, `helm lint`,
and a `helm template` render check.

## Accessing Harbor

```
kubectl -n harbor get svc harbor   # EXTERNAL-IP column is the NLB hostname; also in the CD run's job summary
```

**Admin login**: username `admin`, password from Secrets Manager:
```
aws secretsmanager get-secret-value --secret-id $(terraform -chdir=terraform/main output -raw harbor_admin_secret_arn) --query SecretString --output text
```

### Trusting the registry CA

Because there's no owned domain, Harbor's cert is self-signed by its own generated CA, not a
publicly trusted one. `docker`/`podman`/`nerdctl` will refuse to push/pull until they trust it:

```
kubectl -n harbor get secret harbor-ingress -o jsonpath='{.data.ca\.crt}' | base64 -d > harbor-ca.crt
sudo cp harbor-ca.crt /etc/docker/certs.d/<nlb-hostname>/ca.crt   # Linux Docker
# then: docker login <nlb-hostname>
```

## Cost (us-east-1, rough)

| Item | ~Monthly |
|---|---|
| EKS control plane | $73 |
| 2x t3.small nodes (on-demand) | ~$30 |
| RDS db.t3.micro | free tier / ~$13 after |
| ElastiCache cache.t3.micro | free tier / ~$12 after |
| NLB | ~$16 + traffic |
| S3, Secrets Manager, CloudWatch logs | a few $ |

No NAT Gateway, so that ~$35/mo recurring cost isn't in this list. Set `db_deletion_protection`
and `db_multi_az` (`terraform/main/variables.tf`) to `true` once this holds real data instead of
being a demo.

## Local tooling

`terraform`, `kubectl`, `awscli`, and `helm` are expected on your machine only for the one-time
bootstrap and any manual debugging — the CD pipeline itself runs entirely in GitHub Actions.
