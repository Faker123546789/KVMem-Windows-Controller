@echo off
setlocal
set "ROOT=%~dp0"
if not exist "%ROOT%runtime\bin\llama-kvmem-server.exe" (
    echo First launch: verifying and unpacking the portable runtimes.
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Bootstrap-Portable.ps1" -Root "%ROOT%"
    if errorlevel 1 (
        echo.
        pause
        exit /b 1
    )
)
wscript.exe "%ROOT%Open-KVMem-Controller.vbs"
