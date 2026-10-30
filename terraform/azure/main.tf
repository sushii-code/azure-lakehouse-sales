# Azure storage for the lakehouse (VALIDATE-ONLY, not deployed). See README.md.

# A resource group is a folder in Azure that holds related resources (delete it = delete all)
resource "azurerm_resource_group" "lakehouse" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

# ADLS Gen2 storage account: blob storage with a real folder tree (hierarchical namespace)
resource "azurerm_storage_account" "lake" {
  name                     = "${var.name_prefix}lake"
  resource_group_name      = azurerm_resource_group.lakehouse.name
  location                 = azurerm_resource_group.lakehouse.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS" # 3 copies in one data centre (cheapest)

  is_hns_enabled                  = true     # hierarchical namespace = ADLS Gen2 (folders, fast renames)
  min_tls_version                 = "TLS1_2" # refuse old, insecure TLS versions
  https_traffic_only_enabled      = true     # no unencrypted HTTP
  allow_nested_items_to_be_public = false    # no container or blob can ever be made public
}

# One private container per lakehouse layer
resource "azurerm_storage_container" "layer" {
  for_each = toset(["bronze", "silver", "gold"])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}
