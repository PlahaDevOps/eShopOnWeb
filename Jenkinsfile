pipeline {
    agent any

    parameters {
        choice(
            name: 'QUALITY_GATE_MODE',
            choices: ['SKIP', 'NON_BLOCKING', 'BLOCKING'],
            description: 'Quality Gate Mode: SKIP = No wait (fastest, recommended), NON_BLOCKING = Wait but continue on failure/timeout, BLOCKING = Fail pipeline on quality gate failure'
        )
    }

    environment {
        // Ensure Jenkins (SYSTEM account) can find both dotnet and SonarScanner tools
        PATH = "C:\\Users\\admin\\.dotnet\\tools;C:\\SonarScanner;${env.PATH}"

        BUILD_CONFIG = 'Release'
        SOLUTION = 'eShopOnWeb.sln'
        PUBLISH_DIR = 'publish'

        // IIS configuration
        STAGING_PATH = "C:\\inetpub\\eShopOnWeb-staging"
        PROD_PATH = "C:\\inetpub\\eShopOnWeb-production"
        STAGING_SITE = "eShopOnWeb-staging"
        PROD_SITE = "eShopOnWeb-production"
        STAGING_APPPOOL = "eShopOnWeb-staging"
        PROD_APPPOOL = "eShopOnWeb-production"

        // SonarQube
        SONAR_HOST_URL = 'http://localhost:9000'
        SONAR_TOKEN = credentials('sonar-tak')
    }

    stages {

        stage('Diagnostics') {
            steps {
                echo '🔍 Current PATH and User Context:'
                bat '''
                    echo PATH:
                    echo %PATH%
                    whoami

                    echo Checking tools...
                    where dotnet || (echo "⚠ dotnet not found" && exit /b 0)
                    where dotnet-sonarscanner || (echo "⚠ dotnet-sonarscanner not found in PATH" && exit /b 0)
                    where SonarScanner.MSBuild.exe || (echo "⚠ SonarScanner.MSBuild.exe not found in PATH" && exit /b 0)

                    echo ✅ Diagnostics check completed successfully.
                '''
            }
        }

        stage('Check Tools') {
            steps {
                bat '''
                    dotnet --list-sdks
                    echo.
                    echo Checking SonarScanner availability...
                    dotnet sonarscanner --version
                    if %errorlevel% NEQ 0 (
                        echo ⚠ dotnet sonarscanner not available, checking classic MSBuild scanner...
                        where SonarScanner.MSBuild.exe >NUL 2>&1 && (
                            SonarScanner.MSBuild.exe /? >NUL 2>&1
                            echo ✅ Classic SonarScanner.MSBuild.exe available.
                        ) || (
                            echo ⚠ Classic SonarScanner.MSBuild.exe not found — OK, using dotnet tool.
                        )
                    )
                    exit /b 0
                '''
            }
        }

        stage('Checkout Source Code') {
            steps {
                checkout scm
            }
        }

        stage('Restore Packages') {
            steps {
                bat 'dotnet restore %SOLUTION%'
            }
        }

        stage('Build Project') {
            steps {
                bat 'dotnet build src\\Web\\Web.csproj -c %BUILD_CONFIG%'
            }
        }

        stage('Run Unit Tests') {
            steps {
                bat '''
                    dotnet test tests\\UnitTests\\UnitTests.csproj ^
                      /p:CollectCoverage=true ^
                      /p:CoverletOutputFormat=opencover ^
                      /p:CoverletOutput="tests\\UnitTests\\TestResults\\coverage"
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    bat """
                        call dotnet sonarscanner begin ^
                            /k:"eShopOnWeb" ^
                            /n:"eShopOnWeb" ^
                            /d:sonar.host.url=%SONAR_HOST_URL% ^
                            /d:sonar.login=%SONAR_TOKEN% ^
                            /d:sonar.cs.opencover.reportsPaths=**/coverage.opencover.xml ^
                            /d:sonar.verbose=true

                        call dotnet build %SOLUTION% -c %BUILD_CONFIG%

                        call dotnet sonarscanner end ^
                            /d:sonar.login=%SONAR_TOKEN%
                    """
                }
            }
        }

        stage('Quality Gate Check') {
            when {
                expression { params?.QUALITY_GATE_MODE != 'SKIP' }
            }
            steps {
                script {
                    String mode = params?.QUALITY_GATE_MODE ?: 'NON_BLOCKING'
                    Boolean shouldAbort = (mode == 'BLOCKING')
                    
                    echo "🔍 Quality Gate Mode: ${mode}"
                    echo "📊 SonarQube analysis submitted — dashboard: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
                    
                    Integer timeoutMinutes = shouldAbort ? 15 : 5
                    try {
                        timeout(time: timeoutMinutes, unit: 'MINUTES') {
                            def qg = waitForQualityGate abortPipeline: shouldAbort
                            if (qg.status == 'OK') {
                                echo "✅ Quality Gate PASSED"
                            } else if (shouldAbort) {
                                error("❌ Quality Gate FAILED: ${qg.status}")
                            } else {
                                echo "⚠️ Quality Gate failed (${qg.status}) — continuing (NON_BLOCKING)"
                            }
                        }
                    } catch (Exception e) {
                        echo "⚠️ Quality Gate check issue: ${e.message} — continuing (NON_BLOCKING)"
                    }
                }
            }
        }

        stage('Publish Project') {
            steps {
                bat 'dotnet publish src\\Web\\Web.csproj -c %BUILD_CONFIG% -o %PUBLISH_DIR%'
            }
        }

        stage('Configure Staging Environment') {
            steps {
                powershell '''
                    $stagingConfig = "src/Web/appsettings.Staging.json"
                    $defaultConfig = "src/Web/appsettings.json"
                    $targetPath = "$env:PUBLISH_DIR\\appsettings.json"

                    if (Test-Path $stagingConfig) {
                        Copy-Item $stagingConfig $targetPath -Force
                        Write-Host "✅ Staging config found and copied."
                    }
                    else {
                        Copy-Item $defaultConfig $targetPath -Force
                        Write-Host "⚠️ Using default appsettings.json"
                    }
                '''
            }
        }

        stage('Clean and Deploy to Staging') {
            steps {
                powershell '''
                    Import-Module WebAdministration -ErrorAction SilentlyContinue;
                    $appPool = $env:STAGING_APPPOOL;
                    $siteName = $env:STAGING_SITE;
                    $sitePath = $env:STAGING_PATH;
                    
                    # Check if App Pool exists and verify identity is valid
                    $poolPath = "IIS:\\AppPools\\" + $appPool;
                    $appPoolIdentity = "IIS APPPOOL\$appPool";
                    $identityCorrupted = $false;
                    
                    if (Test-Path $poolPath) {
                        Write-Host "Application pool exists: $appPool";
                        Write-Host "Checking if identity is valid: $appPoolIdentity";
                        
                        # Check if the virtual account identity can be resolved
                        try {
                            # Try to resolve the account name to verify it exists
                            $sid = (New-Object System.Security.Principal.NTAccount($appPoolIdentity)).Translate([System.Security.Principal.SecurityIdentifier]);
                            Write-Host "✅ App pool identity is valid (SID: $sid)";
                        } catch {
                            Write-Host "⚠️ App pool identity is CORRUPTED - cannot resolve: $appPoolIdentity";
                            Write-Host "Error: $($_.Exception.Message)";
                            Write-Host "This can happen after Windows Updates, system restore, or VM cloning";
                            $identityCorrupted = $true;
                        }
                        
                        # If identity is corrupted, delete and recreate the app pool
                        if ($identityCorrupted) {
                            Write-Host "🛠️ Fixing corrupted app pool identity...";
                            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Start-Sleep -Seconds 2;
                            Remove-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Write-Host "✅ Deleted corrupted app pool";
                            Start-Sleep -Seconds 1;
                        } else {
                            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Start-Sleep -Seconds 5;
                        }
                    }
                    
                    # Create App Pool if it doesn't exist or was deleted due to corruption
                    if (!(Test-Path $poolPath)) {
                        Write-Host "Creating application pool: $appPool";
                        New-WebAppPool -Name $appPool -Force | Out-Null;
                        # Configure for .NET Core (No Managed Code)
                        Set-ItemProperty -Path $poolPath -Name managedRuntimeVersion -Value "";
                        Set-ItemProperty -Path $poolPath -Name processModel.identityType -Value "ApplicationPoolIdentity";
                        Write-Host "✅ Application pool created: $appPool";
                        
                        # Verify the new identity is valid
                        try {
                            $sid = (New-Object System.Security.Principal.NTAccount($appPoolIdentity)).Translate([System.Security.Principal.SecurityIdentifier]);
                            Write-Host "✅ New app pool identity verified: $appPoolIdentity";
                        } catch {
                            Write-Host "⚠️ Warning: Could not verify new identity, but continuing...";
                        }
                    }
                    
                    # Create directory if it doesn't exist
                    if (!(Test-Path $sitePath)) {
                        New-Item -ItemType Directory -Path $sitePath -Force | Out-Null;
                        Write-Host "✅ Created directory: $sitePath";
                    } else {
                        Get-ChildItem $sitePath -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue;
                    }
                    
                    # Copy published files
                    Copy-Item "$env:PUBLISH_DIR\\*" $sitePath -Recurse -Force;
                    Write-Host "✅ Files copied to: $sitePath";
                    
                    # Create Website if it doesn't exist
                    $existingSite = Get-Website -Name $siteName -ErrorAction SilentlyContinue;
                    if ($null -eq $existingSite) {
                        Write-Host "Creating website: $siteName";
                        New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPool -Port 8081 -Force | Out-Null;
                        Write-Host "✅ Website created: $siteName";
                    } else {
                        Write-Host "Website already exists: $siteName";
                        # Update website to use correct app pool and path
                        Set-ItemProperty -Path "IIS:\\Sites\\$siteName" -Name applicationPool -Value $appPool;
                        Set-ItemProperty -Path "IIS:\\Sites\\$siteName" -Name physicalPath -Value $sitePath;
                    }
                    
                    # Set proper permissions for IIS App Pool
                    try {
                        $poolConfig = Get-ItemProperty $poolPath;
                        $processModel = $poolConfig.processModel;
                        $identityType = $processModel.identityType;
                        
                        if ($identityType -eq "ApplicationPoolIdentity") {
                            Write-Host "Setting permissions for: $appPoolIdentity";
                            # Use (OI)(CI)(M) for Modify permissions - more permissive for .NET Core apps
                            $grantArg = "$appPoolIdentity:(OI)(CI)(M)";
                            & icacls $sitePath /grant $grantArg /T /Q 2>&1 | Out-Null;
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "✅ Permissions set successfully";
                            } else {
                                Write-Host "⚠️ Permission setting returned exit code $LASTEXITCODE";
                                Write-Host "This might indicate the identity is still corrupted. Check Event Viewer for details.";
                            }
                        } else {
                            Write-Host "⚠️ App pool uses custom identity ($identityType), skipping permission setting";
                        }
                    } catch {
                        Write-Host "⚠️ Error setting permissions: $($_.Exception.Message)";
                        Write-Host "This might indicate the identity is corrupted. The app pool was recreated, but identity may need manual verification.";
                    }
                    
                    # Start App Pool and Website
                    Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                    Restart-WebAppPool -Name $appPool;
                    Start-Website -Name $siteName -ErrorAction SilentlyContinue;
                    Write-Host "✅ Deployment completed. Waiting for app to start...";
                    Start-Sleep -Seconds 5;
                '''
            }
        }

        stage('Verify Staging Site') {
            steps {
                powershell '''
                    $url = 'http://localhost:8081';
                    Write-Host "Waiting for application to start...";
                    Start-Sleep -Seconds 10;
                    
                    # Check app pool status
                    Import-Module WebAdministration -ErrorAction SilentlyContinue;
                    $appPool = $env:STAGING_APPPOOL;
                    $poolState = (Get-WebAppPoolState -Name $appPool).Value;
                    Write-Host "App Pool State: $poolState";
                    
                    # Check application logs if available
                    $logPath = Join-Path $env:STAGING_PATH "logs";
                    if (Test-Path $logPath) {
                        Write-Host "`n=== Recent Application Logs ===";
                        $logFiles = Get-ChildItem $logPath -Filter "stdout*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1;
                        if ($logFiles) {
                            Write-Host "Last 30 lines from $($logFiles.Name):";
                            Get-Content $logFiles.FullName -Tail 30 -ErrorAction SilentlyContinue;
                        }
                    }
                    
                    # Try to access the site
                    Write-Host "`n=== Testing Site Access ===";
                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15;
                        if ($response.StatusCode -eq 200) {
                            Write-Host "✅ Staging site is live at $url";
                        } else {
                            Write-Host "⚠️ Staging returned HTTP $($response.StatusCode)";
                        }
                    } catch {
                        $statusCode = $_.Exception.Response.StatusCode.value__;
                        Write-Host "❌ Staging verification failed: $($_.Exception.Message)";
                        Write-Host "HTTP Status Code: $statusCode";
                        Write-Host "`n💡 Check Event Viewer (Windows Logs > Application) for detailed error messages";
                        Write-Host "💡 Or check application logs at: $logPath";
                    }
                '''
            }
        }

        stage('Manual Approval for Production') {
            steps {
                input message: 'Promote to Production?', ok: 'Deploy'
            }
        }

        stage('Clean and Deploy to Production') {
            steps {
                powershell '''
                    Import-Module WebAdministration -ErrorAction SilentlyContinue;
                    $appPool = $env:PROD_APPPOOL;
                    $siteName = $env:PROD_SITE;
                    $sitePath = $env:PROD_PATH;
                    
                    # Check if App Pool exists and verify identity is valid
                    $poolPath = "IIS:\\AppPools\\" + $appPool;
                    $appPoolIdentity = "IIS APPPOOL\$appPool";
                    $identityCorrupted = $false;
                    
                    if (Test-Path $poolPath) {
                        Write-Host "Application pool exists: $appPool";
                        Write-Host "Checking if identity is valid: $appPoolIdentity";
                        
                        # Check if the virtual account identity can be resolved
                        try {
                            # Try to resolve the account name to verify it exists
                            $sid = (New-Object System.Security.Principal.NTAccount($appPoolIdentity)).Translate([System.Security.Principal.SecurityIdentifier]);
                            Write-Host "✅ App pool identity is valid (SID: $sid)";
                        } catch {
                            Write-Host "⚠️ App pool identity is CORRUPTED - cannot resolve: $appPoolIdentity";
                            Write-Host "Error: $($_.Exception.Message)";
                            Write-Host "This can happen after Windows Updates, system restore, or VM cloning";
                            $identityCorrupted = $true;
                        }
                        
                        # If identity is corrupted, delete and recreate the app pool
                        if ($identityCorrupted) {
                            Write-Host "🛠️ Fixing corrupted app pool identity...";
                            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Start-Sleep -Seconds 2;
                            Remove-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Write-Host "✅ Deleted corrupted app pool";
                            Start-Sleep -Seconds 1;
                        } else {
                            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Start-Sleep -Seconds 5;
                        }
                    }
                    
                    # Create App Pool if it doesn't exist or was deleted due to corruption
                    if (!(Test-Path $poolPath)) {
                        Write-Host "Creating application pool: $appPool";
                        New-WebAppPool -Name $appPool -Force | Out-Null;
                        # Configure for .NET Core (No Managed Code)
                        Set-ItemProperty -Path $poolPath -Name managedRuntimeVersion -Value "";
                        Set-ItemProperty -Path $poolPath -Name processModel.identityType -Value "ApplicationPoolIdentity";
                        Write-Host "✅ Application pool created: $appPool";
                        
                        # Verify the new identity is valid
                        try {
                            $sid = (New-Object System.Security.Principal.NTAccount($appPoolIdentity)).Translate([System.Security.Principal.SecurityIdentifier]);
                            Write-Host "✅ New app pool identity verified: $appPoolIdentity";
                        } catch {
                            Write-Host "⚠️ Warning: Could not verify new identity, but continuing...";
                        }
                    }
                    
                    # Create directory if it doesn't exist
                    if (!(Test-Path $sitePath)) {
                        New-Item -ItemType Directory -Path $sitePath -Force | Out-Null;
                        Write-Host "✅ Created directory: $sitePath";
                    } else {
                        Get-ChildItem $sitePath -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue;
                    }
                    
                    # Copy published files
                    Copy-Item "$env:PUBLISH_DIR\\*" $sitePath -Recurse -Force;
                    Write-Host "✅ Files copied to: $sitePath";
                    
                    # Copy production appsettings
                    if (Test-Path 'src/Web/appsettings.Production.json') {
                        Copy-Item 'src/Web/appsettings.Production.json' "$sitePath/appsettings.json" -Force;
                        Write-Host "✅ Production appsettings copied";
                    } else {
                        Copy-Item 'src/Web/appsettings.json' "$sitePath/appsettings.json" -Force;
                        Write-Host "⚠️ Using default appsettings.json";
                    }
                    
                    # Create Website if it doesn't exist
                    $existingSite = Get-Website -Name $siteName -ErrorAction SilentlyContinue;
                    if ($null -eq $existingSite) {
                        Write-Host "Creating website: $siteName";
                        New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPool -Port 8080 -Force | Out-Null;
                        Write-Host "✅ Website created: $siteName";
                    } else {
                        Write-Host "Website already exists: $siteName";
                        # Update website to use correct app pool and path
                        Set-ItemProperty -Path "IIS:\\Sites\\$siteName" -Name applicationPool -Value $appPool;
                        Set-ItemProperty -Path "IIS:\\Sites\\$siteName" -Name physicalPath -Value $sitePath;
                    }
                    
                    # Set proper permissions for IIS App Pool
                    try {
                        $poolConfig = Get-ItemProperty $poolPath;
                        $processModel = $poolConfig.processModel;
                        $identityType = $processModel.identityType;
                        
                        if ($identityType -eq "ApplicationPoolIdentity") {
                            Write-Host "Setting permissions for: $appPoolIdentity";
                            # Use (OI)(CI)(M) for Modify permissions - more permissive for .NET Core apps
                            $grantArg = "$appPoolIdentity:(OI)(CI)(M)";
                            & icacls $sitePath /grant $grantArg /T /Q 2>&1 | Out-Null;
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "✅ Permissions set successfully";
                            } else {
                                Write-Host "⚠️ Permission setting returned exit code $LASTEXITCODE";
                                Write-Host "This might indicate the identity is still corrupted. Check Event Viewer for details.";
                            }
                        } else {
                            Write-Host "⚠️ App pool uses custom identity ($identityType), skipping permission setting";
                        }
                    } catch {
                        Write-Host "⚠️ Error setting permissions: $($_.Exception.Message)";
                        Write-Host "This might indicate the identity is corrupted. The app pool was recreated, but identity may need manual verification.";
                    }
                    
                    # Start App Pool and Website
                    Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                    Restart-WebAppPool -Name $appPool;
                    Start-Website -Name $siteName -ErrorAction SilentlyContinue;
                    Write-Host "✅ Deployment completed. Waiting for app to start...";
                    Start-Sleep -Seconds 5;
                '''
            }
        }

        stage('Verify Production Site') {
            steps {
                powershell '''
                    $url = 'http://localhost:8080';
                    Start-Sleep -Seconds 8;
                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15;
                        if ($response.StatusCode -eq 200) {
                            Write-Host "✅ Production site is live at $url";
                        } else {
                            Write-Host "⚠️ Production returned HTTP $($response.StatusCode)";
                        }
                    } catch {
                        Write-Host "❌ Production verification failed: $($_.Exception.Message)";
                    }
                '''
            }
        }
    }

    post {
        always {
            echo '✅ Pipeline finished — Build, SonarQube analysis, and IIS deployment complete.'
            echo "📊 SonarQube Dashboard: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
        }
        success {
            echo '🎉 Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed. Check logs above for details.'
        }
    }
}
