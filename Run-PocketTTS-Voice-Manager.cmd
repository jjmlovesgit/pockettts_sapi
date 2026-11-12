@echo off
setlocal
set "INSTALL_ROOT=%ProgramFiles%\PocketTTS"
if not exist "%INSTALL_ROOT%\pocket-tts.exe" (
  echo Pocket TTS was not found at "%INSTALL_ROOT%".
  echo Edit INSTALL_ROOT in this launcher if it is installed in another folder.
  pause
  exit /b 1
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\VoiceManager.ps1" -InstallRoot "%INSTALL_ROOT%"
endlocal
