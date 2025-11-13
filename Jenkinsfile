pipeline {
    agent { label 'windows' }

    environment {
        DOTNET_ROOT = "C:\\Program Files\\dotnet"
        PATH = "C:\\Users\\admin\\.dotnet\\tools;C:\\SonarScanner;${env.PATH}"
        SOLUTION = "eShopOnWeb.sln"
        PROJECT = "src\\Web\\Web.csproj"
        PUBLISH_DIR = "${WORKSPACE}\\publish"
        STAGING_DIR = "C:\\inetpub\\eShopOnWeb-staging"
        STAGING_POOL = "eShopOnWeb-staging"
        SONAR_HOST = "http://localhost:9000"
        SONAR_PROJECT = "eShopOnWeb"
    }

    stages {

        stage('Workspace Cleanup') {
            steps {
                powershell '''
                    Write-Host "Cleaning workspace..."
                    Get-ChildItem -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                '''
            }
        }

        stage('Diagnostics') {
            steps {
                powershell '''
                    Write-Host "Workspace: $env:WORKSPACE"
                    Write-Host ".NET Version:"
                    dotnet --version
                '''
            }
        }

        stage('Check Tools') {
            steps {
                powershell '''
                    Write-Host "Checking SonarScanner..."
                    where.exe SonarScanner.MSBuild.exe
                '''
            }
        }

        stage('Checkout Source Code') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/PlahaDevOps/eShopOnWeb.git',
                    credentialsId: 'git-pat'
            }
        }

        stage('Restore Packages') {
            steps {
                powershell "dotnet restore ${env.SOLUTION}"
            }
        }

        stage('Build Project') {
            steps {
                powershell "dotnet build ${env.SOLUTION} -c Release --no-restore"
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    powershell """
                        SonarScanner.MSBuild.exe begin /k:${env.SONAR_PROJECT} /d:sonar.host.url=${env.SONAR_HOST} /d:sonar.login=$env:SONAR_TOKEN
                        dotnet build ${env.SOLUTION} -c Release
                        SonarScanner.MSBuild.exe end /d:sonar.login=$env:SONAR_TOKEN
                    """
                }
            }
        }

        stage('Publish Project') {
            steps {
                powershell """
                    if (Test-Path '${env:PUBLISH_DIR}') {
                        Remove-Item '${env:PUBLISH_DIR}' -Recurse -Force
                    }
                    dotnet publish ${env.PROJECT} -c Release -o ${env:PUBLISH_DIR}
                """
            }
        }

        stage('Configure Staging Environment') {
            steps {
                powershell '''
                    if (Test-Path "src/Web/appsettings.Staging.json") {
                        Copy-Item "src/Web/appsettings.Staging.json" "${env:PUBLISH_DIR}\\appsettings.json" -Force
                        Write-Host "Staging config applied."
                    }
                '''
            }
        }

        stage('Clean and Deploy to Staging') {
            steps {
                powershell '''
                    $publish = "${env:PUBLISH_DIR}"
                    $sitePath = "${env:STAGING_DIR}"
                    $pool = "${env:STAGING_POOL}"
                    $identity = "IIS APPPOOL\\${pool}"

                    # Validate publish directory
                    if (!(Test-Path $publish)) {
                        Write-Host "ERROR: Publish directory does not exist: $publish"
                        exit 1
                    }

                    # Create app pool
                    if (-not (Get-WebAppPoolState -Name $pool -ErrorAction SilentlyContinue)) {
                        New-WebAppPool -Name $pool
                        Write-Host "Created app pool: $pool"
                    }

                    # Create website directory
                    if (!(Test-Path $sitePath)) {
                        New-Item -ItemType Directory -Path $sitePath -Force
                    } else {
                        Get-ChildItem $sitePath -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                    }

                    # Copy files
                    Copy-Item "$publish\\*" $sitePath -Recurse -Force

                    # Set file permissions
                    icacls $sitePath /grant "${identity}:(OI)(CI)(M)" /T /Q

                    # Create website if missing
                    if (-not (Test-Path IIS:\\Sites\\eShopOnWeb-staging)) {
                        New-Website -Name "eShopOnWeb-staging" `
                                    -Port 8081 `
                                    -PhysicalPath $sitePath `
                                    -ApplicationPool $pool
                    }
                '''
            }
        }
    }

    post {
        always {
            echo "Pipeline finished."
            echo "SonarQube: http://localhost:9000/dashboard?id=eShopOnWeb"
        }
        failure {
            echo "Pipeline failed."
        }
    }
}