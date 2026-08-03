-- [[ CONFIGURATION ]] --
local DISTANCE = 30           -- ระยะทางสูงสุดที่เข้าใกล้เป้าหมายแล้วใช้ได้ (30 Studs)
local RANGE = 4               -- ระยะห่างที่จะไปหยุดอยู่ด้านหลังเป้าหมาย (4 Studs)
local SPEED_N = 95            -- ความเร็วในการพุ่ง
local PREDICTION = 0.1        -- การคาดการณ์การเคลื่อนที่ล่วงหน้า
local ARC_OFFSET = 12         -- ความกว้างของวงโค้งตอนพุ่งอ้อม (ยิ่งเยอะยิ่งโค้งกว้าง)

-- 🎬 ID Animation ฝั่งซ้าย/ขวา
local ANIMATION_LEFT = "0"    -- ID ท่าแดชอ้อมฝั่งซ้าย
local ANIMATION_RIGHT = "0"   -- ID ท่าแดชอ้อมฝั่งขวา

-- [[ SERVICES ]] --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
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
ScreenGui.Name = "ArcDashGui"
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

-- [[ 1. SELECT TARGET SYSTEM (DOUBLE TAP) ]] --
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

-- [[ QUADRATIC BEZIER CURVE FUNCTION ]] --
local function getQuadraticBezierPoint(p0, p1, p2, t)
    return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

-- [[ 2. ARC SIDE DASH SYSTEM ]] --
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
        
        if currentDist <= DISTANCE then
            isDashing = true

            -- 1. เช็คตำแหน่งเป้าหมายบนหน้าจอ (เพื่อเลือกฝั่งโค้ง ซ้าย หรือ ขวา)
            local screenPos = camera:WorldToViewportPoint(selectedTargetRoot.Position)
            local screenWidth = camera.ViewportSize.X
            local isLeft = (screenPos.X < screenWidth / 2)
            local sideName = isLeft and "Left" or "Right"

            -- 2. เล่น Animation
            local activeTrack = playSideAnimation(humanoid, sideName)

            -- 3. คำนวณจุดเริ่มต้น (P0) และ จุดสิ้นสุดหลังเป้าหมาย (P2)
            local startPos = myRoot.Position
            local targetVelocity = selectedTargetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            local predictedTargetPos = selectedTargetRoot.Position + (targetVelocity * PREDICTION)
            local targetLookVector = selectedTargetRoot.CFrame.LookVector
            
            -- จุดหยุดหลังเป้าหมาย (Distance = RANGE = 4)
            local endPos = predictedTargetPos - (targetLookVector * RANGE)
            endPos = Vector3.new(endPos.X, selectedTargetRoot.Position.Y, endPos.Z)

            -- 4. คำนวณจุดดึงเส้นโค้ง (Control Point - P1)
            local midPoint = (startPos + endPos) / 2
            local targetRightVector = selectedTargetRoot.CFrame.RightVector
            
            -- ถ้าอยู่ซ้ายหน้าจอ โค้งเบี่ยงออกทางซ้าย / ถ้าอยู่ขวาหน้าจอ โค้งเบี่ยงออกทางขวา
            local curveDirection = isLeft and -targetRightVector or targetRightVector
            local controlPos = midPoint + (curveDirection * ARC_OFFSET)

            -- 5. คำนวณเวลาและระยะทางวิถีโค้ง
            local approxDistance = (startPos - controlPos).Magnitude + (controlPos - endPos).Magnitude
            local baseDuration = math.max(approxDistance / SPEED_N, 0.1)

            -- 6. ทำการเคลื่อนที่แบบเส้นโค้ง (Arc Movement) พร้อมชะลอตอนท้าย
            local startTime = tick()
            local connection
            
            connection = RunService.RenderStepped:Connect(function()
                local elapsed = tick() - startTime
                local rawT = math.clamp(elapsed / baseDuration, 0, 1)
                
                -- ชะลอความเร็วตอนใกล้ถึงจุดหมาย (Ease Out Quad)
                local t = 1 - (1 - rawT) * (1 - rawT)
                
                -- คำนวณตำแหน่งบนเส้นโค้ง ณ เวลา t
                local currentArcPos = getQuadraticBezierPoint(startPos, controlPos, endPos, t)
                
                -- หันหน้าไปทิศทางเป้าหมายระหว่างพุ่งโค้ง
                myRoot.CFrame = CFrame.new(currentArcPos, predictedTargetPos)

                if rawT >= 1 then
                    connection:Disconnect()
                    -- ปรับ CFrame ขั้นสุดท้ายให้หันเข้าหลังเป้าหมายเป๊ะๆ
                    myRoot.CFrame = CFrame.new(endPos, predictedTargetPos)
                    
                    if activeTrack then
                        activeTrack:Stop()
                    end
                    isDashing = false
                end
            end)
        else
            print("[Arc Dash] Out of Distance! Max: " .. DISTANCE)
        end
    else
        print("[Arc Dash] No target selected! Double tap a player/NPC first.")
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

print("[Arc Dash] Curve Side Dash Loaded Successfully!")
