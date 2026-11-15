@echo off
rem Ouvre la fenetre de demonstration du labo de securite LLM (sans console PowerShell visible).
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0demo_llm.ps1"
