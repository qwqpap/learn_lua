require("wx")
require("editor.Tree")
require("editor.NodeConfig")
require("editor.NodeColor")
require("editor.Templates")

resList = { snd = {} }
function LoadSound(name, path)
    resList.snd[name] = path
end

--dofile("..\\game\\data\\Thlib\\se\\se.lua")
local SEpath = "editor\\se\\"
dofile(SEpath .. "se.lua")

-- 版本信息
_luastg_version = 0x1000
_luastg_min_support = 0x1000

if not pcall(require, "editor.EditorSetting") then
    setting = {
        ["updatelib"] = false,
        ["projpath"] = "",
        ["windowed"] = true,
        ["cheat"] = false,
        ["resx"] = 800,
        ["resy"] = 600,
    }
end

-- Please take care when you add to the local variables.
-- The number of upvalues in a function is limited.
-- (The limited number is 60 in this case.)
-- If you add too much local variables here, the main function will be errors.

local xmlResource
local frame
local projectTree
local rootNode
local curNode
local logWindow
local logHtml = ''
local attrLabel = {}
local attrCombo = {}
local attrButton = {}
local typeNameLabel
local lineNumText
local Id2Type = {}
local dialog = {
    --NewProj = nil,
    --EditText = nil,
    --Setting = nil,
    --SoundEffect = nil,
    --Type = nil,
    --Image = nil,
    --InputParameter = nil,
    --InputTypeName = nil,
    --SelectEnemyStyle = nil,
    --SelectBulletStyle = nil,
    --SelectColor = nil,
}
local listTemplate
local filePickerNewProj
local editAttrLabel
local editAttrText
local attrIndex
local resXText
local resYText
local windowedCheckBox
local cheatCheckBox
local updateLibCheckBox
local soundListBox
local typeListBox
local imageListBox
local imageString
local imagePrevPanel
local paramNameLabel = {}
local paramText = {}
local typeNameText
local difficultyCombo
local selectEnemyStyleButton = {}
local selectBulletStyleButton = {}
local selectColorButton = {}

local treeImageList

local bitmapBackground

local curProjFile
local curProjDir

local isDebug = false
local debugNode
local scDebugNode

function MakeFullPath(path)
    local fn = wx.wxFileName(path)
    if not fn:IsAbsolute() then
        fn:MakeAbsolute(curProjDir)
        return fn:GetFullPath()
    else
        return fn:GetFullPath()
    end
end

function FileExists(path)
    local fn = wx.wxFileName(path)
    if not fn:IsAbsolute() then
        fn:MakeAbsolute(curProjDir)
        return fn:FileExists()
    else
        return fn:FileExists()
    end
end

function GetClipboard()
    local cp = wx.wxClipboard.Get()
    local text_data = wx.wxTextDataObject("")
    if not cp:Open() then
        return
    end
    local ret = cp:GetData(text_data)
    cp:Close()
    if not ret then
        return false
    else
        return text_data:GetText()
    end
end

function SetClipboard(s)
    local cp = wx.wxClipboard.Get()
    local text_data = wx.wxTextDataObject(s)
    if not cp:Open() then
        return
    end
    local ret = cp:SetData(text_data)
    cp:Flush()
    cp:Close()
    return ret
end

local insertPos = "after"

local treeShot = {}
local treeShotPos = 0
local savedPos = 0

local lineNum = 0

outputName = ""

do
    local index = 0
    cwd = wx.wxFileName(arg[index]):GetPath(wx.wxPATH_GET_VOLUME)
end

local function ID(s)
    return xmlResource.GetXRCID(s)
end

local function IsValid(node)
    if node == nil then
        return false
    else
        if Tree.data[node:GetValue()] then
            return true
        else
            return false
        end
    end
end

local function IsRoot(node)
    if node == nil then
        return false
    else
        return node:GetValue() == rootNode:GetValue()
    end
end

local function OutputLog(msg, icon)
    logHtml = string.format('%s<p><img src="editor/images/%s.png">%s</p>\n', logHtml, icon, msg)
    logWindow:SetPage(logHtml)
    logWindow:Scroll(-1, 65536)
end

local function ClearLog()
    logHtml = ''
    logWindow:SetPage(logHtml)
    logWindow:Scroll(-1, 0)
end

local ancStack = {}
local function CheckAnc(data)
    local ret
    local anc = nodeType[data.type].needancestor
    if anc then
        ret = false
        for _, v in ipairs(ancStack) do
            if anc[v] then
                ret = true
            end
        end
    else
        ret = true
    end
    if not ret then
        local needed = {}
        for k in pairs(anc) do
            if type(k) == 'string' then
                table.insert(needed, k)
            end
        end
        OutputLog(string.format('%q need ancestor: %s', data.type, table.concat(needed, '/')), "error")
        return false
    end
    anc = nodeType[data.type].forbidancestor
    if anc then
        for _, v in ipairs(ancStack) do
            if anc[v] then
                OutputLog(string.format('%q forbid ancestor: %s', data.type, v), "error")
                return false
            end
        end
    end
    if data.child then
        table.insert(ancStack, data.type)
        for _, child in ipairs(data.child) do
            ret = (ret and CheckAnc(child))
        end
        ancStack[#ancStack] = nil
    end
    return ret
end

function main()
    xmlResource = wx.wxXmlResource()
    xmlResource:InitAllHandlers()
    xmlResource:Load("editor/LuaSTG Editor.xrc")
    --
    frame = wx.wxFrame()
    xmlResource:LoadFrame(frame, wx.NULL, "LuaSTG Editor")
    projectTree = frame:FindWindow(ID("LeftTree")):DynamicCast("wxTreeCtrl")
    logWindow = frame:FindWindow(ID("LogWindow")):DynamicCast("wxHtmlWindow")
    for i = 1, 15 do
        attrLabel[i] = frame:FindWindow(ID("AttrLabel" .. i)):DynamicCast("wxStaticText")
        attrCombo[i] = frame:FindWindow(ID("AttrCombo" .. i)):DynamicCast("wxComboBox")
        attrButton[i] = frame:FindWindow(ID("AttrButton" .. i)):DynamicCast("wxButton")
    end
    typeNameLabel = frame:FindWindow(ID("TypeNameLabel")):DynamicCast("wxStaticText")
    lineNumText = frame:FindWindow(ID("LineNumText")):DynamicCast("wxTextCtrl")
    treeImageList = wx.wxImageList(16, 16, false)
    local o = 0
    for k, v in pairs(nodeType) do
        Id2Type[ID("Insert_" .. k)] = v
        local btn = frame:FindWindow(ID("Insert_" .. k))
        if btn then
            btn:SetToolTip(nodeType[k].disptype)
        end
        treeImageList:Add(wx.wxBitmap("editor\\images\\16x16\\" .. k .. ".png", wx.wxBITMAP_TYPE_PNG))
        Tree.imageIndex[k] = o
        o = o + 1
    end
    projectTree:AssignImageList(treeImageList)
    rootNode = projectTree:AddRoot("project", Tree.imageIndex.folder)
    --
    bitmapBackground = wx.wxBitmap("editor\\images\\imagebackground.png")
    --
    dialog.NewProj = wx.wxDialog()
    xmlResource:LoadDialog(dialog.NewProj, wx.NULL, "New Project")
    listTemplate = dialog.NewProj:FindWindow(ID("ListTemplate")):DynamicCast("wxListBox")
    filePickerNewProj = dialog.NewProj:FindWindow(ID("FilePickerNewProj")):DynamicCast("wxFilePickerCtrl")
    for _i = 1, #templates do
        listTemplate:Append(templates[_i][1])
    end
    listTemplate:SetSelection(0)
    --
    dialog.EditText = wx.wxDialog()
    xmlResource:LoadDialog(dialog.EditText, wx.NULL, "Edit Text")
    editAttrLabel = dialog.EditText:FindWindow(ID("EditAttrLabel")):DynamicCast("wxStaticText")
    --文字编辑窗口
    editAttrText = dialog.EditText:FindWindow(ID("EditAttrText")):DynamicCast("wxTextCtrl")
    editAttrText.FontSize = 10--文字编辑窗口字体大小
    --绑定快捷键ctrl+shift+上下键控制字体大小更改
    local accelTable = wx.wxAcceleratorTable({
        { wx.wxACCEL_CTRL + wx.wxACCEL_SHIFT, wx.WXK_UP, ID "FontSize+" },
        { wx.wxACCEL_CTRL + wx.wxACCEL_SHIFT, wx.WXK_DOWN, ID "FontSize-" },
    })
    editAttrText:SetAcceleratorTable(accelTable)
    --快捷键事件
    editAttrText:Connect(ID "FontSize+", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        if editAttrText.FontSize < 100 then
            editAttrText.FontSize = editAttrText.FontSize + 1
            editAttrText:SetFont(wx.wxFont(editAttrText.FontSize, 70, 90, 90, False, ""))
        end
    end)
    editAttrText:Connect(ID "FontSize-", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        if editAttrText.FontSize > 1 then
            editAttrText.FontSize = editAttrText.FontSize - 1
            editAttrText:SetFont(wx.wxFont(editAttrText.FontSize, 70, 90, 90, False, ""))
        end
    end)
    --设置窗口
    dialog.Setting = wx.wxDialog()
    xmlResource:LoadDialog(dialog.Setting, wx.NULL, "Setting")
    resXText = dialog.Setting:FindWindow(ID("ResXText")):DynamicCast("wxTextCtrl")
    resYText = dialog.Setting:FindWindow(ID("ResYText")):DynamicCast("wxTextCtrl")
    windowedCheckBox = dialog.Setting:FindWindow(ID("WindowedCheckBox")):DynamicCast("wxCheckBox")
    cheatCheckBox = dialog.Setting:FindWindow(ID("CheatCheckBox")):DynamicCast("wxCheckBox")
    updateLibCheckBox = dialog.Setting:FindWindow(ID("UpdateLibCheckBox")):DynamicCast("wxCheckBox")
    --
    dialog.SoundEffect = wx.wxDialog()
    xmlResource:LoadDialog(dialog.SoundEffect, wx.NULL, "Select Sound Effect")
    soundListBox = dialog.SoundEffect:FindWindow(ID("SoundListBox")):DynamicCast("wxListBox")
    --
    dialog.Type = wx.wxDialog()
    xmlResource:LoadDialog(dialog.Type, wx.NULL, "Select Type")
    typeListBox = dialog.Type:FindWindow(ID("TypeListBox")):DynamicCast("wxListBox")
    --
    dialog.Image = wx.wxDialog()
    xmlResource:LoadDialog(dialog.Image, wx.NULL, "Select Image")
    imageListBox = dialog.Image:FindWindow(ID("ImageListBox")):DynamicCast("wxListBox")
    imageString = dialog.Image:FindWindow(ID("imageString")):DynamicCast("wxTextCtrl")
    imagePrevPanel = dialog.Image:FindWindow(ID("ImagePrevPanel")):DynamicCast("wxPanel")
    --
    dialog.InputParameter = wx.wxDialog()
    xmlResource:LoadDialog(dialog.InputParameter, wx.NULL, "Input Parameter")
    for _i = 1, 16 do
        paramNameLabel[_i] = dialog.InputParameter:FindWindow(ID("ParamNameLabel" .. _i)):DynamicCast("wxStaticText")
        paramText[_i] = dialog.InputParameter:FindWindow(ID("ParamText" .. _i)):DynamicCast("wxTextCtrl")
    end
    --
    dialog.InputTypeName = wx.wxDialog()
    xmlResource:LoadDialog(dialog.InputTypeName, wx.NULL, "Input Type Name")
    typeNameText = dialog.InputTypeName:FindWindow(ID("TypeNameText")):DynamicCast("wxTextCtrl")
    difficultyCombo = dialog.InputTypeName:FindWindow(ID("DifficultyCombo")):DynamicCast("wxComboBox")
    --
    dialog.SelectEnemyStyle = wx.wxDialog()
    xmlResource:LoadDialog(dialog.SelectEnemyStyle, wx.NULL, "Select Enemy Style")
    for _i = 1, 34 do
        selectEnemyStyleButton[_i] = dialog.SelectEnemyStyle:FindWindow(ID("Style" .. _i)):DynamicCast("wxBitmapButton")
    end
    --
    dialog.SelectBulletStyle = wx.wxDialog()
    xmlResource:LoadDialog(dialog.SelectBulletStyle, wx.NULL, "Select Bullet Style")
    for _i, n in ipairs(enumType.bulletshow) do
        selectBulletStyleButton[_i] = dialog.SelectBulletStyle:FindWindow(ID(n)):DynamicCast("wxBitmapButton")
    end
    --
    dialog.SelectColor = wx.wxDialog()
    xmlResource:LoadDialog(dialog.SelectColor, wx.NULL, "Select Color")
    for _i, n in ipairs(enumType.color) do
        selectColorButton[_i] = dialog.SelectColor:FindWindow(ID(n)):DynamicCast("wxBitmapButton")
    end
    --
    local picker = {
        sound = dialog.SoundEffect,
        image = dialog.Image,
        selecttype = dialog.Type,
        param = dialog.InputParameter,
        typename = dialog.InputTypeName,
        selectenemystyle = dialog.SelectEnemyStyle,
        bulletstyle = dialog.SelectBulletStyle,
        color = dialog.SelectColor,
    }
    --
    local fileMenu = wx.wxMenu()
    fileMenu:Append(wx.wxID_NEW, "&New...")
    fileMenu:Append(wx.wxID_OPEN, "&Open...")
    fileMenu:Append(wx.wxID_SAVE, "&Save")
    fileMenu:Append(wx.wxID_SAVEAS, "Save &As...")
    fileMenu:Append(wx.wxID_CLOSE, "&Close")
    fileMenu:Append(wx.wxID_EXIT, "E&xit")

    local editMenu = wx.wxMenu()
    editMenu:Append(wx.wxID_UNDO, "&Undo")
    editMenu:Append(wx.wxID_REDO, "&Redo")
    editMenu:Append(wx.wxID_DELETE, "&Delete")
    editMenu:Append(wx.wxID_COPY, "&Copy")
    editMenu:Append(wx.wxID_CUT, "Cu&t")
    editMenu:Append(wx.wxID_PASTE, "&Paste")

    local helpMenu = wx.wxMenu()
    helpMenu:Append(wx.wxID_ABOUT, "&About")

    local menuBar = wx.wxMenuBar()
    menuBar:Append(fileMenu, "&File")
    menuBar:Append(editMenu, "&Edit")
    menuBar:Append(helpMenu, "&Help")

    frame:SetMenuBar(menuBar)
    --
    local function SetCurProjFile(s)
        curProjFile = s
        if s == nil then
            frame:SetTitle("LuaSTG Editor")
            curProjDir = nil
            ClearLog()
        else
            frame:SetTitle(curProjFile .. " - LuaSTG Editor")
            curProjDir = wx.wxFileName(curProjFile):GetPath(wx.wxPATH_GET_VOLUME)
            setting.projpath = curProjDir
            local f = io.open("editor\\EditorSetting.lua", "w")
            f:write("setting=" .. Tree.Serialize(setting))
            f:close()
            OutputLog(string.format("current project file: %s", wx.wxFileName(curProjFile):GetName()), "Info")
        end
    end
    local function SaveToFile(file)
        local f, msg = io.open(file, "w")
        if f == nil then
            return msg
        end
        local tmp = {}
        for node in Tree.Children(projectTree, rootNode) do
            table.insert(tmp, Tree.Ctrl2Data(projectTree, node))
        end
        tmp._proj_version = _luastg_version
        f:write(Tree.Serialize(tmp))
        f:close()
    end
    local function LoadFromFile(file, ignore_setting)
        local f, msg = io.open(file, "r")
        if f == nil then
            return msg
        end
        local tmp = Tree.DeSerialize(f:read("*a"))
        if tmp._proj_version and tmp._proj_version > _luastg_version then
            return 'LuaSTG version is too low.'
        end
        for _i = 1, #tmp do
            if not ignore_setting or tmp[_i]["type"] ~= "setting" then
                Tree.Data2Ctrl(projectTree, rootNode, -1, tmp[_i])
            end
        end
        f:close()
    end
    function ApplyDepth(s, depth)
        local ret = string.gsub(s, "\n", "\n" .. string.rep(' ', depth * 4))
        if string.sub(s, -1) == "\n" then
            ret = string.sub(ret, 1, -1 - depth * 4)
        end
        return string.rep(' ', depth * 4) .. ret
    end
    local auto_save_counter = 1
    local function AutoSave()
        if curProjFile then
            local msg = SaveToFile(curProjFile .. ".bak." .. (auto_save_counter % 4))
            if msg ~= nil then
                OutputLog(msg, "Error")
                return msg
            end
            auto_save_counter = auto_save_counter + 1
        end
    end
    function CompileToFile(f, node, depth)
        local data = Tree.data[node:GetValue()]
        local check = nodeType[data.type].check
        local checkafter = nodeType[data.type].checkafter
        local head = nodeType[data.type].tohead
        local foot = nodeType[data.type].tofoot
        local msg
        -- check for every attr
        for _i, v in ipairs(data.attr) do
            local checkattr = nodeType[data.type][_i][3]
            if checkattr then
                msg = checkattr(v)
                if msg ~= nil then
                    projectTree:SelectItem(node)
                    attrCombo[_i]:SetFocus()
                    return string.format("Attribute %q is invalid: %s", nodeType[data.type][_i][1], msg)
                end
            end
        end
        -- check for whole node
        if check then
            msg = check(data)
            if msg ~= nil then
                projectTree:SelectItem(node)
                return msg
            end
        end
        -- debug
        if debugNode and debugNode[2] == node:GetValue() then
            f:write('end ')
        end
        -- head
        if head then
            f:write(ApplyDepth(head(data), depth))
        end
        -- child
        for child in Tree.Children(projectTree, node) do
            msg = CompileToFile(f, child, depth + (nodeType[data.type].depth or 1))
            if msg ~= nil then
                return msg
            end
        end
        -- foot
        if foot then
            f:write(ApplyDepth(foot(data), depth))
        end
        -- debug
        if debugNode and debugNode[1] == node:GetValue() then
            f:write('if false then ')
        end
        if scDebugNode and scDebugNode:GetValue() == node:GetValue() then
            className = Tree.data[projectTree:GetItemParent(scDebugNode):GetValue()].attr[1]
            f:write(string.format("_boss_class_name=%q\n", className))
            f:write(string.format("_boss_class_sc_index=#_editor_class[%q].cards\n", className))
        end
        -- after check
        if checkafter then
            msg = checkafter(data)
            if msg ~= nil then
                projectTree:SelectItem(node)
                return msg
            end
        end
    end
    local function TreeShotUpdate()
        local tmp = {}
        for node in Tree.Children(projectTree, rootNode) do
            table.insert(tmp, Tree.Ctrl2Data(projectTree, node))
        end
        treeShotPos = treeShotPos + 1
        treeShot[treeShotPos] = tmp
        for _i = treeShotPos + 1, #treeShot do
            treeShot[_i] = nil
        end
    end
    local function SubmitAttr()
        local changed = false
        if IsValid(curNode) then
            local data = Tree.data[curNode:GetValue()]
            for _i = 1, #(data.attr) do
                if data.attr[_i] ~= attrCombo[_i]:GetValue() then
                    changed = true
                    data.attr[_i] = attrCombo[_i]:GetValue()
                end
            end
            projectTree:SetItemText(curNode, (nodeType[data.type].totext)(data))
        end
        if changed then
            TreeShotUpdate()
        end
        return changed
    end
    local function InsertNode(tree, node, data, block)
        if not curProjFile then
            return
        end
        tree:SetFocus()
        local parent, pos, ret
        if insertPos == "child" or IsRoot(node) then
            parent = node
            pos = -1
        elseif insertPos == "after" then
            parent = tree:GetItemParent(node)
            pos = node
        else
            parent = tree:GetItemParent(node)
            pos = tree:GetPrevSibling(node)
        end
        --
        local ptype
        if IsValid(parent) then
            ptype = Tree.data[parent:GetValue()]["type"]
        else
            ptype = "root"
        end
        local ctype = data.type
        if ptype ~= "root" then
            if nodeType[ptype].allowchild and not nodeType[ptype].allowchild[ctype] then
                OutputLog(string.format('can not insert %q as child of %q', ctype, ptype), "Error")
                return
            end
            if nodeType[ptype].forbidchild and nodeType[ptype].forbidchild[ctype] then
                OutputLog(string.format('can not insert %q as child of %q', ctype, ptype), "Error")
                return
            end
        end
        if nodeType[ctype].allowparent and not nodeType[ctype].allowparent[ptype] then
            OutputLog(string.format('can not insert %q as child of %q', ctype, ptype), "Error")
            return
        end
        if nodeType[ctype].forbidparent and nodeType[ctype].forbidparent[ptype] then
            OutputLog(string.format('can not insert %q as child of %q', ctype, ptype), "Error")
            return
        end
        --
        ancStack = {}
        local pnode = parent
        while IsValid(pnode) do
            table.insert(ancStack, Tree.data[pnode:GetValue()]["type"])
            pnode = tree:GetItemParent(pnode)
        end
        if not CheckAnc(data) then
            return
        end
        --
        ret = Tree.Data2Ctrl(tree, parent, pos, data)
        tree:Expand(parent)
        tree:SelectItem(ret)
        if block then
        else
            TreeShotUpdate()
            AutoSave()
        end
        --
        return ret
    end
    local function SaveProj()
        SubmitAttr()
        if curProjFile then
            local msg = SaveToFile(curProjFile)
            if msg ~= nil then
                OutputLog(msg, "Error")
                return msg
            end
            savedPos = treeShotPos
        end
    end
    local function SaveProjAs()
        SubmitAttr()
        if curProjFile then
            local fd = wx.wxFileDialog(frame, "Save project", setting.projpath, "", "LuaSTG project (*.luastg)|*.luastg|All files (*.*)|*.*", wx.wxFD_SAVE + wx.wxFD_OVERWRITE_PROMPT)
            if fd:ShowModal() == wx.wxID_OK then
                local fileName = fd:GetPath()
                local msg = SaveToFile(fileName)
                if msg == nil then
                    SetCurProjFile(fileName)
                    savedPos = treeShotPos
                else
                    OutputLog(msg, "Error")
                    return msg
                end
            end
        end
    end
    local function CloseProj(event)
        if curProjFile then
            local answer
            if savedPos ~= treeShotPos then
                answer = wx.wxMessageBox('Save file "' .. curProjFile .. '" ?', "Save", wx.wxYES_NO + wx.wxCANCEL)
            else
                answer = wx.wxNO
            end
            if answer == wx.wxYES then
                local msg = SaveProj(event)
                if msg == nil then
                    projectTree:DeleteChildren(rootNode)
                    Tree.data = {}
                    treeShot = {}
                    treeShotPos = 0
                    savedPos = 0
                    SetCurProjFile(nil)
                else
                    return msg
                end
            elseif answer == wx.wxNO then
                projectTree:DeleteChildren(rootNode)
                Tree.data = {}
                treeShot = {}
                treeShotPos = 0
                savedPos = 0
                SetCurProjFile(nil)
            elseif answer == wx.wxCANCEL then
                return "cancelled by user"
            end
        end
    end
    local function OpenProj(event)
        if curProjFile ~= nil then
            local msg = CloseProj(event)
            if msg ~= nil then
                return msg
            end
        end
        local fd = wx.wxFileDialog(frame, "Open project", setting.projpath, "", "LuaSTG project (*.luastg)|*.luastg|All files (*.*)|*.*", wx.wxFD_FILE_MUST_EXIST + wx.wxFD_OPEN)
        if fd:ShowModal() == wx.wxID_OK then
            local fileName = fd:GetPath()
            local msg = LoadFromFile(fileName)
            if msg == nil then
                SetCurProjFile(fileName)
                projectTree:Expand(rootNode)
                TreeShotUpdate()
                savedPos = 1
                projectTree:SetFocus()
            else
                OutputLog(msg, "Error")
                return msg
            end
        end
    end
    local function NewProj(event)
        if CloseProj(event) == nil then
            frame:Enable(false)
            dialog.NewProj:Show(true)
        end
    end
    local _def_node_type = { enemydefine = true, bulletdefine = true, objectdefine = true, laserdefine = true, laserbentdefine = true, rebounderdefine = true, taskdefine = true }
    local _init_node_type = { enemyinit = true, bulletinit = true, objectinit = true, laserinit = true, laserbentinit = true, rebounderinit = true }
    local function CalcParamNumAll(node)
        if _def_node_type[node.type] then
            if node.type == "taskdefine" then
                paramNumDict[node.attr[1]] = CalcParamNum(node.attr[2])
            else
                for _, v in pairs(node.child) do
                    if _init_node_type[v.type] then
                        paramNumDict[node.attr[1]] = CalcParamNum(v.attr[1])
                        break
                    end
                end
            end
        elseif node.type == 'folder' then
            for _, v in pairs(node.child) do
                CalcParamNumAll(v)
            end
        end
    end
    local function PackProj()
        if curProjFile then
            SubmitAttr()
            checkSoundName = {}
            checkImageName = {}
            checkAniName = {}
            checkParName = {}
            checkBgmName = {}
            checkAnonymous = {}
            checkResFile = {}
            checkClassName = {}
            watchDict = {}
            paramNumDict = {}
            className = nil
            difficulty = nil
            comment_n = 0
            for _, v in pairs(treeShot[treeShotPos]) do
                CalcParamNumAll(v)
            end
            for key, wdata in pairs(Tree.watch) do
                watchDict[key] = {}
                if key == "sound" then
                    for item, _ in pairs(wdata) do
                        watchDict[key][Tree.data[item].attr[2]] = true
                    end
                elseif key ~= 'image' then
                    for item, _ in pairs(wdata) do
                        watchDict[key][Tree.data[item].attr[1]] = true
                    end
                end
            end
            watchDict.imageonly = {}
            for k in pairs(Tree.watch.image) do
                if Tree.data[k]["type"] == 'loadimage' then
                    watchDict.image['image:' .. Tree.data[k].attr[2]] = true
                    watchDict.imageonly['image:' .. Tree.data[k].attr[2]] = true
                elseif Tree.data[k]["type"] == 'loadani' then
                    watchDict.image['ani:' .. Tree.data[k].attr[2]] = true
                elseif Tree.data[k]["type"] == 'loadparticle' then
                    watchDict.image['particle:' .. Tree.data[k].attr[2]] = true
                end
            end
            for child in Tree.Children(projectTree, rootNode) do
                local data = Tree.data[child:GetValue()]
                if data.type == 'setting' then
                    outputName = data.attr[1]
                    break
                end
            end
            if outputName == 'unnamed' then
                outputName = wx.wxFileName(curProjFile):GetName()
            end
            local f, msg = io.open("editor\\tmp\\_pack_res.bat", "w")
            if f == nil then
                OutputLog(msg, "Error")
                return msg
            end
            f:write('del "..\\game\\mod\\' .. outputName .. '.zip"\n')
            f:write('..\\tools\\toutf8\\toutf8 .\\editor\\tmp\\_editor_output.lua\n')
            f:write('..\\tools\\7z\\7z u -tzip -mcu=on "..\\game\\mod\\' .. outputName .. '.zip" .\\editor\\root.lua .\\editor\\tmp\\_editor_output.lua\n')
            f:close()

            f, msg = io.open("editor\\tmp\\_pack_lib.bat", "w")
            if f == nil then
                OutputLog(msg, "Error")
                return msg
            end
            f:write('mkdir "..\\libs\\' .. outputName .. '\\"\n')
            f:write('copy .\\editor\\tmp\\_editor_output.lua ..\\libs\\' .. outputName .. '\\' .. outputName .. '.lua\n')
            f:close()

            f, msg = io.open("editor\\tmp\\_editor_output.lua", "w")
            if f == nil then
                OutputLog(msg, "Error")
                return msg
            end
            local debugCode
            if isDebug and curNode then
                local taskNode = projectTree:GetItemParent(curNode)
                if Tree.data[taskNode:GetValue()]['type'] == 'stagetask' then
                    local stageNode, groupNode
                    stageNode = projectTree:GetItemParent(taskNode)
                    groupNode = projectTree:GetItemParent(stageNode)
                    debugCode = string.format("_debug_stage_name='%s@%s'\nInclude 'THlib\\\\UI\\\\debugger.lua'\n", Tree.data[stageNode:GetValue()].attr[1], Tree.data[groupNode:GetValue()].attr[1])
                    firstNode = projectTree:GetFirstChild(taskNode)
                    if firstNode:GetValue() ~= curNode:GetValue() then
                        debugNode = { firstNode:GetValue(), curNode:GetValue() }
                    end
                else
                    f:close()
                    return "must debug from direct child node of stagetask node"
                end
            end
            for child in Tree.Children(projectTree, rootNode) do
                msg = CompileToFile(f, child, 0)
                if msg then
                    f:close()
                    projectTree:SetFocus()
                    return msg
                end
            end
            if debugCode then
                f:write(debugCode)
            end
            if scDebugNode then
                f:write("Include 'THlib\\\\UI\\\\scdebugger.lua'\n")
            end
            f:close()
            if projectmode == 'lib' then
                os.execute('editor\\tmp\\_pack_lib.bat > pack_log.txt')
            else
                os.execute('editor\\tmp\\_pack_res.bat > pack_log.txt')
            end
        end
    end
    local function OnQuit(event)
        local msg = CloseProj(event)
        if msg == nil then
            event:Skip()
            wx.wxExit()
        end
    end
    local function ToolUndo()
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if treeShot[treeShotPos - 1] then
                treeShotPos = treeShotPos - 1
                projectTree:DeleteChildren(rootNode)
                Tree.data = {}
                for _i = 1, #(treeShot[treeShotPos]) do
                    Tree.Data2Ctrl(projectTree, rootNode, -1, treeShot[treeShotPos][_i])
                end
            end
        end
    end
    local function ToolRedo()
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if treeShot[treeShotPos + 1] then
                treeShotPos = treeShotPos + 1
                projectTree:DeleteChildren(rootNode)
                Tree.data = {}
                for _i = 1, #(treeShot[treeShotPos]) do
                    Tree.Data2Ctrl(projectTree, rootNode, -1, treeShot[treeShotPos][_i])
                end
            end
        end
    end
    local function ToolDelete()
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if IsValid(curNode) and not nodeType[Tree.data[curNode:GetValue()]["type"]].forbiddelete then
                projectTree:Delete(curNode)
                TreeShotUpdate()
            end
        end
    end
    local function ToolCopy()
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if IsValid(curNode) then
                SetClipboard("\001LuaSTG" .. Tree.Serialize(Tree.Ctrl2Data(projectTree, curNode)))
            end
        end
    end
    local function ToolMove(mode)
        local flag = false
        local cp = ''
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if IsValid(curNode) then
                cp = Tree.Serialize(Tree.Ctrl2Data(projectTree, curNode))
                flag = true
            end
        end
        if not flag then
            return false
        end
        local lastmode = insertPos
        local node0 = curNode
        --local node2 = curNode
        local node1 = curNode
        --local root0 = projectTree:GetRootItem()

        if lastmode == 'child' then
            local flag2 = true
            if mode == 'up' then
                insertPos = 'child'
                node0 = projectTree:GetPrevSibling(curNode)
                if not IsValid(node0) then
                    flag2 = false
                end
            end
            if mode == 'down' then
                insertPos = 'before'
                node0 = projectTree:GetNextSibling(curNode)
                if not IsValid(node0) then
                    flag2 = false
                end
                if projectTree:GetChildrenCount(node0) > 0 then
                    node0 = projectTree:GetFirstChild(node0)
                else
                    insertPos = 'child'
                end
            end
            if flag2 then
                local s = InsertNode(projectTree, node0, Tree.DeSerialize(cp), true)
                if s ~= nil then
                    projectTree:Delete(node1)
                    TreeShotUpdate()
                    insertPos = lastmode
                    return true
                end

            end
        end
        if mode == 'up' then
            insertPos = 'before'
            node0 = projectTree:GetPrevSibling(curNode)
            if not IsValid(node0) then
                node0 = projectTree:GetItemParent(curNode)
            end
        end
        if mode == 'down' then
            insertPos = 'after'
            node0 = projectTree:GetNextSibling(curNode)
            if not IsValid(node0) then
                node0 = projectTree:GetItemParent(curNode)
            end
        end
        local s = InsertNode(projectTree, node0, Tree.DeSerialize(cp), true)
        if s ~= nil then
            projectTree:Delete(node1)
            TreeShotUpdate()
            insertPos = lastmode
            return true
        end
        insertPos = lastmode
        return false
    end
    local function ToolCut()
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if IsValid(curNode) and not nodeType[Tree.data[curNode:GetValue()]["type"]].forbiddelete then
                SetClipboard("\001LuaSTG" .. Tree.Serialize(Tree.Ctrl2Data(projectTree, curNode)))
                projectTree:Delete(curNode)
                TreeShotUpdate()
            end
        end
    end
    local function ToolPaste()
        if frame:FindFocus():GetId() == projectTree:GetId() then
            if IsValid(curNode) or IsRoot(curNode) then
                local cp = GetClipboard()
                if cp and string.sub(cp, 1, 7) == "\001LuaSTG" then
                    InsertNode(projectTree, curNode, Tree.DeSerialize(string.sub(cp, 8, -1)))
                end
            end
        end
    end
    --
    frame:Connect(wx.wxID_NEW, wx.wxEVT_COMMAND_MENU_SELECTED, NewProj)
    frame:Connect(wx.wxID_CLOSE, wx.wxEVT_COMMAND_MENU_SELECTED, CloseProj)
    frame:Connect(wx.wxID_SAVEAS, wx.wxEVT_COMMAND_MENU_SELECTED, SaveProjAs)
    frame:Connect(wx.wxID_OPEN, wx.wxEVT_COMMAND_MENU_SELECTED, OpenProj)
    frame:Connect(wx.wxID_SAVE, wx.wxEVT_COMMAND_MENU_SELECTED, SaveProj)
    frame:Connect(wx.wxID_EXIT, wx.wxEVT_COMMAND_MENU_SELECTED, function()
        frame:Close(true)
    end)
    frame:Connect(wx.wxEVT_CLOSE_WINDOW, OnQuit)
    frame:Connect(wx.wxID_UNDO, wx.wxEVT_COMMAND_MENU_SELECTED, ToolUndo)
    frame:Connect(wx.wxID_REDO, wx.wxEVT_COMMAND_MENU_SELECTED, ToolRedo)
    frame:Connect(wx.wxID_DELETE, wx.wxEVT_COMMAND_MENU_SELECTED, ToolDelete)
    frame:Connect(wx.wxID_COPY, wx.wxEVT_COMMAND_MENU_SELECTED, ToolCopy)
    frame:Connect(wx.wxID_CUT, wx.wxEVT_COMMAND_MENU_SELECTED, ToolCut)
    frame:Connect(wx.wxID_PASTE, wx.wxEVT_COMMAND_MENU_SELECTED, ToolPaste)
    --
    accelTable = wx.wxAcceleratorTable({
        { wx.wxACCEL_CTRL, string.byte('N'), wx.wxID_NEW },
        { wx.wxACCEL_CTRL, string.byte('O'), wx.wxID_OPEN },
        { wx.wxACCEL_CTRL, string.byte('S'), wx.wxID_SAVE },
        { wx.wxACCEL_CTRL + wx.wxACCEL_SHIFT, string.byte('S'), wx.wxID_SAVEAS },
        { wx.wxACCEL_CTRL, string.byte('W'), wx.wxID_CLOSE },
        { wx.wxACCEL_CTRL, string.byte('Z'), wx.wxID_UNDO },
        { wx.wxACCEL_CTRL, string.byte('Y'), wx.wxID_REDO },
        { wx.wxACCEL_NORMAL, wx.WXK_DELETE, wx.wxID_DELETE },
        { wx.wxACCEL_CTRL, string.byte('C'), wx.wxID_COPY },
        { wx.wxACCEL_CTRL, string.byte('X'), wx.wxID_CUT },
        { wx.wxACCEL_CTRL, string.byte('V'), wx.wxID_PASTE },
        { wx.wxACCEL_NORMAL, wx.WXK_F7, ID "ToolPack" },
        { wx.wxACCEL_NORMAL, wx.WXK_F6, ID "ToolDebugStage" },
        { wx.wxACCEL_SHIFT, wx.WXK_F6, ID "ToolDebugSC" },
        { wx.wxACCEL_NORMAL, wx.WXK_F5, ID "ToolRun" },
        { wx.wxACCEL_ALT, wx.WXK_UP, ID "ToolMoveUp" },
        { wx.wxACCEL_ALT, wx.WXK_DOWN, ID "ToolMoveDown" },
        --{wx.wxACCEL_ALT,wx.WXK_RIGHT,ID"ToolInsertChild"}
    })
    frame:SetAcceleratorTable(accelTable)
    --
    frame:Connect(ID "ToolNew", wx.wxEVT_COMMAND_TOOL_CLICKED, NewProj)
    frame:Connect(ID "ToolOpen", wx.wxEVT_COMMAND_TOOL_CLICKED, OpenProj)
    frame:Connect(ID "ToolSave", wx.wxEVT_COMMAND_TOOL_CLICKED, SaveProj)
    frame:Connect(ID "ToolMerge", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        local fd = wx.wxFileDialog(frame, "Open project", setting.projpath, "", "LuaSTG project (*.luastg)|*.luastg|All files (*.*)|*.*", wx.wxFD_FILE_MUST_EXIST + wx.wxFD_OPEN)
        if fd:ShowModal() == wx.wxID_OK then
            local fileName = fd:GetPath()
            local msg = LoadFromFile(fileName, true)
            if msg == nil then
                TreeShotUpdate()
                projectTree:SetFocus()
            else
                OutputLog(msg, "Error")
                return msg
            end
        end
    end)
    --
    frame:Connect(ID "ToolSetting", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        resXText:SetValue(tostring(setting.resx))
        resYText:SetValue(tostring(setting.resy))
        windowedCheckBox:SetValue(setting.windowed)
        cheatCheckBox:SetValue(setting.cheat)
        updateLibCheckBox:SetValue(setting.updatelib)
        dialog.Setting:Show(true)
    end)
    dialog.Setting:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        if tonumber(resXText:GetValue()) == nil or tonumber(resYText:GetValue()) == nil then
            wx.wxMessageBox("Resolution must be number", "Error", wx.wxICON_ERROR)
            return
        end
        setting.resx = tonumber(resXText:GetValue())
        setting.resy = tonumber(resYText:GetValue())
        setting.windowed = windowedCheckBox:GetValue()
        setting.cheat = cheatCheckBox:GetValue()
        setting.updatelib = updateLibCheckBox:GetValue()
        local f = io.open("editor\\EditorSetting.lua", "w")
        f:write("setting=" .. Tree.Serialize(setting))
        f:close()
        event:Skip()
    end)
    frame:Connect(ID "ToolPack", wx.wxEVT_COMMAND_TOOL_CLICKED, function(event)
        isDebug = false
        debugNode = nil
        scDebugNode = nil
        local msg = PackProj(event)
        if msg ~= nil then
            OutputLog(msg, "Error")
        end
    end)
    local function LaunchGame()
        os.execute(string.format('cd "..\\game\\" && start /b ..\\game\\LuaSTGPlus.dev.exe "start_game=true is_debug=true setting.nosplash=true setting.windowed=%s setting.resx=%s setting.resy=%s cheat=%s updatelib=%s setting.mod=\'%s\'"',
                tostring(setting.windowed), tostring(setting.resx), tostring(setting.resy), tostring(setting.cheat), tostring(setting.updatelib), outputName))
    end
    frame:Connect(ID "ToolRun", wx.wxEVT_COMMAND_TOOL_CLICKED, function(event)
        if curProjFile then
            isDebug = false
            debugNode = nil
            scDebugNode = nil
            local msg = PackProj(event)
            if msg == nil then
                LaunchGame()
            else
                OutputLog(msg, "Error")
            end
        end
    end)
    frame:Connect(ID "ToolDebugStage", wx.wxEVT_COMMAND_TOOL_CLICKED, function(event)
        if curProjFile then
            isDebug = true
            debugNode = nil
            scDebugNode = nil
            local msg = PackProj(event)
            if msg == nil then
                LaunchGame()
            else
                OutputLog(msg, "Error")
            end
        end
    end)
    frame:Connect(ID "ToolDebugSC", wx.wxEVT_COMMAND_TOOL_CLICKED, function(event)
        if curProjFile then
            isDebug = false
            debugNode = nil
            scDebugNode = curNode
            if Tree.data[scDebugNode:GetValue()]['type'] ~= 'bossspellcard' then
                OutputLog('current node is not a spell card node', "Error")
            else
                local msg = PackProj(event)
                if msg == nil then
                    LaunchGame()
                else
                    OutputLog(msg, "Error")
                end
            end
        end
    end)
    local function CountEnter(s)
        local _, n = string.gsub(s, "\n", "\n")
        lineNum = lineNum - n
    end
    local function FindNode(node)
        local data = Tree.data[node:GetValue()]
        local head = nodeType[data.type].tohead
        local foot = nodeType[data.type].tofoot
        if head then
            CountEnter(head(data))
        end
        if lineNum <= 0 then
            projectTree:SelectItem(node)
            return true
        end
        for child in Tree.Children(projectTree, node) do
            if FindNode(child) then
                return true
            end
        end
        if foot then
            CountEnter(foot(data))
        end
        if lineNum <= 0 then
            projectTree:SelectItem(node)
            return true
        end
    end
    local function GoToLineNum()
        if curProjFile then
            lineNum = tonumber(lineNumText:GetValue())
            if lineNum == nil then
                wx.wxMessageBox("Must input an integer", "Error", wx.wxICON_ERROR)
                lineNumText:SetValue("")
                return
            end
            comment_n = 0--OLC comment fix
            for child in Tree.Children(projectTree, rootNode) do
                if FindNode(child) then
                    projectTree:SetFocus()
                    return
                end
            end
            wx.wxMessageBox("End of project is reached", "Info", wx.wxICON_INFORMATION)
        end
    end
    frame:Connect(ID "ToolFind", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        GoToLineNum()
    end)
    lineNumText:Connect(wx.wxEVT_COMMAND_TEXT_ENTER, function()
        GoToLineNum()
    end)
    --
    frame:Connect(ID "ToolDelete", wx.wxEVT_COMMAND_TOOL_CLICKED, ToolDelete)
    frame:Connect(ID "ToolCopy", wx.wxEVT_COMMAND_TOOL_CLICKED, ToolCopy)
    frame:Connect(ID "ToolCut", wx.wxEVT_COMMAND_TOOL_CLICKED, ToolCut)
    frame:Connect(ID "ToolPaste", wx.wxEVT_COMMAND_TOOL_CLICKED, ToolPaste)
    frame:Connect(ID "ToolUndo", wx.wxEVT_COMMAND_TOOL_CLICKED, ToolUndo)
    frame:Connect(ID "ToolRedo", wx.wxEVT_COMMAND_TOOL_CLICKED, ToolRedo)
    --
    frame:Connect(ID "ToolInsertAfter", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        insertPos = "after"
    end)
    frame:Connect(ID "ToolInsertBefore", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        insertPos = "before"
    end)
    frame:Connect(ID "ToolInsertChild", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        insertPos = "child"
    end)
    --
    frame:Connect(ID "ToolMoveUp", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        ToolMove('up')
    end)
    frame:Connect(ID "ToolMoveDown", wx.wxEVT_COMMAND_TOOL_CLICKED, function()
        ToolMove('down')
    end)
    dialog.NewProj:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        local fileName = filePickerNewProj:GetPath()
        if fileName == "" then
            wx.wxMessageBox("Specify file path and name first", "Error", wx.wxICON_ERROR)
            return
        end
        local msg = LoadFromFile("editor\\templates\\" .. templates[listTemplate:GetSelection() + 1][2])
        --if string.sub(fileName, -7)~=".luastg" then
        --    fileName="project\\"..fileName..".luastg"
        --end
        if msg == nil then
            local msg2 = SaveToFile(fileName)
            if msg2 == nil then
                projectTree:Expand(rootNode)
                SetCurProjFile(fileName)
                frame:Enable(true)
                TreeShotUpdate()
                savedPos = 1
                event:Skip()
            else
                Tree.data = {}
                projectTree:DeleteChildren(rootNode)
                OutputLog(msg2, "Error")
            end
        else
            OutputLog(msg, "Error")
        end
    end)
    dialog.NewProj:Connect(wx.wxID_CANCEL, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        frame:Enable(true)
        event:Skip()
    end)
    local function EditAttr()
        local data = Tree.data[curNode:GetValue()]
        if data then
            local enum = nodeType[data.type][attrIndex][2]
            if picker[enum] then
                picker[enum]:Show(true)
            elseif enum == "resfile" then
                local wildCard
                if data.type == 'loadsound' or data.type == 'loadbgm' then
                    wildCard = "Audio file (*.wav;*.ogg)|*.wav;*.ogg"
                elseif data.type == 'loadimage' or data.type == 'loadani' or data.type == 'bossdefine' or data.type == 'bossexdefine' then
                    wildCard = "Image file (*.png;*.jpg;*.bmp)|*.png;*.jpg;*.bmp"
                elseif data.type == 'loadparticle' then
                    wildCard = "Particle system info file (*.psi)|*.psi"
                elseif data.type == 'patch' then
                    wildCard = "Lua file (*.lua)|*.lua"
                elseif data.type == 'loadFX' then
                    wildCard = "FX file (*.fx)|*.fx"
                else
                    wildCard = "All types (*.*)|*.*"
                end
                local fd = wx.wxFileDialog(frame, "Select resource file", curProjDir, "", wildCard, wx.wxFD_FILE_MUST_EXIST + wx.wxFD_OPEN)
                if fd:ShowModal() == wx.wxID_OK then
                    local fn = wx.wxFileName(fd:GetPath())
                    if not fn:MakeRelativeTo(curProjDir) then
                        OutputLog("It is recommended that resource file path is relative to project path.", "Warning")
                    end
                    if data.type == 'bossdefine' or data.type == 'bossexdefine' then
                        attrCombo[5]:SetValue(fn:GetFullPath())
                    elseif data.type == 'patch' then
                        attrCombo[1]:SetValue(fn:GetFullPath())
                    elseif data.type == 'FileAddIntoPack' then
                        attrCombo[1]:SetValue(fn:GetFullPath())
                    else
                        attrCombo[1]:SetValue(fn:GetFullPath())
                        attrCombo[2]:SetValue(fn:GetName())
                        if data.type == 'loadparticle' then
                            local f, msg = io.open(fd:GetPath(), 'rb')
                            if f == nil then
                                OutputLog(msg, "Error")
                            else
                                local s = f:read(1)
                                f:close()
                                attrCombo[3]:SetValue('parimg' .. (string.byte(s, 1) + 1))
                            end
                        end
                    end
                    SubmitAttr()
                end
            else
                dialog.EditText:Show(true)
            end
        end
    end
    projectTree:Connect(wx.wxEVT_COMMAND_TREE_SEL_CHANGED, function(event)
        SubmitAttr()
        curNode = event:GetItem()
        if curNode:GetValue() ~= rootNode:GetValue() then
            local data = Tree.data[curNode:GetValue()]
            typeNameLabel:SetLabel("Node type: " .. nodeType[data["type"]].disptype)
            for _i = 1, #(data.attr) do
                attrLabel[_i]:SetLabel(nodeType[data["type"]][_i][1])
                attrCombo[_i]:Clear()
                for _, v in ipairs(enumType[nodeType[data["type"]][_i][2]]) do
                    attrCombo[_i]:Append(v)
                end
                attrCombo[_i]:SetValue(data.attr[_i])
                attrButton[_i]:Enable(true)
                local enum = nodeType[data["type"]][_i][2]
                if picker[enum] or enum == 'resfile' then
                    attrButton[_i]:SetLabel("...")
                    attrCombo[_i]:Enable(true)
                else
                    attrButton[_i]:SetLabel(" . ")
                    attrCombo[_i]:Enable(true)
                end
            end
            for _i = #(data.attr) + 1, 15 do
                attrLabel[_i]:SetLabel("")
                attrCombo[_i]:SetValue("")
                attrCombo[_i]:Enable(false)
                attrButton[_i]:Enable(false)
                attrButton[_i]:SetLabel(" . ")
            end
            if data.attr[1] == "" and nodeType[data["type"]].editfirst then
                attrIndex = 1
                EditAttr(event)
            end
        else
            typeNameLabel:SetLabel("Node type: project")
            for _i = 1, 15 do
                attrLabel[_i]:SetLabel("")
                attrCombo[_i]:SetValue("")
                attrCombo[_i]:Enable(false)
                attrButton[_i]:Enable(false)
                attrButton[_i]:SetLabel("...")
            end
        end
    end)
    projectTree:Connect(wx.wxEVT_COMMAND_TREE_DELETE_ITEM, function(event)
        local item_id = event:GetItem():GetValue()
        if nodeType[Tree.data[item_id]["type"]].watch then
            Tree.watch[nodeType[Tree.data[item_id]["type"]].watch][item_id] = nil
        end
        Tree.data[item_id] = nil
        event:Skip()
    end)
    projectTree:Connect(wx.wxEVT_KEY_DOWN, function(event)
        if event:GetKeyCode() == wx.WXK_RETURN and IsValid(curNode) then
            if #(Tree.data[curNode:GetValue()].attr) ~= 0 then
                attrIndex = 1
                EditAttr(event)
            end
        end
        event:Skip()
    end)
    projectTree:Connect(wx.wxEVT_COMMAND_TREE_ITEM_RIGHT_CLICK, function(event)
        projectTree:SelectItem(event:GetItem())
        if IsValid(curNode) then
            if #(Tree.data[curNode:GetValue()].attr) ~= 0 then
                attrIndex = 1
                EditAttr(event)
            end
        end
        event:Skip()
    end)
    --
    for _i = 1, 15 do
        attrCombo[_i]:Connect(wx.wxEVT_KEY_UP, function(event)
            if event:GetKeyCode() == wx.WXK_ESCAPE and IsValid(curNode) then
                local data = Tree.data[curNode:GetValue()]
                attrCombo[_i]:SetValue(data.attr[_i])
            end
        end)
        attrCombo[_i]:Connect(wx.wxEVT_COMMAND_TEXT_ENTER, function()
            SubmitAttr()
        end)
    end
    --
    for _i = 1, 15 do
        attrButton[_i]:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
            attrIndex = _i
            EditAttr(event)
        end)
    end
    --
    dialog.EditText:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        attrCombo[attrIndex]:SetValue(editAttrText:GetValue())
        SubmitAttr()
        event:Skip()
    end)
    dialog.EditText:Connect(wx.wxEVT_SHOW, function(event)
        if dialog.EditText:IsShown() then
            editAttrLabel:SetLabel(attrLabel[attrIndex]:GetLabel())
            editAttrText:SetValue(attrCombo[attrIndex]:GetValue())
        end
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    accelTable = wx.wxAcceleratorTable({
        { wx.wxACCEL_CTRL, wx.WXK_RETURN, wx.wxID_OK },
    })
    dialog.EditText:SetAcceleratorTable(accelTable)
    --
    dialog.SoundEffect:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        if soundListBox:GetStringSelection() ~= "" then
            attrCombo[attrIndex]:SetValue(soundListBox:GetStringSelection())
        end
        SubmitAttr()
        event:Skip()
    end)
    dialog.SoundEffect:Connect(wx.wxEVT_COMMAND_LISTBOX_SELECTED, function(event)
        local sel = soundListBox:GetStringSelection()
        if resList.snd[sel] then
            wx.wxSound.Play(SEpath .. resList.snd[sel])
        else
            wx.wxSound.Play(MakeFullPath(soundList[sel]))
        end
        event:Skip()
    end)
    dialog.SoundEffect:Connect(wx.wxEVT_SHOW, function(event)
        if dialog.SoundEffect:IsShown() then
            soundListBox:Clear()
            for k in pairs(resList.snd) do
                soundListBox:Append(k)
            end
            soundList = {}
            for k in pairs(Tree.watch.sound) do
                soundListBox:Append(Tree.data[k].attr[2])
                soundList[Tree.data[k].attr[2]] = Tree.data[k].attr[1]
            end
            soundListBox:SetStringSelection(attrCombo[attrIndex]:GetValue())
        end
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    --
    dialog.Type:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        if typeListBox:GetStringSelection() ~= "" then
            attrCombo[attrIndex]:SetValue(typeListBox:GetStringSelection())
        end
        SubmitAttr()
        event:Skip()
    end)
    dialog.Type:Connect(wx.wxEVT_SHOW, function(event)
        if dialog.Type:IsShown() then
            typeListBox:Clear()
            local watch
            local t = Tree.data[curNode:GetValue()]["type"]
            if t == 'enemycreate' then
                watch = 'enemydefine'
            elseif t == 'bosscreate' then
                watch = 'bossdefine'
            elseif t == 'bulletcreate' then
                watch = 'bulletdefine'
            elseif t == 'objectcreate' then
                watch = 'objectdefine'
            elseif t == 'lasercreate' then
                watch = 'laserdefine'
            elseif t == 'laserbentcreate' then
                watch = 'laserbentdefine'
            elseif t == 'bossdefine' then
                watch = 'bgdefine'
            elseif t == 'bossexdefine' then
                watch = 'bgdefine'
            elseif t == 'reboundercreate' then
                watch = 'rebounder'
            elseif t == 'taskattach' then
                watch = 'taskdefine'
            else
                --
            end
            local list = {}
            local function append(s)
                if not list[s] then
                    list[s] = true
                    typeListBox:Append(s)
                end
            end
            if t ~= 'bossdefine' and t ~= 'bossexdefine' then
                for k in pairs(Tree.watch[watch]) do
                    local tmp = string.match(Tree.data[k].attr[1], '^(.+):.+$')
                    if tmp then
                        append(tmp)
                    else
                        append(Tree.data[k].attr[1])
                    end
                end
            else
                for k in pairs(Tree.watch[watch]) do
                    append(Tree.data[k].attr[1])
                end
            end
            typeListBox:SetStringSelection(attrCombo[attrIndex]:GetValue())
        end
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    --
    dialog.InputParameter:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        local plist = {}
        for _i = 1, 16 do
            if paramText[_i]:IsEditable() then
                if paramText[_i]:GetValue() == "" then
                    table.insert(plist, "nil")
                else
                    table.insert(plist, paramText[_i]:GetValue())
                end
            end
        end
        attrCombo[attrIndex]:SetValue(table.concat(plist, ","))
        SubmitAttr()
        event:Skip()
    end)
    local function SplitParam(s)
        if string.match(s, "^[%s]*$") then
            return {}
        end
        local pos = { 0 }
        local ret = {}
        local b1 = 0
        local b2 = 0
        for _i = 1, #s do
            local c = string.byte(s, _i)
            if b1 == 0 and b2 == 0 and c == 44 then
                table.insert(pos, _i)
            elseif c == 40 then
                b1 = b1 + 1
            elseif c == 41 then
                b1 = b1 - 1
            elseif c == 123 then
                b2 = b2 + 1
            elseif c == 125 then
                b2 = b2 - 1
            end
        end
        table.insert(pos, #s + 1)
        for _i = 1, #pos - 1 do
            table.insert(ret, string.sub(s, pos[_i] + 1, pos[_i + 1] - 1):match("^%s*(.-)%s*$"))
        end
        return ret
    end
    local function FindNodeByTypeName(node, tname)
        if _def_node_type[node.type] then
            if node.attr[1] == tname then
                return node
            else
                return
            end
        else
            local ret
            for _, v in pairs(node.child) do
                ret = FindNodeByTypeName(v, tname)
                if ret then
                    return ret
                end
            end
        end
    end
    local function FindDifficulty(node)
        while true do
            if node:GetValue() == rootNode:GetValue() then
                break
            end
            if _def_node_type[Tree.data[node:GetValue()].type] then
                return string.match(Tree.data[node:GetValue()].attr[1], '^.+:(.+)$')
            elseif Tree.data[node:GetValue()].type == 'stagegroup' then
                return Tree.data[node:GetValue()].attr[1]
            end
            node = projectTree:GetItemParent(node)
        end
    end
    dialog.InputParameter:Connect(wx.wxEVT_SHOW, function(event)
        if dialog.InputParameter:IsShown() then
            local tname = Tree.data[curNode:GetValue()].attr[1]
            local tnamefull
            local plist = Tree.data[curNode:GetValue()].attr[attrIndex]
            local diff = FindDifficulty(curNode)
            local ret

            if diff then
                tnamefull = tname .. ":" .. diff
                for _, v in pairs(treeShot[treeShotPos]) do
                    ret = FindNodeByTypeName(v, tnamefull)
                    if ret then
                        break
                    end
                end
            end

            if not ret then
                for _, v in pairs(treeShot[treeShotPos]) do
                    ret = FindNodeByTypeName(v, tname)
                    if ret then
                        break
                    end
                end
            end

            if ret then

                if ret.type == 'taskdefine' then

                    local ret2 = SplitParam(ret.attr[2])
                    local ret3 = SplitParam(plist)
                    for _i = 1, #ret2 do
                        paramNameLabel[_i]:SetLabel(ret2[_i])
                        paramText[_i]:SetValue(ret3[_i] or "")
                        paramText[_i]:SetEditable(true)
                    end
                    for _i = #ret2 + 1, 16 do
                        paramNameLabel[_i]:SetLabel("")
                        paramText[_i]:SetValue("")
                        paramText[_i]:SetEditable(false)
                    end

                else
                    for _, v in pairs(ret.child) do
                        if _init_node_type[v.type] then
                            local ret2 = SplitParam(v.attr[1])
                            local ret3 = SplitParam(plist)
                            for i = 1, #ret2 do
                                paramNameLabel[i]:SetLabel(ret2[i])
                                paramText[i]:SetValue(ret3[i] or "")
                                paramText[i]:SetEditable(true)
                            end
                            for i = #ret2 + 1, 16 do
                                paramNameLabel[i]:SetLabel("")
                                paramText[i]:SetValue("")
                                paramText[i]:SetEditable(false)
                            end
                        end
                    end
                end
            else
                paramNameLabel[1]:SetLabel("Parameters")
                paramText[1]:SetValue(plist)
                paramText[1]:SetEditable(true)
                for i = 2, 16 do
                    paramNameLabel[i]:SetLabel("")
                    paramText[i]:SetValue("")
                    paramText[i]:SetEditable(false)
                end
                OutputLog(string.format("Type %q not found", tname), 'warning')
            end
        end

        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    --
    --[[
	dialog.InputTypeName=wx.wxDialog()
	xmlResource:LoadDialog(dialog.InputTypeName,wx.NULL,"Input Type Name")
	typeNameText=dialog.InputTypeName:FindWindow(ID("TypeNameText")):DynamicCast("wxTextCtrl")
	difficultyCombo=dialog.InputTypeName:FindWindow(ID("DifficultyCombo")):DynamicCast("wxComboBox")
	--]]
    dialog.InputTypeName:Connect(wx.wxEVT_SHOW, function(event)
        if dialog.InputTypeName:IsShown() then
            local tname = Tree.data[curNode:GetValue()].attr[1]
            local t1 = string.match(tname, '^(.+):.+$')
            local t2 = string.match(tname, '^.+:(.+)$')
            if t1 then
                typeNameText:SetValue(t1)
                difficultyCombo:SetValue(t2)
            else
                typeNameText:SetValue(tname)
                difficultyCombo:SetValue("All")
            end
        end
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    dialog.InputTypeName:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        if difficultyCombo:GetValue() == 'All' or string.match(difficultyCombo:GetValue(), "^[%s]*$") then
            attrCombo[attrIndex]:SetValue(typeNameText:GetValue())
        else
            attrCombo[attrIndex]:SetValue(typeNameText:GetValue() .. ":" .. difficultyCombo:GetValue())
        end
        SubmitAttr()
        event:Skip()
    end)
    --
    dialog.Image:Connect(wx.wxID_OK, wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        if imageListBox:GetStringSelection() ~= "" then
            attrCombo[attrIndex]:SetValue(imageListBox:GetStringSelection() .. imageString:GetValue())
        end
        SubmitAttr()
        event:Skip()
    end)

    local function ImagePrevPanelPaint(event, x, y)
        local sel = imageListBox:GetStringSelection()
        local panel_dc = wx.wxClientDC(imagePrevPanel)
        panel_dc:DrawBitmap(bitmapBackground, 0, 0, false)
        if imageList[sel] then
            local cur_bmp = wx.wxBitmap(MakeFullPath(imageList[sel]))
            local scale = 1
            local imagew = cur_bmp:GetWidth()
            local imageh = cur_bmp:GetHeight()
            local scale0 = imagew
            if imageh > imagew then
                scale0 = imageh
            end
            scale0 = scale0 / 256

            if scale0 > 0 then
                if scale0 > 1.0 then
                    scale = (0.9) / scale0
                end
                while scale0 < 0.5 do
                    scale0 = scale0 * 2
                    scale = scale * 2
                end
            end
            imagew = imagew * scale
            imageh = imageh * scale

            panel_dc:SetDeviceOrigin(128, 128)
            panel_dc:SetUserScale(scale, scale)

            panel_dc:DrawBitmap(cur_bmp, 0 - cur_bmp:GetWidth() / 2, 0 - cur_bmp:GetHeight() / 2, true)

            panel_dc:SetDeviceOrigin(0, 0)
            panel_dc:SetUserScale(1, 1)

            local pen = wx.wxPen('red', 2, wx.wxSOLID)
            panel_dc:SetPen(pen)
            local x1 = 128 - cur_bmp:GetWidth() / 2 * scale
            local x2 = 128 + cur_bmp:GetWidth() / 2 * scale
            local y1 = 128 - cur_bmp:GetHeight() / 2 * scale
            local y2 = 128 + cur_bmp:GetHeight() / 2 * scale

            local p = imageString:GetValue()
            if ImageRW[sel] then
                local nx = ImageRW[sel].r
                local ny = ImageRW[sel].w
                local w0 = (x2 - x1) / nx
                local h0 = (y2 - y1) / ny
                local nn = tonumber(p)
                if x ~= nil then
                    local ix = math.floor((x - x1) / w0)
                    local iy = math.floor((y - y1) / h0)
                    if ix < 0 or ix >= nx or iy < 0 or iy >= ny then
                        nn = 0
                        p = ''
                    else
                        nn = 1 + ix + iy * nx
                        p = '' .. nn
                    end
                    imageString:SetValue(p)
                end
                if nn ~= nil and nn > 0 then
                    local ix = (nn - 1) % nx
                    local iy = math.floor((nn - 1) / nx)

                    x2 = x1 + w0 * (ix + 1)
                    x1 = x1 + w0 * ix
                    y2 = y1 + h0 * (iy + 1)
                    y1 = y1 + h0 * iy
                end
            end

            panel_dc:DrawLine(x1, y1, x2, y1)
            panel_dc:DrawLine(x2, y2, x2, y1)
            panel_dc:DrawLine(x2, y2, x1, y2)
            panel_dc:DrawLine(x1, y1, x1, y2)
        end
        event:Skip()
    end
    function GetNumInStringBack(str)
        local i = string.len(str)
        local iz = i
        local z = ''
        for ii = i, 1, -1 do
            local c = string.sub(str, ii, ii)
            if c >= '0' and c <= '9' then
                iz = ii - 1
                z = c .. z
            else
                break
            end
        end
        if iz == i then
            return str, 0, ''
        else
            return string.sub(str, 1, iz), tonumber(z), z
        end
    end
    dialog.Image:Connect(wx.wxEVT_COMMAND_LISTBOX_SELECTED, function(event)
        ImagePrevPanelPaint(event)
    end)
    dialog.Image:Connect(wx.wxEVT_PAINT, function(event)
        ImagePrevPanelPaint(event)
    end)
    imageString:Connect(wx.wxEVT_KEY_UP, function(event)
        ImagePrevPanelPaint(event)
    end)
    imageString:Connect(wx.wxEVT_COMMAND_TEXT_ENTER, function(event)
        ImagePrevPanelPaint(event)
    end)
    dialog.Image:Connect(wx.wxEVT_COMMAND_TEXT_ENTER, function(event)
        ImagePrevPanelPaint(event)
    end)
    imagePrevPanel:Connect(wx.wxEVT_LEFT_DOWN, function(event)
        local x = event:GetX()
        local y = event:GetY()
        ImagePrevPanelPaint(event, x, y)
    end)
    dialog.Image:Connect(wx.wxEVT_SHOW, function(event)
        if dialog.Image:IsShown() then
            ImageRW = {}
            local imgonly = false
            if Tree.data[curNode:GetValue()]["type"] == 'loadparticle' or Tree.data[curNode:GetValue()]["type"] == 'bglayer' then
                imgonly = true
            end
            imageListBox:Clear()
            imageList = {}
            local _find = false
            local current = attrCombo[attrIndex]:GetValue()
            if imgonly then
                for k in pairs(Tree.watch.image) do
                    if Tree.data[k]["type"] == 'loadimage' then
                        if ('image:' .. Tree.data[k].attr[2] == current) then
                            _find = true
                        end
                        imageListBox:Append('image:' .. Tree.data[k].attr[2])
                        imageList['image:' .. Tree.data[k].attr[2]] = Tree.data[k].attr[1]
                    elseif Tree.data[k]["type"] == 'loadimagegroup' then
                        local img = 'image:' .. Tree.data[k].attr[2]
                        imageListBox:Append(img)
                        imageList[img] = Tree.data[k].attr[1]
                        ImageRW[img] = {}
                        local rw = Tree.data[k].attr[4]
                        k = loadstring('return ' .. rw)
                        local r = 1
                        local w = 1
                        r, w = k()
                        ImageRW[img].r = r
                        ImageRW[img].w = w
                    end
                end
            else
                for k in pairs(Tree.watch.image) do
                    if Tree.data[k]["type"] == 'loadimage' then
                        if ('image:' .. Tree.data[k].attr[2] == current) then
                            _find = true
                        end
                        imageListBox:Append('image:' .. Tree.data[k].attr[2])
                        imageList['image:' .. Tree.data[k].attr[2]] = Tree.data[k].attr[1]
                    elseif Tree.data[k]["type"] == 'loadani' then
                        if ('ani:' .. Tree.data[k].attr[2] == current) then
                            _find = true
                        end
                        imageListBox:Append('ani:' .. Tree.data[k].attr[2])
                        imageList['ani:' .. Tree.data[k].attr[2]] = Tree.data[k].attr[1]
                    elseif Tree.data[k]["type"] == 'loadparticle' then
                        if ('particle:' .. Tree.data[k].attr[2] == current) then
                            _find = true
                        end
                        imageListBox:Append('particle:' .. Tree.data[k].attr[2])
                    elseif Tree.data[k]["type"] == 'loadimagegroup' then
                        local img = 'image:' .. Tree.data[k].attr[2]
                        imageListBox:Append(img)
                        imageList[img] = Tree.data[k].attr[1]
                        ImageRW[img] = {}
                        local rw = Tree.data[k].attr[4]
                        k = loadstring('return ' .. rw)
                        local r = 1
                        local w = 1
                        r, w = k()
                        ImageRW[img].r = r
                        ImageRW[img].w = w
                    end
                end
            end

            if (_find) then
                imageListBox:SetStringSelection(attrCombo[attrIndex]:GetValue())
                imageString:SetValue('')
            else
                local n = 0
                local ns = ''
                current, n, ns = GetNumInStringBack(current)
                imageListBox:SetStringSelection(current)
                imageString:SetValue(ns)
            end
        end
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    --
    dialog.SelectEnemyStyle:Connect(wx.wxEVT_SHOW, function(event)
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    for i = 1, 34 do
        selectEnemyStyleButton[i]:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
            dialog.SelectEnemyStyle:Hide(true)
            attrCombo[attrIndex]:SetValue(tostring(i))
            SubmitAttr()
            event:Skip()
        end)
    end
    --
    dialog.SelectBulletStyle:Connect(wx.wxEVT_SHOW, function(event)
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    for i, n in ipairs(enumType.bulletstyle) do
        selectBulletStyleButton[i]:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
            dialog.SelectBulletStyle:Hide(true)
            attrCombo[attrIndex]:SetValue(n)
            SubmitAttr()
            event:Skip()
        end)
    end
    --
    dialog.SelectColor:Connect(wx.wxEVT_SHOW, function(event)
        frame:Enable(not frame:IsEnabled())
        event:Skip()
    end)
    for i, n in ipairs(enumType.color) do
        selectColorButton[i]:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
            dialog.SelectColor:Hide(true)
            attrCombo[attrIndex]:SetValue(n)
            SubmitAttr()
            event:Skip()
        end)
    end
    --
    frame:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        local nodeType = Id2Type[event:GetId()]
        if nodeType and (IsValid(curNode) or IsRoot(curNode)) then
            local data
            if nodeType.default then
                data = nodeType.default
            else
                data = { ["type"] = nodeType.name, attr = {} }
                for i = 1, #(nodeType) do
                    data.attr[i] = nodeType[i][4] or enumType[nodeType[i][2]][1] or ""
                end
            end
            InsertNode(projectTree, curNode, data)
        end
    end)
    --
    frame:CreateStatusBar()
    frame:GetStatusBar():SetStatusText("Ready.")
    --
    frame:Center()
    frame:Maximize(true)
    frame:Show(true)
end

main()
wx.wxGetApp():MainLoop()
