@echo off
rem Starts the yoshida website, editor and render server on http://localhost:8080
rem (another port: start.bat 9000). The editor is at /editor/, the docs at
rem /docs/. Close this window to stop it.
cd /d "%~dp0"
set PORT=%1
if "%PORT%"=="" set PORT=8080
echo Open http://localhost:%PORT%/editor/ in your browser (docs: http://localhost:%PORT%/docs/).
start "" "http://localhost:%PORT%/editor/"
"bin\x86_64-windows\yoshida-server.exe" --host 127.0.0.1 --port %PORT% --web web
pause
