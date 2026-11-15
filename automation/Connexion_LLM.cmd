@echo off
rem Connexion d'un camarade au labo de securite LLM (cree ta cle, puis ouvre la demo).
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0connexion_llm.ps1"
