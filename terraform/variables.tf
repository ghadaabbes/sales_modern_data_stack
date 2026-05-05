

variable "snowflake_account" {
  description = "The Snowflake account name (without the .snowflakecomputing.com suffix)"
  type        = string
  
}

variable "snowflake_password" {
  description = "The Snowflake password"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "The Snowflake role to use for authentication"
  type        = string
  default     = "ACCOUNTADMIN"
}

variable "organization_name" {
  description = "The Snowflake organization name (if using Snowflake for AWS or Azure)"
  type        = string
  default     = ""
}

variable "snowflake_user" {
  description = "The Snowflake user name"
  type        = string
}