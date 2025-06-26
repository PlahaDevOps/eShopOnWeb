# install-iis-dotnet.ps1

param(
    [string]$OrgUrl = "https://dev.azure.com/weworku4/",
    [string]$Pat,
    [string]$PoolName = "WinServerCorePool",
    [string]$AgentName = "eShopOnWeb-VM"
)

Write-Host "Step 0: Checking for Administrator rights"
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "You must run this script as an Administrator!"
    exit 1
}
Write-Host "Step 0: Running as Administrator"

Write-Host "Step 1: Importing IIS module"
Import-Module WebAdministration
Write-Host "Step 1: IIS module imported"

Write-Host "Step 2: Checking IIS and required sub-features"
$features = @(
    "Web-Server", "Web-WebServer", "Web-Common-Http", "Web-Default-Doc", "Web-Dir-Browsing",
    "Web-Http-Errors", "Web-Static-Content", "Web-App-Dev", "Web-Net-Ext45", "Web-Asp-Net45",
    "Web-ISAPI-Ext", "Web-ISAPI-Filter", "Web-Mgmt-Console", "Web-Mgmt-Service",
    "Web-Mgmt-Compat", "Web-WMI", "Web-Metabase"
)

foreach ($feature in $features) {
    $f = Get-WindowsFeature -Name $feature
    if ($f -and $f.Installed) {
        Write-Host "IIS feature $feature is already installed."
    } else {
        Write-Host "Installing missing feature: $feature..."
        Install-WindowsFeature -Name $feature
        Write-Host "Feature $feature installed."
    }
}

Write-Host "Step 3: Checking .NET Hosting Bundle"
$dotnetBundleDisplayName = "Microsoft ASP.NET Core Module V2"
$dotnetBundleInstalled = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName -like "*$dotnetBundleDisplayName*" }

if (-not $dotnetBundleInstalled) {
    Write-Host ".NET 9 Hosting Bundle not found. Installing..."
    $dotnetUrl = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/9.0.6/dotnet-hosting-9.0.6-win.exe"
    $dotnetInstaller = "$env:TEMP\dotnet-hosting-9.0.6-win.exe"
    Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetInstaller
    Start-Process -FilePath $dotnetInstaller -ArgumentList "/quiet" -Wait
    Write-Host ".NET 9 Hosting Bundle installed."
} else {
    Write-Host ".NET 9 Hosting Bundle already installed."
}

Write-Host "Step 4: Creating deployment folders"
$webPath = "C:\deploy\Web"
$apiPath = "C:\deploy\PublicApi"

if (-not (Test-Path $webPath)) {
    New-Item -Path $webPath -ItemType Directory -Force | Out-Null
    Write-Host "Web folder created."
} else {
    Write-Host "Web folder already exists."
}

if (-not (Test-Path $apiPath)) {
    New-Item -Path $apiPath -ItemType Directory -Force | Out-Null
    Write-Host "API folder created."
} else {
    Write-Host "API folder already exists."
}

function Test-AppPoolExists { param([string]$Name); Test-Path "IIS:\AppPools\$Name" }

Write-Host "Step 5: Setting up eShopOnWeb app pool"
if (-not (Test-AppPoolExists -Name "eShopOnWeb")) {
    New-WebAppPool -Name "eShopOnWeb"
    Write-Host "App pool 'eShopOnWeb' created."
} else {
    Write-Host "App pool 'eShopOnWeb' already exists."
}
Set-ItemProperty IIS:\AppPools\eShopOnWeb -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\eShopOnWeb -Name processModel.identityType -Value "ApplicationPoolIdentity"

Write-Host "Step 6: Setting up eShopOnWebApi app pool"
if (-not (Test-AppPoolExists -Name "eShopOnWebApi")) {
    New-WebAppPool -Name "eShopOnWebApi"
    Write-Host "App pool 'eShopOnWebApi' created."
} else {
    Write-Host "App pool 'eShopOnWebApi' already exists."
}
Set-ItemProperty IIS:\AppPools\eShopOnWebApi -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty IIS:\AppPools\eShopOnWebApi -Name processModel.identityType -Value "ApplicationPoolIdentity"

Write-Host "Step 7: Configuring eShopOnWeb site (port 80)"
if (-not (Get-Website -Name "eShopOnWeb" -ErrorAction SilentlyContinue)) {
    New-Website -Name "eShopOnWeb" -Port 80 -PhysicalPath $webPath -ApplicationPool "eShopOnWeb" -Force
    Write-Host "Website 'eShopOnWeb' created."
} else {
    Write-Host "Website 'eShopOnWeb' already exists. Updating settings..."
    Set-ItemProperty "IIS:\Sites\eShopOnWeb" -Name physicalPath -Value $webPath
    Set-ItemProperty "IIS:\Sites\eShopOnWeb" -Name applicationPool -Value "eShopOnWeb"
    if ((Get-Website -Name "eShopOnWeb").Bindings.Collection.bindingInformation -notcontains "*:80:") {
        Remove-WebBinding -Name "eShopOnWeb" -Port 80 -Protocol "http" -ErrorAction SilentlyContinue
        New-WebBinding -Name "eShopOnWeb" -Protocol "http" -Port 80 -IPAddress "*"
        Write-Host "Port 80 binding ensured."
    }
}

Write-Host "Step 8: Configuring eShopOnWebApi site (port 8080)"
if (-not (Get-Website -Name "eShopOnWebApi" -ErrorAction SilentlyContinue)) {
    New-Website -Name "eShopOnWebApi" -Port 8080 -PhysicalPath $apiPath -ApplicationPool "eShopOnWebApi" -Force
    Write-Host "Website 'eShopOnWebApi' created."
} else {
    Write-Host "Website 'eShopOnWebApi' already exists. Updating settings..."
    Set-ItemProperty "IIS:\Sites\eShopOnWebApi" -Name physicalPath -Value $apiPath
    Set-ItemProperty "IIS:\Sites\eShopOnWebApi" -Name applicationPool -Value "eShopOnWebApi"
    if ((Get-Website -Name "eShopOnWebApi").Bindings.Collection.bindingInformation -notcontains "*:8080:") {
        Remove-WebBinding -Name "eShopOnWebApi" -Port 8080 -Protocol "http" -ErrorAction SilentlyContinue
        New-WebBinding -Name "eShopOnWebApi" -Protocol "http" -Port 8080 -IPAddress "*"
        Write-Host "Port 8080 binding ensured."
    }
}

Write-Host "Step 9: Ensuring Windows Firewall rules"
if (-not (Get-NetFirewallRule -DisplayName "Allow HTTP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
    Write-Host "Firewall rule for port 80 created."
} else {
    Write-Host "Firewall rule for port 80 already exists."
}

if (-not (Get-NetFirewallRule -DisplayName "Allow API" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow API" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow
    Write-Host "Firewall rule for port 8080 created."
} else {
    Write-Host "Firewall rule for port 8080 already exists."
}

Write-Host "Step 10: Installing and Configuring Azure Pipelines Agent"
$agentPath = "C:\azagent"
$agentUrl = "https://download.agent.dev.azure.com/agent/4.258.1/vsts-agent-win-x64-4.258.1.zip"
$agentZip = "$env:TEMP\vsts-agent-win-x64.zip"

# Download agent if not already present
if (-not (Test-Path $agentZip)) {
    try {
        Write-Host "Downloading Azure Pipelines Agent..."
        Invoke-WebRequest -Uri $agentUrl -OutFile $agentZip -ErrorAction Stop
        Write-Host "Agent downloaded."
    } catch {
        Write-Error "Failed to download Azure Pipelines Agent: $_"
        exit 1
    }
}

# Extract agent
try {
    Expand-Archive -Path $agentZip -DestinationPath $agentPath -Force
    Write-Host "Agent extracted."
} catch {
    Write-Error "Failed to extract Azure Pipelines Agent: $_"
    exit 1
}

# Check for config.cmd
if (-not (Test-Path "$agentPath\\config.cmd")) {
    Write-Error "config.cmd not found in $agentPath. Extraction failed."
    exit 1
}

# Configure agent
if (-not $Pat) {
    Write-Error "PAT token is missing! Cannot configure agent."
    exit 1
}
Write-Host "Configuring Azure Pipelines Agent..."
$configArgs = @(
    "--unattended",
    "--url", $OrgUrl,
    "--auth", "pat",
    "--token", $Pat,
    "--pool", $PoolName,
    "--agent", $AgentName,
    "--work", "_work",
    "--runAsService",
    "--replace"
)
Push-Location $agentPath
& .\config.cmd @configArgs
$exitCode = $LASTEXITCODE
Pop-Location

if ($exitCode -ne 0) {
    Write-Error "Azure Pipelines Agent configuration failed with exit code $exitCode"
    exit 1
} else {
    Write-Host "Agent configured successfully."
}

# Start the agent service if not running
$svcCmd = "$agentPath\\svc.cmd"
if (Test-Path $svcCmd) {
    & $svcCmd install
    & $svcCmd start
    Write-Host "Azure Pipelines Agent service started."
} else {
    Write-Host "svc.cmd not found. Please check agent installation."
}

Write-Host "✅ Script completed successfully!"