output "batch_account_id" {
  value = "${azurerm_batch_account.batchAccount1.id}"
}

output "batch_account_name" {
  value = "${azurerm_batch_account.batchAccount1.name}"
}

output "batch_pool_name" {
  value = "${azurerm_batch_pool.batchPool1.name}"
}

output "batch_access_key" {
  value = "${azurerm_batch_account.batchAccount1.primary_access_key}"
}

output "batch_endpoint" {
  value = "${azurerm_batch_account.batchAccount1.account_endpoint}"
}