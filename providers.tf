provider "azurerm" {
	subscription_id 	= "${var.subscription_id}"
	client_id 			= "${var.client_id}"
	client_secret 		= "${var.client_secret}"
	tenant_id 			= "${var.tenant_id}"
}

terraform {
  backend "azurerm" {
    storage_account_name = "__TF_VAR_storage_acct__"
    container_name       = "state"
    key                  = "terraform.tfstate"
	access_key			 = "__access_key__"
  }
}
