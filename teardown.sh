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
aws s3 rm "s3://$TFSTATE_BUCKET" --recursive --region "$REGION"
aws s3api delete-bucket --bucket "$TFSTATE_BUCKET" --region "$REGION"

echo "==> Deleting the Terraform state lock DynamoDB table"
aws dynamodb delete-table --table-name "$TFSTATE_LOCK_TABLE" --region "$REGION" >/dev/null

echo "==> Deleting the namegen-terraform IAM user's access key(s), then the user itself (last step — this is the identity running everything above)"
for KEY_ID in $(aws iam list-access-keys --user-name "$IAM_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$KEY_ID"
done
aws iam delete-user --user-name "$IAM_USER"

echo "==> Teardown complete. Manually spot-check the AWS console (EKS, EC2, ELB, ECR, S3, DynamoDB, IAM, Billing) for anything left over."
