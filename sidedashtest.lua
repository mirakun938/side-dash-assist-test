-- [[ CONFIGURATION (BATTLEGROUND VERSION) ]] --
local DISTANCE = 30           -- ระยะเริ่มตรวจจับเป้าหมาย
local RANGE = 4               -- ระยะหยุดด้านหลัง
local DASH_SPEED = 150        -- ความเร็วในการพุ่ง (ปรับให้เหมาะกับเกมแนวต่อสู้)
local PREDICTION = 0.2        -- การคาดการณ์ล่วงหน้า

-- [[ SERVICES ]] --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

-- [[ CREATE UI BUTTON ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BattlegroundDashGui"
ScreenGui.Parent = localPlayer:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false

local DashButton = Instance.new("TextButton")
DashButton.Name = "DashButton"
DashButton.Parent = ScreenGui
DashButton.Size = UDim2.new(0, 70, 0, 70)
DashButton.Position = UDim2.new(0.85, 0, 0.6, 0)
DashButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
DashButton.BackgroundTransparency = 0.4
DashButton.Text = "C"
DashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
DashButton.TextSize = 28
DashButton.Font = Enum.Font.SourceSansBold
DashButton.Active = true

local ButtonCorner = Instance.new("UICorner")
ButtonCorner.CornerRadius = UDim.new(1, 0)
ButtonCorner.Parent = DashButton

-- [[ TARGET HIGHLIGHT ]] --
local highlight = Instance.new("Highlight")
highlight.Name = "BattlegroundHighlight"
highlight.FillColor = Color3.fromRGB(255, 0, 0)
highlight.FillTransparency = 0.5
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.Parent = ScreenGui

-- [[ FIND TARGET (COMPATIBLE WITH BATTLEGROUNDS) ]] --
local function getNearestTarget()
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local myRoot = character.HumanoidRootPart

    local nearestTargetModel = nil
    local nearestTargetRoot = nil
    local shortestDistance = DISTANCE

    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj ~= character and obj:IsA("Model") then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local targetRoot = obj:FindFirstChild("HumanoidRootPart")
            
            -- เช็คว่ามีชีวิตอยู่ และไม่ใช่ตัวเรา (รองรับทั้ง Player และ Dummy/NPC ในเกม)
            if humanoid and humanoid.Health > 0 and targetRoot then
                local isPlayer = Players:GetPlayerFromCharacter(obj)
                if not isPlayer or isPlayer ~= localPlayer then
                    local dist = (myRoot.Position - targetRoot.Position).Magnitude
                    if dist <= shortestDistance then
                        shortestDistance = dist
                        nearestTargetModel = obj
                        nearestTargetRoot = targetRoot
                    end
                end
            end
        end
    end

    return nearestTargetRoot, nearestTargetModel
end

-- [[ REAL-TIME HIGHLIGHT ]] --
RunService.RenderStepped:Connect(function()
    pcall(function()
        local _, targetModel = getNearestTarget()
        if targetModel then
            highlight.Adornee = targetModel
        else
            highlight.Adornee = nil
        end
    end)
end)

-- [[ SAFE DASH SYSTEM FOR BATTLEGROUNDS ]] --
local isDashing = false

local function performBehindDash()
    if isDashing then return end
    
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local myRoot = character.HumanoidRootPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    -- ป้องกันถ้าร่างกายติดสถานะ Stun หรือล้ม (Ragdoll) ให้ขัดขวางการแดช
    if humanoid and humanoid.PlatformStand then return end

    local targetRoot, _ = getNearestTarget()
    if targetRoot then
        isDashing = true

        -- คำนวณตำแหน่งด้านหลังเป้าหมาย
        local targetVelocity = targetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
        local predictedPos = targetRoot.Position + (targetVelocity * PREDICTION)
        local targetLookVector = targetRoot.CFrame.LookVector
        local behindPos = predictedPos - (targetLookVector * RANGE)
        behindPos = Vector3.new(behindPos.X, targetRoot.Position.Y, behindPos.Z)

        -- ใช้การเคลื่อนที่แบบซูมความเร็วสูง (Tween/Velocity) เลี่ยง Anti-Cheat
        local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tweenService = game:GetService("TweenService")
        
        local dashTween = tweenService:Create(myRoot, tweenInfo, {
            CFrame = CFrame.new(behindPos, predictedPos)
        })
        
        dashTween:Play()
        dashTween.Completed:Wait()
        
        isDashing = false
    end
end

-- [[ INPUTS ]] --
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.C then
        performBehindDash()
    end
end)

DashButton.MouseButton1Click:Connect(function()
    performBehindDash()
end)

print("[Side Dash Assist] Battleground Fixed Version Loaded!")
