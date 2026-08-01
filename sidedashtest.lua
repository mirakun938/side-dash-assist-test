-- [[ CONFIGURATION ]] --
local DISTANCE = 30           -- ระยะเริ่มตรวจจับเป้าหมายที่แท้จริง (สแกนหาในรัศมี 30)
local RANGE = 4               -- ระยะห่างด้านหลังเป้าหมายที่จะไปหยุดอยู่ (4 Studs)
local SPEED_N = 95            -- ความเร็วในการพุ่ง
local DURATION = 0.25         -- ระยะเวลาพุ่ง
local PREDICTION = 0.4        -- การคาดการณ์การเคลื่อนที่ล่วงหน้าของเป้าหมาย

-- [[ SERVICES ]] --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

-- [[ CREATE UI BUTTON FOR MOBILE / PC ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SideDashGui"
ScreenGui.Parent = localPlayer:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false

local DashButton = Instance.new("TextButton")
DashButton.Name = "DashButton"
DashButton.Parent = ScreenGui
DashButton.Size = UDim2.new(0, 70, 0, 70)
DashButton.Position = UDim2.new(0.85, 0, 0.6, 0) -- โซนนิ้วโป้งขวา
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

-- [[ TARGET HIGHLIGHT (วงแหวนเป้าหมาย) ]] --
local highlight = Instance.new("Highlight")
highlight.Name = "TargetNearestHighlight"
highlight.Adornee = nil
highlight.FillColor = Color3.fromRGB(255, 0, 0)
highlight.FillTransparency = 0.5
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0
highlight.Parent = ScreenGui

-- [[ FIND NEAREST TARGET (USING DISTANCE FOR DETECTION) ]] --
local function getNearestTarget()
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local myRoot = character.HumanoidRootPart

    local nearestTargetModel = nil
    local nearestTargetRoot = nil
    local shortestDistance = DISTANCE -- ใช้ระยะ 30 เป็นตัวสแกนหาเป้าหมาย

    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj ~= character and obj:IsA("Model") then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local targetRoot = obj:FindFirstChild("HumanoidRootPart")
            
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

-- [[ UPDATE HIGHLIGHT IN REAL-TIME ]] --
RunService.RenderStepped:Connect(function()
    local _, targetModel = getNearestTarget()
    if targetModel then
        highlight.Adornee = targetModel
    else
        highlight.Adornee = nil
    end
end)

-- [[ SIDE DASH / BEHIND TELEPORT ASSIST ]] --
local isDashing = false

local function performBehindDash()
    if isDashing then return end
    
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local myRoot = character.HumanoidRootPart

    local targetRoot, _ = getNearestTarget()
    if targetRoot then
        isDashing = true

        local targetVelocity = targetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
        local predictedPos = targetRoot.Position + (targetVelocity * PREDICTION)

        local targetLookVector = targetRoot.CFrame.LookVector
        -- ใช้ RANGE (4) เป็นระยะห่างด้านหลังเป้าหมายที่จะไปหยุด
        local behindPos = predictedPos - (targetLookVector * RANGE)
        behindPos = Vector3.new(behindPos.X, targetRoot.Position.Y, behindPos.Z)

        local startTime = tick()
        local startCFrame = myRoot.CFrame
        local endCFrame = CFrame.new(behindPos, predictedPos)

        local connection
        connection = RunService.RenderStepped:Connect(function()
            local elapsed = tick() - startTime
            local alpha = math.clamp(elapsed / DURATION, 0, 1)
            
            if myRoot and targetRoot then
                myRoot.CFrame = startCFrame:Lerp(endCFrame, alpha)
            end

            if alpha >= 1 then
                connection:Disconnect()
                isDashing = false
            end
        end)
    else
        print("[Side Dash] No target found within detection distance (" .. DISTANCE .. ")!")
    end
end

-- [[ INPUT TRIGGERS ]] --
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.C then
        performBehindDash()
    end
end)

DashButton.MouseButton1Click:Connect(function()
    performBehindDash()
end)

print("[Side Dash Assist] Loaded with Correct Distance (30) & Range (4)!")
