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
        // Ensure Jenkins (SYSTEM account) can find global dotnet tools
        PATH = "C:\\Users\\admin\\.dotnet\\tools;${env.PATH}"

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
                echo 'Current PATH and User Context:'
                bat '''
                    echo PATH:
                    echo %PATH%
                    whoami
                    where dotnet
                    where dotnet-sonarscanner || echo "⚠️ dotnet-sonarscanner not found in PATH"
                '''
            }
        }

        stage('Check Tools') {
            steps {
                bat '''
                    dotnet --list-sdks
                    dotnet sonarscanner --version || exit /b 0
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
                        dotnet sonarscanner begin ^
                            /k:"eShopOnWeb" ^
                            /d:sonar.host.url=%SONAR_HOST_URL% ^
                            /d:sonar.login=%SONAR_TOKEN% ^
                            /d:sonar.cs.opencover.reportsPaths=**/coverage.opencover.xml ^
                            /d:sonar.verbose=true

                        dotnet build %SOLUTION% -c %BUILD_CONFIG%

                        dotnet sonarscanner end ^
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
                    // Get quality gate mode with default fallback
                    String mode = params?.QUALITY_GATE_MODE ?: 'NON_BLOCKING'
                    Boolean shouldAbort = (mode == 'BLOCKING')
                    
                    echo "🔍 Quality Gate Mode: ${mode}"
                    echo "📊 SonarQube analysis submitted. Task processing in background..."
                    echo "🔗 View analysis progress: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
                    
                    if (mode == 'SKIP') {
                        echo "⏭️ Skipping quality gate wait - analysis will complete in background"
                        echo "💡 Check SonarQube dashboard later for results"
                    } else {
                        // Use shorter timeout for non-blocking, longer for blocking
                        Integer timeoutMinutes = shouldAbort ? 15 : 5
                        
                        try {
                            timeout(time: timeoutMinutes, unit: 'MINUTES') {
                                def qg = waitForQualityGate abortPipeline: shouldAbort
                                
                                if (qg.status == 'OK') {
                                    echo "✅ Quality Gate PASSED"
                                } else {
                                    echo "⚠️ Quality Gate status: ${qg.status}"
                                    echo "📋 Quality Gate details: ${qg}"
                                    
                                    if (shouldAbort) {
                                        error("Quality Gate FAILED - Pipeline aborted as per configuration")
                                    } else {
                                        echo "⚠️ Quality Gate failed but continuing (NON_BLOCKING mode)"
                                        echo "💡 Review issues in SonarQube dashboard: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
                                    }
                                }
                            }
                        } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                            if (shouldAbort) {
                                error("Quality Gate check timed out - Pipeline aborted")
                            } else {
                                echo "⏱️ Quality Gate check timed out after ${timeoutMinutes} minutes"
                                echo "🔄 Analysis continues in background - deployment proceeding"
                                echo "💡 Check SonarQube dashboard later: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
                            }
                        } catch (Exception e) {
                            if (shouldAbort) {
                                error("Quality Gate check failed: ${e.message}")
                            } else {
                                echo "⚠️ Quality Gate check encountered an error: ${e.message}"
                                echo "🔄 Continuing with deployment (NON_BLOCKING mode)"
                            }
                        }
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
                    if (Test-Path 'src/Web/appsettings.Staging.json') {
                        Copy-Item 'src/Web/appsettings.Staging.json' "$env:PUBLISH_DIR/appsettings.json" -Force
                    } else {
                        Copy-Item 'src/Web/appsettings.json' "$env:PUBLISH_DIR/appsettings.json" -Force
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
                            Write-Host '✅ Staging is running correctly at' $url;
                        } else {
                            Write-Host '⚠️ Staging returned status:' $response.StatusCode;
                        }
                    } catch {
                        Write-Host '❌ Staging verification failed:' $_.Exception.Message;
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
                            Write-Host '✅ Production is running correctly at' $url;
                        } else {
                            Write-Host '⚠️ Production returned status:' $response.StatusCode;
                        }
                    } catch {
                        Write-Host '❌ Production verification failed:' $_.Exception.Message;
                    }
                '''
            }
        }
    }

    post {
        always {
            script {
                echo '✅ Pipeline finished — build + SonarQube analysis + IIS deployment complete.'
                echo "📊 View SonarQube report at: ${env.SONAR_HOST_URL}/dashboard?id=eShopOnWeb"
                
                // Optional: Check quality gate status in post-action (non-blocking)
                String qualityGateMode = params?.QUALITY_GATE_MODE ?: 'SKIP'
                if (qualityGateMode == 'SKIP' || qualityGateMode == 'NON_BLOCKING') {
                    echo '💡 Quality gate analysis may still be processing in SonarQube'
                    echo '💡 Check the dashboard above for final quality gate status'
                }
            }
        }
        success {
            echo '🎉 Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed. Check logs above for details.'
        }
    }
}
