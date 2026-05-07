# Valeurs non-sensibles pour l'environnement prod.
# Le mot de passe vient de TF_VAR_snowflake_password (GitHub Secret en CI/CD).

snowflake_account  = "DR90600"
snowflake_user     = "GHADAAB"
organization_name  = "GOERPYE"
snowflake_role     = "ACCOUNTADMIN"   # ACCOUNTADMIN pour provisionner, TRANSFORMER pour dbt
