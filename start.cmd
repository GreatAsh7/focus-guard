@echo off
cd /d "%~dp0"
start "" http://localhost:4747
node --env-file-if-exists=.env server.js
