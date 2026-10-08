@echo off
rem Starts the yoshida editor and render server on http://localhost:8080
rem (another port: start.bat 9000). Close this window to stop it.
cd /d "%~dp0"
set PORT=%1
if "%PORT%"=="" set PORT=8080
echo Open http://localhost:%PORT% in your browser.
start "" "http://localhost:%PORT%"
"bin\x86_64-windows\yoshida-server.exe" --host 127.0.0.1 --port %PORT% --web web
pause
