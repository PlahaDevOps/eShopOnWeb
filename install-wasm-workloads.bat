@echo off
REM Install WebAssembly Workloads for Jenkins Build Agent
REM Run this script as Administrator on the Jenkins agent

echo === Installing WebAssembly Workloads ===
echo.

echo Step 1: Installing wasm-tools...
dotnet workload install wasm-tools
if errorlevel 1 (
    echo ERROR: Failed to install wasm-tools
    exit /b 1
)
echo [OK] wasm-tools installed
echo.

echo Step 2: Installing wasm-tools-net8...
dotnet workload install wasm-tools-net8
if errorlevel 1 (
    echo WARNING: Failed to install wasm-tools-net8 (may not be available)
) else (
    echo [OK] wasm-tools-net8 installed
)
echo.

echo Step 3: Installing wasm-experimental (optional)...
dotnet workload install wasm-experimental
if errorlevel 1 (
    echo WARNING: Failed to install wasm-experimental (optional, continuing...)
) else (
    echo [OK] wasm-experimental installed
)
echo.

echo === Verifying Installation ===
echo.
dotnet workload list
echo.

echo === Installation Complete ===
echo.
echo Next steps:
echo 1. Restart Jenkins service (if needed)
echo 2. Run the pipeline again
echo 3. BlazorAdmin should now build successfully
echo.

pause

