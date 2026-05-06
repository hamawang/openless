; NSIS installer hook：注册 / 反注册 OpenLess TSF 输入法 DLL。
;
; 背景：MSI 包通过 wix/openless-ime.wxs 的 CustomAction 跑 regsvr32，可正常注册到
; HKLM 下的 TSF 注册表四件套；NSIS 包没有等价钩子 → NSIS 安装的用户在
; "设置 → 权限"页面看到 "Windows 输入法后端：不可用"。
;
; 这里的 hook 在 NSIS 安装/卸载流程里调 regsvr32 把 OpenLessIme.dll 注册到 HKLM。
; bundle.resources 把 x64 / x86 DLL 拷到 $INSTDIR\tsf-ime\{x64,x86}\OpenLessIme.dll
; (resources map 的 target 必须避开 wxs fragment 已声明的 windows-ime\x64\
; 路径，否则 MSI 包里同一路径会被两个 component 占用)。
; tauri.conf.json 的 nsis.installMode = "perMachine" 让 NSIS 以管理员身份运行
; (写 HKLM 必需)。
;
; 必须同时注册 x64 + x86 两份 dll：windows_ime_profile.rs 的
; inspect_windows_ime_registration() 会用 KEY_WOW64_64KEY 和 KEY_WOW64_32KEY 两次
; 检查 HKLM CLSID InprocServer32，少了任何一边都会被判 RegistrationBroken。
; - x64 用 $SYSDIR\regsvr32.exe (System32 = 64-bit on x64 Windows)
; - x86 用 $WINDIR\SysWOW64\regsvr32.exe (32-bit regsvr32 → 写 KEY_WOW64_32KEY)
;
; regsvr32 失败时不阻塞安装：用户仍可以靠 SendInput / 粘贴兜底完成上屏。

!macro NSIS_HOOK_POSTINSTALL
  DetailPrint "Registering OpenLess TSF IME (x64) ..."
  nsExec::ExecToLog '"$SYSDIR\regsvr32.exe" /s "$INSTDIR\tsf-ime\x64\OpenLessIme.dll"'
  Pop $0
  ${If} $0 != 0
    DetailPrint "OpenLess TSF IME x64 registration failed (exit $0); fallback insertion paths still work."
  ${EndIf}

  DetailPrint "Registering OpenLess TSF IME (x86) ..."
  nsExec::ExecToLog '"$WINDIR\SysWOW64\regsvr32.exe" /s "$INSTDIR\tsf-ime\x86\OpenLessIme.dll"'
  Pop $0
  ${If} $0 != 0
    DetailPrint "OpenLess TSF IME x86 registration failed (exit $0); fallback insertion paths still work."
  ${EndIf}
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  DetailPrint "Unregistering OpenLess TSF IME (x86) ..."
  nsExec::ExecToLog '"$WINDIR\SysWOW64\regsvr32.exe" /s /u "$INSTDIR\tsf-ime\x86\OpenLessIme.dll"'
  Pop $0
  DetailPrint "Unregistering OpenLess TSF IME (x64) ..."
  nsExec::ExecToLog '"$SYSDIR\regsvr32.exe" /s /u "$INSTDIR\tsf-ime\x64\OpenLessIme.dll"'
  Pop $0
!macroend
