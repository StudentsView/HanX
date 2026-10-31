; Per-user component wizard. The GUI always retains an internal native engine.
!include nsDialogs.nsh
!include LogicLib.nsh
!include FileFunc.nsh
Var HanXCLI
Var HanXGUI
Var HanXCLICheck
Var HanXGUICheck

!macro customInit
  StrCpy $HanXCLI 1
  StrCpy $HanXGUI 1
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/COMPONENTS=" $R1
  ${IfNot} ${Errors}
    ${If} $R1 == "cli"
      StrCpy $HanXGUI 0
    ${ElseIf} $R1 == "gui"
      StrCpy $HanXCLI 0
    ${ElseIf} $R1 != "all"
      IfSilent +2
      MessageBox MB_OK|MB_ICONSTOP "Use /COMPONENTS=cli, gui, or all."
      SetErrorLevel 2
      Quit
    ${EndIf}
  ${EndIf}
!macroend

!macro customPageAfterChangeDir
  Page custom HanXComponentsCreate HanXComponentsLeave
!macroend

!ifndef BUILD_UNINSTALLER
Function HanXComponentsCreate
  !insertmacro MUI_HEADER_TEXT "Choose HanX components" "Install the desktop editor, terminal commands, or both."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateCheckbox} 0 8u 100% 18u "Desktop app (GUI)"
  Pop $HanXGUICheck
  ${NSD_SetState} $HanXGUICheck $HanXGUI
  ${NSD_CreateCheckbox} 0 35u 100% 18u "Terminal commands (CLI) — add to my user PATH"
  Pop $HanXCLICheck
  ${NSD_SetState} $HanXCLICheck $HanXCLI
  ${NSD_CreateLabel} 0 68u 100% 52u "The desktop app includes an internal document engine. GUI only does not expose terminal commands.$\r$\n$\r$\nPDF export may need a compatible local renderer. No optional application is installed automatically."
  Pop $0
  nsDialogs::Show
FunctionEnd
Function HanXComponentsLeave
  ${NSD_GetState} $HanXGUICheck $HanXGUI
  ${NSD_GetState} $HanXCLICheck $HanXCLI
  ${If} $HanXGUI == 0
  ${AndIf} $HanXCLI == 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "Choose at least one component."
    Abort
  ${EndIf}
FunctionEnd
!endif

!macro customInstall
  ${If} $HanXCLI == 1
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\manage-path.ps1" -Action Install -CliDirectory "$INSTDIR\resources\cli"'
  ${Else}
    ; Switching to GUI only removes only the PATH entry that HanX previously added.
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\manage-path.ps1" -Action Remove -CliDirectory "$INSTDIR\resources\cli"'
  ${EndIf}
  Pop $0
  ${If} $0 != 0
    IfSilent +2
    MessageBox MB_OK|MB_ICONEXCLAMATION "HanX installed, but user PATH setup failed. Review $INSTDIR\resources\cli in your user PATH."
  ${EndIf}
  WriteRegDWORD HKCU "Software\HanX\Components" "CLI" $HanXCLI
  WriteRegDWORD HKCU "Software\HanX\Components" "GUI" $HanXGUI
  ${If} $HanXGUI == 0
    ; CLI-only keeps its full DLL/runtime tree and uninstaller, without Electron GUI files.
    Delete "$DESKTOP\${SHORTCUT_NAME}.lnk"
    Delete "$SMPROGRAMS\${SHORTCUT_NAME}.lnk"
    !ifdef MENU_FILENAME
      Delete "$SMPROGRAMS\${MENU_FILENAME}\${SHORTCUT_NAME}.lnk"
      RMDir "$SMPROGRAMS\${MENU_FILENAME}"
    !endif
    Delete "$INSTDIR\${APP_EXECUTABLE_FILENAME}"
    Delete "$INSTDIR\*.dll"
    Delete "$INSTDIR\*.pak"
    Delete "$INSTDIR\*.bin"
    Delete "$INSTDIR\*.dat"
    Delete "$INSTDIR\LICENSE.electron.txt"
    Delete "$INSTDIR\LICENSES.chromium.html"
    Delete "$INSTDIR\resources\app.asar"
    RMDir /r "$INSTDIR\locales"
    RMDir /r "$INSTDIR\resources\app.asar.unpacked"
  ${EndIf}
!macroend

!macro customFinishPage
  !define MUI_PAGE_CUSTOMFUNCTION_SHOW HanXFinishShow
  !insertmacro MUI_PAGE_FINISH
!macroend
!ifndef BUILD_UNINSTALLER
Function HanXFinishShow
  ${If} $HanXGUI == 0
    !insertmacro MUI_HEADER_TEXT "HanX CLI installed" "Open a new terminal to use hanx and hanx-cli."
  ${Else}
    !insertmacro MUI_HEADER_TEXT "HanX installed" "Open HanX from the Start menu."
  ${EndIf}
FunctionEnd
!endif

!macro customUnInstall
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\manage-path.ps1" -Action Remove -CliDirectory "$INSTDIR\resources\cli"'
  Pop $0
  ${If} $0 != 0
    IfSilent +2
    MessageBox MB_OK|MB_ICONEXCLAMATION "Remove $INSTDIR\resources\cli from your user PATH manually."
  ${EndIf}
  DeleteRegKey HKCU "Software\HanX\Components"
!macroend
