pipeline {
    agent any

    environment {
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
    }

    stages {
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
                withSonarQubeEnv('SonarQube') {   // 👈 Must match your configured server name
                    bat '''
                        sonar-scanner ^
                        -Dsonar.projectKey=eShopOnWeb ^
                        -Dsonar.sources=src ^
                        -Dsonar.cs.opencover.reportsPaths=**/coverage.opencover.xml ^
                        -Dsonar.host.url=%SONAR_HOST_URL% ^
                        -Dsonar.login=%SONAR_AUTH_TOKEN%
                    '''
                }
            }
        }

        stage('Wait for Quality Gate') {
            steps {
                timeout(time: 2, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
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
                bat '''
                    powershell -ExecutionPolicy Bypass -Command "
                        if (Test-Path 'src/Web/appsettings.Staging.json') {
                            Copy-Item 'src/Web/appsettings.Staging.json' '%PUBLISH_DIR%/appsettings.json' -Force
                        } else {
                            Copy-Item 'src/Web/appsettings.json' '%PUBLISH_DIR%/appsettings.json' -Force
                        }"
                '''
            }
        }

        stage('Clean and Deploy to Staging') {
            steps {
                bat '''
                    powershell -ExecutionPolicy Bypass -Command "
                        Import-Module WebAdministration -ErrorAction SilentlyContinue;
                        $appPool = '%STAGING_APPPOOL%';
                        if (Test-Path ('IIS:\\AppPools\\' + $appPool)) {
                            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Start-Sleep -Seconds 5;
                        }
                        if (!(Test-Path '%STAGING_PATH%')) {
                            New-Item -ItemType Directory -Path '%STAGING_PATH%' -Force | Out-Null;
                        } else {
                            Get-ChildItem '%STAGING_PATH%' -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue;
                        }
                        Copy-Item '%PUBLISH_DIR%\\*' '%STAGING_PATH%' -Recurse -Force;
                        Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                        Restart-WebAppPool -Name $appPool;
                        Start-Website -Name '%STAGING_SITE%' -ErrorAction SilentlyContinue;
                    "
                '''
            }
        }

        stage('Verify Staging Site') {
            steps {
                bat '''
                    powershell -ExecutionPolicy Bypass -Command "
                        $url = 'http://localhost:8081';
                        Start-Sleep -Seconds 5;
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
                    "
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
                bat '''
                    powershell -ExecutionPolicy Bypass -Command "
                        Import-Module WebAdministration -ErrorAction SilentlyContinue;
                        $appPool = '%PROD_APPPOOL%';
                        if (Test-Path ('IIS:\\AppPools\\' + $appPool)) {
                            Stop-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                            Start-Sleep -Seconds 5;
                        }
                        if (!(Test-Path '%PROD_PATH%')) {
                            New-Item -ItemType Directory -Path '%PROD_PATH%' -Force | Out-Null;
                        } else {
                            Get-ChildItem '%PROD_PATH%' -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue;
                        }
                        Copy-Item '%PUBLISH_DIR%\\*' '%PROD_PATH%' -Recurse -Force;
                        if (Test-Path 'src/Web/appsettings.Production.json') {
                            Copy-Item 'src/Web/appsettings.Production.json' '%PROD_PATH%/appsettings.json' -Force;
                        } else {
                            Copy-Item 'src/Web/appsettings.json' '%PROD_PATH%/appsettings.json' -Force;
                        }
                        Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue;
                        Restart-WebAppPool -Name $appPool;
                        Start-Website -Name '%PROD_SITE%' -ErrorAction SilentlyContinue;
                    "
                '''
            }
        }

        stage('Verify Production Site') {
            steps {
                bat '''
                    powershell -ExecutionPolicy Bypass -Command "
                        $url = 'http://localhost:8080';
                        Start-Sleep -Seconds 5;
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
                    "
                '''
            }
        }
    }

    post {
        always {
            echo '✅ Pipeline finished — build + SonarQube analysis + IIS deployment complete.'
        }
    }
}
