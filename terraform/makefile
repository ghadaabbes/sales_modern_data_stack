TERRAFORM_DIR := .

# GitHub Secrets injectés comme variables d'environnement dans le workflow :
#   TF_VAR_snowflake_account      → secret SNOWFLAKE_ACCOUNT
#   TF_VAR_snowflake_user         → secret SNOWFLAKE_USER
#   TF_VAR_snowflake_password     → secret SNOWFLAKE_PASSWORD
#   TF_VAR_organization_name      → secret SNOWFLAKE_ORGANIZATION_NAME
# Terraform les lit automatiquement — aucun -var nécessaire ici.

DEV_VARS := -var-file=variables.dev.tfvars

.PHONY: help check-env init fmt validate plan apply apply-auto plan-dev apply-dev destroy destroy-auto output clean

help:
	@echo "Snowflake Terraform - targets disponibles :"
	@echo "  check-env    - Vérifie que les variables d'environnement sont bien définies"
	@echo "  init         - Initialise Terraform et télécharge les providers"
	@echo "  fmt          - Formate les fichiers .tf"
	@echo "  validate     - Valide la configuration Terraform"
	@echo "  plan         - Aperçu des ressources à créer/modifier/supprimer"
	@echo "  apply        - Applique le plan (avec confirmation)"
	@echo "  apply-auto   - Applique le plan sans confirmation"
	@echo "  destroy      - Supprime les ressources Snowflake (avec confirmation)"
	@echo "  destroy-auto - Supprime les ressources sans confirmation"
	@echo "  output       - Affiche les outputs Terraform"
	@echo "  clean        - Supprime .terraform/ et les fichiers d'état locaux"

check-env:
	@test -n "$(TF_VAR_snowflake_account)"   || (echo "ERROR: TF_VAR_snowflake_account manquant"   && exit 1)
	@test -n "$(TF_VAR_snowflake_user)"      || (echo "ERROR: TF_VAR_snowflake_user manquant"      && exit 1)
	@test -n "$(TF_VAR_snowflake_password)"  || (echo "ERROR: TF_VAR_snowflake_password manquant"  && exit 1)
	@test -n "$(TF_VAR_organization_name)"   || (echo "ERROR: TF_VAR_organization_name manquant"   && exit 1)
	@echo "Variables d'environnement OK."

init:
	terraform -chdir=$(TERRAFORM_DIR) init

fmt:
	terraform -chdir=$(TERRAFORM_DIR) fmt -recursive

validate: init
	terraform -chdir=$(TERRAFORM_DIR) validate

plan: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) plan

apply: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) apply

apply-auto: check-env validate
	terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve

# ── Développement local (utilise variables.dev.tfvars) ──────────────────────
plan-dev: validate
	terraform -chdir=$(TERRAFORM_DIR) plan $(DEV_VARS)

apply-dev: validate
	terraform -chdir=$(TERRAFORM_DIR) apply $(DEV_VARS)

destroy: check-env
	terraform -chdir=$(TERRAFORM_DIR) destroy

destroy-auto: check-env
	terraform -chdir=$(TERRAFORM_DIR) destroy -auto-approve

output:
	terraform -chdir=$(TERRAFORM_DIR) output

clean:
	rm -rf $(TERRAFORM_DIR)/.terraform
	rm -f $(TERRAFORM_DIR)/.terraform.lock.hcl
	rm -f $(TERRAFORM_DIR)/terraform.tfstate
	rm -f $(TERRAFORM_DIR)/terraform.tfstate.backup
