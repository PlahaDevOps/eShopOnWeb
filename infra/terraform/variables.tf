variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "vnet_name" {
  type        = string
  description = "Name of the virtual network"
}

variable "subnet_name" {
  type        = string
  description = "Name of the subnet"
}

variable "nsg_name" {
  type        = string
  description = "Name of the Network Security Group"
}

variable "vm_name" {
  type        = string
  description = "Name of the Virtual Machine"
}

variable "vm_size" {
  type        = string
  description = "Size of the Virtual Machine"
}

variable "admin_username" {
  type        = string
  description = "Admin username"
}

variable "admin_password" {
  type        = string
  description = "Admin password"
  sensitive   = true
}

variable "nsg_rules" {
  description = "List of NSG rules"
  type = list(object({
    name                                       = string
    priority                                   = number
    direction                                  = string
    access                                     = string
    protocol                                   = string
    source_port_range                          = string
    destination_port_range                     = string
    source_address_prefix                      = string
    destination_address_prefix                 = string
    description                                = string
    source_port_ranges                         = list(string)
    destination_port_ranges                    = list(string)
    source_address_prefixes                    = list(string)
    destination_address_prefixes               = list(string)
    source_application_security_group_ids      = list(string)
    destination_application_security_group_ids = list(string)
  }))
}

variable "azure_devops_org_url" {
  type        = string
  description = "Azure DevOps organization URL"
}

variable "agent_pool_name" {
  type        = string
  description = "Azure DevOps agent pool name"
}

variable "agent_name" {
  type        = string
  description = "Azure DevOps agent name"
}

variable "keyvault_name" {
  type        = string
  description = "Azure Key Vault name storing the Azure DevOps PAT"
}

variable "keyvault_secret_name" {
  type        = string
  description = "Secret name in Key Vault that stores the Azure DevOps PAT"
}

variable "keyvault_resource_group_name" {
  type        = string
  description = "Resource group name where the Key Vault is located"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "client_id" {
  type        = string
  description = "Azure service principal client ID"
}

variable "client_secret" {
  type        = string
  description = "Azure service principal client secret"
  sensitive   = true
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID"
}
