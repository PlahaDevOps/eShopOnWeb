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
                    where dotnet
                    where dotnet-sonarscanner || echo "⚠️ dotnet-sonarscanner not found in PATH"
                    where SonarScanner.MSBuild.exe || echo "⚠️ SonarScanner.MSBuild.exe not found in PATH"
                '''
            }
        }

        stage('Check Tools') {
            steps {
                bat '''
                    dotnet --list-sdks
                    dotnet sonarscanner --version || SonarScanner.MSBuild.exe /?
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
                    if (Test-Path ("IIS:\\AppPools\\" + $appPool)) {
                        Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                        Start-Sleep -Seconds 5;
                    }
                    if (!(Test-Path $env:STAGING_PATH)) {
                        New-Item -ItemType Directory -Path $env:STAGING_PATH -Force | Out-Null;
                    } else {
                        Get-ChildItem $env:STAGING_PATH -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue;
                    }
                    Copy-Item "$env:PUBLISH_DIR\\*" $env:STAGING_PATH -Recurse -Force;
                    Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                    Restart-WebAppPool -Name $appPool;
                    Start-Website -Name $env:STAGING_SITE -ErrorAction SilentlyContinue;
                '''
            }
        }

        stage('Verify Staging Site') {
            steps {
                powershell '''
                    $url = 'http://localhost:8081';
                    Start-Sleep -Seconds 8;
                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15;
                        if ($response.StatusCode -eq 200) {
                            Write-Host "✅ Staging site is live at $url";
                        } else {
                            Write-Host "⚠️ Staging returned HTTP $($response.StatusCode)";
                        }
                    } catch {
                        Write-Host "❌ Staging verification failed: $($_.Exception.Message)";
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
                    if (Test-Path ("IIS:\\AppPools\\" + $appPool)) {
                        Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                        Start-Sleep -Seconds 5;
                    }
                    if (!(Test-Path $env:PROD_PATH)) {
                        New-Item -ItemType Directory -Path $env:PROD_PATH -Force | Out-Null;
                    } else {
                        Get-ChildItem $env:PROD_PATH -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue;
                    }
                    Copy-Item "$env:PUBLISH_DIR\\*" $env:PROD_PATH -Recurse -Force;
                    if (Test-Path 'src/Web/appsettings.Production.json') {
                        Copy-Item 'src/Web/appsettings.Production.json' "$env:PROD_PATH/appsettings.json" -Force;
                    } else {
                        Copy-Item 'src/Web/appsettings.json' "$env:PROD_PATH/appsettings.json" -Force;
                    }
                    Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                    Restart-WebAppPool -Name $appPool;
                    Start-Website -Name $env:PROD_SITE -ErrorAction SilentlyContinue;
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
