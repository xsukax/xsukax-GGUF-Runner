@echo off
if exist "gguf-config.json" del /f /q "gguf-config.json"

(
echo {
echo   "Temperature": 0.8,
echo   "ContextSize": 4096,
echo   "MaxTokens": 2048,
echo   "GpuLayers": -1,
echo   "ServerPort": 8080,
echo   "Threads": 0,
echo   "LastModel": ""
echo }
) > gguf-config.json

powershell -ExecutionPolicy Bypass -File "%~dp0xsukax-gguf-runner.ps1"
pause