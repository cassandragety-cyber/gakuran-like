@echo off
chcp 65001 >nul
title Installation du bot
cd /d "%~dp0"
echo.
echo  ==========================================
echo     Installation du bot Discord
echo  ==========================================
echo.
where node >nul 2>nul
if errorlevel 1 (
  echo  [X] Node.js n'est pas installe.
  echo      Telecharge la version LTS sur https://nodejs.org puis relance ce fichier.
  start https://nodejs.org
  pause
  exit /b 1
)
for /f "tokens=*" %%v in ('node -v') do echo  Node.js %%v detecte.
echo.
echo  Installation des dependances (1 a 3 minutes)...
call npm install --omit=dev
if errorlevel 1 (
  echo  [X] L'installation a echoue. Lis le message ci-dessus.
  pause
  exit /b 1
)
if not exist ".env" (
  copy ".env.example" ".env" >nul
  echo.
  echo  Le fichier .env a ete cree : colle ton TOKEN et ton ID dedans.
  notepad ".env"
)
echo.
echo  [OK] Installation terminee. Lance DEMARRER.bat pour allumer le bot.
pause
