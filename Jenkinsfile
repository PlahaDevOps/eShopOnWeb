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

        PROD_PATH   = "C:\\inetpub\\eShopOnWeb-production"
        PROD_SITE   = "eShopOnWeb-production"
        PROD_APPPOOL = "eShopOnWeb-production"

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
                    echo Cleaning NuGet cache...
                    dotnet nuget locals all --clear

                    echo Restoring solution...
                    dotnet restore %SOLUTION% --verbosity minimal /maxcpucount:1
                '''
            }
        }

        stage('Build') {
            steps {
                bat "dotnet build src\\Web\\Web.csproj -c %BUILD_CONFIG% --no-restore"
            }
        }

        stage('Test') {
            steps {
                bat '''
                    dotnet test tests\\UnitTests\\UnitTests.csproj ^
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
                            "${scannerHome}\\SonarScanner.MSBuild.exe" begin ^
                                /k:"eShopOnWeb" ^
                                /n:"eShopOnWeb" ^
                                /d:sonar.host.url=%SONAR_HOST_URL% ^
                                /d:sonar.login=%SONAR_TOKEN% ^
                                /d:sonar.cs.opencover.reportsPaths=**\\coverage.opencover.xml ^
                                /d:sonar.verbose=true
                            
                            echo === BUILDING SOLUTION ===
                            dotnet build %SOLUTION% -c %BUILD_CONFIG% /p:UseSharedCompilation=false
                            
                            echo === SONAR END ===
                            "${scannerHome}\\SonarScanner.MSBuild.exe" end ^
                                /d:sonar.login=%SONAR_TOKEN%
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
                bat "dotnet publish src\\Web\\Web.csproj -c %BUILD_CONFIG% -o %PUBLISH_DIR%"
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

                    if (!(Test-Path $sitePath)) {
                        New-Item -ItemType Directory -Path $sitePath -Force
                    } else {
                        Get-ChildItem $sitePath -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    Copy-Item "$publish\\*" $sitePath -Recurse -Force

                    # Logs folder
                    $logs = "$sitePath\\logs"
                    if (!(Test-Path $logs)) { New-Item -ItemType Directory -Path $logs -Force }

                    # App Pool
                    if (!(Test-Path "IIS:\\AppPools\\$pool")) {
                        New-WebAppPool $pool
                    }
                    Set-ItemProperty "IIS:\\AppPools\\$pool" -Name processModel.identityType -Value ApplicationPoolIdentity
                    Set-ItemProperty "IIS:\\AppPools\\$pool" -Name managedRuntimeVersion -Value ""

                    # Website
                    if (!(Get-Website -Name $site -ErrorAction SilentlyContinue)) {
                        New-Website -Name $site -Port 8081 -PhysicalPath $sitePath -ApplicationPool $pool
                    } else {
                        Set-ItemProperty "IIS:\\Sites\\$site" -Name physicalPath -Value $sitePath
                        Set-ItemProperty "IIS:\\Sites\\$site" -Name applicationPool -Value $pool
                    }

                    # Permissions
                    $identity = "IIS APPPOOL\\$pool"
                    icacls $sitePath /grant "${identity}:(OI)(CI)(M)" /T /Q
                    icacls $logs /grant "${identity}:(OI)(CI)(M)" /T /Q

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
            steps {
                powershell '''
                    $url = "http://localhost:8081"
                    $logs = "$env:STAGING_PATH\\logs"

                    Start-Sleep -Seconds 10

                    Write-Host "Checking App Pool..."
                    $poolState = (Get-WebAppPoolState $env:STAGING_APPPOOL).Value
                    Write-Host "App Pool State: $poolState"

                    if (Test-Path $logs) {
                        $file = Get-ChildItem $logs -Filter "stdout*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($file) {
                            Write-Host "======= Last log file: $($file.Name) ======="
                            Get-Content $file.FullName -Tail 20
                        } else {
                            Write-Host "No logs found."
                        }
                    }

                    Write-Host "Checking website..."
                    try {
                        $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
                        if ($res.StatusCode -eq 200) {
                            Write-Host "Staging is RUNNING OK."
                        } else {
                            Write-Host "Unexpected status: $($res.StatusCode)"
                        }
                    } catch {
                        Write-Host "Staging ERROR: $($_.Exception.Message)"
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
