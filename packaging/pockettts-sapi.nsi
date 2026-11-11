Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!define PRODUCT "Pocket TTS for Windows"
!define ROOT "${__FILEDIR__}\.."
!define STAGE "${ROOT}\build\package"
!define MUI_ICON "${ROOT}\assets\pockettts-pocket.ico"
!define MUI_UNICON "${ROOT}\assets\pockettts-pocket.ico"
!ifndef OUT_NAME
  !define OUT_NAME "PocketTTS-SAPI-Setup.exe"
!endif
!define CLSID "{52586884-B3DC-46C5-A298-A49606CC5421}"
!define TOKEN "PocketTTSDefaultAlba"
!define MEDIUM_MODEL "english_7m_refl_2026-10"
Var PackFrench
Var PackGerman
Var PackItalian
Var PackSpanish
Var PackPortuguese
Var PackDutch
Var InstallStartTick
Var PackStartTick
Var BaseStartTick
Var PackExitCode

!macro RecordTiming Phase Language StartTick
  System::Call 'kernel32::GetTickCount() i .r0'
  IntOp $0 $0 - ${StartTick}
  FileOpen $1 "$TEMP\PocketTTS-Setup-Timings.csv" a
  FileSeek $1 0 END
  FileWrite $1 "${Phase},${Language},$0$\r$\n"
  FileClose $1
  DetailPrint "Timing ${Phase} ${Language}: $0 ms"
!macroend

!macro PreparePack Flag Language Display
  ${If} ${Flag} == 1
    DetailPrint "Verifying ${Display} native model, tokenizer, and demo voice (about 225 MB)"
    System::Call 'kernel32::GetTickCount() i .r0'
    StrCpy $PackStartTick $0
    nsExec::ExecToLog '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\install-language-pack.ps1" -Language ${Language} -InstallRoot "$INSTDIR" -ManifestPath "$PLUGINSDIR\language-packs.json" -DownloadCache "$TEMP\PocketTTS-PackDownloads" -PrepareOnly'
    Pop $0
    StrCpy $PackExitCode $0
    !insertmacro RecordTiming prepare ${Language} $PackStartTick
    ${If} $PackExitCode != 0
      BringToFront
      MessageBox MB_ICONSTOP|MB_TOPMOST|MB_SETFOREGROUND "${Display} pack download or verification failed. See Setup details. Access to Kyutai's official Hugging Face model repository may require HF_TOKEN. Setup has not changed the installed voice."
      Abort
    ${EndIf}
  ${EndIf}
!macroend

!macro ApplyPack Flag Language Display
  ${If} ${Flag} == 1
    DetailPrint "Installing ${Display} native voice"
    System::Call 'kernel32::GetTickCount() i .r0'
    StrCpy $PackStartTick $0
    nsExec::ExecToLog '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\tools\install-language-pack.ps1" -Language ${Language} -InstallRoot "$INSTDIR" -ManifestPath "$INSTDIR\tools\language-packs.json" -DownloadCache "$TEMP\PocketTTS-PackDownloads"'
    Pop $0
    StrCpy $PackExitCode $0
    !insertmacro RecordTiming install ${Language} $PackStartTick
    ${If} $PackExitCode != 0
      BringToFront
      MessageBox MB_ICONSTOP|MB_TOPMOST|MB_SETFOREGROUND "${Display} pack installation failed. The base voice remains installed; see the Setup details for the selected pack."
      Abort
    ${EndIf}
  ${EndIf}
!macroend

!macro RemovePackToken Language
  ReadRegStr $1 HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\PocketTTS.Locale.${Language}" "CLSID"
  ${If} $1 == "${CLSID}"
    DeleteRegKey HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\PocketTTS.Locale.${Language}"
  ${EndIf}
  ReadRegStr $1 HKLM "Software\Microsoft\Speech\Voices\Tokens\PocketTTS.Locale.${Language}" "CLSID"
  ${If} $1 == "${CLSID}"
    DeleteRegKey HKLM "Software\Microsoft\Speech\Voices\Tokens\PocketTTS.Locale.${Language}"
  ${EndIf}
!macroend

Name "${PRODUCT} (local evaluation)"
OutFile "${ROOT}\build\${OUT_NAME}"
InstallDir "$PROGRAMFILES64\PocketTTS"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUnInstDetails show

!insertmacro MUI_PAGE_LICENSE "${STAGE}\LICENSES\NOTICE.txt"
!define MUI_COMPONENTSPAGE_SMALLDESC
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "English: Alba (6.9M, included)" SEC_ENGLISH
  SectionIn RO
  ; The SAPI COM server and maintenance scripts are machine-wide/elevated.
  ; Keep them under the inherited Program Files ACL, even if /D overrides InstallDir.
  StrCmp $INSTDIR "$PROGRAMFILES64\PocketTTS" install_root_ok
  BringToFront
  MessageBox MB_ICONSTOP|MB_TOPMOST|MB_SETFOREGROUND "Pocket TTS must be installed to $PROGRAMFILES64\PocketTTS so Windows can safely load its machine-wide SAPI engine."
  Abort
install_root_ok:
  System::Call 'kernel32::GetTickCount() i .r0'
  StrCpy $InstallStartTick $0
  FileOpen $1 "$TEMP\PocketTTS-Setup-Timings.csv" w
  FileWrite $1 "phase,language,milliseconds$\r$\n"
  FileClose $1
SectionEnd

Section /o "French: Estelle (about 227 MB download)" SEC_FRENCH
  AddSize 221531
  StrCpy $PackFrench 1
SectionEnd
Section /o "German: Juergen (about 225 MB download)" SEC_GERMAN
  AddSize 220090
  StrCpy $PackGerman 1
SectionEnd
Section /o "Italian: Giovanni (about 223 MB download)" SEC_ITALIAN
  AddSize 218171
  StrCpy $PackItalian 1
SectionEnd
Section /o "Spanish: Lola (about 225 MB download)" SEC_SPANISH
  AddSize 219467
  StrCpy $PackSpanish 1
SectionEnd
Section /o "Brazilian Portuguese: Rafael (about 226 MB download)" SEC_PORTUGUESE
  AddSize 220235
  StrCpy $PackPortuguese 1
SectionEnd
Section /o "Dutch: Daan (about 223 MB download)" SEC_DUTCH
  AddSize 217929
  StrCpy $PackDutch 1
SectionEnd

Section "-Download selected language packs" SEC_DOWNLOAD_PACKS
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File "${STAGE}\tools\install-language-pack.ps1"
  File "${STAGE}\tools\language-packs.json"
  !insertmacro PreparePack $PackFrench french French
  !insertmacro PreparePack $PackGerman german German
  !insertmacro PreparePack $PackItalian italian Italian
  !insertmacro PreparePack $PackSpanish spanish Spanish
  !insertmacro PreparePack $PackPortuguese portuguese "Brazilian Portuguese"
  !insertmacro PreparePack $PackDutch dutch Dutch
SectionEnd

Section "-Release files for upgrade" SEC_PREPARE
  DetailPrint "Releasing Pocket TTS files used by Windows apps"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File "${STAGE}\tools\prepare-upgrade.ps1"
  SetOutPath "$WINDIR"
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\prepare-upgrade.ps1" -InstallRoot "$INSTDIR" -LogPath "$TEMP\PocketTTS-Setup-LockFix.log"' $0
  ${If} $0 != 0
    BringToFront
    MessageBox MB_ICONSTOP|MB_TOPMOST|MB_SETFOREGROUND "Setup could not release the Pocket TTS files. Details are in $TEMP\PocketTTS-Setup-LockFix.log. Setup will stop before replacing any files."
    Abort
  ${EndIf}
SectionEnd

Section "-Pocket TTS SAPI base" SEC_MAIN
  SectionIn RO
  System::Call 'kernel32::GetTickCount() i .r0'
  StrCpy $BaseStartTick $0
  SetRegView 64
  ReadRegStr $1 HKLM "Software\Microsoft\Speech\Voices\Tokens\PocketTTSDefaultButter" "CLSID"
  ${If} $1 == "${CLSID}"
    DeleteRegKey HKLM "Software\Microsoft\Speech\Voices\Tokens\PocketTTSDefaultButter"
  ${EndIf}
  ReadRegStr $1 HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\PocketTTSDefaultButter" "CLSID"
  ${If} $1 == "${CLSID}"
    DeleteRegKey HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\PocketTTSDefaultButter"
  ${EndIf}
  Delete "$INSTDIR\voices\Butter*"
  SetOutPath "$INSTDIR"
  File "${STAGE}\pocket-tts.exe"
  File "${STAGE}\pocket_sapi.dll"
  File "${STAGE}\pockettts-pocket.ico"
  Delete "$INSTDIR\models\hf\models--kyutai--pocket-tts\snapshots\db04f0e653473e5c7333c69686ac92b7460b0c1d\languages\english_2m_2026-10\model.safetensors"
  Delete "$INSTDIR\models\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\08ffc58775e62aad9409511b9591c9af626270f3\languages\english_2m_2026-10\tokenizer.model"
  SetOutPath "$INSTDIR\models\hf\models--kyutai--pocket-tts\snapshots\db04f0e653473e5c7333c69686ac92b7460b0c1d\languages\${MEDIUM_MODEL}"
  File "${STAGE}\models-medium\model.safetensors"
  SetOutPath "$INSTDIR\models\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\08ffc58775e62aad9409511b9591c9af626270f3\languages\${MEDIUM_MODEL}"
  File "${STAGE}\models-common\tokenizer.model"
  SetOutPath "$INSTDIR\voices"
  File /oname=Alba.safetensors "${STAGE}\voices\Alba-medium.safetensors"
  File /oname=Alba-slow.safetensors "${STAGE}\voices\Alba-medium-slow.safetensors"
  File /oname=Alba-fast.safetensors "${STAGE}\voices\Alba-medium-fast.safetensors"
  SetOutPath "$INSTDIR\tools"
  File "${STAGE}\tools\VoiceManager.ps1"
  File "${STAGE}\tools\remove-user-voices.ps1"
  File "${STAGE}\tools\stop-worker.ps1"
  File "${STAGE}\tools\machine-voice-token.ps1"
  File "${STAGE}\tools\install-language-pack.ps1"
  File "${STAGE}\tools\language-packs.json"
  File "${STAGE}\tools\pocket_prompt_rate.exe"
  File "${STAGE}\tools\pocket_soundtouch.dll"
  SetOutPath "$INSTDIR\LICENSES"
  File "${STAGE}\LICENSES\NOTICE.txt"
  File "${STAGE}\LICENSES\pocket-tts-MIT.txt"
  File "${STAGE}\LICENSES\CC-BY-4.0.txt"
  File "${STAGE}\LICENSES\model-CC-BY-4.0.txt"
  File "${STAGE}\LICENSES\Alba-CC-BY-4.0.txt"
  File "${STAGE}\LICENSES\SoundTouch-LGPL-2.1.txt"
  File "${STAGE}\LICENSES\SoundTouch-2.3.3-source.tar.gz"

  SetOutPath "$INSTDIR\voices"
  File "${STAGE}\voices\Alba-slow.wav"
  File "${STAGE}\voices\Alba-normal.wav"
  File "${STAGE}\voices\Alba-fast.wav"

  WriteRegStr HKLM "Software\PocketTTS" "InstallRoot" "$INSTDIR"
  WriteRegStr HKLM "Software\PocketTTS" "ModelLanguage" "${MEDIUM_MODEL}"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "" "Alba (Pocket TTS)"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "CLSID" "${CLSID}"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "VoiceStatePath" "$INSTDIR\voices\Alba.safetensors"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "ModelLanguage" "${MEDIUM_MODEL}"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "VoicePromptSlowPath" "$INSTDIR\voices\Alba-slow.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "VoicePromptNormalPath" "$INSTDIR\voices\Alba-normal.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}" "VoicePromptFastPath" "$INSTDIR\voices\Alba-fast.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "Name" "Alba (Pocket TTS)"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "Language" "409"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "Gender" "Unknown"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "Age" "Adult"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "Vendor" "Pocket TTS"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "VoiceStatePath" "$INSTDIR\voices\Alba.safetensors"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "VoicePromptSlowPath" "$INSTDIR\voices\Alba-slow.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "VoicePromptNormalPath" "$INSTDIR\voices\Alba-normal.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}\Attributes" "VoicePromptFastPath" "$INSTDIR\voices\Alba-fast.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "" "Alba (Pocket TTS)"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "CLSID" "${CLSID}"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "VoiceName" "${TOKEN}"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "VoiceStatePath" "$INSTDIR\voices\Alba.safetensors"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "ModelLanguage" "${MEDIUM_MODEL}"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "VoicePromptSlowPath" "$INSTDIR\voices\Alba-slow.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "VoicePromptNormalPath" "$INSTDIR\voices\Alba-normal.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "VoicePromptFastPath" "$INSTDIR\voices\Alba-fast.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "Name" "Alba (Pocket TTS)"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "VoiceName" "Alba (Pocket TTS)"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "Language" "0409"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "Gender" "Unknown"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "Age" "Adult"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "Vendor" "Pocket TTS"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "VoiceId" "${TOKEN}"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "VoiceStatePath" "$INSTDIR\voices\Alba.safetensors"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "VoicePromptSlowPath" "$INSTDIR\voices\Alba-slow.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "VoicePromptNormalPath" "$INSTDIR\voices\Alba-normal.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "VoicePromptFastPath" "$INSTDIR\voices\Alba-fast.wav"
  WriteRegStr HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}\Attributes" "Rate" "1.0"
  WriteRegStr HKLM "Software\Classes\CLSID\${CLSID}" "" "Pocket TTS SAPI Engine"
  WriteRegStr HKLM "Software\Classes\CLSID\${CLSID}\InprocServer32" "" "$INSTDIR\pocket_sapi.dll"
  WriteRegStr HKLM "Software\Classes\CLSID\${CLSID}\InprocServer32" "ThreadingModel" "Both"
  WriteRegStr HKLM "Software\Classes\CLSID\${CLSID}\ProgID" "" "PocketTTS.SapiEngine"
  WriteRegStr HKLM "Software\Classes\PocketTTS.SapiEngine\CLSID" "" "${CLSID}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\PocketTTS-SAPI" "DisplayName" "${PRODUCT} (local evaluation)"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\PocketTTS-SAPI" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Pocket TTS"
  CreateShortcut "$SMPROGRAMS\Pocket TTS\Voice Manager.lnk" "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" '-NoProfile -STA -ExecutionPolicy Bypass -File "$INSTDIR\tools\VoiceManager.ps1" -InstallRoot "$INSTDIR"' "$INSTDIR\pockettts-pocket.ico" 0
  !insertmacro RecordTiming install english $BaseStartTick
SectionEnd

Section "-Install selected language packs" SEC_APPLY_PACKS
  !insertmacro ApplyPack $PackFrench french French
  !insertmacro ApplyPack $PackGerman german German
  !insertmacro ApplyPack $PackItalian italian Italian
  !insertmacro ApplyPack $PackSpanish spanish Spanish
  !insertmacro ApplyPack $PackPortuguese portuguese "Brazilian Portuguese"
  !insertmacro ApplyPack $PackDutch dutch Dutch
  !insertmacro RecordTiming total all $InstallStartTick
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_ENGLISH} "Required English 6.9M ReFL model, Alba voice, SAPI engine, and Voice Manager. Included with Setup."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_FRENCH} "Optional native French model and Estelle demo voice. Downloads about 227 MB."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_GERMAN} "Optional native German model and Juergen demo voice. Downloads about 225 MB."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_ITALIAN} "Optional native Italian model and Giovanni demo voice. Downloads about 223 MB."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_SPANISH} "Optional native Spanish model and Lola demo voice. Downloads about 225 MB."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_PORTUGUESE} "Optional native Brazilian Portuguese model and Rafael demo voice. Downloads about 226 MB."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_DUTCH} "Optional native Dutch model and Daan demo voice. Downloads about 223 MB."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetRegView 64
  ; Older builds allowed user-writable install paths. Never elevate scripts from one.
  StrCmp $INSTDIR "$PROGRAMFILES64\PocketTTS" uninstall_root_safe
  DetailPrint "Skipping install-folder maintenance scripts because this is not the protected Pocket TTS location."
  Goto uninstall_scripts_done
uninstall_root_safe:
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\tools\stop-worker.ps1" -InstallRoot "$INSTDIR"'
uninstall_scripts_done:
  ReadRegStr $0 HKLM "Software\Classes\CLSID\${CLSID}\InprocServer32" ""
  ${If} $0 == "$INSTDIR\pocket_sapi.dll"
    !insertmacro RemovePackToken french
    !insertmacro RemovePackToken german
    !insertmacro RemovePackToken italian
    !insertmacro RemovePackToken spanish
    !insertmacro RemovePackToken portuguese
    !insertmacro RemovePackToken dutch
    ReadRegStr $1 HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}" "CLSID"
    ${If} $1 == "${CLSID}"
      DeleteRegKey HKLM "Software\Microsoft\Speech_OneCore\Voices\Tokens\${TOKEN}"
    ${EndIf}
    DeleteRegKey HKLM "Software\Microsoft\Speech\Voices\Tokens\${TOKEN}"
    DeleteRegKey HKLM "Software\Classes\CLSID\${CLSID}"
    DeleteRegKey HKLM "Software\Classes\PocketTTS.SapiEngine"
  ${EndIf}
  ReadRegStr $0 HKLM "Software\PocketTTS" "InstallRoot"
  ${If} $0 == "$INSTDIR"
    DeleteRegValue HKLM "Software\PocketTTS" "InstallRoot"
    DeleteRegValue HKLM "Software\PocketTTS" "ModelLanguage"
    DeleteRegKey /ifempty HKLM "Software\PocketTTS"
  ${EndIf}
  StrCmp $INSTDIR "$PROGRAMFILES64\PocketTTS" uninstall_remove_voices_safe
  Goto uninstall_remove_voices_done
uninstall_remove_voices_safe:
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\tools\remove-user-voices.ps1"'
uninstall_remove_voices_done:
  Delete "$SMPROGRAMS\Pocket TTS\Voice Manager.lnk"
  RMDir "$SMPROGRAMS\Pocket TTS"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\PocketTTS-SAPI"
  RMDir /r "$INSTDIR"
SectionEnd
