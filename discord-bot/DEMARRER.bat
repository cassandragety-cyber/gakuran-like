@echo off
chcp 65001 >nul
title Bot Discord
cd /d "%~dp0"
if not exist "node_modules" (
  echo  Les dependances ne sont pas installees : lance d'abord INSTALLER.bat
  pause
  exit /b 1
)
if not exist ".env" (
  copy ".env.example" ".env" >nul
  echo  Remplis le fichier .env (TOKEN et OWNER_IDS) puis relance.
  notepad ".env"
  pause
  exit /b 1
)
:boucle
echo.
echo  Demarrage du bot... (ferme cette fenetre pour l'eteindre)
node src/index.js
echo.
echo  Le bot s'est arrete. Redemarrage dans 5 secondes (Ctrl+C pour annuler)...
timeout /t 5 >nul
goto boucle
