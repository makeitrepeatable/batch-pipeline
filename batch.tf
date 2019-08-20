resource "random_string" "random" {
  length  = 12
  special = false
  lower   = true
  upper   = false
}

resource "azurerm_resource_group" "batchRG" {
  name     = "Batch"
  location = "westeurope"
}

resource "azurerm_storage_account" "batchStorage" {
  name                     = "azbatch${random_string.random.result}"
  resource_group_name      = "Storage"
  location                 = "${azurerm_resource_group.batchRG.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_batch_account" "batchAccount1" {
  name                 = "azbatch${random_string.random.result}"
  resource_group_name  = "${azurerm_resource_group.batchRG.name}"
  location             = "${azurerm_resource_group.batchRG.location}"
  pool_allocation_mode = "BatchService"
  storage_account_id   = "${azurerm_storage_account.batchStorage.id}"

  tags = {
    env = "Dev"
  }
}

resource "azurerm_batch_pool" "batchPool1" {
  name                = "pool1"
  resource_group_name = "${azurerm_resource_group.batchRG.name}"
  account_name        = "${azurerm_batch_account.batchAccount1.name}"
  display_name        = "Test Acc Pool Auto"
  vm_size             = "Standard_A1"
  node_agent_sku_id   = "batch.node.ubuntu 16.04"

  auto_scale {
    evaluation_interval = "PT5M"

    formula = <<EOF
                  // In this example, the pool size is adjusted based on the number of tasks in the queue. 
                  // Note that both comments and line breaks are acceptable in formula strings.

                  // Get pending tasks for the past 5 minute.
                  $samples = $ActiveTasks.GetSamplePercent(TimeInterval_Minute * 5);
                  // If we have fewer than 70 percent data points, we use the last sample point, otherwise we use the maximum of last sample point and the history average.
                  $tasks = $samples < 70 ? max(0, $ActiveTasks.GetSample(1)) : 
                  max( $ActiveTasks.GetSample(1), avg($ActiveTasks.GetSample(TimeInterval_Minute * 5)));
                  // If number of pending tasks is not 0, set targetVM to pending tasks, otherwise half of current dedicated.
                  $targetVMs = $tasks > 0 ? $tasks : max(0, $TargetDedicatedNodes / 2);
                  // The pool size is capped at 20, if target VM value is more than that, set it to 20. This value should be adjusted according to your use case.
                  cappedPoolSize = 20;
                  $TargetDedicatedNodes = max(0, min($targetVMs, cappedPoolSize));
                  // Set node deallocation mode - keep nodes active only until tasks finish
                  $NodeDeallocationOption = taskcompletion;
              EOF
  }

  storage_image_reference {
    publisher = "canonical"
    offer     = "ubuntuserver"
    sku       = "16.04-LTS"
    version   = "latest"
  }

}

