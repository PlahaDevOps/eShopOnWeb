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
                checkout scm
            }
        }

        stage('Restore') {
            steps {
                bat "dotnet restore %SOLUTION%"
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

                    icacls $sitePath /grant "IIS_IUSRS:(OI)(CI)(M)" /T /Q

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
                    Start-Sleep -Seconds 10
                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
                        if ($response.StatusCode -eq 200) {
                            Write-Host "Staging is running correctly at $url"
                        } else {
                            Write-Host "Staging returned status code $($response.StatusCode)"
                        }
                    } catch {
                        Write-Host "Staging verification failed: $($_.Exception.Message)"
                    }
                '''
            }
        }

        stage('Manual Approval for Production') {
            steps {
                input message: 'Promote build to Production?', ok: 'Deploy'
            }
        }

        stage('Deploy to Production') {
            steps {
                powershell '''
                    Import-Module WebAdministration -ErrorAction SilentlyContinue

                    $publishPath = "$env:WORKSPACE\\$env:PUBLISH_DIR"
                    $sitePath    = $env:PROD_PATH
                    $appPool     = $env:PROD_APPPOOL
                    $siteName    = $env:PROD_SITE

                    Write-Host "Publish path: $publishPath"
                    Write-Host "Production path: $sitePath"

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
                    Write-Host "Files copied to production path."

                    $prodConfig = "src/Web/appsettings.Production.json"
                    if (Test-Path $prodConfig) {
                        Copy-Item $prodConfig "$sitePath\\appsettings.json" -Force
                        Write-Host "Production config applied."
                    } else {
                        Copy-Item "src/Web/appsettings.json" "$sitePath\\appsettings.json" -Force
                        Write-Host "Production config not found. Using default appsettings.json."
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
                        New-Website -Name $siteName -PhysicalPath $sitePath -ApplicationPool $appPool -Port 8080 -Force | Out-Null
                    }

                    icacls $sitePath /grant "IIS_IUSRS:(OI)(CI)(M)" /T /Q

                    Start-WebAppPool -Name $appPool -ErrorAction SilentlyContinue
                    Restart-WebAppPool -Name $appPool
                    Start-Website -Name $siteName -ErrorAction SilentlyContinue

                    Write-Host "Production deployment completed."
                '''
            }
        }

        stage('Verify Production') {
            steps {
                powershell '''
                    $url = "http://localhost:8080"
                    Start-Sleep -Seconds 10
                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
                        if ($response.StatusCode -eq 200) {
                            Write-Host "Production is running correctly at $url"
                        } else {
                            Write-Host "Production returned status code $($response.StatusCode)"
                        }
                    } catch {
                        Write-Host "Production verification failed: $($_.Exception.Message)"
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
