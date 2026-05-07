TERRAFORM_DIR := .

# Credentials via variables d'environnement (jamais dans les fichiers tfvars) :
#   export TF_VAR_snowflake_password="ton_mot_de_passe"
# Terraform les lit automatiquement — aucun -var nécessaire.
#
# En CI/CD (GitHub Actions), ces variables viennent des GitHub Secrets :
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
	@echo "Snowflake Terraform — targets disponibles"
	@echo "─────────────────────────────────────────"
	@echo "  Général"
	@echo "    check-env    Vérifie que TF_VAR_snowflake_password est défini"
	@echo "    init         Initialise Terraform et télécharge les providers"
	@echo "    fmt          Formate les fichiers .tf"
	@echo "    validate     Valide la configuration Terraform"
	@echo ""
	@echo "  Dev (variables.dev.tfvars)"
	@echo "    plan-dev     Aperçu des changements en dev"
	@echo "    apply-dev    Applique en dev (avec confirmation)"
	@echo ""
	@echo "  Prod (variables.prod.tfvars)"
	@echo "    plan-prod    Aperçu des changements en prod"
	@echo "    apply-prod   Applique en prod (avec confirmation)"
	@echo ""
	@echo "  CI/CD"
	@echo "    apply-auto   Applique sans confirmation (pour GitHub Actions)"
	@echo ""
	@echo "  Maintenance"
	@echo "    output       Affiche les outputs (noms de ressources)"
	@echo "    destroy      Supprime les ressources (avec confirmation)"
	@echo "    clean        Supprime l'état local (.terraform/, tfstate)"
	@echo "    restart      clean + init + apply-dev (repartir de zéro)"
	@echo ""

check-env:
	@test -n "$(TF_VAR_snowflake_password)" || \
		(echo "ERREUR : TF_VAR_snowflake_password non défini." && \
		 echo "Lancer : export TF_VAR_snowflake_password='ton_mot_de_passe'" && exit 1)
	@echo "Variables d'environnement OK."

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

# ── CI/CD (sans confirmation interactive) ─────────────────────────────────────

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

# Repartir de zéro : supprime l'état local, réinitialise et applique en dev.
# Les ressources existantes dans Snowflake sont ré-importées via les blocs import{}.
restart: clean init apply-dev
