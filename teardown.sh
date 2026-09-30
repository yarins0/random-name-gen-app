#!/usr/bin/env bash
# Phase 5 teardown from docs/PLAN.md, automated in order. Destructive — deletes real AWS resources.
#
# NOTE: keep this in sync with docs/PLAN.md's Phase 5 checklist and with whatever
# terraform/ actually contains at teardown time. In particular, Phase 3 (CI/CD) is
# expected to add an OIDC provider + IAM role for GitHub Actions to terraform/ —
# once that exists, "terraform destroy" below already covers it (same state), no
# extra step needed, but re-check this script if Phase 3 provisions anything
# OUTSIDE terraform/ (e.g. manually-created GitHub secrets) that also needs cleanup.

set -euo pipefail

REGION="eu-north-1"
CLUSTER_NAME="namegen"
APP_NS="namegen"
APP_SERVICE="namegen"
MONITORING_NS="monitoring"
TFSTATE_BUCKET="namegen-tfstate-592404497449"
IAM_USER="namegen-terraform"

read -r -p "This will DESTROY all namegen AWS resources (EKS cluster, VPC, ECR, state backend, IAM user). Type 'destroy' to continue: " CONFIRM
if [[ "$CONFIRM" != "destroy" ]]; then
  echo "Aborted."
  exit 1
fi

echo "==> Deleting the app's LoadBalancer Service first, so the NLB deprovisions before the cluster does"
kubectl delete svc "$APP_SERVICE" --namespace "$APP_NS" --ignore-not-found

echo "==> Removing the Prometheus/Grafana stack, if it is installed"
if command -v helm >/dev/null 2>&1; then
  helm uninstall monitoring --namespace "$MONITORING_NS" 2>/dev/null || true
fi

# EBS volumes for dynamically provisioned PVCs are created by the CSI driver, not by
# Terraform, so `terraform destroy` does not know about them. Deleting the cluster with
# PVCs still present orphans their volumes, which keep billing indefinitely.
#
# Workloads must go before their PVCs. A running pod holds its PVC open through the
# kubernetes.io/pvc-protection finalizer, so `delete pvc` only blocks until the timeout
# and the volume outlives the cluster. Deleting the PVCs alone orphaned the mongo-0
# volume on a real run, which is the exact failure this section exists to prevent.
echo "==> Deleting workloads, then their PVCs, so the CSI driver reclaims the EBS volumes"
for NS in "$APP_NS" "$MONITORING_NS"; do
  kubectl get namespace "$NS" >/dev/null 2>&1 || continue
  kubectl delete statefulset,deployment --all --namespace "$NS" --timeout=5m
  # No `|| true` here on purpose: a timeout means a volume is about to be orphaned and
  # bill indefinitely, so stop before terraform destroy removes the CSI driver that
  # would have reclaimed it. Swallowing this error is what let the leak through before.
  kubectl delete pvc --all --namespace "$NS" --timeout=5m
done
kubectl delete namespace "$APP_NS" "$MONITORING_NS" --ignore-not-found --timeout=5m || true

echo "==> terraform destroy (cluster, VPC, ECR repo, and any OIDC/IAM role Phase 3 added to this state)"
(cd terraform && terraform destroy -auto-approve)

echo "==> Verifying no EKS cluster remains"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "WARNING: cluster $CLUSTER_NAME still exists — check the AWS console before continuing."
  exit 1
fi

echo "==> Emptying and deleting the Terraform state S3 bucket (the only state-backend resource)"
# The backend uses S3-native locking (use_lockfile), so the .tflock object lives in this
# same bucket and is removed by the version purge below — there is no DynamoDB table to delete.
# The bucket has versioning enabled, so a plain `s3 rm --recursive` only clears current-version
# objects and leaves old versions + delete markers behind — delete-bucket then fails with
# BucketNotEmpty (hit this during the real teardown). Purge every version and delete marker first.
VERSIONS_JSON=$(aws s3api list-object-versions --bucket "$TFSTATE_BUCKET" --region "$REGION" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)
if [[ "$(echo "$VERSIONS_JSON" | grep -c '"Key"')" -gt 0 ]]; then
  aws s3api delete-objects --bucket "$TFSTATE_BUCKET" --region "$REGION" --delete "$VERSIONS_JSON" >/dev/null
fi
MARKERS_JSON=$(aws s3api list-object-versions --bucket "$TFSTATE_BUCKET" --region "$REGION" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)
if [[ "$(echo "$MARKERS_JSON" | grep -c '"Key"')" -gt 0 ]]; then
  aws s3api delete-objects --bucket "$TFSTATE_BUCKET" --region "$REGION" --delete "$MARKERS_JSON" >/dev/null
fi
aws s3api delete-bucket --bucket "$TFSTATE_BUCKET" --region "$REGION"

echo "==> Last: delete the $IAM_USER IAM user (the identity running everything above)"
# delete-user requires zero group memberships, but removing the user from its groups also
# takes away every permission granted through them — including the permission to delete
# itself. A real run did exactly that: the group removal succeeded, then list-access-keys
# and delete-user both failed with AccessDenied, leaving the user behind and the local
# credentials unable to verify anything. So refuse to start a sequence that cannot finish.
USER_GROUPS=$(aws iam list-groups-for-user --user-name "$IAM_USER" \
  --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")
if [[ -n "$USER_GROUPS" ]]; then
  echo "WARNING: $IAM_USER belongs to IAM group(s): $USER_GROUPS"
  echo "         Removing it from them would revoke the permissions needed to delete it,"
  echo "         so this script stops here instead of stripping its own access."
  echo "         Finish in the AWS IAM console with an admin identity: delete this user's"
  echo "         access keys, then delete the user."
  exit 1
fi

# No groups, so permissions are attached directly and survive until the user is deleted.
# Deleting the access key still invalidates this session's credentials, so it goes last.
for KEY_ID in $(aws iam list-access-keys --user-name "$IAM_USER" \
  --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$KEY_ID"
done
if ! aws iam delete-user --user-name "$IAM_USER" 2>/tmp/namegen-delete-user-err.log; then
  echo "WARNING: could not delete IAM user $IAM_USER automatically. Finish it in the AWS IAM console (delete any remaining access keys, then the user):"
  cat /tmp/namegen-delete-user-err.log
  rm -f /tmp/namegen-delete-user-err.log
  exit 1
fi
rm -f /tmp/namegen-delete-user-err.log

echo "==> Teardown complete. Manually spot-check the AWS console (EKS, EC2 incl. Volumes, ELB, ECR, S3, IAM, Billing) for anything left over."
echo "    Check EC2 > Volumes specifically: orphaned EBS volumes from PVCs are the most common leftover cost."
