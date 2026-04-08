resource "azurerm_virtual_network" "vpc" {
  name                = "${var.name_prefix}-vpc"
  location = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${azurerm_virtual_network.vpc.name}-subnet"
  resource_group_name = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.1.0/24"]

  service_endpoints    = ["Microsoft.Storage"]
}
