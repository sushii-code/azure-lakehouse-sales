# Inputs that change between environments.

# Azure region for every resource
variable "location" {
  type    = string
  default = "uksouth"
}

# Short prefix for resource names, e.g. "olistsales" -> rg "olistsales-rg", storage "olistsaleslake".
# Storage account names must be 3-24 lowercase letters or digits and unique across Azure,
# so the prefix is limited to 3-20 lowercase letters/digits (20 + "lake" = 24).
variable "name_prefix" {
  type    = string
  default = "olistsales"

  validation {
    condition     = can(regex("^[a-z0-9]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters or digits."
  }
}
