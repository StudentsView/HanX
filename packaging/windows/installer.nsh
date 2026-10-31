; Per-user component wizard. The GUI always retains an internal native engine.
!include nsDialogs.nsh
!include LogicLib.nsh
!include FileFunc.nsh
!ifndef BUILD_UNINSTALLER
Var HanXCLI
Var HanXGUI
Var HanXCLICheck
Var HanXGUICheck
Var HanXPDF
Var HanXPDFCheck
!endif

!macro customInit
  StrCpy $HanXCLI 1
  StrCpy $HanXGUI 1
  StrCpy $HanXPDF 0
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
      MessageBox MB_OK|MB_ICONSTOP "/COMPONENTS=cli, gui 또는 all을 지정하세요."
      SetErrorLevel 2
      Quit
    ${EndIf}
  ${EndIf}
  ClearErrors
  ${GetOptions} $R0 "/PDFDEPENDENCIES=" $R1
  ${IfNot} ${Errors}
    ${If} $R1 == "1"
      StrCpy $HanXPDF 1
    ${EndIf}
  ${EndIf}
!macroend

!macro customPageAfterChangeDir
  Page custom HanXComponentsCreate HanXComponentsLeave
!macroend

!ifndef BUILD_UNINSTALLER
Function HanXComponentsCreate
  !insertmacro MUI_HEADER_TEXT "HanX 설치 항목 선택" "문서 편집 앱, 터미널 명령 또는 둘 다 선택하세요."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateCheckbox} 0 8u 100% 18u "문서 편집 앱 (GUI)"
  Pop $HanXGUICheck
  ${NSD_SetState} $HanXGUICheck $HanXGUI
  ${NSD_CreateCheckbox} 0 35u 100% 18u "터미널 명령 (CLI) — 내 사용자 PATH에 추가"
  Pop $HanXCLICheck
  ${NSD_SetState} $HanXCLICheck $HanXCLI
  ${NSD_CreateLabel} 0 65u 100% 45u "GUI에는 내부 문서 엔진이 포함됩니다. GUI만 선택하면 터미널 명령은 등록하지 않습니다.$\r$\n$\r$\nPDF 변환 도구는 선택하여 추가할 수 있습니다. 동의 없이 설치하지 않습니다."
  Pop $0
  ${NSD_CreateCheckbox} 0 116u 100% 18u "PDF 도구도 설치 (LibreOffice + Poppler, 별도 프로그램)"
  Pop $HanXPDFCheck
  ${NSD_SetState} $HanXPDFCheck $HanXPDF
  nsDialogs::Show
FunctionEnd
Function HanXComponentsLeave
  ${NSD_GetState} $HanXGUICheck $HanXGUI
  ${NSD_GetState} $HanXCLICheck $HanXCLI
  ${NSD_GetState} $HanXPDFCheck $HanXPDF
  ${If} $HanXGUI == 0
  ${AndIf} $HanXCLI == 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "설치할 항목을 하나 이상 선택하세요."
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
    MessageBox MB_OK|MB_ICONEXCLAMATION "설치는 완료했지만 사용자 PATH 설정에 실패했습니다. $INSTDIR\resources\cli 경로를 확인하세요."
  ${EndIf}
  ${If} $HanXPDF == 1
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\install-pdf.ps1" -Install'
    Pop $0
    ${If} $0 != 0
      IfSilent +2
      MessageBox MB_OK|MB_ICONEXCLAMATION "PDF 도구 설치를 마치지 못했습니다. winget에서 LibreOffice와 Poppler를 설치한 뒤 다시 시도하세요."
      SetErrorLevel 1
    ${EndIf}
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
    !insertmacro MUI_HEADER_TEXT "HanX CLI 설치 완료" "새 터미널을 열면 hanx와 hanx-cli를 사용할 수 있습니다."
  ${Else}
    !insertmacro MUI_HEADER_TEXT "HanX 설치 완료" "시작 메뉴에서 HanX를 여세요."
  ${EndIf}
FunctionEnd
!endif

!macro customUnInstall
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\manage-path.ps1" -Action Remove -CliDirectory "$INSTDIR\resources\cli"'
  Pop $0
  ${If} $0 != 0
    IfSilent +2
    MessageBox MB_OK|MB_ICONEXCLAMATION "사용자 PATH에서 $INSTDIR\resources\cli 경로를 직접 제거하세요."
  ${EndIf}
  DeleteRegKey HKCU "Software\HanX\Components"
!macroend
