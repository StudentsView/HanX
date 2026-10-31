; electron-builder NSIS include. Per-user wizard; no administrator PATH changes.
!macro customInstall
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\manage-path.ps1" -Action Install -CliDirectory "$INSTDIR\resources\cli"'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "HanX installed, but terminal PATH setup failed. Add $INSTDIR\resources\cli to your user PATH manually."
  ${EndIf}
!macroend
!macro customUnInstall
  ; This hook runs before resource deletion. Remove only an entry owned by HanX.
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\manage-path.ps1" -Action Remove -CliDirectory "$INSTDIR\resources\cli"'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "Terminal PATH cleanup failed. Remove $INSTDIR\resources\cli from your user PATH manually."
  ${EndIf}
!macroend
