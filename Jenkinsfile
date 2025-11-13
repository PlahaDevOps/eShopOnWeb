pipeline {
    agent { label 'windows' }

    environment {
        DOTNET_ROOT = "C:\\Program Files\\dotnet"
        PATH = "C:\\Users\\admin\\.dotnet\\tools;C:\\SonarScanner;${env.PATH}"

        PROJECT = "eShopOnWeb"
        SOLUTION = "eShopOnWeb.sln"

        PUBLISH_DIR = "${WORKSPACE}\\publish"

        STAGING_DIR = "C:\\inetpub\\eShopOnWeb-staging"
        STAGING_POOL = "eShopOnWeb-staging"

        PROD_DIR = "C:\\inetpub\\eShopOnWeb"
        PROD_POOL = "eShopOnWeb"
    }

    stages {

        stage('Workspace Cleanup') {
            steps {
                powershell '''
                    Write-Host "Cleaning workspace..."
                    Remove-Item -Recurse -Force "$env:WORKSPACE\\publish" -ErrorAction SilentlyContinue
                '''
            }
        }

        stage('Diagnostics') {
            steps {
                powershell '''
                    Write-Host "Dotnet Version:"
                    dotnet --version

                    Write-Host "SonarScanner:"
                    SonarScanner.MSBuild.exe /version
                '''
            }
        }

        stage('Restore Packages') {
            steps {
                powershell '''
                    dotnet restore "$env:SOLUTION"
                '''
            }
        }

        stage('Build Project') {
            steps {
                powershell '''
                    dotnet build "$env:SOLUTION" -c Release --no-restore
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                powershell '''
                    dotnet test "$env:SOLUTION" --no-build
                '''
            }
        }

        stage('SonarQube Analysis') {
            when {
                expression { return env.SONAR_TOKEN?.trim() }
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    powershell '''
                        SonarScanner.MSBuild.exe begin /k:"eShopOnWeb" /d:sonar.host.url=http://localhost:9000 /d:sonar.login=$env:SONAR_TOKEN
                        dotnet build "$env:SOLUTION" -c Release
                        SonarScanner.MSBuild.exe end /d:sonar.login=$env:SONAR_TOKEN
                    '''
                }
            }
        }

        stage('Publish Project') {
            steps {
                powershell '''
                    dotnet publish "src/Web/Web.csproj" -c Release -o "$env:PUBLISH_DIR"
                '''
            }
        }

        stage('Configure Staging Environment') {
            steps {
                powershell '''
                    if (Test-Path "src/Web/appsettings.Staging.json") {
                        Copy-Item "src/Web/appsettings.Staging.json" "$env:PUBLISH_DIR\\appsettings.json" -Force
                        Write-Host "Staging config applied."
                    }
                '''
            }
        }

        stage('Clean and Deploy to Staging') {
            steps {
                powershell '''
                    $publish = "$env:PUBLISH_DIR"
                    $target = "$env:STAGING_DIR"
                    $pool   = "$env:STAGING_POOL"
                    $identity = "IIS APPPOOL\\$pool"

                    if (!(Test-Path $publish)) {
                        Write-Host "ERROR: Publish directory not found: $publish"
                        exit 1
                    }

                    # Create app pool if not exists
                    if (-not (Get-WebAppPoolState -Name $pool -ErrorAction SilentlyContinue)) {
                        New-WebAppPool -Name $pool
                    }

                    # Create site directory
                    if (!(Test-Path $target)) {
                        New-Item -ItemType Directory -Path $target -Force | Out-Null
                    } else {
                        Get-ChildItem $target -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    # Copy files
                    Copy-Item "$publish\\*" $target -Recurse -Force

                    # FIXED: correct identity formatting
                    icacls $target /grant "${identity}:(OI)(CI)(M)" /T /Q

                    # Create website if missing
                    if (-not (Test-Path IIS:\\Sites\\eShopOnWeb-staging)) {
                        New-Website -Name "eShopOnWeb-staging" -Port 8081 -PhysicalPath $target -ApplicationPool $pool
                    }
                '''
            }
        }

        stage('Verify Staging Site') {
            steps {
                powershell '''
                    try {
                        $response = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing -TimeoutSec 10
                        if ($response.StatusCode -ne 200) { throw "Non-200 response" }
                        Write-Host "Staging site is running."
                    } catch {
                        Write-Host "ERROR: Staging site check failed."
                        exit 1
                    }
                '''
            }
        }

        stage('Manual Approval for Production') {
            steps {
                input message: "Deploy to PRODUCTION?", ok: "Deploy"
            }
        }

        stage('Deploy to Production') {
            steps {
                powershell '''
                    $publish = "$env:PUBLISH_DIR"
                    $target = "$env:PROD_DIR"
                    $pool   = "$env:PROD_POOL"
                    $identity = "IIS APPPOOL\\$pool"

                    if (!(Test-Path $publish)) {
                        Write-Host "ERROR: Publish directory missing!"
                        exit 1
                    }

                    if (-not (Get-WebAppPoolState -Name $pool -ErrorAction SilentlyContinue)) {
                        New-WebAppPool -Name $pool
                    }

                    if (!(Test-Path $target)) {
                        New-Item -ItemType Directory -Path $target -Force | Out-Null
                    } else {
                        Get-ChildItem $target -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    Copy-Item "$publish\\*" $target -Recurse -Force

                    icacls $target /grant "${identity}:(OI)(CI)(M)" /T /Q

                    if (-not (Test-Path IIS:\\Sites\\eShopOnWeb)) {
                        New-Website -Name "eShopOnWeb" -Port 8080 -PhysicalPath $target -ApplicationPool $pool
                    }
                '''
            }
        }

        stage('Verify Production Site') {
            steps {
                powershell '''
                    try {
                        $response = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing -TimeoutSec 10
                        if ($response.StatusCode -ne 200) { throw "Non-200 response" }
                        Write-Host "Production site is running."
                    } catch {
                        Write-Host "ERROR: Production site check failed."
                        exit 1
                    }
                '''
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully."
        }
        failure {
            echo "Pipeline failed. Check logs."
        }
    }
}
