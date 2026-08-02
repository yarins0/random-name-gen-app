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
APP_SERVICE="namegen"
TFSTATE_BUCKET="namegen-tfstate-592404497449"
TFSTATE_LOCK_TABLE="namegen-tfstate-lock"
IAM_USER="namegen-terraform"

read -r -p "This will DESTROY all namegen AWS resources (EKS cluster, VPC, ECR, state backend, IAM user). Type 'destroy' to continue: " CONFIRM
if [[ "$CONFIRM" != "destroy" ]]; then
  echo "Aborted."
  exit 1
fi

echo "==> Deleting the app's LoadBalancer Service first, so the NLB deprovisions before the cluster does"
kubectl delete svc "$APP_SERVICE" --ignore-not-found

echo "==> terraform destroy (cluster, VPC, ECR repo, and any OIDC/IAM role Phase 3 added to this state)"
(cd terraform && terraform destroy -auto-approve)

echo "==> Verifying no EKS cluster remains"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "WARNING: cluster $CLUSTER_NAME still exists — check the AWS console before continuing."
  exit 1
fi

echo "==> Emptying and deleting the Terraform state S3 bucket (must be last of the state-backend resources)"
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

echo "==> Deleting the Terraform state lock DynamoDB table"
aws dynamodb delete-table --table-name "$TFSTATE_LOCK_TABLE" --region "$REGION" >/dev/null

echo "==> Removing $IAM_USER from any IAM groups (delete-user requires zero group memberships)"
for GROUP in $(aws iam list-groups-for-user --user-name "$IAM_USER" --query 'Groups[].GroupName' --output text); do
  aws iam remove-user-from-group --user-name "$IAM_USER" --group-name "$GROUP"
done

echo "==> Deleting the namegen-terraform IAM user's access key(s), then the user itself (last step — this is the identity running everything above)"
# ponytail: if these are the AWS CLI's own active credentials, deleting the access key
# invalidates every call after it — including delete-user itself — so this can fail here
# even with nothing left actually wrong. If it does, finish manually in the IAM console:
# delete the user's remaining access key(s) (if any), then delete the user.
for KEY_ID in $(aws iam list-access-keys --user-name "$IAM_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$KEY_ID"
done
if ! aws iam delete-user --user-name "$IAM_USER" 2>/tmp/namegen-delete-user-err.log; then
  echo "WARNING: could not delete IAM user $IAM_USER automatically — its own access key was likely just revoked, invalidating this session's credentials. Finish manually in the AWS IAM console (delete any remaining access keys, then delete the user):"
  cat /tmp/namegen-delete-user-err.log
  rm -f /tmp/namegen-delete-user-err.log
  exit 1
fi
rm -f /tmp/namegen-delete-user-err.log

echo "==> Teardown complete. Manually spot-check the AWS console (EKS, EC2, ELB, ECR, S3, DynamoDB, IAM, Billing) for anything left over."
