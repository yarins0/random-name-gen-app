# 🎲 random-name-gen-app

[![Terraform](https://img.shields.io/badge/Terraform-1.11+-7B42BC?logo=terraform&logoColor=white)](terraform/)
[![AWS EKS](https://img.shields.io/badge/AWS-EKS%20Auto%20Mode-ED7100?logo=amazonaws&logoColor=white)](terraform/eks.tf)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.33-326CE5?logo=kubernetes&logoColor=white)](k8s/)
[![Docker](https://img.shields.io/badge/Docker-node%3A24--alpine-2496ED?logo=docker&logoColor=white)](Dockerfile)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions%20%2B%20OIDC-2088FF?logo=githubactions&logoColor=white)](.github/workflows/)
[![Grafana](https://img.shields.io/badge/Monitoring-Prometheus%20%2B%20Grafana-F46800?logo=grafana&logoColor=white)](k8s/monitoring/)
[![Node.js](https://img.shields.io/badge/Node.js-24-339933?logo=nodedotjs&logoColor=white)](package.json)
[![MongoDB](https://img.shields.io/badge/MongoDB-8.0-47A248?logo=mongodb&logoColor=white)](k8s/mongo.yaml)
[![Trivy](https://img.shields.io/badge/Security-Trivy-1904DA?logo=aquasecurity&logoColor=white)](.github/workflows/security.yml)

A demonstration app (Express API + MongoDB, jQuery/Bootstrap front end) for generating and persisting random names via `@faker-js/faker`. Originally forked from [`redhat-developer-demos/namegen`](https://github.com/reselbob/random-name-gen-app) (kept as the `upstream` remote).

The app itself is a vehicle for the real project: **deploying it to AWS EKS (Auto Mode) with a full Terraform + GitHub Actions CI/CD pipeline.** This was a one-time practice deploy — built, demoed, screenshotted (see `screenshots/`), and fully torn down afterward to avoid ongoing AWS cost. See `docs/PLAN.md` for the full decision log if you have access to it (gitignored, local-only).

## 📑 Table of Contents

- [🏗️ Architecture](#-architecture)
- [🔄 CI/CD Pipeline](#-cicd-pipeline)
- [🛡️ Security Scanning](#-security-scanning)
- [💻 Local Development](#-local-development)
- [☁️ AWS Deployment](#-aws-deployment)
  - [1️⃣ Bootstrap the Terraform state backend](#1-bootstrap-the-terraform-state-backend)
  - [2️⃣ Provision the infrastructure](#2-provision-the-infrastructure)
  - [3️⃣ First image build + manual deploy](#3-first-image-build--manual-deploy)
  - [4️⃣ Enable CI/CD](#4-enable-cicd)
  - [5️⃣ Install monitoring (Prometheus + Grafana)](#5-install-monitoring-prometheus--grafana)
- [🧹 Teardown](#-teardown)
- [📁 Repo Layout](#-repo-layout)

## 🏗️ Architecture

Both diagrams below are exported from [`docs/architecture.drawio`](docs/architecture.drawio), the editable draw.io source — two pages, *Architecture* and *CI-CD Pipeline*, drawn with the official AWS architecture icon set and the Kubernetes icon set that ship with draw.io, plus embedded Terraform, Prometheus, and Grafana logos. Every icon is inlined, so the file needs no network access to render. Edit that file and re-export to PNG to change either diagram.

![Architecture: a browser reaching an EKS Auto Mode cluster through a Network Load Balancer, with the namegen Deployment, the mongo StatefulSet on an EBS volume, a monitoring namespace running Prometheus and Grafana, plus ECR, the GitHub Actions OIDC role, and the S3 Terraform state bucket](screenshots/draw.io/Architecture.png)

- **Node.js app** (`server.js`) serves the static front end (`public/index.html`) and the `/api/*` routes from the same process.
- **MongoDB 8.0** runs as a single-replica `StatefulSet` with an EBS-backed `PersistentVolumeClaim` (see `k8s/mongo.yaml` — Auto Mode needs its own `StorageClass`, the default `gp2` in-tree class isn't usable on Auto Mode nodes).
- **Exposure** is a Kubernetes `Service` of type `LoadBalancer`, using EKS Auto Mode's built-in NLB provisioning (no separate AWS Load Balancer Controller installed).
- **Monitoring** is `kube-prometheus-stack` in a `monitoring` namespace: Prometheus scrapes cAdvisor and `kube-state-metrics`, and Grafana renders the namegen dashboard from `k8s/monitoring/` (see [step 5](#5-install-monitoring-prometheus--grafana)).
- **GitHub Actions** authenticates to AWS via an OIDC-federated IAM role — no long-lived AWS access keys stored in GitHub.

## 🔄 CI/CD Pipeline

![CI/CD pipeline: a push to main triggers checkout, assuming the AWS IAM role through GitHub OIDC, docker build tagged with the commit SHA and latest, push to ECR, aws eks update-kubeconfig, kubectl set image, and kubectl rollout status](screenshots/draw.io/CI-CD%20Pipeline.png)

Defined in `.github/workflows/deploy.yml`. A separate `.github/workflows/test.yml` runs the Mocha test suite against a `mongo:8.0` service container on every push, independent of deploy.

> The diagram predates the Trivy gate. Since then, deploy runs as two jobs: `build` builds the image and scans it with Trivy, with no AWS access at all, and hands the image over as an artifact. `deploy` then assumes the OIDC role, pushes only the `:<commit-sha>` tag (the ECR repo is `IMMUTABLE`, so there is no `:latest`), and `kubectl apply`s `k8s/app.yaml` with that tag substituted.

## 🛡️ Security Scanning

[Trivy](https://trivy.dev) scans everything this repo builds or declares, in two places:

- **Deploy gate** (`deploy.yml`, `build` job): the exact image that will be pushed. A fixable HIGH/CRITICAL vulnerability or a leaked secret stops the release before any AWS credentials exist in the run.
- **`security.yml`**, on every push plus a weekly re-scan (new CVEs appear in code that hasn't changed):
  - `config`: misconfigurations in `terraform/` (including the EKS and VPC registry modules), `k8s/` and the `Dockerfile`, plus secrets anywhere in the repo. Fails on HIGH/CRITICAL.
  - `image`: OS packages and npm dependencies in the app image. Fails on fixable HIGH/CRITICAL.
  - `mongo-image`: the official `mongo` image from `k8s/mongo.yaml`, **report-only**. Its remaining CVEs sit in binaries only MongoDB can rebuild, so they're tracked, not gated.

All results, at every severity, are uploaded to the repo's **Security → Code scanning** tab.

**Accepted findings** are listed with the reasoning for each in [`.trivyignore.yaml`](.trivyignore.yaml): the public EKS endpoint, the public node subnets, and ECR using AWS-managed rather than customer-managed KMS keys. All three are cost and complexity trade-offs for a short-lived demo, and each entry names the real fix. `trivy.yaml` loads that file automatically, so a local run matches CI:

```bash
trivy config .                                  # IaC + Dockerfile
docker build -t namegen:local . && trivy image namegen:local
```

Every third-party GitHub Action is pinned to a full commit SHA, since a version tag can be moved to point at different code.

## 💻 Local Development

**Prerequisites**: Node.js, a running MongoDB instance (local or remote).

1. Clone the repo and `npm install`.
2. Create a `.env` file in the project root:
   ```
   MONGODB_URL=<connection_string_to_your_mongodb_server>
   ```
   Optional: `SERVER_PORT=<port>` (defaults to `8080`), `DB_NAME=<name>` (defaults to `namegen`).
3. Start the server: `node server.js`
4. Open `http://localhost:8080/` (or whatever `SERVER_PORT` you set).

**Tests**: `npm test` is a placeholder script — run Mocha directly instead:
```
npx mocha tests/*.js
```

## ☁️ AWS Deployment

Redeploying this from scratch requires: an AWS account, the AWS CLI, Terraform, `kubectl`, and Docker.

### 1️⃣ Bootstrap the Terraform state backend

Terraform's own state has to live somewhere before `terraform init` can use it as a backend, so this one step is created manually (not by Terraform):

```bash
aws s3api create-bucket --bucket <unique-bucket-name> --region <region> \
  --create-bucket-configuration LocationConstraint=<region>
aws s3api put-bucket-versioning --bucket <unique-bucket-name> \
  --versioning-configuration Status=Enabled

aws iam create-user --user-name <terraform-iam-user>
aws iam attach-user-policy --user-name <terraform-iam-user> \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess   # scope down for anything long-lived
aws iam create-access-key --user-name <terraform-iam-user>   # configure these as your active AWS credentials
```

No DynamoDB lock table is needed — the backend uses S3-native state locking (`use_lockfile`, Terraform 1.11+), which stores the lock as an object in the same bucket.

Update the bucket name in `terraform/backend.tf` to match. Every other value (region, cluster name, Kubernetes version, CIDRs, the OIDC subject) is a variable in `terraform/variables.tf` — override the defaults there or with `-var`.

### 2️⃣ Provision the infrastructure

```bash
cd terraform
terraform init
terraform apply
```

This creates: the VPC, the EKS Auto Mode cluster, the ECR repo, and the OIDC provider + IAM role GitHub Actions will assume.

```bash
aws eks update-kubeconfig --name namegen --region <region>
kubectl get nodes   # Auto Mode provisions a node on-demand once something needs scheduling
```

### 3️⃣ First image build + manual deploy

```bash
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <ecr-repo-url>
IMAGE_TAG=$(git rev-parse HEAD)   # the repo is IMMUTABLE, so tags are commit SHAs, never :latest
docker build -t <ecr-repo-url>:$IMAGE_TAG .
docker push <ecr-repo-url>:$IMAGE_TAG

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/mongo.yaml
kubectl apply -f k8s/secret.yaml
sed "s|:IMAGE_TAG|:$IMAGE_TAG|" k8s/app.yaml | kubectl apply -f -
```

Get the app's public URL:
```bash
kubectl get svc namegen -n namegen   # EXTERNAL-IP column is the NLB DNS name; app listens on :8080
```

### 4️⃣ Enable CI/CD

Push to `main` — `.github/workflows/deploy.yml` picks up from here automatically (build → Trivy scan → push to ECR → roll out to EKS). No GitHub secrets are needed; the role ARN is embedded in the workflow and trust is scoped to this exact repo via OIDC.

### 5️⃣ Install monitoring (Prometheus + Grafana)

`kube-prometheus-stack` provides Prometheus, Grafana, `kube-state-metrics`, and `node-exporter`, plus a purpose-built dashboard for the namegen Deployment and the MongoDB StatefulSet.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values k8s/monitoring/values.yaml \
  --set grafana.adminPassword='<choose-a-password>'

kubectl create configmap namegen-dashboard --namespace monitoring \
  --from-file=k8s/monitoring/namegen-dashboard.json
kubectl label configmap namegen-dashboard --namespace monitoring grafana_dashboard=1
```

Grafana stays on a ClusterIP Service, so reach it through a port-forward rather than a second public load balancer:

```bash
kubectl port-forward --namespace monitoring svc/monitoring-grafana 3000:80
```

Open <http://localhost:3000>, sign in as `admin`, then open **Dashboards → namegen — Application & MongoDB**.

Apply `k8s/` before installing: the chart's PVCs need the `ebs-sc` StorageClass that `k8s/mongo.yaml` defines. Full details, panel descriptions, and cost notes are in [`k8s/monitoring/README.md`](k8s/monitoring/README.md).

## 🧹 Teardown

Everything provisioned above is destroyable. `teardown.sh` (repo root) automates it in the required order — deleting the state backend or the IAM user too early will strand resources or lock you out of destroying them:

```bash
./teardown.sh   # prompts for confirmation before doing anything
```

Order: delete the `LoadBalancer` Service (deprovisions the NLB) → uninstall the monitoring stack → delete all PVCs → `terraform destroy` (cluster, VPC, ECR, OIDC role) → empty + delete the S3 state bucket → delete the bootstrap IAM user's access key and the user itself.

PVCs are deleted before `terraform destroy` on purpose. Their EBS volumes are provisioned by the CSI driver rather than by Terraform, so destroying the cluster while PVCs still exist orphans those volumes and they keep billing. Check **EC2 → Volumes** afterwards.

After running it, spot-check the AWS Console (EKS, EC2/ELB, ECR, S3, IAM, and Billing/Cost Explorer) to confirm nothing billable is left.

## 📁 Repo Layout

- `server.js`, `data/`, `public/` — the app itself
- `Dockerfile` — multi-stage container build (`node:24-alpine`, non-root, npm/yarn stripped from the runtime image)
- `terraform/` — all AWS infrastructure (VPC, EKS, ECR, OIDC/IAM, remote state backend config)
- `k8s/` — Kubernetes manifests (`namegen` namespace with Pod Security `restricted`, app `Deployment`/`Service`, Mongo `StatefulSet`/`PVC`, `Secret`)
- `k8s/monitoring/` — Prometheus + Grafana Helm values and the namegen Grafana dashboard
- `docs/architecture.drawio` — editable draw.io source for both diagrams (open at [app.diagrams.net](https://app.diagrams.net))
- `.github/workflows/` — CI (`test.yml`), CD (`deploy.yml`) and Trivy scanning (`security.yml`)
- `trivy.yaml`, `.trivyignore.yaml` — shared Trivy config and the accepted-findings list
- `screenshots/` — app UI states, EKS/ECR/NLB console views, Grafana/Prometheus views, and pipeline run logs
- `screenshots/draw.io/` — the two diagrams above, exported to PNG from `docs/architecture.drawio`
- `teardown.sh` — Phase 5 automation (see above)
