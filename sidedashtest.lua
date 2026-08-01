-- [[ CONFIGURATION (BATTLEGROUND VERSION - FIXED HIGHLIGHT) ]] --
local DISTANCE = 50           -- เพิ่มระยะตรวจจับให้กว้างขึ้น
local RANGE = 4               -- ระยะหยุดด้านหลัง
local PREDICTION = 0.1        -- การคาดการณ์ล่วงหน้า

-- [[ SERVICES ]] --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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

-- [[ FIXED HIGHLIGHT SYSTEM ]] --
local highlight = Instance.new("Highlight")
highlight.Name = "BattlegroundHighlight"
highlight.FillColor = Color3.fromRGB(255, 0, 0)
highlight.FillTransparency = 0.4
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0
highlight.Parent = ScreenGui -- ย้ายมาไว้ที่ ScreenGui หรือ CoreGui เพื่อบังคับให้เรนเดอร์

-- [[ FIND TARGET (IMPROVED SEARCH) ]] --
local function getNearestTarget()
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local myRoot = character.HumanoidRootPart

    local nearestTargetModel = nil
    local nearestTargetRoot = nil
    local shortestDistance = DISTANCE

    -- ค้นหาทั้งใน Workspace และโฟลเดอร์ผู้เล่นทั่วไป
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj ~= character and obj:IsA("Model") then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local targetRoot = obj:FindFirstChild("HumanoidRootPart")
            
            if humanoid and humanoid.Health > 0 and targetRoot then
                local isPlayer = Players:GetPlayerFromCharacter(obj)
                -- อนุญาตให้ล็อคได้ทั้ง Player อื่น และ Dummy ฝึกซ้อมในแมพ
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

-- [[ REAL-TIME HIGHLIGHT UPDATER ]] --
RunService.RenderStepped:Connect(function()
    pcall(function()
        local _, targetModel = getNearestTarget()
        if targetModel then
            -- บังคับให้ Highlight จับคู่กับ Model ของเป้าหมายโดยตรง
            highlight.Adornee = targetModel
        else
            highlight.Adornee = nil
        end
    end)
end)

-- [[ SAFE DASH SYSTEM ]] --
local isDashing = false

local function performBehindDash()
    if isDashing then return end
    
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local myRoot = character.HumanoidRootPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid and humanoid.PlatformStand then return end

    local targetRoot, _ = getNearestTarget()
    if targetRoot then
        isDashing = true

        local targetVelocity = targetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
        local predictedPos = targetRoot.Position + (targetVelocity * PREDICTION)
        local targetLookVector = targetRoot.CFrame.LookVector
        local behindPos = predictedPos - (targetLookVector * RANGE)
        behindPos = Vector3.new(behindPos.X, targetRoot.Position.Y, behindPos.Z)

        local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local dashTween = TweenInfo.new()
        
        local tween = TweenService:Create(myRoot, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            CFrame = CFrame.new(behindPos, predictedPos)
        })
        
        tween:Play()
        tween.Completed:Wait()
        
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

print("[Side Dash Assist] Highlight Fix Applied Successfully!")
