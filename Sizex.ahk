#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; AHK v2 視窗位置記憶與自動定位腳本 (極致修復版)
; ==============================================================================

global IniFile := A_ScriptDir "\Sizex.ini"
global CurrentHotkey := ""
global SettingsGuiObj := ""
global HotkeyRecorderHook := ""
global MouseRecordList := ["*MButton", "*RButton", "*XButton1", "*XButton2", "*WheelUp", "*WheelDown", "*LButton"]

; --- 全域變數：追蹤目前是否正在拖拉視窗 ---
global IsWindowMoving := false
global MovingHwnd := 0

; --- 初始化設定與托盤圖示 ---
InitTrayMenu()
InitGlobalHotkey()

; --- 啟動 WinEvent 系統事件監聽 ---
SetWinEventHook()

; --- 啟動時自動恢復已有紀錄之視窗位置 ---
SetTimer RestoreAllSavedWindows, -200

; ------------------------------------------------------------------------------
; 托盤選單初始化 (右鍵選單僅保留「設定」與「離開」)
; ------------------------------------------------------------------------------
InitTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("⚙️ 設定", (*) => ShowSettingsGui())
    A_TrayMenu.Add("❌ 離開", (*) => ExitApp())
}

; ------------------------------------------------------------------------------
; 初始化全域熱鍵
; ------------------------------------------------------------------------------
InitGlobalHotkey() {
    global CurrentHotkey, IniFile
    savedHk := IniRead(IniFile, "Settings", "Hotkey", "^#z")
    if (savedHk == "")
        savedHk := "^#z"
    ApplyGlobalHotkey(savedHk, true)
}

; ------------------------------------------------------------------------------
; 註冊/更新全域熱鍵
; ------------------------------------------------------------------------------
ApplyGlobalHotkey(newHk, silent := false) {
    global CurrentHotkey, IniFile
    if (newHk == "")
        return false

    oldHk := CurrentHotkey
    if (oldHk != "") {
        try Hotkey(oldHk, "Off")
    }

    try {
        Hotkey(newHk, (*) => ShowMenu(), "On")
        CurrentHotkey := newHk
        IniWrite(CurrentHotkey, IniFile, "Settings", "Hotkey")
        if (!silent) {
            ToolTip("已成功套用熱鍵: " HotkeyToHumanReadable(CurrentHotkey))
            SetTimer ClearToolTip, -2000
        }
        return true
    } catch as err {
        if (oldHk != "") {
            try Hotkey(oldHk, (*) => ShowMenu(), "On")
        }
        if (!silent) {
            MsgBox("熱鍵註冊失敗！`n可能是該組合鍵無效或已被系統其他程式佔用。", "熱鍵設定錯誤", "Icon! 16")
        }
        return false
    }
}

; ------------------------------------------------------------------------------
; 熱鍵代碼轉換為易讀文字 (如 ^#z -> Ctrl + Win + Z, ^MButton -> Ctrl + 滑鼠中鍵)
; ------------------------------------------------------------------------------
HotkeyToHumanReadable(hk) {
    if (hk == "")
        return "(未設定)"
    res := []
    temp := hk
    isCtrl := false, isAlt := false, isShift := false, isWin := false

    while (temp != "") {
        char := SubStr(temp, 1, 1)
        if (char == "^") {
            isCtrl := true
            temp := SubStr(temp, 2)
        } else if (char == "!") {
            isAlt := true
            temp := SubStr(temp, 2)
        } else if (char == "+") {
            isShift := true
            temp := SubStr(temp, 2)
        } else if (char == "#") {
            isWin := true
            temp := SubStr(temp, 2)
        } else {
            break
        }
    }

    if (isCtrl)
        res.Push("Ctrl")
    if (isAlt)
        res.Push("Alt")
    if (isShift)
        res.Push("Shift")
    if (isWin)
        res.Push("Win")

    if (temp != "") {
        mouseMap := Map(
            "mbutton", "滑鼠中鍵 (MButton)",
            "rbutton", "滑鼠右鍵 (RButton)",
            "lbutton", "滑鼠左鍵 (LButton)",
            "xbutton1", "滑鼠側鍵1 (XButton1)",
            "xbutton2", "滑鼠側鍵2 (XButton2)",
            "wheelup", "滾輪向上 (WheelUp)",
            "wheeldown", "滾輪向下 (WheelDown)"
        )
        lowerTemp := StrLower(temp)
        if (mouseMap.Has(lowerTemp)) {
            res.Push(mouseMap[lowerTemp])
        } else if (StrLen(temp) == 1) {
            res.Push(StrUpper(temp))
        } else {
            res.Push(temp)
        }
    }

    out := ""
    for i, p in res
        out .= (i == 1 ? "" : " + ") p
    return out
}

; ------------------------------------------------------------------------------
; 建立與顯示主選單 (按下熱鍵時彈出)
; ------------------------------------------------------------------------------
ShowMenu() {
    mainMenu := Menu()
    mainMenu.Add("📌 記住當前焦點視窗位置", SaveCurrentWindow)
    mainMenu.Add("⚙️ 設定", (*) => ShowSettingsGui())
    
    sectionsList := GetIniSections(IniFile)

    if (sectionsList.Length > 0) {
        mainMenu.Add()
        for section in sectionsList {
            if (section != "") {
                mainMenu.Add(section, ApplyWindowProfile)
            }
        }
    } else {
        mainMenu.Add()
        mainMenu.Add("(尚無儲存的視窗位置)", (*) => "")
        mainMenu.Disable("(尚無儲存的視窗位置)")
    }

    mainMenu.Show()
}

; ------------------------------------------------------------------------------
; 安全讀取 INI 所有 Section 清單 (自動排除 Settings 等系統 Section)
; ------------------------------------------------------------------------------
GetIniSections(file) {
    sections := []
    if !FileExist(file)
        return sections

    iniText := FileRead(file, "UTF-8")
    Loop Parse, iniText, "`n", "`r" {
        line := Trim(A_LoopField)
        if (RegExMatch(line, "^\[(.*)\]$", &match)) {
            secName := match[1]
            if (StrCompare(secName, "Settings", false) != 0) {
                sections.Push(secName)
            }
        }
    }
    return sections
}

; ------------------------------------------------------------------------------
; 設定視窗 GUI (熱鍵設定、視窗紀錄管理、匯入/匯出)
; ------------------------------------------------------------------------------
ShowSettingsGui(*) {
    global SettingsGuiObj, CurrentHotkey, HotkeyRecorderHook

    ; 若設定視窗已存在則直接啟用焦點
    if (SettingsGuiObj != "") {
        try {
            SettingsGuiObj.Show()
            return
        }
    }

    sg := Gui("+AlwaysOnTop -MinimizeBox", "Sizex - 設定")
    sg.SetFont("s9", "Segoe UI")

    tab := sg.Add("Tab3", "x12 y10 w510 h330", ["⌨️ 熱鍵設定", "📋 視窗紀錄管理", "📂 匯入 / 匯出"])

    ; ==================== 分頁 1: 熱鍵設定 ====================
    tab.UseTab(1)
    sg.Add("GroupBox", "x25 y45 w480 h170", "呼叫選單熱鍵")

    sg.Add("Text", "x45 y75 w100 h25", "目前熱鍵名稱：")
    editDisplay := sg.Add("Edit", "x150 y72 w330 h26 ReadOnly Center", HotkeyToHumanReadable(CurrentHotkey))
    editDisplay.SetFont("s10 bold", "Segoe UI")

    sg.Add("Text", "x45 y110 w100 h25", "AHK 格式代碼：")
    txtAhkCode := sg.Add("Edit", "x150 y107 w330 h26 ReadOnly Center", CurrentHotkey)

    btnRecord := sg.Add("Button", "x45 y150 w435 h42", "🎯 點擊開始錄製按鍵 (支援鍵盤組合鍵與滑鼠按鍵)")
    btnRecord.SetFont("s10 bold", "Segoe UI")

    btnSaveHk := sg.Add("Button", "x45 y230 w150 h36 Default", "💾 儲存並套用熱鍵")
    btnResetHk := sg.Add("Button", "x210 y230 w150 h36", "🔄 重設預設 (^#z)")

    btnRecord.OnEvent("Click", (*) => StartHotkeyRecording(btnRecord, editDisplay, txtAhkCode))
    btnSaveHk.OnEvent("Click", (*) => OnSaveSettings(txtAhkCode.Value))
    btnResetHk.OnEvent("Click", (*) => OnResetSettings(btnRecord, editDisplay, txtAhkCode))

    ; ==================== 分頁 2: 視窗紀錄管理 ====================
    tab.UseTab(2)
    lvProfiles := sg.Add("ListView", "x25 y45 w480 h210 Grid -Multi", ["名稱", "X", "Y", "寬度 (W)", "高度 (H)", "進程名稱 (Exe)"])
    
    btnDeleteSelected := sg.Add("Button", "x25 y265 w135 h35", "🗑️ 刪除選取紀錄")
    btnClearAll := sg.Add("Button", "x170 y265 w135 h35", "🧹 清空所有紀錄")
    btnRefreshLv := sg.Add("Button", "x315 y265 w100 h35", "🔄 重新整理")

    RefreshProfileListView(lvProfiles)

    btnDeleteSelected.OnEvent("Click", (*) => DeleteSelectedProfile(lvProfiles))
    btnClearAll.OnEvent("Click", (*) => ClearAllProfiles(lvProfiles))
    btnRefreshLv.OnEvent("Click", (*) => RefreshProfileListView(lvProfiles))

    ; ==================== 分頁 3: 匯入 / 匯出 ====================
    tab.UseTab(3)
    sg.Add("GroupBox", "x25 y45 w480 h220", "設定檔備份與遷移")

    sg.Add("Text", "x45 y75 w440 h40", "您可以將目前的視窗設定匯出為 INI 備份檔案，或是從其他 INI 檔案匯入並合併設定。")

    btnImport := sg.Add("Button", "x45 y125 w205 h42", "📂 匯入 INI 設定檔")
    btnImport.SetFont("s10 bold", "Segoe UI")

    btnExport := sg.Add("Button", "x270 y125 w205 h42", "💾 匯出目前 INI 設定檔")
    btnExport.SetFont("s10 bold", "Segoe UI")

    btnOpenIni := sg.Add("Button", "x45 y185 w430 h35", "📝 開啟目前 INI 檔案編輯")

    btnImport.OnEvent("Click", (*) => ImportIniFile(lvProfiles))
    btnExport.OnEvent("Click", (*) => ExportIniFile())
    btnOpenIni.OnEvent("Click", (*) => OpenCurrentIni())

    ; ==================== 底部通用按鈕 ====================
    tab.UseTab()
    btnClose := sg.Add("Button", "x405 y350 w115 h35", "關閉")
    btnClose.OnEvent("Click", (*) => OnSettingsClose(sg))

    sg.OnEvent("Close", OnSettingsClose)
    sg.OnEvent("Escape", OnSettingsClose)

    SettingsGuiObj := sg
    sg.Show("w535 h395")
}

; ------------------------------------------------------------------------------
; 熱鍵與滑鼠錄製功能
; ------------------------------------------------------------------------------
StartHotkeyRecording(btnRecord, editDisplay, txtAhkCode) {
    global HotkeyRecorderHook
    StopAllRecording()

    btnRecord.Text := "🔴 請按下按鍵或滑鼠鍵... (按 Esc 取消)"
    btnRecord.Enabled := false

    ; 1. 啟用鍵盤輸入監聽
    HotkeyRecorderHook := InputHook("V")
    HotkeyRecorderHook.KeyOpt("{All}", "+N +S")
    HotkeyRecorderHook.OnKeyDown := (hook, vk, sc) => ProcessRecordKeyDown(hook, vk, sc, btnRecord, editDisplay, txtAhkCode)
    HotkeyRecorderHook.Start()

    ; 2. 啟用滑鼠按鍵監聽
    ToggleMouseRecorder(true, (thisHk) => ProcessMouseKeyDown(thisHk, btnRecord, editDisplay, txtAhkCode))
}

ToggleMouseRecorder(enable, callback := "") {
    global MouseRecordList
    for hk in MouseRecordList {
        try {
            if (enable)
                Hotkey(hk, callback, "On")
            else
                Hotkey(hk, "Off")
        }
    }
}

StopAllRecording() {
    global HotkeyRecorderHook
    if (HotkeyRecorderHook != "") {
        try HotkeyRecorderHook.Stop()
        HotkeyRecorderHook := ""
    }
    ToggleMouseRecorder(false)
}

ProcessRecordKeyDown(hook, vk, sc, btnRecord, editDisplay, txtAhkCode) {
    keyName := GetKeyName(Format("vk{:02x}sc{:03x}", vk, sc))

    ; 按 Esc 取消錄製
    if (keyName = "Escape" && !GetKeyState("Ctrl", "P") && !GetKeyState("Alt", "P") && !GetKeyState("Shift", "P") && !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P")) {
        StopAllRecording()
        btnRecord.Text := "🎯 點擊開始錄製按鍵 (支援鍵盤組合鍵與滑鼠按鍵)"
        btnRecord.Enabled := true
        return
    }

    ; 單純按下修飾鍵時等待後續按鍵
    if (keyName = "LControl" || keyName = "RControl" || keyName = "Control"
     || keyName = "LAlt" || keyName = "RAlt" || keyName = "Alt"
     || keyName = "LShift" || keyName = "RShift" || keyName = "Shift"
     || keyName = "LWin" || keyName = "RWin") {
        return
    }

    ; 取得修飾鍵
    modStr := ""
    if GetKeyState("Ctrl", "P")
        modStr .= "^"
    if GetKeyState("Alt", "P")
        modStr .= "!"
    if GetKeyState("Shift", "P")
        modStr .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        modStr .= "#"

    baseKey := (StrLen(keyName) == 1) ? StrLower(keyName) : keyName
    capturedHk := modStr . baseKey

    StopAllRecording()

    editDisplay.Value := HotkeyToHumanReadable(capturedHk)
    txtAhkCode.Value := capturedHk
    btnRecord.Text := "🎯 點擊重新錄製按鍵"
    btnRecord.Enabled := true
}

ProcessMouseKeyDown(thisHk, btnRecord, editDisplay, txtAhkCode) {
    cleanHk := RegExReplace(thisHk, "^\*")

    ; 若無修飾鍵且點擊左鍵，視為一般點擊操作不進行綁定
    hasMod := (GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("Shift", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
    if (cleanHk = "LButton" && !hasMod) {
        return
    }

    modStr := ""
    if GetKeyState("Ctrl", "P")
        modStr .= "^"
    if GetKeyState("Alt", "P")
        modStr .= "!"
    if GetKeyState("Shift", "P")
        modStr .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        modStr .= "#"

    capturedHk := modStr . cleanHk

    StopAllRecording()

    editDisplay.Value := HotkeyToHumanReadable(capturedHk)
    txtAhkCode.Value := capturedHk
    btnRecord.Text := "🎯 點擊重新錄製按鍵"
    btnRecord.Enabled := true
}

OnSaveSettings(newHk) {
    ApplyGlobalHotkey(newHk)
}

OnResetSettings(btnRecord, editDisplay, txtAhkCode) {
    editDisplay.Value := HotkeyToHumanReadable("^#z")
    txtAhkCode.Value := "^#z"
    btnRecord.Text := "🎯 點擊開始錄製按鍵 (支援鍵盤組合鍵與滑鼠按鍵)"
}

OnSettingsClose(guiObj, *) {
    global SettingsGuiObj
    StopAllRecording()
    SettingsGuiObj := ""
    try guiObj.Destroy()
}

; ------------------------------------------------------------------------------
; 視窗紀錄清單管理
; ------------------------------------------------------------------------------
RefreshProfileListView(lv) {
    lv.Delete()
    sectionsList := GetIniSections(IniFile)
    for sec in sectionsList {
        if (sec == "")
            continue
        iX := IniRead(IniFile, sec, "X", "")
        iY := IniRead(IniFile, sec, "Y", "")
        iW := IniRead(IniFile, sec, "W", "")
        iH := IniRead(IniFile, sec, "H", "")
        iExe := IniRead(IniFile, sec, "Exe", "")
        lv.Add(, sec, iX, iY, iW, iH, iExe)
    }
    lv.ModifyCol(1, 130)
    lv.ModifyCol(2, 50)
    lv.ModifyCol(3, 50)
    lv.ModifyCol(4, 75)
    lv.ModifyCol(5, 75)
    lv.ModifyCol(6, 90)
}

DeleteSelectedProfile(lv) {
    row := lv.GetNext(0)
    if (!row) {
        MsgBox("請先在清單中選取要刪除的紀錄！", "提示", "Icon! 48")
        return
    }
    secName := lv.GetText(row, 1)
    if (MsgBox("確定要刪除 [" secName "] 的視窗紀錄嗎？", "確認刪除", "YesNo Icon? 32") == "Yes") {
        IniDelete(IniFile, secName)
        lv.Delete(row)
        ToolTip("已從設定中刪除 [" secName "]")
        SetTimer ClearToolTip, -1500
    }
}

ClearAllProfiles(lv) {
    sectionsList := GetIniSections(IniFile)
    if (sectionsList.Length == 0) {
        MsgBox("目前沒有任何已儲存的視窗紀錄。", "提示", "Iconi 64")
        return
    }

    if (MsgBox("確定要清空所有已儲存的視窗紀錄嗎？`n此動作無法復原！", "警告", "YesNo Icon! 48") == "Yes") {
        for sec in sectionsList {
            if (sec != "")
                IniDelete(IniFile, sec)
        }
        RefreshProfileListView(lv)
        MsgBox("已成功清空所有視窗紀錄！", "已清空", "Iconi 64")
    }
}

; ------------------------------------------------------------------------------
; 匯入 / 匯出 / 開啟 INI 設定檔
; ------------------------------------------------------------------------------
ImportIniFile(lv := "") {
    selectedFile := FileSelect(3, , "請選擇要匯入的 INI 設定檔", "Configuration Files (*.ini)")
    if (selectedFile == "")
        return

    try {
        sectionsList := GetIniSections(selectedFile)
        count := 0
        for sec in sectionsList {
            if (sec != "") {
                iX := IniRead(selectedFile, sec, "X", "")
                iY := IniRead(selectedFile, sec, "Y", "")
                iW := IniRead(selectedFile, sec, "W", "")
                iH := IniRead(selectedFile, sec, "H", "")
                iExe := IniRead(selectedFile, sec, "Exe", "")

                if (iX != "") {
                    IniWrite(iX, IniFile, sec, "X")
                    IniWrite(iY, IniFile, sec, "Y")
                    IniWrite(iW, IniFile, sec, "W")
                    IniWrite(iH, IniFile, sec, "H")
                    if (iExe != "")
                        IniWrite(iExe, IniFile, sec, "Exe")
                    count += 1
                }
            }
        }
        if (lv != "" && IsObject(lv))
            RefreshProfileListView(lv)
        RestoreAllSavedWindows()
        MsgBox("已成功匯入並合併 " count " 筆視窗設定！", "匯入成功", "Iconi 64")
    } catch {
        MsgBox("匯入設定檔失敗，請確認檔案格式是否正確。", "錯誤", "Icon! 16")
    }
}

ExportIniFile() {
    exportPath := FileSelect("S 16", "Sizex_Backup.ini", "匯出 INI 設定檔", "Configuration Files (*.ini)")
    if (exportPath == "")
        return
    if (!RegExMatch(exportPath, "i)\.ini$"))
        exportPath .= ".ini"

    try {
        if FileExist(IniFile) {
            FileCopy(IniFile, exportPath, 1)
            MsgBox("設定檔已成功匯出至：`n" exportPath, "匯出成功", "Iconi 64")
        } else {
            MsgBox("尚未建立任何設定檔，無法匯出。", "提示", "Icon! 48")
        }
    } catch as err {
        MsgBox("匯出設定檔失敗: " err.Message, "錯誤", "Icon! 16")
    }
}

OpenCurrentIni() {
    if !FileExist(IniFile) {
        FileAppend("", IniFile, "UTF-8")
    }
    try {
        Run(IniFile)
    } catch as err {
        MsgBox("無法開啟檔案: " err.Message, "錯誤", "Icon! 16")
    }
}

; ------------------------------------------------------------------------------
; 儲存當前焦點視窗位置與尺寸
; ------------------------------------------------------------------------------
SaveCurrentWindow(*) {
    try {
        activeHwnd := WinGetID("A")
        activeTitle := WinGetTitle("ahk_id " activeHwnd)
        exeName := WinGetProcessName("ahk_id " activeHwnd)
    } catch {
        MsgBox("無法存取當前視窗！", "提示", "Icon! 48")
        return
    }

    sectionKey := GenerateSmartKey(activeTitle, exeName)

    WinGetPos(&X, &Y, &W, &H, "ahk_id " activeHwnd)

    IniWrite(X, IniFile, sectionKey, "X")
    IniWrite(Y, IniFile, sectionKey, "Y")
    IniWrite(W, IniFile, sectionKey, "W")
    IniWrite(H, IniFile, sectionKey, "H")
    IniWrite(exeName, IniFile, sectionKey, "Exe")

    ToolTip("已成功儲存 [" sectionKey "]\nX:" X " Y:" Y " W:" W " H:" H)
    SetTimer ClearToolTip, -2000
}

GenerateSmartKey(title, exe) {
    exeLower := StrLower(exe)
    if InStr(exeLower, "vivaldi")
        return "Vivaldi"
    if InStr(exeLower, "chrome")
        return "Google Chrome"
    if InStr(exeLower, "msedge")
        return "Microsoft Edge"
    if InStr(exeLower, "firefox")
        return "Firefox"
    if InStr(exeLower, "parsecd") || InStr(exeLower, "parsec")
        return "Parsec"
    if InStr(exeLower, "explorer")
        return "Explorer"

    return (title != "") ? title : exe
}

; ------------------------------------------------------------------------------
; 手動恢復：直接作用於當前焦點視窗 (Active Window)
; ------------------------------------------------------------------------------
ApplyWindowProfile(ItemName, ItemPos, MyMenu) {
    try {
        currentHwnd := WinGetID("A")
        MoveWindowToTarget(ItemName, currentHwnd)
        ToolTip("已將當前焦點視窗套用設定 [" ItemName "]")
        SetTimer ClearToolTip, -1200
    } catch {
        MsgBox("無法取得當前焦點視窗！", "錯誤", "Icon! 16")
    }
}

; ------------------------------------------------------------------------------
; 核心定位邏輯
; ------------------------------------------------------------------------------
MoveWindowToTarget(targetKey, hwnd := 0) {
    try {
        targetX := Integer(IniRead(IniFile, targetKey, "X"))
        targetY := Integer(IniRead(IniFile, targetKey, "Y"))
        targetW := Integer(IniRead(IniFile, targetKey, "W"))
        targetH := Integer(IniRead(IniFile, targetKey, "H"))
    } catch {
        return false
    }

    targetHwnd := 0
    if (hwnd && WinExist("ahk_id " hwnd)) {
        if (IsCandidateMainAppWindow(hwnd))
            targetHwnd := hwnd
    } else {
        savedExe := IniRead(IniFile, targetKey, "Exe", "")
        if (savedExe != "") {
            for h in WinGetList("ahk_exe " savedExe) {
                if (IsCandidateMainAppWindow(h)) {
                    targetHwnd := h
                    break
                }
            }
        } else if WinExist(targetKey) {
            hCandidate := WinGetID(targetKey)
            if (IsCandidateMainAppWindow(hCandidate))
                targetHwnd := hCandidate
        }
    }

    if (targetHwnd) {
        try {
            WinGetPos(&curX, &curY, &curW, &curH, "ahk_id " targetHwnd)

            if (Abs(curX - targetX) <= 5 && Abs(curY - targetY) <= 5 && Abs(curW - targetW) <= 5 && Abs(curH - targetH) <= 5) {
                return true
            }

            ; 靜默移動 (0x0014 = SWP_NOACTIVATE | SWP_NOZORDER)
            DllCall("SetWindowPos"
                , "Ptr", targetHwnd
                , "Ptr", 0
                , "Int", targetX, "Int", targetY, "Int", targetW, "Int", targetH
                , "UInt", 0x0014)

            return true
        } catch {
            return false
        }
    }
    return false
}

; ------------------------------------------------------------------------------
; 實時座標更新 Timer (僅在系統確認「正在拖動視窗」時運作)
; ------------------------------------------------------------------------------
UpdateDragToolTip() {
    global IsWindowMoving, MovingHwnd
    if (IsWindowMoving && MovingHwnd && WinExist("ahk_id " MovingHwnd)) {
        try {
            MouseGetPos &mX, &mY
            WinGetPos &wX, &wY, &wW, &wH, "ahk_id " MovingHwnd
            ToolTip("X: " wX " | Y: " wY "`nW: " wW " | H: " wH, mX + 15, mY + 15)
        }
    } else {
        SetTimer UpdateDragToolTip, 0
        ToolTip()
    }
}

; ------------------------------------------------------------------------------
; Windows 原生事件 Hook 註冊
; ------------------------------------------------------------------------------
SetWinEventHook() {
    ; 1. 監聽 EVENT_SYSTEM_MOVESIZESTART (0x000A) 與 EVENT_SYSTEM_MOVESIZEEND (0x000B)
    static hMoveHook := DllCall("SetWinEventHook"
        , "UInt", 0x000A, "UInt", 0x000B
        , "Ptr", 0
        , "Ptr", CallbackCreate(OnMoveSizeEvent, "CDecl")
        , "UInt", 0, "UInt", 0
        , "UInt", 0, "Ptr")

    ; 2. 監聽 EVENT_OBJECT_SHOW (0x8002) - 新開視窗自動定位
    static hShowHook := DllCall("SetWinEventHook"
        , "UInt", 0x8002, "UInt", 0x8002
        , "Ptr", 0
        , "Ptr", CallbackCreate(OnWindowShow, "CDecl")
        , "UInt", 0, "UInt", 0
        , "UInt", 0, "Ptr")
}

; ------------------------------------------------------------------------------
; 系統視窗拖拉/縮放 事件處理器
; ------------------------------------------------------------------------------
OnMoveSizeEvent(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    global IsWindowMoving, MovingHwnd

    ; 僅處理標準主視窗，排除輸入法/浮動元件
    if (idObject != 0 || !hwnd || !IsCandidateMainAppWindow(hwnd))
        return

    if (event == 0x000A) { ; EVENT_SYSTEM_MOVESIZESTART (使用者開始拖動或縮放視窗)
        IsWindowMoving := true
        MovingHwnd := hwnd
        SetTimer UpdateDragToolTip, 30
    }
    else if (event == 0x000B) { ; EVENT_SYSTEM_MOVESIZEEND (使用者放開滑鼠結束拖動)
        IsWindowMoving := false
        MovingHwnd := 0
        SetTimer UpdateDragToolTip, 0
        ToolTip()
    }
}

; ------------------------------------------------------------------------------
; 新開視窗自動定位處理器
; ------------------------------------------------------------------------------
OnWindowShow(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    if (idObject != 0 || !hwnd)
        return

    ; 徹底過濾：排除小狼毫 IME 候選詞視窗、工具視窗、選單、浮動提示等
    if (!IsCandidateMainAppWindow(hwnd))
        return

    try {
        title := WinGetTitle("ahk_id " hwnd)
        exe := WinGetProcessName("ahk_id " hwnd)

        if (title == "" && exe == "")
            return

        sectionsList := GetIniSections(IniFile)
        for sec in sectionsList {
            if (sec == "")
                continue

            savedExe := IniRead(IniFile, sec, "Exe", "")

            if ((savedExe != "" && StrCompare(exe, savedExe, false) == 0) || (title != "" && InStr(title, sec))) {
                BindAndSetTimer(sec, hwnd)
                break
            }
        }
    }
}

; ------------------------------------------------------------------------------
; 判斷是否為標準應用程式主視窗 (排除小狼毫/系統輸入法候選框、Tooltip、選單、陰影等)
; ------------------------------------------------------------------------------
IsCandidateMainAppWindow(hwnd) {
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return false

    try {
        ; 1. 排除輸入法服務進程
        exe := StrLower(WinGetProcessName("ahk_id " hwnd))
        if (exe = "weaselserver.exe" || exe = "weaseldeployer.exe" || exe = "textinputhost.exe" || exe = "ctfmon.exe")
            return false

        ; 2. 排除常見輸入法與浮動視窗類別 (Class)
        cls := WinGetClass("ahk_id " hwnd)
        if (cls = "WeaselUIWnd" || cls = "WeaselCandidateWindow" || cls = "MSCTFIME UI" || cls = "IME"
            || InStr(cls, "tooltips_class") || InStr(cls, "SysShadow") || InStr(cls, "DropShadow")
            || InStr(cls, "Xaml_WindowedPopupClass") || InStr(cls, "PopupHost") || cls = "ComboLBox")
            return false

        ; 3. 視窗樣式檢查
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)

        ; 排除子視窗 (WS_CHILD = 0x40000000)
        if (style & 0x40000000)
            return false

        ; 排除工具視窗 (WS_EX_TOOLWINDOW = 0x00000080) 與 無焦點浮動視窗 (WS_EX_NOACTIVATE = 0x08000000)
        if ((exStyle & 0x00000080) || (exStyle & 0x08000000))
            return false

        ; 4. 排除擁有 Owner 的彈出子視窗 (輸入法候選欄/下拉框 GW_OWNER != 0，標準主視窗 GW_OWNER == 0)
        ownerHwnd := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr") ; 4 = GW_OWNER
        if (ownerHwnd != 0)
            return false

        ; 5. 必須具備主視窗特徵 (WS_CAPTION = 0x00C00000, WS_THICKFRAME = 0x00040000, WS_EX_APPWINDOW = 0x00040000)
        if (!(style & 0x00C00000) && !(style & 0x00040000) && !(exStyle & 0x00040000))
            return false

        return true
    } catch {
        return false
    }
}

; ------------------------------------------------------------------------------
; 啟動時自動還原所有已記錄之視窗尺寸與位置
; ------------------------------------------------------------------------------
RestoreAllSavedWindows() {
    sectionsList := GetIniSections(IniFile)
    if (sectionsList.Length == 0)
        return

    try {
        allHwnds := WinGetList()
        for hwnd in allHwnds {
            try {
                if (!IsCandidateMainAppWindow(hwnd))
                    continue

                title := WinGetTitle("ahk_id " hwnd)
                exe := WinGetProcessName("ahk_id " hwnd)
                if (title == "" && exe == "")
                    continue

                for sec in sectionsList {
                    if (sec == "")
                        continue
                    savedExe := IniRead(IniFile, sec, "Exe", "")
                    if ((savedExe != "" && StrCompare(exe, savedExe, false) == 0) || (title != "" && InStr(title, sec))) {
                        MoveWindowToTarget(sec, hwnd)
                        break
                    }
                }
            }
        }
    }
}

BindAndSetTimer(targetKey, targetHwnd) {
    SetTimer () => MoveWindowToTarget(targetKey, targetHwnd), -200
}

ClearToolTip() {
    ToolTip()
}