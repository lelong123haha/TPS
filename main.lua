-- [[ CONFIGURATION ]]
_G.AutoTap = true
_G.AutoHatch = true
_G.AutoRebirthMax = true
_G.AutoCollectQuest = true
_G.AutoBuyWorld = true
_G.AutoUpgrade = true
_G.AutoClaimRank = true 
_G.AutoVoidSpin = true
_G.AutoGoldenConfig = {
    ["Enabled"] = true,
    ["Pets"] = {
        ["Void Burst"] = 4,   -- Tên Pet = Số lượng mỗi lần ép
        ["Abyssal Raven"] = 4

    }
}
-- [[ CONFIGURATION ]]
_G.AutoRainbow = {
    ["Enabled"] = true,
    ["Pets"] = {
        ["40M Void Burst"] = 5,
        ["Abyssal Raven"] = 5,
    }
}

-- [[ SERVICES & MODULES ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Network = require(ReplicatedStorage.Modules.Network)
local Replication = require(ReplicatedStorage.Game.Replication)
local Rebirths = require(ReplicatedStorage.Game.Rebirths)
local Quests = require(ReplicatedStorage.Game.Quests)
local Worlds = require(ReplicatedStorage.Game.Worlds)
local Player = game.Players.LocalPlayer
local Network = require(game:GetService("ReplicatedStorage").Modules.Network)
local GemShopData = require(game:GetService("ReplicatedStorage").Game.GemShop)
local Replication = require(game:GetService("ReplicatedStorage").Game.Replication)

--- --- --- --- --- --- --- --- --- --- --- --- ---
-- [[ LUỒNG 1: AUTO TAP (HEARTBEAT) ]]
--- --- --- --- --- --- --- --- --- --- --- --- ---

_G.TapsPerSecond = 500
_G.IsRebirthing = false -- Cầu chì ngắt các luồng khác khi đang Rebirth
local RunService = game:GetService("RunService")
local tapAcc = 0

RunService.Heartbeat:Connect(function(dt)
    if _G.AutoTap and not _G.IsRebirthing then
        tapAcc = tapAcc + dt
        local tapInterval = 1 / (_G.TapsPerSecond or 10)
        local taps = math.floor(tapAcc / tapInterval)

        if taps > 0 then
            for i = 1, math.min(taps, 50) do 
                if _G.IsRebirthing then break end
                Network:FireServer("Tap", true, false, true)
            end
            tapAcc = 0
        end
    else
        tapAcc = 0 
    end
end)



local function SmartCleanInventory()
    local Network = require(game:GetService("ReplicatedStorage").Modules.Network)
    local Replication = require(game:GetService("ReplicatedStorage").Game.Replication)
    local PetStats = require(game:GetService("ReplicatedStorage").Game.PetStats)

    local inventory = Replication.Data.Pets
    if not inventory then return end

    -- Bảng xếp hạng bậc (Tier) để so sánh
    local TierPriority = {
        ["Void"] = 4,
        ["Rainbow"] = 3,
        ["Golden"] = 2,
        ["Normal"] = 1
    }

    local SafeRarities = {
        ["Secret I"] = true, ["Secret II"] = true, ["Secret III"] = true, 
        ["Godly"] = true, ["Divine"] = true, ["Celestial"] = true, ["Exotic"] = true
    }
    
    local allPets = {}
    
    -- 1. Thu thập danh sách pet có thể xóa
    for id, data in pairs(inventory) do
        local stats = PetStats:GetStats(data.Name)
        local rarity = stats and stats.Rarity or "Common"
        local tier = data.Tier or "Normal"
        
        -- Bỏ qua pet đang dùng, bị khóa hoặc hàng hiếm
        if data.Equipped or data.Locked or SafeRarities[rarity] then
            continue 
        end

        table.insert(allPets, {
            id = id,
            tierName = tier,
            tierLevel = TierPriority[tier] or 0 -- Lấy điểm số bậc
        })
    end

    -- 2. Sắp xếp: Thằng nào bậc cao (Void, Rainbow) nằm lên đầu
    table.sort(allPets, function(a, b) 
        return a.tierLevel > b.tierLevel 
    end)

    -- 3. Xác định danh sách xóa
    local idsToDelete = {}
    local MAX_KEEP = 80 -- Giữ lại 80 con tốt nhất theo bậc

    for i, pet in ipairs(allPets) do
        -- Nếu vượt quá số lượng giữ lại (80), hoặc nếu con này bậc thấp hơn con đã giữ
        if i > MAX_KEEP then
            table.insert(idsToDelete, pet.id)
        end
    end

    -- 4. Thực thi xóa
    if #idsToDelete > 0 then
        for _, petId in pairs(idsToDelete) do
            -- Kiểm tra lại lần cuối để tránh xóa nhầm pet đang trang bị (nếu data cập nhật chậm)
            local currentPet = Replication.Data.Pets[petId]
            if currentPet and not currentPet.Equipped then
                Network:InvokeServer("DeletePet", petId)
                task.wait(0.02) -- Tốc độ xóa nhanh hơn một chút
            end
        end
    end
end
task.spawn(function()
    -- Vòng lặp tự động chạy mỗi 60 giây
    while _G.AutoHatch == true do
        pcall(function()
            local Network = require(game:GetService("ReplicatedStorage").Modules.Network)
            Network:InvokeServer("EquipBest")
            task.wait(1)
            SmartCleanInventory()
        end)
        task.wait(1)
    end
end)

local function RunAutoEgg()
    local EggDatabase = require(ReplicatedStorage.Game.Eggs) -- 
    
    -- Mốc tiền 1 Trình (1,000,000,000,000)
    local ONE_TRILLION = 1000000000000

    local function GetTargetEgg()
        local stats = Replication.Data and Replication.Data.Statistics -- 
        if not stats then return nil end
        
        -- Lấy số Clicks hiện tại 
        local currentClicks = stats["Clicks"] or 0
        
        -- LOGIC: Nếu tiền từ 1t trở lên, bắt buộc tìm mua trứng Void
        if currentClicks >= ONE_TRILLION then
            for eggName, _ in pairs(EggDatabase) do
                if string.find(string.lower(eggName), "void") then
                    return eggName
                end
            end
        end

        -- LOGIC: Nếu dưới 1t hoặc không tìm thấy trứng Void, mua Best Egg đắt nhất có thể
        local bestEgg = nil
        local maxPrice = -1

        for eggName, eggData in pairs(EggDatabase) do
            if type(eggData) == "table" and eggData.Price then -- 
                local price = eggData.Price
                local currency = eggData.Currency or "Clicks" -- 
                
                if stats[currency] and price <= stats[currency] and price > maxPrice then
                    maxPrice = price
                    bestEgg = eggName
                end
            end
        end
        return bestEgg
    end

    -- Vòng lặp thực thi
    task.spawn(function()
        print("DEBUG: Auto Egg 1T Started - Checking for Void or Best Egg...")
        while _G.AutoHatch == true do
            local target = GetTargetEgg()
            if target then
                -- InvokeServer theo cấu trúc game: OpenEgg, Tên trứng, Số lượng, Bảng xóa pet 
                pcall(function()
                    Network:InvokeServer("OpenEgg", target, 3, {}) -- 
                end)
            end
            task.wait() -- Delay an toàn để tránh bị hệ thống chặn 
        end
    end)
end

-- Kích hoạt function
RunAutoEgg()

--- --- --- --- --- --- --- --- --- --- --- --- ---
-- [[ LUỒNG 3: LOGIC REBIRTH, WORLD & QUEST ]]
--- --- --- --- --- --- --- --- --- --- --- --- ---
task.spawn(function()
    local lastRebirthTick = 0
    while task.wait(0.2) do
        local data = Replication.Data
        if not data or not data.Statistics then continue end

        -- 1. Auto Rebirth Max (Giới hạn Index tối đa là 20)
        if _G.AutoRebirthMax == true and not _G.IsRebirthing then
            local options = data.RebirthOptions
            -- Lấy index cao nhất hiện có trong data
            local rawMaxIdx = (type(options) == "table" and #options) or (tonumber(options) or 0)
            
            -- CHỈNH SỬA TẠI ĐÂY: Dùng math.min để giới hạn tối đa là 20
            local maxIdx = math.min(rawMaxIdx, 23) 

            if maxIdx > 0 and (tick() - lastRebirthTick >= 0.5) then
                local rbAmount = Rebirths:fromIndex(maxIdx)
                local basePrice = Rebirths:getPrice(rbAmount)
                local finalPrice = Rebirths:ClicksPrice(basePrice, data.Statistics.Rebirths)

                if data.Statistics.Clicks >= finalPrice then
                    _G.IsRebirthing = true 
                    task.wait(0.1)
                    
                    local success = pcall(function()
                        -- Thực hiện rebirth với index đã giới hạn
                        return Network:InvokeServer("Rebirth", maxIdx)
                    end)
                    
                    if success then
                        lastRebirthTick = tick()
                        print(">>> ĐÃ REBIRTH TẠI INDEX: " .. maxIdx)
                    end
                    
                    task.wait(0.2)
                    _G.IsRebirthing = false 
                end
            end
        end

        -- 3. Auto Claim Quest
        if _G.AutoCollectQuest == true and data.Quests then
            for qName, qData in pairs(data.Quests) do
                if not qData.Claimed and qData.Amount >= (Quests[qName] and Quests[qName].Goal or 9e9) then
                    pcall(function() Network:InvokeServer("ClaimQuest", qName) end)
                end
            end
        end
    end
end)

--- --- --- --- --- --- --- --- --- --- --- --- ---
-- [[ LUỒNG 4: AUTO ZONE (PORTAL) ]]
--- --- --- --- --- --- --- --- --- --- --- --- ---
local function AutoOpenBestPortal()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Network = require(ReplicatedStorage.Modules.Network)
    local Replication = require(ReplicatedStorage.Game.Replication)
    local PortalsData = require(ReplicatedStorage.Game.Portals)
    
    -- 1. Lấy danh sách cổng và sắp xếp theo giá (y hệt logic của game)
    local sortedPortals = {}
    for name, data in pairs(PortalsData) do
        table.insert(sortedPortals, {Name = name, Price = data.Price})
    end
    
    table.sort(sortedPortals, function(a, b)
        return a.Price < b.Price
    end)

    -- 2. Kiểm tra dữ liệu người chơi
    if not Replication.Loaded or not Replication.Data then return end
    
    local currentClicks = Replication.Data.Statistics.Clicks
    local ownedPortals = Replication.Data.Portals

    -- 3. Tìm cổng tiếp theo chưa sở hữu mà bạn đủ tiền mua
    for _, portal in ipairs(sortedPortals) do
        if not ownedPortals[portal.Name] then
            if currentClicks >= portal.Price then
                print("--- Đang tự động mở cổng: " .. portal.Name .. " (" .. portal.Price .. " Clicks) ---")
                
                -- Gọi Remote mua cổng từ server
                local success = Network:InvokeServer("BuyPortal", portal.Name)
                
                if success then
                    print("✅ Đã mở khóa thành công portal: " .. portal.Name)
                    -- Nếu thất bại thường là do chưa mở cổng trước đó
                    print("❌ Không thể mua " .. portal.Name .. ". Có thể do chưa mở cổng trước đó.")
                end
                -- Sau khi thử mua 1 cổng thì dừng lại để chờ chu kỳ sau
                return 
            else
                -- Nếu không đủ tiền mua cổng này, thì chắc chắn không đủ tiền mua các cổng sau (vì đã sắp xếp theo giá)
                break
            end
        end
    end
end

task.spawn(function()
    while _G.AutoBuyWorld == true do
        pcall(AutoOpenBestPortal)
        task.wait()
    end
end)

local function autoBuyUpgrades()
    for upgradeName, details in pairs(GemShopData) do
        -- Get current level from the replication module
        local currentLevel = Replication.Data.GemShop[upgradeName] or 0
        local maxLevel = details.Total
        
        -- If not maxed, try to upgrade
        if currentLevel < maxLevel then
            -- Invoke the server (Matching the decompiled signature)
            Network:InvokeServer("UpgradeGemShop", upgradeName, nil)
            task.wait(0.1) -- Small delay to prevent crashing/kicking
        end
    end
end
task.spawn(function()
    while _G.AutoUpgrade == true do
        autoBuyUpgrades()
        Network:InvokeServer("UpgradeGemShop", "RebirthButtons")
        task.wait(1)
    end
end)



task.spawn(function()
    while _G.AutoClaimRank == true do
        -- Kiểm tra dữ liệu game đã tải xong chưa
        local data = Replication.Data
        if data and data.Ranks then
            local currentTime = os.time()
            local nextRewardTime = data.Ranks.NextRewardTime or 0
            
            -- Nếu thời gian hiện tại đã vượt qua thời gian chờ nhận thưởng
            if currentTime >= nextRewardTime then
                
                -- Gọi Remote nhận thưởng giống như khi bấm nút
                local success, response = Network:InvokeServer("ClaimRankReward")
                
                if success then
                    print("✅ Nhận thưởng thành công!")
                    -- Chờ thêm một chút để dữ liệu Server cập nhật
                    task.wait(2) 
                end
            end
        end
        
        -- Kiểm tra mỗi 5 giây để tránh làm lag máy
        task.wait(5)
    end
end)


-- Tọa độ máy Golden mặc định ông vừa đưa
local GOLDEN_MACHINE_POS = Vector3.new(-192.82, 221.40, 197.21)

local function RunAutoCraftGolden()
    local Config = _G.AutoGoldenConfig
    if not Config or not Config.Enabled then return end

    local Replication = require(game:GetService("ReplicatedStorage").Game.Replication)
    local Network = require(game:GetService("ReplicatedStorage").Modules.Network)
    local Player = game.Players.LocalPlayer
    local Character = Player.Character
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then return end
    
    local RootPart = Character.HumanoidRootPart
    if not Replication.Data or not Replication.Data.Pets then return end
    
    local inventory = Replication.Data.Pets
    local groups = {}
    local oldCFrame = RootPart.CFrame -- Lưu vị trí đang đứng farm
    local needsToTeleport = false

    -- 1. Quét túi đồ và kiểm tra điều kiện
    for id, petData in pairs(inventory) do
        if petData.Tier == "Normal" and not petData.Locked and not petData.Equipped then
            local pNameLower = string.lower(petData.Name)
            for targetName, amount in pairs(Config.Pets) do
                if string.find(pNameLower, string.lower(targetName)) then
                    if not groups[petData.Name] then
                        groups[petData.Name] = { ids = {}, required = amount }
                    end
                    table.insert(groups[petData.Name].ids, id)
                    break 
                end
            end
        end
    end

    -- 2. Kiểm tra xem có đủ pet để thực hiện ít nhất 1 lần ép không
    for _, data in pairs(groups) do
        if #data.ids >= data.required then
            needsToTeleport = true
            break
        end
    end

    -- 3. Thực hiện Teleport và Ép
    if needsToTeleport then
        print(">>> Đang Teleport về máy Golden...")
        RootPart.CFrame = CFrame.new(GOLDEN_MACHINE_POS)
        task.wait(0.6) -- Đợi server nhận vị trí

        for petRealName, data in pairs(groups) do
            local totalAvailable = #data.ids
            local amountPerCraft = data.required

            if totalAvailable >= amountPerCraft then
                local craftsPossible = math.floor(totalAvailable / amountPerCraft)
                
                for i = 1, craftsPossible do
                    local craftBatch = {}
                    for j = 1, amountPerCraft do
                        table.insert(craftBatch, table.remove(data.ids))
                    end
                    
                    local success = Network:InvokeServer("CraftPets", craftBatch)
                    if success then
                        print("✅ Golden thành công: " .. petRealName)
                    end
                    task.wait(0.5)
                end
            end
        end

        -- 4. Quay lại vị trí cũ sau khi ép xong
        print(">>> Quay lại vị trí cũ...")
        RootPart.CFrame = oldCFrame
    end
end

-- Vòng lặp kiểm tra mỗi 10 giây
task.spawn(function()
    print(">>> AUTO GOLDEN (RETURN TO FARM) READY <<<")
    while true do
        if _G.AutoGoldenConfig and _G.AutoGoldenConfig.Enabled then
            pcall(RunAutoCraftGolden)
        end
        task.wait(1)
    end
end)
-- [[ CONFIGURATION ]]
_G.AutoRainbow = {
    ["Enabled"] = true,
    ["Pets"] = {
        ["40M Void Burst"] = 5,
        ["Abyssal Raven"] = 5,
    }
}

local RAINBOW_MACHINE_POS = Vector3.new(1205.83, 668.98, -13383.21)

local function RunAutoRainbow()
    local Config = _G.AutoRainbow
    local Network = require(game:GetService("ReplicatedStorage").Modules.Network)
    local Replication = require(game:GetService("ReplicatedStorage").Game.Replication)
    local Player = game.Players.LocalPlayer
    local RootPart = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    
    if not RootPart or not Replication.Data or not Replication.Data.Pets then return end

    local activeCrafts = Replication.Data.CraftingPets.Rainbow
    local oldCFrame = RootPart.CFrame
    local hasAction = false

    local needClaim = false
    for slotId, data in pairs(activeCrafts) do
        if data.EndTime - workspace:GetServerTimeNow() <= 0 then
            needClaim = true
            break
        end
    end

    local inventory = Replication.Data.Pets
    local batch = {}
    local canCraft = false
    for targetName, reqAmount in pairs(Config.Pets) do
        local tempBatch = {}
        for id, data in pairs(inventory) do
            if data.Tier == "Golden" and not data.Locked and not data.Equipped and string.find(data.Name, targetName) then
                table.insert(tempBatch, id)
            end
            if #tempBatch >= reqAmount then break end
        end
        if #tempBatch >= reqAmount then
            batch = tempBatch
            canCraft = true
            break
        end
    end

    local slotCount = 0
    for _ in pairs(activeCrafts) do slotCount = slotCount + 1 end

    if needClaim or (canCraft and slotCount < 3) then
        RootPart.CFrame = CFrame.new(RAINBOW_MACHINE_POS)
        task.wait(1.5)

        for slotId, data in pairs(activeCrafts) do
            if data.EndTime - workspace:GetServerTimeNow() <= 0 then
                Network:InvokeServer("ClaimRainbow", slotId)
                hasAction = true
                task.wait(0.5)
            end
        end

        if canCraft and slotCount < 3 then
            local success = Network:InvokeServer("StartRainbow", batch)
            if success then
                hasAction = true
            else
                Network:InvokeServer("StartRainbow", "1", batch)
            end
        end

        if hasAction then
            task.wait(0.5)
            RootPart.CFrame = oldCFrame
        end
    end
end

task.spawn(function()
    while true do
        if _G.AutoRainbow and _G.AutoRainbow.Enabled then
            pcall(RunAutoRainbow)
        end
        task.wait(1)
    end
end)
-- 1. Ẩn mọi thứ trong Workspace (Transparency = 1 và tắt Va chạm)
for _, item in ipairs(workspace:GetDescendants()) do
    if item:IsA("BasePart") and not item:IsDescendantOf(game.Players) then
        item.Transparency = 1
    end
end

print("Đã ẩn Workspace và neo tất cả HumanoidRootPart!")
local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

for _, gui in ipairs(playerGui:GetChildren()) do
    if gui:IsA("ScreenGui") then
        gui.Enabled = false
    end
end

task.spawn(function()
    while _G.AutoVoidSpin do
        -- Lấy dữ liệu lượt quay từ Replication module
        local data = Replication.Data
        local spins = data and data.Items and data.Items.VoidSpins or 0
        
        -- Chỉ quay nếu có lượt (> 0) và không đang trong quá trình quay (_G.Spinning)
        if spins > 0 and not _G.Spinning then
            -- Gọi server để quay
            Network:InvokeServer("SpinWheel", "VoidSpinWheel")
            print("Spun Void Wheel! Remaining: " .. (spins - 1))
            
            -- Đợi vòng quay kết thúc (khoảng 7 giây)
            task.wait(7)
        end
        
        task.wait(2) -- Kiểm tra lại sau mỗi 2 giây
    end
end)
--------------------------
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local CoreGui = game:GetService('CoreGui')
local LocalPlayer = Players.LocalPlayer

--// KHỞI TẠO GUI GỐC
local ScreenGui = Instance.new('ScreenGui')
ScreenGui.Name = 'FullOverlayStats'
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 2147483647 
ScreenGui.IgnoreGuiInset = true 
ScreenGui.Parent = (gethui and gethui()) or CoreGui

--// NỀN ĐEN PHỦ TOÀN MÀN HÌNH
local Background = Instance.new('Frame')
Background.Size = UDim2.new(1, 0, 1, 0) 
Background.BackgroundColor3 = Color3.new(0, 0, 0) 
Background.BackgroundTransparency = 0.5 
Background.BorderSizePixel = 0
Background.Parent = ScreenGui

--// KHUNG CHÍNH CHỨA CHỮ
local MainFrame = Instance.new('Frame')
MainFrame.Size = UDim2.new(0.9, 0, 0.9, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundTransparency = 1
MainFrame.Parent = Background

local AspectRatio = Instance.new("UIAspectRatioConstraint")
AspectRatio.AspectRatio = 1.4 -- Adjusted for the extra line
AspectRatio.AspectType = Enum.AspectType.ScaleWithParentSize
AspectRatio.Parent = MainFrame

local Layout = Instance.new('UIListLayout')
Layout.Parent = MainFrame
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
Layout.VerticalAlignment = Enum.VerticalAlignment.Center
Layout.Padding = UDim.new(0.012, 0)

--// HÀM TẠO LABEL
local function createLabel(name, text, color, order)
    local label = Instance.new('TextLabel')
    label.Name = name
    label.Text = text
    label.TextColor3 = color
    label.Font = Enum.Font.LuckiestGuy
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.9, 0, 0.09, 0)
    label.TextScaled = true 
    label.LayoutOrder = order

    local SizeConstraint = Instance.new("UITextSizeConstraint")
    SizeConstraint.MaxTextSize = 80
    SizeConstraint.MinTextSize = 10
    SizeConstraint.Parent = label

    local UIStroke = Instance.new('UIStroke')
    UIStroke.Thickness = 2.5
    UIStroke.Color = Color3.new(0, 0, 0)
    UIStroke.Parent = label
    
    label.Parent = MainFrame
    return label
end

--// CÁC DÒNG HIỂN THỊ
local UserLabel = createLabel('UserLabel', LocalPlayer.Name:upper(), Color3.new(1, 1, 1), 1)
local TimeLabel = createLabel('TimeLabel', 'TIME: 00:00:00', Color3.fromRGB(200, 200, 200), 2)
local FPSLabel = createLabel('FPSLabel', 'FPS: 0', Color3.fromRGB(255, 180, 0), 3)
local ClicksLabel = createLabel('ClicksLabel', 'CLICKS: 0', Color3.fromRGB(0, 255, 255), 4)
local EggsLabel = createLabel('EggsLabel', 'EGGS: 0', Color3.fromRGB(255, 255, 0), 5)
local EggsMinLabel = createLabel('EggsMinLabel', 'EGGS/MIN: 0', Color3.fromRGB(255, 150, 0), 6) -- New Label
local RarestLabel = createLabel('RarestLabel', 'RAREST: 0', Color3.fromRGB(255, 0, 255), 7)
local RebirthsLabel = createLabel('RebirthsLabel', 'REBIRTHS: 0', Color3.fromRGB(0, 255, 0), 8)

--// LOGIC EGGS PER MINUTE
local eggHistory = {} -- Lưu trữ thời gian mỗi khi nhận trứng

local function updateEggsPerMin()
    local now = tick()
    -- Xóa các bản ghi cũ hơn 60 giây
    for i = #eggHistory, 1, -1 do
        if now - eggHistory[i] > 60 then
            table.remove(eggHistory, i)
        end
    end
    EggsMinLabel.Text = "EGGS/MIN: " .. #eggHistory
end

--// LOGIC CẬP NHẬT LEADERSTATS
local function updateLeaderstats()
    local leaderstats = LocalPlayer:WaitForChild("leaderstats", 20)
    if leaderstats then
        local function setupStat(statName, label, prefix)
            local stat = leaderstats:FindFirstChild(statName)
            if stat then
                label.Text = prefix .. ": " .. tostring(stat.Value)
                
                stat:GetPropertyChangedSignal("Value"):Connect(function()
                    -- Nếu là Eggs, ghi nhận thời gian để tính Eggs/Min
                    if statName == "Eggs" then
                        table.insert(eggHistory, tick())
                    end
                    label.Text = prefix .. ": " .. tostring(stat.Value)
                end)
            end
        end
        setupStat("Clicks", ClicksLabel, "CLICKS")
        setupStat("Eggs", EggsLabel, "EGGS")
        setupStat("Rarest", RarestLabel, "RAREST")
        setupStat("Rebirths", RebirthsLabel, "REBIRTHS")
    end
end
task.spawn(updateLeaderstats)

--// LOGIC FPS, TIME & EPM LOOP
local startTime = os.time()
local lastUpdate = tick()
local frames = 0
RunService.RenderStepped:Connect(function()
    frames = frames + 1
    local now = tick()
    
    if now - lastUpdate >= 1 then
        FPSLabel.Text = "FPS: " .. tostring(frames)
        frames = 0
        lastUpdate = now
        updateEggsPerMin() -- Cập nhật Eggs/Min mỗi giây
    end
    
    local elapsed = os.time() - startTime
    local hours = math.floor(elapsed / 3600)
    local mins = math.floor((elapsed % 3600) / 60)
    local secs = elapsed % 60
    TimeLabel.Text = string.format('TIME: %02d:%02d:%02d', hours, mins, secs)
end)
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Vòng lặp nhấn phím P liên tục
while true do
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.P, false, game)
    task.wait(0.1) -- Tốc độ nhấn (0.1 giây)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.P, false, game)
    task.wait(50)
end
----------------
--end
