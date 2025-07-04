# install-iis-dotnet.ps1

param(
    [string]$OrgUrl = "https://dev.azure.com/learndevops4mes/",
    [string]$KeyVaultName = "my-pat-vault",
    [string]$KeyVaultSecretName = "AzureDevOpsPAT",
    [string]$PoolName = "WinServerCorePool",
    [string]$AgentName = "eShopOnWeb-VM"
)

Write-Host "🔐 Installing Azure PowerShell module..."
try {
    Install-Module -Name Az -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
    Import-Module Az -ErrorAction Stop
    Write-Host "✅ Azure PowerShell module installed successfully"
} catch {
    Write-Error "❌ Failed to install Azure PowerShell module: $($_.Exception.Message)"
    exit 1
}

Write-Host "🔐 Logging into Azure using Managed Identity..."
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Host "✅ Successfully authenticated with managed identity"
} catch {
    Write-Error "❌ Failed to authenticate with managed identity: $($_.Exception.Message)"
    exit 1
}

Write-Host "🔐 Fetching PAT from Azure Key Vault '$KeyVaultName'..."
try {
    $Pat = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName -ErrorAction Stop
    if (-not $Pat) {
        Write-Error "❌ Failed to retrieve PAT from Key Vault - secret is null"
        exit 1
    }
    $PatValue = $Pat.SecretValue | ConvertFrom-SecureString -AsPlainText
    Write-Host "✅ PAT successfully retrieved from Key Vault"
} catch {
    Write-Error "❌ Failed to retrieve PAT from Key Vault: $($_.Exception.Message)"
    Write-Host "Make sure the VM's managed identity has 'Get' permission on the Key Vault secret"
    exit 1
}

Write-Host "Step 0: Checking for Administrator rights"
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "You must run this script as an Administrator!"
    exit 1
}

Write-Host "Step 1: Installing IIS and importing IIS module"
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Import-Module WebAdministration

$features = @(
    "Web-Server", "Web-WebServer", "Web-Common-Http", "Web-Default-Doc", "Web-Dir-Browsing",
    "Web-Http-Errors", "Web-Static-Content", "Web-App-Dev", "Web-Net-Ext45", "Web-Asp-Net45",
    "Web-ISAPI-Ext", "Web-ISAPI-Filter", "Web-Mgmt-Console", "Web-Mgmt-Service",
    "Web-Mgmt-Compat", "Web-WMI", "Web-Metabase"
)

foreach ($feature in $features) {
    $f = Get-WindowsFeature -Name $feature
    if (-not $f.Installed) {
        Install-WindowsFeature -Name $feature
    }
}

Write-Host "Step 2: Installing .NET 9 Hosting Bundle"
$dotnetUrl = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/9.0.6/dotnet-hosting-9.0.6-win.exe"
$installerPath = "$env:TEMP\dotnet-hosting-9.0.6-win.exe"
Invoke-WebRequest -Uri $dotnetUrl -OutFile $installerPath
Start-Process -FilePath $installerPath -ArgumentList "/quiet" -Wait

Write-Host "Step 3: Creating deploy folders"
$webPath = "C:\deploy\Web"
$apiPath = "C:\deploy\PublicApi"
foreach ($path in @($webPath, $apiPath)) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

Write-Host "Step 4: Configuring IIS"
Set-ItemProperty 'IIS:\Sites\Default Web Site' -Name physicalPath -Value $webPath
$site = Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
if ($site -and $site.state -ne "Started") {
    Start-Website -Name "Default Web Site"
}

Write-Host "Step 5: Adding firewall rule for HTTP"
if (-not (Get-NetFirewallRule -DisplayName "Allow HTTP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
}

Write-Host "Step 6: Installing Azure DevOps Agent"
$agentPath = "C:\azagent"
$agentUrl = "https://download.agent.dev.azure.com/agent/4.258.1/vsts-agent-win-x64-4.258.1.zip"
$agentZip = "$env:TEMP\vsts-agent-win-x64.zip"

if (-not (Test-Path $agentZip)) {
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentZip -ErrorAction Stop
}
Expand-Archive -Path $agentZip -DestinationPath $agentPath -Force

if (-not (Test-Path "$agentPath\config.cmd")) {
    Write-Error "config.cmd not found. Agent extraction failed."
    exit 1
}

Write-Host "Configuring Azure DevOps Agent..."
Write-Host "DEBUG: OrgUrl is $OrgUrl"
Write-Host "DEBUG: PoolName is $PoolName"
Write-Host "DEBUG: AgentName is $AgentName"
Write-Host "DEBUG: PAT length is $($PatValue.Length) characters"

Push-Location $agentPath
& .\config.cmd --unattended --url $OrgUrl --auth pat --token $PatValue --pool $PoolName --agent $AgentName --work _work --runAsService --replace
if ($LASTEXITCODE -ne 0) {
    Write-Error "Agent config failed with exit code $LASTEXITCODE"
    exit 1
}
Pop-Location

& "$agentPath\svc.cmd" install
& "$agentPath\svc.cmd" start

Write-Host "✅ Script completed successfully!"
