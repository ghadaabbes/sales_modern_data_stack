TERRAFORM_DIR := .

# Credentials via environment variables (never in tfvars files):
#   export TF_VAR_snowflake_password="your_password"
# Terraform reads them automatically — no -var flag needed.
#
# In CI/CD (GitHub Actions), variables come from GitHub Secrets:
#   TF_VAR_snowflake_account      → secret SNOWFLAKE_ACCOUNT
#   TF_VAR_snowflake_user         → secret SNOWFLAKE_USER
#   TF_VAR_snowflake_password     → secret SNOWFLAKE_PASSWORD
#   TF_VAR_organization_name      → secret SNOWFLAKE_ORGANIZATION_NAME

DEV_VARS  := -var-file=variables.dev.tfvars
PROD_VARS := -var-file=variables.prod.tfvars

.PHONY: help check-env init fmt validate \
        plan apply apply-auto \
        plan-dev apply-dev \
        plan-prod apply-prod \
        destroy destroy-auto output clean restart

help:
	@echo ""
	@echo "Snowflake Terraform — available targets"
	@echo "───────────────────────────────────────"
	@echo "  General"
	@echo "    check-env    Check that TF_VAR_snowflake_password is set"
	@echo "    init         Initialize Terraform and download providers"
	@echo "    fmt          Format .tf files"
	@echo "    validate     Validate Terraform configuration"
	@echo ""
	@echo "  Dev (variables.dev.tfvars)"
	@echo "    plan-dev     Preview changes in dev"
	@echo "    apply-dev    Apply in dev (with confirmation)"
	@echo ""
	@echo "  Prod (variables.prod.tfvars)"
	@echo "    plan-prod    Preview changes in prod"
	@echo "    apply-prod   Apply in prod (with confirmation)"
	@echo ""
	@echo "  CI/CD"
	@echo "    apply-auto   Apply without confirmation (for GitHub Actions)"
	@echo ""
	@echo "  Maintenance"
	@echo "    output       Show outputs (resource names)"
	@echo "    destroy      Delete resources (with confirmation)"
	@echo "    clean        Delete local state (.terraform/, tfstate)"
	@echo "    restart      clean + init + apply-dev (start from scratch)"
	@echo ""

check-env:
	@test -n "$(TF_VAR_snowflake_password)" || \
		(echo "ERROR: TF_VAR_snowflake_password is not set." && \
		 echo "Run: export TF_VAR_snowflake_password='your_password'" && exit 1)
	@echo "Environment variables OK."

init:
	terraform -chdir=$(TERRAFORM_DIR) init

fmt:
	terraform -chdir=$(TERRAFORM_DIR) fmt -recursive

validate: init
	terraform -chdir=$(TERRAFORM_DIR) validate

# ── Dev ────────────────────────────────────────────────────────────────────────

plan-dev: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) plan $(DEV_VARS)

apply-dev: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) apply $(DEV_VARS)

# ── Prod ───────────────────────────────────────────────────────────────────────

plan-prod: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) plan $(PROD_VARS)

apply-prod: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) apply $(PROD_VARS)

# ── CI/CD (no interactive confirmation) ───────────────────────────────────────

apply-auto: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve

# ── Maintenance ────────────────────────────────────────────────────────────────

output:
	terraform -chdir=$(TERRAFORM_DIR) output

destroy: check-env
	terraform -chdir=$(TERRAFORM_DIR) destroy $(DEV_VARS)

destroy-auto: check-env
	terraform -chdir=$(TERRAFORM_DIR) destroy -auto-approve $(DEV_VARS)

clean:
	rm -rf $(TERRAFORM_DIR)/.terraform
	rm -f  $(TERRAFORM_DIR)/.terraform.lock.hcl
	rm -f  $(TERRAFORM_DIR)/terraform.tfstate
	rm -f  $(TERRAFORM_DIR)/terraform.tfstate.backup

# Start from scratch: delete local state, reinitialize and apply in dev.
# Existing Snowflake resources are re-imported via import{} blocks in main.tf.
restart: clean init apply-dev
