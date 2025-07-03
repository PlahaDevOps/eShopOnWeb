subscription_id = "9625ea80-f131-4f8e-9bbc-5a43d2a94e08"
client_id       = "a8a7a05a-f11d-456d-af11-1b405412c85a"
client_secret   = "cwA8Q~W4LeE5dhqDdfKYy56NFWyv0aGAGSTSLdkS"
tenant_id       = "bd37e2a3-5723-43b6-92a8-ddfabdadeb3d"

resource_group_name = "eshop-rg"
location            = "East US"
vnet_name           = "eshop-vnet"
subnet_name         = "eshop-subnet"
nsg_name            = "eshop-nsg"
vm_name             = "eshop-vm"
vm_size             = "Standard_B2ms"
admin_username      = "azureuser"
admin_password      = "P@ssw0rd123!"

nsg_rules = [
  {
    name                                       = "AllowRDP"
    priority                                   = 1000
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "3389"
    source_address_prefix                      = "*"
    destination_address_prefix                 = "*"
    description                                = "Allow RDP"
    source_port_ranges                         = []
    destination_port_ranges                    = []
    source_address_prefixes                    = []
    destination_address_prefixes               = []
    source_application_security_group_ids      = []
    destination_application_security_group_ids = []
  },
  {
    name                                       = "AllowHTTP"
    priority                                   = 1010
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "80"
    source_address_prefix                      = "*"
    destination_address_prefix                 = "*"
    description                                = "Allow HTTP"
    source_port_ranges                         = []
    destination_port_ranges                    = []
    source_address_prefixes                    = []
    destination_address_prefixes               = []
    source_application_security_group_ids      = []
    destination_application_security_group_ids = []
  },
  {
    name                                       = "AllowSSH"
    priority                                   = 1080
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "22"
    source_address_prefix                      = "*"
    destination_address_prefix                 = "*"
    description                                = "Allow SSH"
    source_port_ranges                         = []
    destination_port_ranges                    = []
    source_address_prefixes                    = []
    destination_address_prefixes               = []
    source_application_security_group_ids      = []
    destination_application_security_group_ids = []
  },
  {
    name                                       = "AllowCustom8080"
    priority                                   = 1070
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "8080"
    source_address_prefix                      = "*"
    destination_address_prefix                 = "*"
    description                                = "Allow Custom 8080"
    source_port_ranges                         = []
    destination_port_ranges                    = []
    source_address_prefixes                    = []
    destination_address_prefixes               = []
    source_application_security_group_ids      = []
    destination_application_security_group_ids = []
  }
]

azure_devops_org_url = "https://dev.azure.com/learndevops4mes/"
azure_devops_pat     = "8wMKUUSduuXEC56pSPPkzlZCbGBwpLHt2rIx8hxPXC3RfvynssepJQQJ99BGACAAAAAAAAAAAAASAZDO4IEK"
agent_pool_name     = "WinServerCorePool"
agent_name          = "eshop-agent"