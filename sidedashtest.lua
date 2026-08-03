-- [[ CONFIGURATION ]] --
local MAX_DISTANCE = 30       -- ระยะสแกนไกลสุด
local SPIN_TRIGGER_DIST = 12  -- ระยะเริ่มทำการหมุนวนรอบตัว 1 รอบ (Distance 12)
local RANGE = 4               -- ระยะหยุดหลังเป้าหมาย (4 Studs)
local SPEED_N = 95            -- ความเร็วในการพุ่ง
local PREDICTION = 0.1        -- การคาดการณ์การเคลื่อนที่ล่วงหน้า
local ARC_OFFSET = 12         -- ความกว้างของวงโค้งช่วงไกล

-- 🎬 ID Animation ฝั่งซ้าย/ขวา
local ANIMATION_LEFT = "0"
local ANIMATION_RIGHT = "0"

-- [[ SERVICES ]] --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- [[ SELECTED TARGET VARIABLES ]] --
local selectedTargetModel = nil
local selectedTargetRoot = nil
local lastClickTime = 0
local lastClickedModel = nil

-- [[ ANIMATION SYSTEM ]] --
local animObjLeft = Instance.new("Animation")
local animObjRight = Instance.new("Animation")

local function playSideAnimation(humanoid, side)
    if not humanoid then return nil end
    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
    
    local animId = (side == "Left") and ANIMATION_LEFT or ANIMATION_RIGHT
    local animObject = (side == "Left") and animObjLeft or animObjRight
    
    if animId ~= "" and animId ~= "0" then
        local formattedId = animId
        if not string.find(formattedId, "rbxassetid://") then
            formattedId = "rbxassetid://" .. formattedId
        end
        animObject.AnimationId = formattedId
        
        local success, track = pcall(function()
            local trk = animator:LoadAnimation(animObject)
            trk.Priority = Enum.AnimationPriority.Action
            trk:Play()
            return trk
        end)
        if success then return track end
    end
    return nil
end

-- [[ CREATE UI BUTTON ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpinDashGui"
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

-- [[ HIGHLIGHT TARGET ]] --
local highlight = Instance.new("Highlight")
highlight.Name = "TargetSelectHighlight"
highlight.FillColor = Color3.fromRGB(255, 0, 0)
highlight.FillTransparency = 0.3
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0
highlight.Parent = ScreenGui

-- [[ SELECT TARGET SYSTEM ]] --
local function onTouchOrClick(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local unitRay = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
        local raycastParams = RaycastParams.new()
        
        if localPlayer.Character then
            raycastParams.FilterDescendantsInstances = {localPlayer.Character}
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        end
        
        local rayResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
        
        if rayResult and rayResult.Instance then
            local hitPart = rayResult.Instance
            local model = hitPart:FindFirstAncestorOfClass("Model")
            
            if model then
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                local rootPart = model:FindFirstChild("HumanoidRootPart")
                
                if humanoid and rootPart then
                    local currentTime = tick()
                    
                    if lastClickedModel == model and (currentTime - lastClickTime) <= 0.4 then
                        selectedTargetModel = model
                        selectedTargetRoot = rootPart
                        highlight.Adornee = selectedTargetModel
                        print("[Select Target] Target Locked: " .. model.Name)
                    else
                        lastClickTime = currentTime
                        lastClickedModel = model
                    end
                end
            end
        end
    end
end

UserInputService.InputBegan:Connect(onTouchOrClick)

RunService.RenderStepped:Connect(function()
    if selectedTargetModel then
        local humanoid = selectedTargetModel:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 or not selectedTargetModel.Parent then
            selectedTargetModel = nil
            selectedTargetRoot = nil
            highlight.Adornee = nil
        end
    end
end)

-- [[ BEZIER CURVE HELPER ]] --
local function getQuadraticBezierPoint(p0, p1, p2, t)
    return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

-- [[ 2-STAGE SPIN DASH SYSTEM ]] --
local isDashing = false

local function performBehindDash()
    if isDashing then return end
    
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local myRoot = character.HumanoidRootPart
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid and humanoid.PlatformStand then return end

    if selectedTargetRoot then
        local currentDist = (myRoot.Position - selectedTargetRoot.Position).Magnitude
        
        if currentDist <= MAX_DISTANCE then
            isDashing = true

            -- 1. ตรวจสอบทิศทางฝั่งหน้าจอเพื่อเลือกทิศการหมุนวน
            local screenPos = camera:WorldToViewportPoint(selectedTargetRoot.Position)
            local screenWidth = camera.ViewportSize.X
            local isLeft = (screenPos.X < screenWidth / 2)
            
            local sideName = isLeft and "Right" or "Left"
            local activeTrack = playSideAnimation(humanoid, sideName)

            -- 2. คำนวณพิกัดศัตรู
            local targetVelocity = selectedTargetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            local predictedTargetPos = selectedTargetRoot.Position + (targetVelocity * PREDICTION)

            -- [[ ระยะที่ 1: แดชโค้งทางไกล (ถ้าอยู่ไกลเกิน 12 Studs) ]] --
            if currentDist > SPIN_TRIGGER_DIST then
                local startPos = myRoot.Position
                local targetLook = selectedTargetRoot.CFrame.LookVector
                local tempEndPos = predictedTargetPos - (targetLook * SPIN_TRIGGER_DIST)
                
                local midPoint = (startPos + tempEndPos) / 2
                local targetRight = selectedTargetRoot.CFrame.RightVector
                local curveDir = isLeft and targetRight or -targetRight
                local controlPos = midPoint + (curveDir * ARC_OFFSET)

                local approxDist = (startPos - controlPos).Magnitude + (controlPos - tempEndPos).Magnitude
                local stage1Duration = math.max(approxDist / SPEED_N, 0.08)

                local startTime = tick()
                while (tick() - startTime) < stage1Duration do
                    local elapsed = tick() - startTime
                    local rawT = math.clamp(elapsed / stage1Duration, 0, 1)
                    local t = 1 - (1 - rawT) * (1 - rawT)
                    
                    local currentArcPos = getQuadraticBezierPoint(startPos, controlPos, tempEndPos, t)
                    -- ล็อคสายตามองเป้าหมายตลอดเวลา
                    myRoot.CFrame = CFrame.new(currentArcPos, predictedTargetPos)
                    RunService.RenderStepped:Wait()
                end
            end

            -- [[ ระยะที่ 2: หมุนวนวนรอบศัตรู 1 รอบ (Spin Around Target - Distance 12) ]] --
            local spinCenter = predictedTargetPos
            local radius = RANGE -- รัศมีหมุนวนอ้อมหลัง (4 Studs)
            
            -- คำนวณมุมเริ่มต้นและมุมจบ (หมุนครบ 360 องศาเพื่ออ้อมไปด้านหลัง)
            local startOffset = myRoot.Position - spinCenter
            local startAngle = math.atan2(startOffset.Z, startOffset.X)
            
            -- หมุนวน 1 รอบเต็ม (2 * pi)
            local spinDirection = isLeft and 1 or -1
            local totalSpinAngle = (math.pi * 2) * spinDirection 

            local spinArcLength = (2 * math.pi * radius)
            local spinDuration = math.max(spinArcLength / (SPEED_N * 0.8), 0.15)

            local spinStartTime = tick()
            while (tick() - spinStartTime) < spinDuration do
                local elapsed = tick() - spinStartTime
                local rawT = math.clamp(elapsed / spinDuration, 0, 1)
                local t = 1 - (1 - rawT) * (1 - rawT) -- ชะลอความเร็วตอนท้าย
                
                local currentAngle = startAngle + (totalSpinAngle * t)
                local newX = spinCenter.X + math.cos(currentAngle) * radius
                local newZ = spinCenter.Z + math.sin(currentAngle) * radius
                local currentSpinPos = Vector3.new(newX, selectedTargetRoot.Position.Y, newZ)

                -- ล็อคหันหน้าเข้าหาเป้าหมายตลอดเวลาที่หมุนวน
                myRoot.CFrame = CFrame.new(currentSpinPos, predictedTargetPos)
                RunService.RenderStepped:Wait()
            end

            -- [[ จบการทำงาน: ปรับ CFrame ขั้นสุดท้าย ให้ล็อคมองเป้าหมายชัวร์ 100% ]] --
            local finalLook = selectedTargetRoot.CFrame.LookVector
            local finalBehindPos = predictedTargetPos - (finalLook * RANGE)
            finalBehindPos = Vector3.new(finalBehindPos.X, selectedTargetRoot.Position.Y, finalBehindPos.Z)
            
            -- ล็อคหันหน้าเข้าหาเป้าหมาย (Lock On)
            myRoot.CFrame = CFrame.new(finalBehindPos, predictedTargetPos)

            if activeTrack then
                activeTrack:Stop()
            end
            
            isDashing = false
        else
            print("[Spin Dash] Out of Distance! Max: " .. MAX_DISTANCE)
        end
    else
        print("[Spin Dash] No target selected! Double tap a player/NPC first.")
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

print("[Spin Dash] 2-Stage Spin Dash System Loaded!")
