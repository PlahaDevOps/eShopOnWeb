# Install WebAssembly Workloads for Jenkins Build Agent
# Run this script as Administrator on the Jenkins agent

Write-Host "=== Installing WebAssembly Workloads ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator. Some operations may fail." -ForegroundColor Yellow
    Write-Host "Please run this script as Administrator for best results." -ForegroundColor Yellow
    Write-Host ""
}

# Step 1: Install wasm-tools
Write-Host "Step 1: Installing wasm-tools..." -ForegroundColor Yellow
dotnet workload install wasm-tools
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install wasm-tools" -ForegroundColor Red
    exit 1
}
Write-Host "✓ wasm-tools installed" -ForegroundColor Green
Write-Host ""

# Step 2: Install wasm-tools-net8
Write-Host "Step 2: Installing wasm-tools-net8..." -ForegroundColor Yellow
dotnet workload install wasm-tools-net8
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Failed to install wasm-tools-net8 (may not be available for your SDK version)" -ForegroundColor Yellow
} else {
    Write-Host "✓ wasm-tools-net8 installed" -ForegroundColor Green
}
Write-Host ""

# Step 3: Install wasm-experimental (optional)
Write-Host "Step 3: Installing wasm-experimental (optional)..." -ForegroundColor Yellow
dotnet workload install wasm-experimental
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Failed to install wasm-experimental (optional, continuing...)" -ForegroundColor Yellow
} else {
    Write-Host "✓ wasm-experimental installed" -ForegroundColor Green
}
Write-Host ""

# Step 4: Verify installation
Write-Host "=== Verifying Installation ===" -ForegroundColor Cyan
Write-Host ""
$workloads = dotnet workload list
Write-Host $workloads

$hasWasmTools = $workloads -match "wasm-tools"
$hasWasmToolsNet8 = $workloads -match "wasm-tools-net8"

Write-Host ""
if ($hasWasmTools) {
    Write-Host "✓ wasm-tools is installed" -ForegroundColor Green
} else {
    Write-Host "✗ wasm-tools is NOT installed" -ForegroundColor Red
}

if ($hasWasmToolsNet8) {
    Write-Host "✓ wasm-tools-net8 is installed" -ForegroundColor Green
} else {
    Write-Host "⚠ wasm-tools-net8 is NOT installed (may not be required)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart Jenkins service (if needed)" -ForegroundColor White
Write-Host "2. Run the pipeline again" -ForegroundColor White
Write-Host "3. BlazorAdmin should now build successfully" -ForegroundColor White

