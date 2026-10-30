# Values Terraform would print after apply.

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

# ADLS Gen2 addresses of each layer, e.g. abfss://bronze@olistsaleslake.dfs.core.windows.net/
output "layer_urls" {
  value = {
    for name, container in azurerm_storage_container.layer :
    name => "abfss://${name}@${azurerm_storage_account.lake.name}.dfs.core.windows.net/"
  }
}
