subscription_id = "f7e65cbf-e776-47df-94da-81733337bb5a"
client_id       = "1501301b-4eb7-4ae4-b01a-e99f38d4832f"
client_secret   = "WiL8Q~TAEmx9uygbYSh10MDD3l-_.OBuHdftzdBS"
tenant_id       = "61916599-ada7-4a20-a703-25db27ecc589"

resource_group_name = "MyResourceGroup"
location            = "East US"
vnet_name           = "WinCoreLabVNET"
subnet_name         = "WinCoreLabSubnet"
nsg_name            = "WinCoreLabNSG"
vm_name             = "WinCoreLab"
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