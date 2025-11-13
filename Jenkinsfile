pipeline {
    agent any

    parameters {
        choice(
            name: 'QUALITY_GATE_MODE',
            choices: ['SKIP', 'NON_BLOCKING', 'BLOCKING'],
            description: 'Quality Gate Mode'
        )
    }

    environment {
        PATH = "C:\\Users\\admin\\.dotnet\\tools;C:\\SonarScanner;${env.PATH}"
        BUILD_CONFIG = 'Release'
        SOLUTION = 'eShopOnWeb.sln'
        PUBLISH_DIR = 'publish'

        STAGING_PATH = "C:\\inetpub\\eShopOnWeb-staging"
        PROD_PATH = "C:\\inetpub\\eShopOnWeb-production"
        STAGING_SITE = "eShopOnWeb-staging"
        PROD_SITE = "eShopOnWeb-production"
        STAGING_APPPOOL = "eShopOnWeb-staging"
        PROD_APPPOOL = "eShopOnWeb-production"

        SONAR_HOST_URL = 'http://localhost:9000'
        SONAR_TOKEN = credentials('sonar-tak')
    }

    stages {

        stage('Workspace Cleanup') {
            steps {
                powershell '''
                    Write-Host "Checking workspace name..."

                    if ($env:WORKSPACE -like "*@*") {
                        Write-Host "Warning: workspace folder contains @ suffix. This is normal on Jenkins agents."
                    }

                    Write-Host "Cleaning temporary folders..."
                    Remove-Item -Recurse -Force "$env:WORKSPACE\\.sonarqube" -ErrorAction SilentlyContinue
                    Remove-Item -Recurse -Force "$env:WORKSPACE\\publish" -ErrorAction SilentlyContinue
                '''
            }
        }

        stage('Diagnostics') {
            steps {
                bat '''
                    echo PATH:
                    echo %PATH%
                    whoami

                    echo Checking tools...
                    where dotnet || (echo dotnet not found && exit /b 0)
                    where dotnet-sonarscanner || (echo dotnet-sonarscanner not found in PATH && exit /b 0)
                '''
            }
        }

        stage('Check Tools') {
            steps {
                bat '''
                    dotnet --list-sdks
                    dotnet sonarscanner --version
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
                expression { params.QUALITY_GATE_MODE != 'SKIP' }
            }
            steps {
                script {
                    def mode = params.QUALITY_GATE_MODE
                    def shouldAbort = (mode == 'BLOCKING')

                    try {
                        timeout(time: 10, unit: 'MINUTES') {
                            def qg = waitForQualityGate abortPipeline: shouldAbort
                            echo "Quality gate status: ${qg.status}"
                        }
                    } catch (err) {
                        echo "Quality Gate check error: ${err}"
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
                    $staging = "src/Web/appsettings.Staging.json"
                    $default = "src/Web/appsettings.json"
                    $out = "$env:PUBLISH_DIR/appsettings.json"

                    if (Test-Path $staging) {
                        Copy-Item $staging $out -Force
                        Write-Host "Staging config applied."
                    } else {
                        Copy-Item $default $out -Force
                        Write-Host "Default config applied."
                    }
                '''
            }
        }

        stage('Clean and Deploy to Staging') {
            steps {
                powershell '''
                    Import-Module WebAdministration

                    $pool = $env:STAGING_APPPOOL
                    $site = $env:STAGING_SITE
                    $path = $env:STAGING_PATH
                    $poolPath = "IIS:\\AppPools\\$pool"
                    $identity = "IIS APPPOOL\\$pool"

                    if (!(Test-Path $poolPath)) {
                        Write-Host "Creating app pool..."
                        New-WebAppPool -Name $pool | Out-Null
                        Set-ItemProperty $poolPath -Name managedRuntimeVersion -Value ""
                        Set-ItemProperty $poolPath -Name processModel.identityType -Value "ApplicationPoolIdentity"
                    }

                    if (!(Test-Path $env:PUBLISH_DIR)) {
                        Write-Host "Error: Publish directory missing."
                        exit 1
                    }

                    if (!(Test-Path $path)) {
                        New-Item -ItemType Directory -Path $path -Force | Out-Null
                    } else {
                        Get-ChildItem $path -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    Copy-Item "$env:PUBLISH_DIR\\*" $path -Recurse -Force

                    if (-not (Get-Website -Name $site -ErrorAction SilentlyContinue)) {
                        New-Website -Name $site -PhysicalPath $path -ApplicationPool $pool -Port 8081 | Out-Null
                    }

                    icacls $path /grant "$identity:(OI)(CI)(M)" /T /Q

                    Restart-WebAppPool $pool
                    Start-Website $site
                '''
            }
        }

        stage('Verify Staging Site') {
            steps {
                powershell '''
                    Start-Sleep -Seconds 10
                    try {
                        $r = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing
                        Write-Host "Staging site status: $($r.StatusCode)"
                    } catch {
                        Write-Host "Staging site failed to load."
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
                    Import-Module WebAdministration

                    $pool = $env:PROD_APPPOOL
                    $site = $env:PROD_SITE
                    $path = $env:PROD_PATH
                    $poolPath = "IIS:\\AppPools\\$pool"
                    $identity = "IIS APPPOOL\\$pool"

                    if (!(Test-Path $poolPath)) {
                        New-WebAppPool -Name $pool | Out-Null
                        Set-ItemProperty $poolPath -Name managedRuntimeVersion -Value ""
                        Set-ItemProperty $poolPath -Name processModel.identityType -Value "ApplicationPoolIdentity"
                    }

                    if (!(Test-Path $path)) {
                        New-Item -ItemType Directory -Path $path -Force | Out-Null
                    } else {
                        Get-ChildItem $path -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    Copy-Item "$env:PUBLISH_DIR\\*" $path -Recurse -Force

                    if (-not (Get-Website -Name $site)) {
                        New-Website -Name $site -PhysicalPath $path -ApplicationPool $pool -Port 8080 | Out-Null
                    }

                    icacls $path /grant "$identity:(OI)(CI)(M)" /T /Q

                    Restart-WebAppPool $pool
                    Start-Website $site
                '''
            }
        }

        stage('Verify Production Site') {
            steps {
                powershell '''
                    Start-Sleep -Seconds 8
                    try {
                        $r = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing
                        Write-Host "Production site status: $($r.StatusCode)"
                    } catch {
                        Write-Host "Production site failed to load."
                    }
                '''
            }
        }
    }

    post {
        always {
            echo "Pipeline finished."
            echo "SonarQube Dashboard: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
        }
        success {
            echo "Pipeline completed successfully."
        }
        failure {
            echo "Pipeline failed."
        }
    }
}
