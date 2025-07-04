provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "vm_rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vm_vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name
}

resource "azurerm_subnet" "vm_subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.vm_rg.name
  virtual_network_name = azurerm_virtual_network.vm_vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "vm_public_ip" {
  name                = "${var.vm_name}PublicIP"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.vm_name}Nic"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule = [
    for rule in var.nsg_rules : {
      name                                       = rule.name
      priority                                   = rule.priority
      direction                                  = rule.direction
      access                                     = rule.access
      protocol                                   = rule.protocol
      source_port_range                          = rule.source_port_range
      destination_port_range                     = rule.destination_port_range
      source_address_prefix                      = rule.source_address_prefix
      destination_address_prefix                 = rule.destination_address_prefix
      description                                = rule.description
      source_port_ranges                         = rule.source_port_ranges
      destination_port_ranges                    = rule.destination_port_ranges
      source_address_prefixes                    = rule.source_address_prefixes
      destination_address_prefixes               = rule.destination_address_prefixes
      source_application_security_group_ids      = rule.source_application_security_group_ids
      destination_application_security_group_ids = rule.destination_application_security_group_ids
    }
  ]
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                  = var.vm_name
  resource_group_name   = azurerm_resource_group.vm_rg.name
  location              = azurerm_resource_group.vm_rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  provision_vm_agent    = true
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    name                 = "${var.vm_name}_OsDisk"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter-Core"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm_custom_script" {
  name                 = "InstallIISAndDotNet"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
      "fileUris": [
        "https://raw.githubusercontent.com/PlahaDevOps/eShopOnWeb/main/infra/terraform/scripts/install-iis-dotnet.ps1"
      ],
      "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -File install-iis-dotnet.ps1 -OrgUrl \\"${var.azure_devops_org_url}\\" -KeyVaultName \\"${var.keyvault_name}\\" -KeyVaultSecretName \\"${var.keyvault_secret_name}\\" -PoolName \\"${var.agent_pool_name}\\" -AgentName \\"${var.agent_name}\\""
    }
SETTINGS
}

resource "azurerm_network_interface_security_group_association" "vm_nic_nsg" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Grant VM's managed identity access to Key Vault
data "azurerm_key_vault" "existing" {
  name                = var.keyvault_name
  resource_group_name = var.keyvault_resource_group_name
}

resource "azurerm_key_vault_access_policy" "vm_identity" {
  key_vault_id = data.azurerm_key_vault.existing.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_virtual_machine.vm.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}
