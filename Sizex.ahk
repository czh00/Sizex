#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; AHK v2 視窗位置記憶與自動定位腳本 (三種熱鍵並存版: 鍵盤 / 滑鼠 / 控制器)
; ==============================================================================

global IniFile := A_ScriptDir "\Sizex.ini"
global KeyHotkey := ""
global MouseHotkey := ""
global ControllerHotkey := ""
global ActiveKeyHotkey := ""
global ActiveMouseHotkey := ""
global ActiveJoyHotkey := ""

global SettingsGuiObj := ""
global RecordingType := ""
global ActiveInputHook := ""
global JoyPollActive := false
global RecControls := {}
global MouseRecordList := ["*MButton", "*RButton", "*XButton1", "*XButton2", "*WheelUp", "*WheelDown", "*LButton"]

; --- 全域變數：追蹤目前是否正在拖拉視窗 ---
global IsWindowMoving := false
global MovingHwnd := 0

; --- 初始化設定與托盤圖示 ---
InitTrayMenu()
InitGlobalHotkeys()

; --- 啟動 WinEvent 系統事件監聽 ---
SetWinEventHook()

; --- 啟動時自動恢復已有紀錄之視窗位置 ---
SetTimer RestoreAllSavedWindows, -200

; ------------------------------------------------------------------------------
; 托盤選單初始化 (右鍵選單保留「全部歸位」、「設定」與「離開」)
; ------------------------------------------------------------------------------
InitTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("🔄 全部歸位", (*) => RestoreAllSavedWindows(true))
    A_TrayMenu.Add("⚙️ 設定", (*) => ShowSettingsGui())
    A_TrayMenu.Add("❌ 離開", (*) => ExitApp())
    UpdateTrayTip()
}

UpdateTrayTip() {
    global KeyHotkey, MouseHotkey, ControllerHotkey
    tip := "Sizex - 視窗定位工具"
    keys := []
    if (KeyHotkey != "")
        keys.Push("鍵盤:" . KeyHotkey)
    if (MouseHotkey != "")
        keys.Push("滑鼠:" . MouseHotkey)
    if (ControllerHotkey != "")
        keys.Push("手把:" . ControllerHotkey)
    if (keys.Length > 0) {
        tip .= "`n"
        for i, k in keys
            tip .= (i == 1 ? "" : " | ") . k
    }
    try A_IconTip := SubStr(tip, 1, 127)
}

; ------------------------------------------------------------------------------
; 初始化全域熱鍵 (鍵盤、滑鼠、控制器三者並存)
; ------------------------------------------------------------------------------
InitGlobalHotkeys() {
    global KeyHotkey, MouseHotkey, ControllerHotkey, IniFile

    legacyHk := IniRead(IniFile, "Settings", "Hotkey", "")
    KeyHotkey := IniRead(IniFile, "Settings", "KeyHotkey", "")
    MouseHotkey := IniRead(IniFile, "Settings", "MouseHotkey", "")
    ControllerHotkey := IniRead(IniFile, "Settings", "ControllerHotkey", "")

    ; 向下相容舊版設定 (若只存有 Hotkey 鍵值)
    if (KeyHotkey == "" && MouseHotkey == "" && ControllerHotkey == "" && legacyHk != "") {
        if (IsMouseHotkey(legacyHk)) {
            MouseHotkey := legacyHk
            KeyHotkey := "^#z"
        } else if (IsControllerHotkey(legacyHk)) {
            ControllerHotkey := legacyHk
            KeyHotkey := "^#z"
        } else {
            KeyHotkey := legacyHk
        }
    } else {
        if (KeyHotkey == "" && legacyHk == "") {
            KeyHotkey := "^#z"
        }
    }

    ApplyAllHotkeys(KeyHotkey, MouseHotkey, ControllerHotkey, true)
}

; ------------------------------------------------------------------------------
; 註冊/套用三種熱鍵 (鍵盤、滑鼠、控制器三種同時並存)
; ------------------------------------------------------------------------------
ApplyAllHotkeys(newKey, newMouse, newJoy, silent := false) {
    global KeyHotkey, MouseHotkey, ControllerHotkey, IniFile
    global ActiveKeyHotkey, ActiveMouseHotkey, ActiveJoyHotkey

    ; 1. 關閉先前的熱鍵 (如果已變更或清空)
    if (ActiveKeyHotkey != "" && ActiveKeyHotkey != newKey) {
        try Hotkey(ActiveKeyHotkey, "Off")
        ActiveKeyHotkey := ""
    }
    if (ActiveMouseHotkey != "" && ActiveMouseHotkey != newMouse) {
        try Hotkey(ActiveMouseHotkey, "Off")
        ActiveMouseHotkey := ""
    }
    if (ActiveJoyHotkey != "" && ActiveJoyHotkey != newJoy) {
        try Hotkey(ActiveJoyHotkey, "Off")
        ActiveJoyHotkey := ""
    }

    errors := []
    successList := []

    ; 2. 註冊鍵盤熱鍵
    if (newKey != "") {
        try {
            Hotkey(newKey, (*) => ShowMenu(), "On")
            ActiveKeyHotkey := newKey
            KeyHotkey := newKey
            IniWrite(newKey, IniFile, "Settings", "KeyHotkey")
            successList.Push("鍵盤: " . HotkeyToHumanReadable(newKey))
        } catch as err {
            errors.Push("鍵盤熱鍵 [" . newKey . "] 註冊失敗: " . err.Message)
        }
    } else {
        if (ActiveKeyHotkey != "") {
            try Hotkey(ActiveKeyHotkey, "Off")
            ActiveKeyHotkey := ""
        }
        KeyHotkey := ""
        IniWrite("", IniFile, "Settings", "KeyHotkey")
    }

    ; 3. 註冊滑鼠熱鍵
    if (newMouse != "") {
        try {
            Hotkey(newMouse, (*) => ShowMenu(), "On")
            ActiveMouseHotkey := newMouse
            MouseHotkey := newMouse
            IniWrite(newMouse, IniFile, "Settings", "MouseHotkey")
            successList.Push("滑鼠: " . HotkeyToHumanReadable(newMouse))
        } catch as err {
            errors.Push("滑鼠熱鍵 [" . newMouse . "] 註冊失敗: " . err.Message)
        }
    } else {
        if (ActiveMouseHotkey != "") {
            try Hotkey(ActiveMouseHotkey, "Off")
            ActiveMouseHotkey := ""
        }
        MouseHotkey := ""
        IniWrite("", IniFile, "Settings", "MouseHotkey")
    }

    ; 4. 註冊控制器熱鍵
    if (newJoy != "") {
        try {
            Hotkey(newJoy, (*) => ShowMenu(), "On")
            ActiveJoyHotkey := newJoy
            ControllerHotkey := newJoy
            IniWrite(newJoy, IniFile, "Settings", "ControllerHotkey")
            successList.Push("控制器: " . HotkeyToHumanReadable(newJoy))
        } catch as err {
            errors.Push("控制器按鍵 [" . newJoy . "] 註冊失敗: " . err.Message)
        }
    } else {
        if (ActiveJoyHotkey != "") {
            try Hotkey(ActiveJoyHotkey, "Off")
            ActiveJoyHotkey := ""
        }
        ControllerHotkey := ""
        IniWrite("", IniFile, "Settings", "ControllerHotkey")
    }

    ; 維護舊版 Hotkey 鍵值
    legacyVal := (KeyHotkey != "") ? KeyHotkey : ((MouseHotkey != "") ? MouseHotkey : ControllerHotkey)
    IniWrite(legacyVal, IniFile, "Settings", "Hotkey")

    UpdateTrayTip()

    if (!silent) {
        if (errors.Length > 0) {
            errMsg := ""
            for err in errors
                errMsg .= "• " . err . "`n"
            MsgBox("部分熱鍵註冊遇到問題：`n`n" . errMsg, "熱鍵註冊提示", "Icon! 48")
        } else if (successList.Length > 0) {
            tipMsg := "已成功套用熱鍵設定 (三種熱鍵並存生效)：`n"
            for s in successList
                tipMsg .= "• " . s . "`n"
            ToolTip(Trim(tipMsg))
            SetTimer ClearToolTip, -3000
        } else {
            ToolTip("所有熱鍵已清空 (未啟用任何熱鍵)")
            SetTimer ClearToolTip, -2000
        }
    }

    return (errors.Length == 0)
}

; ------------------------------------------------------------------------------
; 檢查是否為滑鼠/控制器熱鍵
; ------------------------------------------------------------------------------
IsMouseHotkey(hk) {
    if (hk == "")
        return false
    lower := StrLower(hk)
    return InStr(lower, "lbutton") || InStr(lower, "rbutton") || InStr(lower, "mbutton")
        || InStr(lower, "xbutton1") || InStr(lower, "xbutton2")
        || InStr(lower, "wheelup") || InStr(lower, "wheeldown")
}

IsControllerHotkey(hk) {
    if (hk == "")
        return false
    return RegExMatch(hk, "i)^\d*Joy\d+$") ? true : false
}

GetConnectedControllerInfo() {
    Loop 16 {
        name := GetKeyState(A_Index . "JoyName")
        if (name != "") {
            btnCount := GetKeyState(A_Index . "JoyButtons")
            return "🟢 已偵測到控制器 #" . A_Index . ": " . name . (btnCount != "" ? " (" . btnCount . " 按鈕)" : "")
        }
    }
    return "⚪ 目前未偵測到已連線手把 (仍可預先設定按鈕代碼)"
}

; ------------------------------------------------------------------------------
; 熱鍵代碼轉換為易讀文字 (支援鍵盤、滑鼠、手把按鈕)
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
        if RegExMatch(temp, "i)^(\d*)Joy(\d+)$", &m) {
            devPrefix := (m[1] != "" && m[1] != "1") ? ("搖桿" . m[1] . " ") : ""
            btnNum := Integer(m[2])
            joyNames := Map(
                1, "A / ╳",
                2, "B / ◯",
                3, "X / ▢",
                4, "Y / △",
                5, "LB / L1",
                6, "RB / R1",
                7, "Back / View / Select",
                8, "Start / Menu / Options",
                9, "LS / 左搖桿下壓",
                10, "RS / 右搖桿下壓"
            )
            desc := joyNames.Has(btnNum) ? ("手把按鈕 " . btnNum . " [" . joyNames[btnNum] . "]") : ("手把按鈕 " . btnNum . " (Joy" . btnNum . ")")
            res.Push(devPrefix . desc)
        } else {
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
    }

    outStr := ""
    for i, p in res
        outStr .= (i == 1 ? "" : " + ") p
    return outStr
}

; ------------------------------------------------------------------------------
; 建立與顯示主選單 (按下熱鍵時彈出)
; ------------------------------------------------------------------------------
ShowMenu() {
    mainMenu := Menu()
    mainMenu.Add("📌 記住當前焦點視窗位置", SaveCurrentWindow)
    mainMenu.Add("🔄 全部歸位", (*) => RestoreAllSavedWindows(true))
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
    global SettingsGuiObj, KeyHotkey, MouseHotkey, ControllerHotkey

    if (SettingsGuiObj != "") {
        try {
            SettingsGuiObj.Show()
            return
        }
    }

    sg := Gui("+AlwaysOnTop -MinimizeBox", "Sizex - 設定")
    sg.SetFont("s9", "Segoe UI")

    tab := sg.Add("Tab3", "x15 y10 w550 h520", ["🎯 熱鍵設定 (三種並存)", "📋 視窗紀錄管理", "📂 匯入 / 匯出"])

    ; ==================== 分頁 1: 熱鍵設定 (鍵盤、滑鼠、控制器三種並存) ====================
    tab.UseTab(1)

    sg.Add("Text", "x30 y42 w520 h20 cGray", "💡 鍵盤、滑鼠、控制器三種熱鍵各自獨立且並存生效，按任一設定鍵皆可呼叫選單。")

    ; --- 1. 鍵盤熱鍵群組 ---
    sg.Add("GroupBox", "x30 y65 w520 h115", "⌨️ 鍵盤熱鍵 (Keyboard)")

    sg.Add("Text", "x45 y95 w75 h20", "目前熱鍵：")
    editKeyDisplay := sg.Add("Edit", "x125 y92 w230 h26 ReadOnly Center", HotkeyToHumanReadable(KeyHotkey))
    editKeyDisplay.SetFont("s10 bold", "Segoe UI")

    sg.Add("Text", "x365 y95 w45 h20", "代碼：")
    txtKeyCode := sg.Add("Edit", "x415 y92 w115 h26 Center", KeyHotkey)

    btnRecordKey := sg.Add("Button", "x125 y130 w155 h32", "🎯 錄製鍵盤組合鍵")
    btnRecordKey.SetFont("s9 bold", "Segoe UI")
    btnClearKey := sg.Add("Button", "x290 y130 w80 h32", "❌ 清除")
    btnResetKey := sg.Add("Button", "x380 y130 w120 h32", "🔄 預設 (^#z)")

    txtKeyCode.OnEvent("Change", (ctrl, *) => editKeyDisplay.Value := HotkeyToHumanReadable(ctrl.Value))
    btnRecordKey.OnEvent("Click", (*) => StartKeyRecording(btnRecordKey, editKeyDisplay, txtKeyCode))
    btnClearKey.OnEvent("Click", (*) => (txtKeyCode.Value := "", editKeyDisplay.Value := HotkeyToHumanReadable("")))
    btnResetKey.OnEvent("Click", (*) => (txtKeyCode.Value := "^#z", editKeyDisplay.Value := HotkeyToHumanReadable("^#z")))

    ; --- 2. 滑鼠熱鍵群組 ---
    sg.Add("GroupBox", "x30 y190 w520 h125", "🖱️ 滑鼠熱鍵 (Mouse)")

    sg.Add("Text", "x45 y218 w75 h20", "目前熱鍵：")
    editMouseDisplay := sg.Add("Edit", "x125 y215 w230 h26 ReadOnly Center", HotkeyToHumanReadable(MouseHotkey))
    editMouseDisplay.SetFont("s10 bold", "Segoe UI")

    sg.Add("Text", "x365 y218 w45 h20", "代碼：")
    txtMouseCode := sg.Add("Edit", "x415 y215 w115 h26 Center", MouseHotkey)

    btnRecordMouse := sg.Add("Button", "x125 y252 w135 h32", "🎯 錄製滑鼠鍵")
    btnRecordMouse.SetFont("s9 bold", "Segoe UI")

    mousePresets := [
        "(快速選取滑鼠按鍵...)",
        "XButton2 (側鍵2 / 前進鍵)",
        "XButton1 (側鍵1 / 後退鍵)",
        "MButton (滾輪中鍵)",
        "WheelUp (滾輪向上)",
        "WheelDown (滾輪向下)",
        "^MButton (Ctrl + 滾輪中鍵)",
        "+MButton (Shift + 滾輪中鍵)",
        "!MButton (Alt + 滾輪中鍵)",
        "^XButton2 (Ctrl + 側鍵2)",
        "^XButton1 (Ctrl + 側鍵1)",
        "RButton (滑鼠右鍵)"
    ]
    ddlMouse := sg.Add("DropDownList", "x270 y253 w175", mousePresets)
    SyncDropdownToValue(ddlMouse, mousePresets, MouseHotkey)

    btnClearMouse := sg.Add("Button", "x455 y252 w75 h32", "❌ 清除")

    sg.Add("Text", "x125 y290 w405 h18 cGray", "※ 支援側鍵 XButton1/2、滾輪中鍵 MButton、滾輪滾動，可搭配 Ctrl/Alt/Shift")

    txtMouseCode.OnEvent("Change", (ctrl, *) => (editMouseDisplay.Value := HotkeyToHumanReadable(ctrl.Value), SyncDropdownToValue(ddlMouse, mousePresets, ctrl.Value)))
    ddlMouse.OnEvent("Change", (ctrl, *) => OnDropdownSelect(ctrl, txtMouseCode, editMouseDisplay))
    btnRecordMouse.OnEvent("Click", (*) => StartMouseRecording(btnRecordMouse, editMouseDisplay, txtMouseCode, ddlMouse, mousePresets))
    btnClearMouse.OnEvent("Click", (*) => (txtMouseCode.Value := "", editMouseDisplay.Value := HotkeyToHumanReadable(""), ddlMouse.Choose(1)))

    ; --- 3. 控制器 / 手把熱鍵群組 ---
    sg.Add("GroupBox", "x30 y325 w520 h140", "🎮 控制器 / 手把熱鍵 (Controller / Gamepad)")

    sg.Add("Text", "x45 y353 w75 h20", "目前熱鍵：")
    editJoyDisplay := sg.Add("Edit", "x125 y350 w230 h26 ReadOnly Center", HotkeyToHumanReadable(ControllerHotkey))
    editJoyDisplay.SetFont("s10 bold", "Segoe UI")

    sg.Add("Text", "x365 y353 w45 h20", "代碼：")
    txtJoyCode := sg.Add("Edit", "x415 y350 w115 h26 Center", ControllerHotkey)

    btnRecordJoy := sg.Add("Button", "x125 y388 w135 h32", "🎯 錄製手把按鍵")
    btnRecordJoy.SetFont("s9 bold", "Segoe UI")

    joyPresets := [
        "(快速選取手把按鍵...)",
        "Joy8 (Start / Menu / Options)",
        "Joy7 (Back / View / Select)",
        "Joy9 (LS / 左搖桿下壓 L3)",
        "Joy10 (RS / 右搖桿下壓 R3)",
        "Joy5 (LB / 左肩鍵 L1)",
        "Joy6 (RB / 右肩鍵 R1)",
        "Joy1 (A / ╳ 按鈕)",
        "Joy2 (B / ◯ 按鈕)",
        "Joy3 (X / ▢ 按鈕)",
        "Joy4 (Y / △ 按鈕)",
        "Joy11 (按鈕 11)",
        "Joy12 (按鈕 12)",
        "Joy13 (按鈕 13)",
        "Joy14 (按鈕 14)",
        "Joy15 (按鈕 15)",
        "Joy16 (按鈕 16)"
    ]
    ddlJoy := sg.Add("DropDownList", "x270 y389 w175", joyPresets)
    SyncDropdownToValue(ddlJoy, joyPresets, ControllerHotkey)

    btnClearJoy := sg.Add("Button", "x455 y388 w75 h32", "❌ 清除")

    txtJoyStatus := sg.Add("Text", "x125 y428 w405 h22 cNavy", GetConnectedControllerInfo())

    txtJoyCode.OnEvent("Change", (ctrl, *) => (editJoyDisplay.Value := HotkeyToHumanReadable(ctrl.Value), SyncDropdownToValue(ddlJoy, joyPresets, ctrl.Value)))
    ddlJoy.OnEvent("Change", (ctrl, *) => OnDropdownSelect(ctrl, txtJoyCode, editJoyDisplay))
    btnRecordJoy.OnEvent("Click", (*) => StartJoyRecording(btnRecordJoy, editJoyDisplay, txtJoyCode, ddlJoy, joyPresets))
    btnClearJoy.OnEvent("Click", (*) => (txtJoyCode.Value := "", editJoyDisplay.Value := HotkeyToHumanReadable(""), ddlJoy.Choose(1)))

    ; --- 儲存按鈕 ---
    btnSaveAllHk := sg.Add("Button", "x145 y475 w290 h38 Default", "💾 儲存並套用所有熱鍵 (鍵盤/滑鼠/控制器)")
    btnSaveAllHk.SetFont("s10 bold", "Segoe UI")
    btnSaveAllHk.OnEvent("Click", (*) => ApplyAllHotkeys(txtKeyCode.Value, txtMouseCode.Value, txtJoyCode.Value))

    ; ==================== 分頁 2: 視窗紀錄管理 ====================
    tab.UseTab(2)
    lvProfiles := sg.Add("ListView", "x30 y45 w520 h415 Grid -Multi", ["名稱", "X", "Y", "寬度 (W)", "高度 (H)", "進程名稱 (Exe)"])

    btnDeleteSelected := sg.Add("Button", "x30 y475 w145 h36", "🗑️ 刪除選取紀錄")
    btnClearAll := sg.Add("Button", "x185 y475 w145 h36", "🧹 清空所有紀錄")
    btnRefreshLv := sg.Add("Button", "x340 y475 w110 h36", "🔄 重新整理")

    RefreshProfileListView(lvProfiles)

    btnDeleteSelected.OnEvent("Click", (*) => DeleteSelectedProfile(lvProfiles))
    btnClearAll.OnEvent("Click", (*) => ClearAllProfiles(lvProfiles))
    btnRefreshLv.OnEvent("Click", (*) => RefreshProfileListView(lvProfiles))

    ; ==================== 分頁 3: 匯入 / 匯出 ====================
    tab.UseTab(3)
    sg.Add("GroupBox", "x30 y45 w520 h420", "設定檔備份與遷移")

    sg.Add("Text", "x50 y85 w480 h40", "您可以將目前的視窗設定匯出為 INI 備份檔案，或是從其他 INI 檔案匯入並合併設定。")

    btnImport := sg.Add("Button", "x50 y145 w225 h45", "📂 匯入 INI 設定檔")
    btnImport.SetFont("s10 bold", "Segoe UI")

    btnExport := sg.Add("Button", "x285 y145 w225 h45", "💾 匯出目前 INI 設定檔")
    btnExport.SetFont("s10 bold", "Segoe UI")

    btnOpenIni := sg.Add("Button", "x50 y215 w460 h38", "📝 開啟目前 INI 檔案編輯")

    btnImport.OnEvent("Click", (*) => ImportIniFile(lvProfiles))
    btnExport.OnEvent("Click", (*) => ExportIniFile())
    btnOpenIni.OnEvent("Click", (*) => OpenCurrentIni())

    ; ==================== 底部通用按鈕 ====================
    tab.UseTab()
    btnClose := sg.Add("Button", "x440 y538 w125 h34", "關閉視窗")
    btnClose.OnEvent("Click", (*) => OnSettingsClose(sg))

    sg.OnEvent("Close", OnSettingsClose)
    sg.OnEvent("Escape", (guiObj, *) => (RecordingType != "" ? StopAllRecording() : OnSettingsClose(guiObj)))

    SettingsGuiObj := sg
    sg.Show("w580 h580")
}

; ------------------------------------------------------------------------------
; 下拉選單與同步輔助函式
; ------------------------------------------------------------------------------
OnDropdownSelect(ctrl, codeCtrl, dispCtrl) {
    sel := ctrl.Text
    if (RegExMatch(sel, "^([^\s]+)", &m)) {
        val := m[1]
        if (SubStr(val, 1, 1) = "(")
            return
        codeCtrl.Value := val
        dispCtrl.Value := HotkeyToHumanReadable(val)
    }
}

SyncDropdownToValue(ddl, presetArray, targetVal) {
    if (!ddl || targetVal == "") {
        try ddl.Choose(1)
        return
    }
    for i, item in presetArray {
        if (RegExMatch(item, "^([^\s]+)", &m) && StrCompare(m[1], targetVal, false) == 0) {
            try ddl.Choose(i)
            return
        }
    }
    try ddl.Choose(1)
}

; ------------------------------------------------------------------------------
; 熱鍵錄製功能 (鍵盤、滑鼠、控制器個別錄製)
; ------------------------------------------------------------------------------
StartKeyRecording(btn, disp, code) {
    global RecordingType, ActiveInputHook, RecControls
    StopAllRecording()

    RecordingType := "Key"
    RecControls := { btn: btn, disp: disp, code: code, defText: "🎯 錄製鍵盤組合鍵" }
    btn.Text := "🔴 請按下鍵盤鍵... (Esc取消)"
    btn.Enabled := false

    ActiveInputHook := InputHook("V")
    ActiveInputHook.KeyOpt("{All}", "+N +S")
    ActiveInputHook.OnKeyDown := ProcessKeyRecorded
    ActiveInputHook.Start()
}

StartMouseRecording(btn, disp, code, ddl, presets) {
    global RecordingType, ActiveInputHook, RecControls
    StopAllRecording()

    RecordingType := "Mouse"
    RecControls := { btn: btn, disp: disp, code: code, ddl: ddl, presets: presets, defText: "🎯 錄製滑鼠鍵" }
    btn.Text := "🔴 請點擊滑鼠鍵... (Esc取消)"
    btn.Enabled := false

    ActiveInputHook := InputHook("V")
    ActiveInputHook.KeyOpt("{Escape}", "+N +S")
    ActiveInputHook.OnKeyDown := (*) => StopAllRecording()
    ActiveInputHook.Start()

    ToggleMouseRecorder(true, ProcessMouseRecorded)
}

StartJoyRecording(btn, disp, code, ddl, presets) {
    global RecordingType, ActiveInputHook, JoyPollActive, RecControls
    StopAllRecording()

    RecordingType := "Joy"
    RecControls := { btn: btn, disp: disp, code: code, ddl: ddl, presets: presets, defText: "🎯 錄製手把按鍵" }
    btn.Text := "🔴 請按下手把鍵... (Esc取消)"
    btn.Enabled := false

    ActiveInputHook := InputHook("V")
    ActiveInputHook.KeyOpt("{Escape}", "+N +S")
    ActiveInputHook.OnKeyDown := (*) => StopAllRecording()
    ActiveInputHook.Start()

    JoyPollActive := true
    SetTimer PollJoyRecord, 25
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
    global RecordingType, ActiveInputHook, JoyPollActive, RecControls

    if (ActiveInputHook != "") {
        try ActiveInputHook.Stop()
        ActiveInputHook := ""
    }
    ToggleMouseRecorder(false)

    if (JoyPollActive) {
        SetTimer PollJoyRecord, 0
        JoyPollActive := false
    }

    if (RecControls.HasProp("btn") && RecControls.btn) {
        try {
            RecControls.btn.Text := RecControls.defText
            RecControls.btn.Enabled := true
        }
    }
    RecordingType := ""
    RecControls := {}
}

ProcessKeyRecorded(hook, vk, sc) {
    global RecControls
    keyName := GetKeyName(Format("vk{:02x}sc{:03x}", vk, sc))

    ; 按 Esc 取消錄製
    if (keyName = "Escape" && !GetKeyState("Ctrl", "P") && !GetKeyState("Alt", "P") && !GetKeyState("Shift", "P") && !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P")) {
        StopAllRecording()
        return
    }

    ; 單純按下修飾鍵時等待後續按鍵
    if (keyName = "LControl" || keyName = "RControl" || keyName = "Control"
     || keyName = "LAlt" || keyName = "RAlt" || keyName = "Alt"
     || keyName = "LShift" || keyName = "RShift" || keyName = "Shift"
     || keyName = "LWin" || keyName = "RWin") {
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

    baseKey := (StrLen(keyName) == 1) ? StrLower(keyName) : keyName
    capturedHk := modStr . baseKey

    btn := RecControls.btn
    disp := RecControls.disp
    code := RecControls.code

    StopAllRecording()

    if (code)
        code.Value := capturedHk
    if (disp)
        disp.Value := HotkeyToHumanReadable(capturedHk)
}

ProcessMouseRecorded(thisHk) {
    global RecControls
    cleanHk := RegExReplace(thisHk, "^\*")

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

    disp := RecControls.disp
    code := RecControls.code
    ddl := RecControls.HasProp("ddl") ? RecControls.ddl : ""
    presets := RecControls.HasProp("presets") ? RecControls.presets : []

    StopAllRecording()

    if (code)
        code.Value := capturedHk
    if (disp)
        disp.Value := HotkeyToHumanReadable(capturedHk)
    if (ddl && presets.Length > 0)
        SyncDropdownToValue(ddl, presets, capturedHk)
}

PollJoyRecord() {
    global RecControls, JoyPollActive
    if (!JoyPollActive)
        return

    Loop 16 {
        joyIndex := A_Index
        bCount := GetKeyState(joyIndex . "JoyButtons")
        if (bCount == "")
            continue

        maxBtn := (bCount > 0) ? Min(Integer(bCount), 32) : 32
        Loop maxBtn {
            btnIndex := A_Index
            if (GetKeyState(joyIndex . "Joy" . btnIndex) == 1) {
                capturedHk := (joyIndex == 1) ? ("Joy" . btnIndex) : (joyIndex . "Joy" . btnIndex)

                disp := RecControls.disp
                code := RecControls.code
                ddl := RecControls.HasProp("ddl") ? RecControls.ddl : ""
                presets := RecControls.HasProp("presets") ? RecControls.presets : []

                StopAllRecording()

                if (code)
                    code.Value := capturedHk
                if (disp)
                    disp.Value := HotkeyToHumanReadable(capturedHk)
                if (ddl && presets.Length > 0)
                    SyncDropdownToValue(ddl, presets, capturedHk)
                return
            }
        }
    }
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
    lv.ModifyCol(1, 140)
    lv.ModifyCol(2, 55)
    lv.ModifyCol(3, 55)
    lv.ModifyCol(4, 80)
    lv.ModifyCol(5, 80)
    lv.ModifyCol(6, 100)
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
RestoreAllSavedWindows(showTip := false, *) {
    sectionsList := GetIniSections(IniFile)
    if (sectionsList.Length == 0) {
        if (showTip) {
            ToolTip("尚無儲存的視窗紀錄")
            SetTimer ClearToolTip, -1500
        }
        return
    }

    count := 0
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
                        if (MoveWindowToTarget(sec, hwnd)) {
                            count++
                        }
                        break
                    }
                }
            }
        }
    }
    if (showTip) {
        if (count > 0)
            ToolTip("已完成全部視窗歸位 (已套用 " count " 個視窗)")
        else
            ToolTip("目前未發現相符之已開啟視窗")
        SetTimer ClearToolTip, -1500
    }
}

BindAndSetTimer(targetKey, targetHwnd) {
    SetTimer () => MoveWindowToTarget(targetKey, targetHwnd), -200
}

ClearToolTip() {
    ToolTip()
}