param(
    [string]$OrgUrl = "https://dev.azure.com/learndevops4mes/",
    [string]$KeyVaultName = "my-pat-vault",
    [string]$KeyVaultSecretName = "AzureDevOpsPAT",
    [string]$PoolName = "WinServerCorePool",
    [string]$AgentName = "eshop-agent"
)

$ErrorActionPreference = "Stop"

Write-Host "🔐 Installing Azure PowerShell module..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name Az -Repository PSGallery -Force -AllowClobber
    Import-Module Az
    Write-Host "✅ Azure PowerShell module installed"
} catch {
    Write-Host "❌ Failed to install Az module: $($_.Exception.Message)"
}

Write-Host "🔐 Authenticating with managed identity..."
$connected = $false
try {
    Connect-AzAccount -Identity
    $connected = $true
    Write-Host "✅ Connected to Azure with managed identity"
} catch {
    Write-Host "❌ Connect-AzAccount -Identity failed: $($_.Exception.Message)"
}

$PatValue = $null
if ($connected) {
    Write-Host "🔍 Fetching PAT from Key Vault '$KeyVaultName'..."
    try {
        $Pat = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName
        if ($Pat -ne $null) {
            $PatValue = $Pat.SecretValue | ConvertFrom-SecureString -AsPlainText
            Write-Host "✅ PAT successfully retrieved"
        } else {
            Write-Host "⚠️ PAT secret was null"
        }
    } catch {
        Write-Host "❌ Failed to get PAT from Key Vault: $($_.Exception.Message)"
    }
} else {
    Write-Host "⚠️ Skipping PAT retrieval — not authenticated"
}

Write-Host "🔧 Checking for administrator rights..."
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "You must run this script as Administrator!"
    exit 1
}

Write-Host "🌐 Installing IIS and features..."
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

Write-Host "🧱 Installing .NET 9 Hosting Bundle..."
$dotnetUrl = "https://download.agent.dev.azure.com/agent/4.258.1/vsts-agent-win-x64-4.258.1.zip"
$installerPath = "$env:TEMP\dotnet-hosting-9.0.6-win.exe"
try {
    Invoke-WebRequest -Uri "https://builds.dot.net/artifacts/aspnetcore/Runtime/9.0.6/dotnet-hosting-9.0.6-win.exe" -OutFile $installerPath
    Start-Process -FilePath $installerPath -ArgumentList "/quiet" -Wait
    Write-Host "✅ .NET Hosting Bundle installed"
} catch {
    Write-Host "❌ Failed to install .NET Hosting Bundle: $($_.Exception.Message)"
}

Write-Host "📁 Creating deployment folders..."
$webPath = "C:\deploy\Web"
$apiPath = "C:\deploy\PublicApi"
foreach ($path in @($webPath, $apiPath)) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

Write-Host "🌐 Configuring IIS..."
$maxRetries = 10
$retry = 0
while ($retry -lt $maxRetries) {
    try {
        if (Test-Path 'IIS:\Sites\Default Web Site') { break }
    } catch {}
    Start-Sleep -Seconds 5
    $retry++
}
if (-not (Test-Path 'IIS:\Sites\Default Web Site')) {
    Write-Error "❌ IIS Default Web Site not available"
    exit 1
}

Set-ItemProperty 'IIS:\Sites\Default Web Site' -Name physicalPath -Value $webPath
$site = Get-Website -Name "Default Web Site"
if ($site.state -ne "Started") {
    Start-Website -Name "Default Web Site"
}

Write-Host "🛡️ Adding HTTP firewall rule..."
if (-not (Get-NetFirewallRule -DisplayName "Allow HTTP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
}

if ($PatValue) {
    Write-Host "🤖 Installing Azure DevOps Agent..."
    $agentPath = "C:\azagent"
    $agentZip = "$env:TEMP\vsts-agent.zip"

    Remove-Item -Recurse -Force $agentPath -ErrorAction SilentlyContinue
    Remove-Item -Force $agentZip -ErrorAction SilentlyContinue

    Invoke-WebRequest -Uri "https://download.agent.dev.azure.com/agent/4.258.1/vsts-agent-win-x64-4.258.1.zip" -OutFile $agentZip
    Expand-Archive -Path $agentZip -DestinationPath $agentPath -Force

    Push-Location $agentPath
    .\config.cmd --unattended --url $OrgUrl --auth pat --token $PatValue --pool $PoolName --agent $AgentName --work _work --runAsService --replace
    if (Test-Path "$agentPath\svc.cmd") {
        .\svc.cmd install
        .\svc.cmd start
        Write-Host "✅ Azure DevOps Agent installed and started"
    } else {
        Write-Error "❌ svc.cmd missing — agent config may have failed"
    }
    Pop-Location
} else {
    Write-Host "⚠️  Skipping Azure DevOps Agent install — no PAT retrieved"
}

Write-Host "Step X: Installing .NET 9 SDK"
$sdkUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.301/dotnet-sdk-9.0.301-win-x64.exe"
$sdkInstaller = "$env:TEMP\\dotnet-sdk-9.0.301-win-x64.exe"
Invoke-WebRequest -Uri $sdkUrl -OutFile $sdkInstaller
Start-Process -FilePath $sdkInstaller -ArgumentList "/quiet" -Wait
Write-Host "✅ .NET 9 SDK installed"

Write-Host "✅ Script completed!"
