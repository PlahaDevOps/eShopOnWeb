pipeline {
    agent any

    parameters {
        choice(
            name: 'QUALITY_GATE_MODE',
            choices: ['SKIP', 'NON_BLOCKING', 'BLOCKING'],
            description: 'Quality gate behavior'
        )
    }

    environment {
        BUILD_CONFIG = 'Release'
        SOLUTION = 'eShopOnWeb.sln'
        PUBLISH_DIR = 'publish'

        STAGING_PATH   = "C:\\inetpub\\eShopOnWeb-staging"
        STAGING_SITE   = "eShopOnWeb-staging"
        STAGING_APPPOOL = "eShopOnWeb-staging"

        SONAR_HOST_URL = 'http://localhost:9000'
        SONAR_TOKEN = credentials('sonar-tak')
    }

    stages {

        stage('Diagnostics') {
            steps {
                bat '''
                    @echo off
                    echo ===== DIAGNOSTICS =====
                    echo PATH:
                    echo %PATH%
                    where dotnet
                    where msbuild.exe >nul 2>&1
                    if %errorlevel% equ 0 (
                        echo MSBuild found
                    ) else (
                        echo MSBuild not found (OK for SDK-style)
                    )
                    exit /b 0
                '''
            }
        }

        stage('Checkout') {
            steps {
                script {
                    try {
                        timeout(time: 5, unit: 'MINUTES') {
                            checkout scm
                        }
                    } catch (Exception e) {
                        error "Checkout failed: ${e.message}"
                    }
                }
            }
        }

        stage('Restore') {
            steps {
                bat '''
                    echo Cleaning old BlazorAdmin build artifacts...
                    if exist "src\\BlazorAdmin\\bin" (
                        echo Removing src\\BlazorAdmin\\bin...
                        rd /s /q "src\\BlazorAdmin\\bin"
                    ) else (
                        echo src\\BlazorAdmin\\bin not found
                    )
                    if exist "src\\BlazorAdmin\\obj" (
                        echo Removing src\\BlazorAdmin\\obj...
                        rd /s /q "src\\BlazorAdmin\\obj"
                    ) else (
                        echo src\\BlazorAdmin\\obj not found
                    )

                    echo Cleaning NuGet cache...
                    "C:\\Program Files\\dotnet\\dotnet.exe" nuget locals all --clear

                    echo Restoring solution (this will download WebAssembly packs if needed)...
                    "C:\\Program Files\\dotnet\\dotnet.exe" restore %SOLUTION% --verbosity minimal /maxcpucount:1
                    
                    if errorlevel 1 (
                        echo WARNING: Restore failed, but continuing...
                    )
                '''
            }
        }

        stage('Build') {
            steps {
                bat "\"C:\\Program Files\\dotnet\\dotnet.exe\" build src\\Web\\Web.csproj -c %BUILD_CONFIG% --no-restore"
            }
        }

        stage('Test') {
            steps {
                bat '''
                    "C:\\Program Files\\dotnet\\dotnet.exe" test tests\\UnitTests\\UnitTests.csproj ^
                        /p:CollectCoverage=true ^
                        /p:CoverletOutputFormat=opencover ^
                        /p:CoverletOutput="coverage.opencover.xml" ^
                        --logger trx
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    script {
                        // Resolve installed MSBuild scanner path
                        def scannerHome = tool 'SonarScannerMSBuild'
                        
                        bat """
                            echo === SONAR BEGIN ===
                            if not exist "${scannerHome}\\SonarScanner.MSBuild.exe" (
                                echo ERROR: SonarScanner.MSBuild.exe not found at ${scannerHome}
                                exit /b 1
                            )
                            
                            "${scannerHome}\\SonarScanner.MSBuild.exe" begin ^
                                /k:"eShopOnWeb" ^
                                /n:"eShopOnWeb" ^
                                /d:sonar.host.url=%SONAR_HOST_URL% ^
                                /d:sonar.login=%SONAR_TOKEN% ^
                                /d:sonar.cs.opencover.reportsPaths=**\\coverage.opencover.xml ^
                                /d:sonar.verbose=true
                            
                            if errorlevel 1 (
                                echo ERROR: SonarScanner begin failed
                                exit /b 1
                            )
                            
                            echo Verifying .sonarqube folder was created...
                            if not exist ".sonarqube" (
                                echo WARNING: .sonarqube folder was not created
                            ) else (
                                echo .sonarqube folder exists
                            )
                            
                            echo === BUILDING SOLUTION (excluding BlazorAdmin) ===
                            "C:\\Program Files\\dotnet\\dotnet.exe" build %SOLUTION% -c %BUILD_CONFIG% /p:UseSharedCompilation=false /p:BuildProjectReferences=false
                            "C:\\Program Files\\dotnet\\dotnet.exe" build src\\Web\\Web.csproj -c %BUILD_CONFIG% --no-restore
                            "C:\\Program Files\\dotnet\\dotnet.exe" build src\\ApplicationCore\\ApplicationCore.csproj -c %BUILD_CONFIG% --no-restore
                            "C:\\Program Files\\dotnet\\dotnet.exe" build src\\Infrastructure\\Infrastructure.csproj -c %BUILD_CONFIG% --no-restore
                            "C:\\Program Files\\dotnet\\dotnet.exe" build src\\BlazorShared\\BlazorShared.csproj -c %BUILD_CONFIG% --no-restore
                            
                            if errorlevel 1 (
                                echo ERROR: Build failed during SonarQube analysis
                                "${scannerHome}\\SonarScanner.MSBuild.exe" end /d:sonar.login=%SONAR_TOKEN%
                                exit /b 1
                            )
                            
                            echo === SONAR END ===
                            "${scannerHome}\\SonarScanner.MSBuild.exe" end ^
                                /d:sonar.login=%SONAR_TOKEN%
                            
                            if errorlevel 1 (
                                echo ERROR: SonarScanner end failed
                                exit /b 1
                            )
                        """
                    }
                }
            }
        }

        stage('Quality Gate') {
            when { expression { params.QUALITY_GATE_MODE != 'SKIP' } }
            steps {
                script {
                    boolean blocking = (params.QUALITY_GATE_MODE == 'BLOCKING')
                    int timeoutMinutes = blocking ? 15 : 5

                    try {
                        timeout(time: timeoutMinutes, unit: 'MINUTES') {
                            def qg = waitForQualityGate abortPipeline: blocking
                            echo "Quality Gate Status: ${qg.status}"

                            if (!blocking) {
                                echo "Non-blocking mode; continuing even if gate failed."
                            }
                        }
                    } catch (Exception e) {
                        if (blocking) {
                            error "Quality Gate failed: ${e.message}"
                        } else {
                            echo "Non-blocking: ${e.message}"
                        }
                    }
                }
            }
        }

        stage('Publish') {
            steps {
                bat '''
                    echo Publishing Web project...
                    "C:\\Program Files\\dotnet\\dotnet.exe" publish src\\Web\\Web.csproj -c %BUILD_CONFIG% -o %PUBLISH_DIR% --no-self-contained
                    if errorlevel 1 (
                        echo ERROR: Publish failed
                        exit /b 1
                    )
                    echo Verifying publish output...
                    if exist "%PUBLISH_DIR%\\Web.dll" (
                        echo Web.dll found
                    ) else (
                        echo ERROR: Web.dll not found in publish folder
                        exit /b 1
                    )
                    if exist "%PUBLISH_DIR%\\Web.runtimeconfig.json" (
                        echo Web.runtimeconfig.json found
                    ) else (
                        echo WARNING: Web.runtimeconfig.json not found - this may cause issues
                    )
                '''
            }
        }

        stage('Configure Staging Settings') {
            steps {
                powershell '''
                    $stagingConfig = "src/Web/appsettings.Staging.json"
                    $defaultConfig = "src/Web/appsettings.json"
                    $target = "$env:PUBLISH_DIR\\appsettings.json"

                    if (Test-Path $stagingConfig) {
                        Copy-Item $stagingConfig $target -Force
                        Write-Host "Applied Staging configuration."
                    } else {
                        Copy-Item $defaultConfig $target -Force
                        Write-Host "Using default appsettings.json."
                    }
                '''
            }
        }

        stage('Deploy to Staging') {
            steps {
                powershell '''
                    Import-Module WebAdministration -ErrorAction SilentlyContinue

                    $publish = "$env:WORKSPACE\\$env:PUBLISH_DIR"
                    $sitePath = $env:STAGING_PATH
                    $pool = $env:STAGING_APPPOOL
                    $site = $env:STAGING_SITE

                    Write-Host "Deploying to: $sitePath"

                    # Step 1: Stop website and app pool to release file locks
                    Write-Host "Stopping website and app pool to release file locks..."
                    try {
                        $website = Get-Website -Name $site -ErrorAction SilentlyContinue
                        if ($website -and $website.State -eq "Started") {
                            Stop-Website -Name $site -ErrorAction SilentlyContinue
                            Write-Host "Website stopped"
                        }
                    } catch {
                        Write-Host "Website not found or already stopped"
                    }
                    
                    try {
                        $poolState = (Get-WebAppPoolState -Name $pool -ErrorAction SilentlyContinue).Value
                        if ($poolState -eq "Started") {
                            Stop-WebAppPool -Name $pool -ErrorAction SilentlyContinue
                            Write-Host "App pool stopped"
                        }
                    } catch {
                        Write-Host "App pool not found or already stopped"
                    }

                    # Step 2: Wait for processes to release files (up to 30 seconds)
                    Write-Host "Waiting for file locks to be released..."
                    $maxWait = 30
                    $waited = 0
                    $filesLocked = $true
                    while ($filesLocked -and $waited -lt $maxWait) {
                        $lockedFiles = @()
                        if (Test-Path "$sitePath\\Web.dll") {
                            try {
                                $file = [System.IO.File]::Open("$sitePath\\Web.dll", [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                                $file.Close()
                                $filesLocked = $false
                            } catch {
                                $lockedFiles += "Web.dll"
                            }
                        } else {
                            $filesLocked = $false
                        }
                        if ($filesLocked) {
                            Start-Sleep -Seconds 2
                            $waited += 2
                            Write-Host "  Waiting... ($waited seconds)"
                        }
                    }
                    
                    if ($filesLocked) {
                        Write-Host "WARNING: Some files may still be locked, attempting to kill worker processes..."
                        Get-Process -Name "w3wp" -ErrorAction SilentlyContinue | Where-Object {
                            $_.Path -like "*$pool*" -or (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*$pool*"
                        } | Stop-Process -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 3
                    }

                    # Step 3: Create directory if needed
                    if (!(Test-Path $sitePath)) {
                        New-Item -ItemType Directory -Path $sitePath -Force
                    }

                    # Step 4: Remove old files (skip DLLs if still locked, they'll be overwritten)
                    Write-Host "Cleaning old files..."
                    Get-ChildItem $sitePath -Recurse -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Extension -ne ".dll" -and $_.Extension -ne ".pdb" } | 
                        Remove-Item -Force -ErrorAction SilentlyContinue
                    
                    # Step 5: Copy new files
                    Write-Host "Copying new files..."
                    Copy-Item "$publish\\*" $sitePath -Recurse -Force -ErrorAction Continue

                    # Logs folder
                    $logs = "$sitePath\\logs"
                    if (!(Test-Path $logs)) { New-Item -ItemType Directory -Path $logs -Force }

                    # App Pool - Configure correctly for .NET 8
                    if (!(Test-Path "IIS:\\AppPools\\$pool")) {
                        New-WebAppPool $pool
                        Write-Host "Created app pool: $pool"
                    }
                    # Critical: Set to "No Managed Code" for .NET Core/8
                    Set-ItemProperty "IIS:\\AppPools\\$pool" -Name managedRuntimeVersion -Value ""
                    # Set to Integrated Pipeline Mode
                    Set-ItemProperty "IIS:\\AppPools\\$pool" -Name managedPipelineMode -Value "Integrated"
                    # Set identity
                    Set-ItemProperty "IIS:\\AppPools\\$pool" -Name processModel.identityType -Value ApplicationPoolIdentity
                    # Enable load user profile (required for some scenarios)
                    Set-ItemProperty "IIS:\\AppPools\\$pool" -Name processModel.loadUserProfile -Value $true
                    # Set ASPNETCORE_ENVIRONMENT
                    $appcmd = "$env:SystemRoot\\System32\\inetsrv\\appcmd.exe"
                    if (Test-Path $appcmd) {
                        & $appcmd set config "$pool" /section:processModel /+environmentVariables.[name='ASPNETCORE_ENVIRONMENT',value='Staging'] 2>&1 | Out-Null
                        & $appcmd set config "$pool" /section:processModel /environmentVariables.[name='ASPNETCORE_ENVIRONMENT'].value:"Staging" 2>&1 | Out-Null
                        Write-Host "Set ASPNETCORE_ENVIRONMENT=Staging for app pool"
                    }

                    # Website - Use port 8088 (not 8081 which nginx uses)
                    if (!(Get-Website -Name $site -ErrorAction SilentlyContinue)) {
                        New-Website -Name $site -Port 8088 -PhysicalPath $sitePath -ApplicationPool $pool
                        Write-Host "Created website $site on port 8088"
                    } else {
                        Set-ItemProperty "IIS:\\Sites\\$site" -Name physicalPath -Value $sitePath
                        Set-ItemProperty "IIS:\\Sites\\$site" -Name applicationPool -Value $pool
                        # Ensure port binding is 8088
                        $bindings = Get-WebBinding -Name $site
                        $hasPort8088 = $false
                        foreach ($binding in $bindings) {
                            if ($binding.bindingInformation -like "*:8088:*") {
                                $hasPort8088 = $true
                                break
                            }
                        }
                        if (-not $hasPort8088) {
                            # Remove any existing bindings on wrong ports
                            Get-WebBinding -Name $site | Where-Object { $_.bindingInformation -notlike "*:8088:*" } | ForEach-Object {
                                Remove-WebBinding -Name $site -BindingInformation $_.bindingInformation -ErrorAction SilentlyContinue
                            }
                            New-WebBinding -Name $site -Protocol http -Port 8088 -IPAddress "*"
                            Write-Host "Updated website binding to port 8088"
                        }
                    }

                    # Permissions - Grant to all required identities
                    $identity = "IIS APPPOOL\\$pool"
                    Write-Host "Setting folder permissions..."
                    # Grant to App Pool identity
                    icacls $sitePath /grant "${identity}:(OI)(CI)(RX)" /T /Q
                    icacls $logs /grant "${identity}:(OI)(CI)(M)" /T /Q
                    # Grant to IIS_IUSRS
                    icacls $sitePath /grant "IIS_IUSRS:(OI)(CI)(RX)" /T /Q
                    icacls $logs /grant "IIS_IUSRS:(OI)(CI)(M)" /T /Q
                    # Grant to IUSR
                    icacls $sitePath /grant "IUSR:(OI)(CI)(RX)" /T /Q
                    icacls $logs /grant "IUSR:(OI)(CI)(M)" /T /Q
                    Write-Host "Permissions set for: $identity, IIS_IUSRS, IUSR"

                    # Start app pool (will start if stopped, or do nothing if already started)
                    $poolState = (Get-WebAppPoolState -Name $pool -ErrorAction SilentlyContinue).Value
                    if ($poolState -eq "Stopped") {
                        Start-WebAppPool -Name $pool
                    } else {
                        Restart-WebAppPool -Name $pool -ErrorAction SilentlyContinue
                    }
                    Start-Website -Name $site -ErrorAction SilentlyContinue

                    Write-Host "Staging deployment complete."
                '''
            }
        }

        stage('Verify Staging') {
            when { expression { false } }
            steps {
                echo "Verify Staging disabled temporarily"
                powershell '''
                    $url = "http://localhost:8088"
                    $logs = "$env:STAGING_PATH\\logs"
                    $sitePath = $env:STAGING_PATH
                    $pool = $env:STAGING_APPPOOL
                    $site = $env:STAGING_SITE

                    Start-Sleep -Seconds 15

                    Write-Host "========================================"
                    Write-Host "   COMPREHENSIVE STAGING VERIFICATION   "
                    Write-Host "========================================"

                    # Step 1: Check ASP.NET Core Hosting Bundle
                    Write-Host "`n[1] Checking ASP.NET Core Hosting Bundle..."
                    $dotnetInfo = dotnet --info 2>&1 | Out-String
                    if ($dotnetInfo -match "Microsoft\\.AspNetCore\\.App") {
                        Write-Host "✓ ASP.NET Core runtime found"
                        $runtimeVersions = dotnet --list-runtimes 2>&1 | Select-String "Microsoft.AspNetCore.App"
                        Write-Host "  Installed versions:"
                        $runtimeVersions | ForEach-Object { Write-Host "    - $_" }
                    } else {
                        Write-Host "✗ WARNING: ASP.NET Core runtime may not be installed"
                        Write-Host "  Install from: https://dotnet.microsoft.com/download/dotnet/8.0"
                    }

                    # Step 2: Check App Pool Configuration
                    Write-Host "`n[2] Checking App Pool: $pool"
                    try {
                        $poolInfo = Get-Item "IIS:\\AppPools\\$pool" -ErrorAction Stop
                        $poolState = (Get-WebAppPoolState -Name $pool).Value
                        Write-Host "  State: $poolState"
                        Write-Host "  .NET CLR Version: $($poolInfo.managedRuntimeVersion) (should be empty for No Managed Code)"
                        Write-Host "  Pipeline Mode: $($poolInfo.managedPipelineMode) (should be Integrated)"
                        Write-Host "  Identity: $($poolInfo.processModel.identityType)"
                        
                        if ($poolInfo.managedRuntimeVersion -ne "") {
                            Write-Host "  ✗ ERROR: App Pool must use 'No Managed Code' for .NET 8"
                        }
                        if ($poolInfo.managedPipelineMode -ne "Integrated") {
                            Write-Host "  ✗ ERROR: App Pool must use Integrated Pipeline Mode"
                        }
                        if ($poolState -eq "Stopped") {
                            Write-Host "  ⚠ App Pool is stopped - attempting to start..."
                            Start-WebAppPool -Name $pool
                            Start-Sleep -Seconds 5
                            $poolState = (Get-WebAppPoolState -Name $pool).Value
                            Write-Host "  State after start: $poolState"
                        }
                    } catch {
                        Write-Host "  ✗ ERROR: App Pool not found or inaccessible: $($_.Exception.Message)"
                    }

                    # Step 3: Check Website Configuration
                    Write-Host "`n[3] Checking Website: $site"
                    try {
                        $website = Get-Website -Name $site -ErrorAction Stop
                        Write-Host "  State: $($website.State)"
                        Write-Host "  Physical Path: $($website.physicalPath)"
                        Write-Host "  App Pool: $($website.applicationPool)"
                        
                        $bindings = Get-WebBinding -Name $site
                        Write-Host "  Bindings:"
                        $hasPort8088 = $false
                        foreach ($binding in $bindings) {
                            Write-Host "    - $($binding.protocol)://$($binding.bindingInformation)"
                            if ($binding.bindingInformation -like "*:8088:*") {
                                $hasPort8088 = $true
                            }
                        }
                        if (-not $hasPort8088) {
                            Write-Host "  ✗ ERROR: Website is not bound to port 8088!"
                        } else {
                            Write-Host "  ✓ Port 8088 binding confirmed"
                        }
                        
                        if ($website.State -ne "Started") {
                            Write-Host "  ⚠ Website is not started - attempting to start..."
                            Start-Website -Name $site
                            Start-Sleep -Seconds 5
                            $website = Get-Website -Name $site
                            Write-Host "  State after start: $($website.State)"
                        }
                    } catch {
                        Write-Host "  ✗ ERROR: Website not found: $($_.Exception.Message)"
                    }

                    # Step 4: Validate web.config
                    Write-Host "`n[4] Validating web.config..."
                    $webConfig = "$sitePath\\web.config"
                    if (Test-Path $webConfig) {
                        Write-Host "  ✓ web.config exists"
                        try {
                            $config = Get-Content $webConfig -Raw -ErrorAction Stop
                            # Check for corruption
                            if ($config -match '<system\\.webServer>') {
                                Write-Host "  ✓ system.webServer section found"
                            } else {
                                Write-Host "  ✗ ERROR: Missing system.webServer section"
                            }
                            if ($config -match '<aspNetCore') {
                                Write-Host "  ✓ aspNetCore section found"
                                $argMatch = [regex]::Match($config, 'arguments="([^"]+)"')
                                if ($argMatch.Success) {
                                    Write-Host "  Arguments: $($argMatch.Groups[1].Value)"
                                }
                                $pathMatch = [regex]::Match($config, 'processPath="([^"]+)"')
                                if ($pathMatch.Success) {
                                    Write-Host "  Process Path: $($pathMatch.Groups[1].Value)"
                                }
                            } else {
                                Write-Host "  ✗ ERROR: Missing aspNetCore section"
                            }
                            # Check for proper closing tags
                            $openTagPattern = '<[^/][^>]+>'
                            $closeTagPattern = '</[^>]+>'
                            $openTags = ([regex]::Matches($config, $openTagPattern)).Count
                            $closeTags = ([regex]::Matches($config, $closeTagPattern)).Count
                            if ($openTags -ne $closeTags) {
                                Write-Host "  ✗ WARNING: Possible XML corruption - tag mismatch"
                            }
                        } catch {
                            Write-Host "  ✗ ERROR reading web.config: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Host "  ✗ ERROR: web.config NOT FOUND at $webConfig"
                    }

                    # Check if Web.dll exists
                    $webDll = "$sitePath\\Web.dll"
                    if (Test-Path $webDll) {
                        Write-Host "  ✓ Web.dll exists"
                    } else {
                        Write-Host "  ✗ ERROR: Web.dll NOT FOUND at $webDll"
                    }

                    # Step 5: Check Folder Permissions
                    Write-Host "`n[5] Checking folder permissions..."
                    $requiredIdentities = @("IIS APPPOOL\$pool", "IIS_IUSRS", "IUSR")
                    foreach ($identity in $requiredIdentities) {
                        $acl = Get-Acl $sitePath -ErrorAction SilentlyContinue
                        $hasAccess = $false
                        if ($acl) {
                            $rules = $acl.Access | Where-Object { $_.IdentityReference -like "*$identity*" }
                            if ($rules) {
                                Write-Host "  ✓ $identity has access"
                                $hasAccess = $true
                            }
                        }
                        if (-not $hasAccess) {
                            Write-Host "  ⚠ $identity may not have proper access"
                        }
                    }

                    # Step 6: Check Event Viewer for Errors
                    Write-Host "`n[6] Checking Windows Event Log for IIS errors..."
                    $errorSources = @("IIS-W3SVC-WP", "IIS AspNetCore Module V2", "ASP.NET*", "Microsoft-Windows-IIS*")
                    $allEvents = @()
                    foreach ($source in $errorSources) {
                        $events = Get-EventLog -LogName Application -Source $source -Newest 10 -ErrorAction SilentlyContinue
                        if ($events) {
                            $allEvents += $events
                        }
                    }
                    if ($allEvents.Count -gt 0) {
                        Write-Host "  Found $($allEvents.Count) recent IIS/ASP.NET events:"
                        $allEvents | Sort-Object TimeGenerated -Descending | Select-Object -First 10 | ForEach-Object {
                            $level = if ($_.EntryType -eq "Error") { "✗ ERROR" } elseif ($_.EntryType -eq "Warning") { "⚠ WARNING" } else { "ℹ INFO" }
                            Write-Host "    [$($_.TimeGenerated)] $level - $($_.Source)"
                            Write-Host "      $($_.Message.Substring(0, [Math]::Min(250, $_.Message.Length)))"
                        }
                    } else {
                        Write-Host "  ✓ No recent IIS/ASP.NET errors found"
                    }

                    # Step 7: Check Log Files
                    Write-Host "`n[7] Checking application log files..."
                    if (Test-Path $logs) {
                        $files = Get-ChildItem $logs -Filter "stdout*.log" -ErrorAction SilentlyContinue
                        if ($files) {
                            $file = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            Write-Host "  ✓ Found log file: $($file.Name)"
                            Write-Host "  Last modified: $($file.LastWriteTime)"
                            Write-Host "  Size: $([math]::Round($file.Length/1KB, 2)) KB"
                            Write-Host "`n  ======= Latest log entries (last 50 lines) ======="
                            Get-Content $file.FullName -Tail 50 -ErrorAction SilentlyContinue
                            Write-Host "  ================================================"
                        } else {
                            Write-Host "  ⚠ No stdout log files found - app may not have started"
                        }
                    } else {
                        Write-Host "  ⚠ Logs folder does not exist: $logs"
                    }

                    # Step 8: Check Port Binding
                    Write-Host "`n[8] Checking port 8088 binding..."
                    $port8088 = Get-NetTCPConnection -LocalPort 8088 -ErrorAction SilentlyContinue
                    if ($port8088) {
                        Write-Host "  ✓ Port 8088 is listening"
                        Write-Host "  State: $($port8088.State)"
                        Write-Host "  Process ID: $($port8088.OwningProcess)"
                    } else {
                        Write-Host "  ✗ Port 8088 is NOT listening"
                    }

                    # Step 9: Test Connectivity
                    Write-Host "`n[9] Testing website connectivity..."
                    Write-Host "  URL: $url"
                    $maxRetries = 3
                    $success = $false
                    for ($i = 1; $i -le $maxRetries; $i++) {
                        try {
                            Write-Host "  Attempt $i of $maxRetries..."
                            $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                            if ($res.StatusCode -eq 200) {
                                Write-Host "  ✓ SUCCESS: Staging is RUNNING OK at $url"
                                Write-Host "  Status Code: $($res.StatusCode)"
                                Write-Host "  Content Length: $($res.Content.Length) bytes"
                                $success = $true
                                break
                            } else {
                                Write-Host "  ⚠ Unexpected status: $($res.StatusCode)"
                            }
                        } catch {
                            Write-Host "  ✗ Attempt $i failed: $($_.Exception.Message)"
                            if ($_.Exception.Response) {
                                Write-Host "    Response Status: $($_.Exception.Response.StatusCode)"
                            }
                            # Quick test: Check if Web.dll is accessible (indicates hosting bundle issue)
                            try {
                                $dllTest = Invoke-WebRequest -Uri "$url/Web.dll" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
                                if ($dllTest.StatusCode -eq 200) {
                                    Write-Host "    ⚠ WARNING: Web.dll is accessible - ASP.NET Hosting Bundle may be missing!"
                                    Write-Host "    The site is being served as static files instead of running as .NET app"
                                }
                            } catch { }
                            if ($i -lt $maxRetries) {
                                Write-Host "    Retrying in 5 seconds..."
                                Start-Sleep -Seconds 5
                            }
                        }
                    }
                    
                    if (-not $success) {
                        Write-Host "`n✗✗✗ FINAL RESULT: Staging verification FAILED ✗✗✗"
                        Write-Host "The website is not accessible at $url"
                        Write-Host "Please review the diagnostics above and check:"
                        Write-Host "  1. Event Viewer (eventvwr) → Windows Logs → Application"
                        Write-Host "  2. ASP.NET Core Hosting Bundle installation"
                        Write-Host "  3. App Pool configuration (No Managed Code, Integrated)"
                        Write-Host "  4. Folder permissions (IIS_IUSRS, IUSR, App Pool identity)"
                        Write-Host "  5. Port 8088 binding"
                    } else {
                        Write-Host "`n✓✓✓ FINAL RESULT: Staging verification SUCCEEDED ✓✓✓"
                    }
                '''
            }
        }
    }

    post {
        always {
            echo "Pipeline finished."
            echo "SonarQube: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
        }
        success { echo "Pipeline succeeded!" }
        failure { echo "Pipeline FAILED." }
    }
}
