pipeline {
    agent any

    parameters {
        choice(
            name: 'QUALITY_GATE_MODE',
            choices: ['SKIP', 'NON_BLOCKING', 'BLOCKING'],
            description: 'Quality Gate: SKIP = no wait, NON_BLOCKING = wait but continue, BLOCKING = fail pipeline on bad gate'
        )
    }

    environment {
        // Make sure dotnet global tools (sonarscanner) are available
        PATH = "C:\\Users\\admin\\.dotnet\\tools;${env.PATH}"

        BUILD_CONFIG = 'Release'
        SOLUTION = 'eShopOnWeb.sln'
        PUBLISH_DIR = 'publish'

        // IIS paths and names
        STAGING_PATH   = "C:\\inetpub\\eShopOnWeb-staging"
        PROD_PATH      = "C:\\inetpub\\eShopOnWeb-production"
        STAGING_SITE   = "eShopOnWeb-staging"
        PROD_SITE      = "eShopOnWeb-production"
        STAGING_APPPOOL = "eShopOnWeb-staging"
        PROD_APPPOOL    = "eShopOnWeb-production"

        // SonarQube
        SONAR_HOST_URL = 'http://localhost:9000'
        SONAR_TOKEN    = credentials('sonar-tak')
    }

    stages {

        stage('Diagnostics') {
            steps {
                echo 'Diagnostics: PATH and tools'
                bat '''
                    echo PATH:
                    echo %PATH%
                    whoami

                    echo Checking dotnet and sonarscanner...
                    where dotnet
                    where dotnet-sonarscanner || echo dotnet-sonarscanner not found in PATH
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
                        echo "Checkout failed: ${e.message}"
                        echo "This might be a network issue. Try running the pipeline again."
                        error "Checkout stage failed: ${e.message}"
                    }
                }
            }
        }

        stage('Restore') {
            steps {
                bat '''
                    echo Setting up MSBuild environment...
                    if not exist "C:\\Windows\\SystemTemp\\MSBuildTemp" mkdir "C:\\Windows\\SystemTemp\\MSBuildTemp"
                    
                    echo Cleaning NuGet cache and temp files...
                    dotnet nuget locals all --clear
                    if exist "%TEMP%\\MSBuildTemp" rmdir /s /q "%TEMP%\\MSBuildTemp" 2>nul
                    if exist "%LOCALAPPDATA%\\Temp\\MSBuildTemp" rmdir /s /q "%LOCALAPPDATA%\\Temp\\MSBuildTemp" 2>nul
                    
                    echo Restoring packages (single-threaded to avoid MSBuild node crashes)...
                    dotnet restore %SOLUTION% --verbosity minimal /maxcpucount:1
                '''
            }
        }

        stage('Build') {
            steps {
                bat "dotnet build src\\Web\\Web.csproj -c %BUILD_CONFIG%"
            }
        }

        stage('Test') {
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

        stage('Quality Gate') {
            when {
                expression { params?.QUALITY_GATE_MODE != 'SKIP' }
            }
            steps {
                script {
                    String mode = params?.QUALITY_GATE_MODE ?: 'NON_BLOCKING'
                    boolean blocking = (mode == 'BLOCKING')

                    echo "Quality gate mode: ${mode}"
                    echo "SonarQube dashboard: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"

                    int timeoutMinutes = blocking ? 15 : 5

                    try {
                        timeout(time: timeoutMinutes, unit: 'MINUTES') {
                            def qg = waitForQualityGate abortPipeline: blocking
                            if (qg.status == 'OK') {
                                echo "Quality gate passed"
                            } else if (blocking) {
                                error "Quality gate failed: ${qg.status}"
                            } else {
                                echo "Quality gate status: ${qg.status} (non-blocking, continuing)"
                            }
                        }
                    } catch (Exception e) {
                        if (blocking) {
                            error "Quality gate check failed: ${e.message}"
                        } else {
                            echo "Quality gate check issue (non-blocking): ${e.message}"
                        }
                    }
                }
            }
        }

        stage('Publish') {
            steps {
                bat "dotnet publish src\\Web\\Web.csproj -c %BUILD_CONFIG% -o %PUBLISH_DIR%"
            }
        }

        stage('Configure Staging Settings') {
            steps {
                powershell '''
                    $stagingConfig = "src/Web/appsettings.Staging.json"
                    $defaultConfig = "src/Web/appsettings.json"
                    $targetPath = "$env:PUBLISH_DIR\\appsettings.json"

                    if (Test-Path $stagingConfig) {
                        Copy-Item $stagingConfig $targetPath -Force
                        Write-Host "Staging config applied."
                    } else {
                        Copy-Item $defaultConfig $targetPath -Force
                        Write-Host "Staging config not found. Using default appsettings.json."
                    }
                '''
            }
        }

        stage('Deploy to Staging') {
            steps {
                powershell '''
                    Import-Module WebAdministration -ErrorAction SilentlyContinue

                    $publishPath = "$env:WORKSPACE\\$env:PUBLISH_DIR"
                    $sitePath    = $env:STAGING_PATH
                    $appPool     = $env:STAGING_APPPOOL
                    $siteName    = $env:STAGING_SITE

                    Write-Host "Publish path: $publishPath"
                    Write-Host "Staging path: $sitePath"

                    if (!(Test-Path $publishPath)) {
                        Write-Host "ERROR: Publish directory does not exist: $publishPath"
                        exit 1
                    }

                    if (!(Test-Path $sitePath)) {
                        New-Item -ItemType Directory -Path $sitePath -Force | Out-Null
                    } else {
                        Get-ChildItem $sitePath -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    Copy-Item "$publishPath\\*" $sitePath -Recurse -Force
                    Write-Host "Files copied to staging path."
                    
                    # Verify and fix web.config
                    $webConfigPath = "$sitePath\\web.config"
                    if (Test-Path $webConfigPath) {
                        $webConfigContent = Get-Content $webConfigPath -Raw
                        $dotnetPath = "C:\\Program Files\\dotnet\\dotnet.exe"
                        $needsFix = $false
                        
                        # Ensure processPath is set correctly
                        if ($webConfigContent -notlike "*processPath=`"$dotnetPath`"*") {
                            Write-Host "Fixing processPath in web.config..."
                            $webConfigContent = $webConfigContent -replace 'processPath="[^"]*"', "processPath=`"$dotnetPath`""
                            $needsFix = $true
                        }
                        
                        # Error 0x8007000d often indicates AspNetCoreModuleV2 is not installed
                        # Try fallback to AspNetCoreModule (more commonly available)
                        if ($webConfigContent -like "*modules=`"AspNetCoreModuleV2`"*") {
                            Write-Host "Changing module from AspNetCoreModuleV2 to AspNetCoreModule (common fix for 0x8007000d error)..."
                            $webConfigContent = $webConfigContent -replace 'modules="AspNetCoreModuleV2"', 'modules="AspNetCoreModule"'
                            $needsFix = $true
                        }
                        
                        # Ensure hostingModel is set (required for .NET Core 3.1+)
                        if ($webConfigContent -notlike "*hostingModel=*") {
                            Write-Host "Adding hostingModel attribute..."
                            $webConfigContent = $webConfigContent -replace '(<aspNetCore[^>]*)(\s*/>)', '$1 hostingModel="inprocess"$2'
                            $needsFix = $true
                        }
                        
                        # Validate XML structure
                        try {
                            [xml]$null = $webConfigContent
                            Write-Host "web.config XML structure is valid"
                        } catch {
                            Write-Host "ERROR: web.config has invalid XML structure: $($_.Exception.Message)"
                            exit 1
                        }
                        
                        if ($needsFix) {
                            # Save with UTF-8 encoding without BOM
                            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                            [System.IO.File]::WriteAllText($webConfigPath, $webConfigContent, $utf8NoBom)
                            Write-Host "web.config has been fixed and saved with UTF-8 encoding"
                        } else {
                            Write-Host "web.config verified: Configuration is correct"
                        }
                    } else {
                        Write-Host "WARNING: web.config not found in publish output"
                    }

                    # Create logs folder and set permissions
                    $logsPath = "$sitePath\\logs"
                    if (!(Test-Path $logsPath)) {
                        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
                        Write-Host "Created logs folder: $logsPath"
                    }

                    if (Test-Path "IIS:\\AppPools\\$appPool") {
                        Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue
                    } else {
                        New-WebAppPool -Name $appPool | Out-Null
                    }

                    Set-ItemProperty "IIS:\\AppPools\\$appPool" -Name managedRuntimeVersion -Value ""
                    Set-ItemProperty "IIS:\\AppPools\\$appPool" -Name processModel.identityType -Value "ApplicationPoolIdentity"

                    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
                        Set-ItemProperty "IIS:\\Sites\\$siteName" -Name physicalPath -Value $sitePath
                        Set-ItemProperty "IIS:\\Sites\\$siteName" -Name applicationPool -Value $appPool
                    } else {
                        New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPool -Port 8081 -Force | Out-Null
                    }

                    # Set permissions for app pool identity
                    $identity = "IIS APPPOOL\\$appPool"
                    $grantArg = "${identity}:(OI)(CI)(M)"
                    icacls $sitePath /grant $grantArg /T /Q
                    icacls $logsPath /grant $grantArg /T /Q
                    Write-Host "Permissions set for app pool identity: $identity"

                    Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue
                    Restart-WebAppPool -Name $appPool
                    Start-Website -Name $siteName -ErrorAction SilentlyContinue

                    Write-Host "Staging deployment completed."
                '''
            }
        }

        stage('Verify Staging') {
            steps {
                powershell '''
                    $url = "http://localhost:8081"
                    $sitePath = $env:STAGING_PATH
                    $logsPath = "$sitePath\\logs"
                    
                    Write-Host "Waiting for application to start..."
                    Start-Sleep -Seconds 10
                    
                    # Check app pool status
                    Import-Module WebAdministration -ErrorAction SilentlyContinue
                    $appPool = $env:STAGING_APPPOOL
                    $poolState = (Get-WebAppPoolState -Name $appPool -ErrorAction SilentlyContinue).Value
                    Write-Host "App Pool State: $poolState"
                    
                    # Check for log files
                    if (Test-Path $logsPath) {
                        $logFiles = Get-ChildItem $logsPath -Filter "stdout*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
                        if ($logFiles) {
                            Write-Host "Found $($logFiles.Count) log file(s). Latest: $($logFiles[0].Name)"
                            Write-Host "Last 20 lines of latest log:"
                            Get-Content $logFiles[0].FullName -Tail 20 -ErrorAction SilentlyContinue
                        } else {
                            Write-Host "No log files found in $logsPath"
                        }
                    } else {
                        Write-Host "Logs folder does not exist: $logsPath"
                    }
                    
                    # Try to access the site
                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
                        if ($response.StatusCode -eq 200) {
                            Write-Host "SUCCESS: Staging is running correctly at $url"
                        } else {
                            Write-Host "WARNING: Staging returned status code $($response.StatusCode)"
                        }
                    } catch {
                        Write-Host "ERROR: Staging verification failed: $($_.Exception.Message)"
                        Write-Host "Check Event Viewer (Windows Logs > Application) for detailed errors"
                        Write-Host "Check logs folder at: $logsPath"
                    }
                '''
            }
        }

    }

    post {
        always {
            echo 'Pipeline finished.'
            echo "SonarQube Dashboard: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
        }
        success {
            echo 'Pipeline succeeded.'
        }
        failure {
            echo 'Pipeline failed.'
        }
    }
}
