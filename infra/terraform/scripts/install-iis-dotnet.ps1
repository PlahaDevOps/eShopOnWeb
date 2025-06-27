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

Write-Host "Step 4: Create custom deploy folders"
$webPath = "C:\deploy\Web"
$apiPath = "C:\deploy\PublicApi"

foreach ($path in @($webPath, $apiPath)) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        Write-Host "Created folder: $path"
    } else {
        Write-Host "Folder already exists: $path"
    }
}

Write-Host "Step 5: Point IIS to custom Web folder"
try {
    Set-ItemProperty 'IIS:\Sites\Default Web Site' -Name physicalPath -Value $webPath
    Write-Host "IIS site path updated to $webPath"
} catch {
    Write-Error "Failed to update IIS site path: $_"
    exit 1
}

Write-Host "Step 6: Ensure Default Web Site is running"
$site = Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
if ($site) {
    if ($site.state -ne "Started") {
        Start-Website -Name "Default Web Site"
        Write-Host "Default Web Site started."
    } else {
        Write-Host "Default Web Site is already running."
    }
} else {
    Write-Error "Default Web Site not found!"
    exit 1
}

Write-Host "Step 7: Add Windows Firewall rule for port 80"
if (-not (Get-NetFirewallRule -DisplayName "Allow HTTP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
    Write-Host "Firewall rule for port 80 created."
} else {
    Write-Host "Firewall rule for port 80 already exists."
}

Write-Host "Step 8: Install and Configure Azure Pipelines Agent"
$agentPath = "C:\azagent"
$agentUrl = "https://download.agent.dev.azure.com/agent/4.258.1/vsts-agent-win-x64-4.258.1.zip"
$agentZip = "$env:TEMP\vsts-agent-win-x64.zip"

if (-not (Test-Path $agentZip)) {
    Write-Host "Downloading Azure Pipelines Agent..."
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentZip -ErrorAction Stop
    Write-Host "Agent downloaded."
}
Expand-Archive -Path $agentZip -DestinationPath $agentPath -Force
Write-Host "Agent extracted."

if (-not (Test-Path "$agentPath\config.cmd")) {
    Write-Error "config.cmd not found in $agentPath. Extraction failed."
    exit 1
}

if (-not $Pat) {
    Write-Error "PAT token is missing! Cannot configure agent."
    exit 1
}

Write-Host "Configuring Azure Pipelines Agent..."
Push-Location $agentPath
& .\config.cmd --unattended --url $OrgUrl --auth pat --token $Pat --pool $PoolName --agent $AgentName --work _work --runAsService --replace
if ($LASTEXITCODE -ne 0) {
    Write-Error "Agent config failed with exit code $LASTEXITCODE"
    exit 1
}
Pop-Location

& "$agentPath\svc.cmd" install
& "$agentPath\svc.cmd" start
Write-Host "Azure Pipelines Agent service started."

Write-Host "✅ Script completed successfully!"
