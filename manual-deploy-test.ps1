# Manual IIS Deployment Test Script
# Run this script as Administrator to test the deployment manually

Write-Host "========================================"
Write-Host "   MANUAL IIS DEPLOYMENT TEST SCRIPT   "
Write-Host "========================================"
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Import-Module WebAdministration -ErrorAction Stop

$sitePath = "C:\inetpub\eShopOnWeb-staging"
$pool = "eShopOnWeb-staging"
$site = "eShopOnWeb-staging"
$port = 8088

Write-Host "[1] Checking deployment files..." -ForegroundColor Cyan
if (Test-Path "$sitePath\Web.dll") {
    Write-Host "  ✓ Web.dll exists" -ForegroundColor Green
} else {
    Write-Host "  ✗ Web.dll NOT FOUND!" -ForegroundColor Red
    exit 1
}

if (Test-Path "$sitePath\web.config") {
    Write-Host "  ✓ web.config exists" -ForegroundColor Green
    $webConfig = Get-Content "$sitePath\web.config" -Raw
    Write-Host "  web.config size: $($webConfig.Length) bytes" -ForegroundColor Gray
} else {
    Write-Host "  ✗ web.config NOT FOUND!" -ForegroundColor Red
    exit 1
}

Write-Host "`n[2] Checking App Pool: $pool" -ForegroundColor Cyan
try {
    $poolInfo = Get-Item "IIS:\AppPools\$pool" -ErrorAction Stop
    $poolState = (Get-WebAppPoolState -Name $pool).Value
    Write-Host "  State: $poolState" -ForegroundColor $(if ($poolState -eq "Started") { "Green" } else { "Yellow" })
    Write-Host "  .NET CLR Version: $($poolInfo.managedRuntimeVersion) (should be empty)" -ForegroundColor Gray
    Write-Host "  Pipeline Mode: $($poolInfo.managedPipelineMode)" -ForegroundColor Gray
    Write-Host "  Identity: $($poolInfo.processModel.identityType)" -ForegroundColor Gray
    
    if ($poolInfo.managedRuntimeVersion -ne "") {
        Write-Host "  ⚠ WARNING: App Pool should use 'No Managed Code' for .NET 8" -ForegroundColor Yellow
        Write-Host "  Fixing..." -ForegroundColor Yellow
        Set-ItemProperty "IIS:\AppPools\$pool" -Name managedRuntimeVersion -Value ""
    }
    
    if ($poolState -ne "Started") {
        Write-Host "  Starting app pool..." -ForegroundColor Yellow
        Start-WebAppPool -Name $pool
        Start-Sleep -Seconds 3
        $poolState = (Get-WebAppPoolState -Name $pool).Value
        Write-Host "  State after start: $poolState" -ForegroundColor $(if ($poolState -eq "Started") { "Green" } else { "Red" })
    }
} catch {
    Write-Host "  ✗ App Pool not found: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Creating app pool..." -ForegroundColor Yellow
    New-WebAppPool $pool
    Set-ItemProperty "IIS:\AppPools\$pool" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$pool" -Name managedPipelineMode -Value "Integrated"
    Set-ItemProperty "IIS:\AppPools\$pool" -Name processModel.identityType -Value ApplicationPoolIdentity
    Start-WebAppPool -Name $pool
}

Write-Host "`n[3] Checking Website: $site" -ForegroundColor Cyan
try {
    $website = Get-Website -Name $site -ErrorAction Stop
    Write-Host "  State: $($website.State)" -ForegroundColor $(if ($website.State -eq "Started") { "Green" } else { "Yellow" })
    Write-Host "  Physical Path: $($website.physicalPath)" -ForegroundColor Gray
    Write-Host "  App Pool: $($website.applicationPool)" -ForegroundColor Gray
    
    $bindings = Get-WebBinding -Name $site
    Write-Host "  Current Bindings:" -ForegroundColor Gray
    foreach ($binding in $bindings) {
        Write-Host "    - $($binding.protocol)://$($binding.bindingInformation)" -ForegroundColor Gray
    }
    
    $hasPort8088 = $false
    foreach ($binding in $bindings) {
        if ($binding.bindingInformation -like "*:$port:*") {
            $hasPort8088 = $true
            break
        }
    }
    
    if (-not $hasPort8088) {
        Write-Host "  ⚠ Port $port binding not found. Fixing..." -ForegroundColor Yellow
        # Remove old bindings
        Get-WebBinding -Name $site | ForEach-Object {
            Remove-WebBinding -Name $site -BindingInformation $_.bindingInformation -ErrorAction SilentlyContinue
        }
        # Add correct binding
        New-WebBinding -Name $site -Protocol http -Port $port -IPAddress "*"
        Write-Host "  ✓ Added binding for port $port" -ForegroundColor Green
    }
    
    # Update physical path and app pool
    Set-ItemProperty "IIS:\Sites\$site" -Name physicalPath -Value $sitePath
    Set-ItemProperty "IIS:\Sites\$site" -Name applicationPool -Value $pool
    
    if ($website.State -ne "Started") {
        Write-Host "  Starting website..." -ForegroundColor Yellow
        Start-Website -Name $site
        Start-Sleep -Seconds 3
        $website = Get-Website -Name $site
        Write-Host "  State after start: $($website.State)" -ForegroundColor $(if ($website.State -eq "Started") { "Green" } else { "Red" })
    }
} catch {
    Write-Host "  ✗ Website not found: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Creating website..." -ForegroundColor Yellow
    New-Website -Name $site -Port $port -PhysicalPath $sitePath -ApplicationPool $pool
    Start-Website -Name $site
}

Write-Host "`n[4] Setting folder permissions..." -ForegroundColor Cyan
$identity = "IIS APPPOOL\$pool"
icacls $sitePath /grant "${identity}:(OI)(CI)(RX)" /T /Q | Out-Null
icacls $sitePath /grant "IIS_IUSRS:(OI)(CI)(RX)" /T /Q | Out-Null
icacls $sitePath /grant "IUSR:(OI)(CI)(RX)" /T /Q | Out-Null
$logs = "$sitePath\logs"
if (Test-Path $logs) {
    icacls $logs /grant "${identity}:(OI)(CI)(M)" /T /Q | Out-Null
}
Write-Host "  ✓ Permissions set" -ForegroundColor Green

Write-Host "`n[5] Setting ASPNETCORE_ENVIRONMENT..." -ForegroundColor Cyan
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    & $appcmd set config "$pool" /section:processModel /+environmentVariables.[name='ASPNETCORE_ENVIRONMENT',value='Staging'] 2>&1 | Out-Null
    & $appcmd set config "$pool" /section:processModel /environmentVariables.[name='ASPNETCORE_ENVIRONMENT'].value:"Staging" 2>&1 | Out-Null
    Write-Host "  ✓ ASPNETCORE_ENVIRONMENT=Staging set" -ForegroundColor Green
} else {
    Write-Host "  ⚠ appcmd.exe not found" -ForegroundColor Yellow
}

Write-Host "`n[6] Checking port $port..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
$portCheck = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
if ($portCheck) {
    Write-Host "  ✓ Port $port is listening" -ForegroundColor Green
    Write-Host "    State: $($portCheck.State)" -ForegroundColor Gray
    Write-Host "    Process ID: $($portCheck.OwningProcess)" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Port $port is NOT listening" -ForegroundColor Red
}

Write-Host "`n[7] Testing website connectivity..." -ForegroundColor Cyan
$url = "http://localhost:$port"
Write-Host "  URL: $url" -ForegroundColor Gray
try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  ✓ SUCCESS! Website is accessible" -ForegroundColor Green
    Write-Host "    Status Code: $($response.StatusCode)" -ForegroundColor Gray
    Write-Host "    Content Length: $($response.Content.Length) bytes" -ForegroundColor Gray
} catch {
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "    Response Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Gray
    }
    
    # Check if Web.dll is accessible (indicates hosting bundle issue)
    try {
        $dllTest = Invoke-WebRequest -Uri "$url/Web.dll" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($dllTest.StatusCode -eq 200) {
            Write-Host "`n  ⚠⚠⚠ CRITICAL WARNING ⚠⚠⚠" -ForegroundColor Red
            Write-Host "  Web.dll is accessible - ASP.NET Core Hosting Bundle is MISSING!" -ForegroundColor Red
            Write-Host "  The site is being served as static files instead of running as .NET app" -ForegroundColor Red
            Write-Host "  Download and install: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
        }
    } catch { }
}

Write-Host "`n[8] Checking log files..." -ForegroundColor Cyan
$logs = "$sitePath\logs"
if (Test-Path $logs) {
    $logFiles = Get-ChildItem $logs -Filter "stdout*.log" -ErrorAction SilentlyContinue
    if ($logFiles) {
        $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Host "  ✓ Found log file: $($latestLog.Name)" -ForegroundColor Green
        Write-Host "  Last modified: $($latestLog.LastWriteTime)" -ForegroundColor Gray
        Write-Host "`n  ===== Latest log entries (last 20 lines) =====" -ForegroundColor Gray
        Get-Content $latestLog.FullName -Tail 20 -ErrorAction SilentlyContinue
        Write-Host "  ==============================================" -ForegroundColor Gray
    } else {
        Write-Host "  ⚠ No stdout log files found" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠ Logs folder does not exist" -ForegroundColor Yellow
}

Write-Host "`n========================================"
Write-Host "   TEST COMPLETE"
Write-Host "========================================"

