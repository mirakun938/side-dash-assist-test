-- [[ CONFIGURATION ]] --
local DISTANCE = 30           -- ระยะทางสูงสุดที่ต้องเข้าใกล้เป้าหมายก่อนถึงจะใช้ Side Dash ได้ (30 Studs)
local RANGE = 4               -- ระยะห่างที่จะไปหยุดอยู่ด้านหลังเป้าหมาย (4 Studs)
local SPEED_N = 95            -- ความเร็วตั้งต้นในการพุ่ง (95 Studs per second)
local PREDICTION = 0.1        -- การคาดการณ์การเคลื่อนที่ล่วงหน้า
local CURVE_OFFSET = 12       -- ระยะความโค้งที่พุ่งออกไปด้านข้าง (ยิ่งเยอะยิ่งโค้งกว้าง)

-- 🎬 ช่องใส่ ID Animation
local ANIMATION_LEFT = "0"    -- เล่นเมื่อเป้าหมายอยู่ฝั่ง "ซ้าย" ของหน้าจอ
local ANIMATION_RIGHT = "0"   -- เล่นเมื่อเป้าหมายอยู่ฝั่ง "ขวา" ของหน้าจอ

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

-- [[ DUAL ANIMATION SYSTEM ]] --
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

-- [[ CREATE UI BUTTON FOR DASH ]] --
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SelectDashGui"
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

-- [[ HIGHLIGHT FOR SELECTED TARGET ]] --
local highlight = Instance.new("Highlight")
highlight.Name = "TargetSelectHighlight"
highlight.FillColor = Color3.fromRGB(255, 0, 0)
highlight.FillTransparency = 0.3
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0
highlight.Parent = ScreenGui

-- [[ 1. SELECT TARGET SYSTEM (DOUBLE TAP PLAYER/NPC) ]] --
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

-- [[ UPDATE HIGHLIGHT & DESELECT IF DEAD ]] --
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

-- [[ BEZIER CURVE CALCULATION (สำหรับพุ่งโค้งแบบในรูป) ]] --
local function getQuadraticBezierPoint(p0, p1, p2, t)
    return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

-- [[ 2. PERFORM CURVE DASH TO BEHIND TARGET ]] --
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

            -- ตรวจสอบว่าเป้าหมายอยู่ฝั่งซ้ายหรือขวาของหน้าจอ
            local screenPos = camera:WorldToViewportPoint(selectedTargetRoot.Position)
            local screenWidth = camera.ViewportSize.X
            local side = (screenPos.X < screenWidth / 2) and "Left" or "Right"

            -- เล่น Animation ตามฝั่ง
            local activeTrack = playSideAnimation(humanoid, side)

            -- 1. จุดเริ่มต้น (P0): ตำแหน่งปัจจุบันของเรา
            local p0 = myRoot.Position

            -- คำนวณตำแหน่งล่วงหน้าของเป้าหมาย
            local targetVelocity = selectedTargetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            local predictedPos = selectedTargetRoot.Position + (targetVelocity * PREDICTION)
            local targetCFrame = selectedTargetRoot.CFrame

            -- 2. จุดปลายทาง (P2): อยู่ด้านหลังเป้าหมายที่ระยะ RANGE (4 Studs)
            local behindPos = predictedPos - (targetCFrame.LookVector * RANGE)
            local p2 = Vector3.new(behindPos.X, selectedTargetRoot.Position.Y, behindPos.Z)

            -- 3. จุดส่วนโค้งด้านข้าง (P1 - Control Point): ฉีกออกไปทางซ้ายของเป้าหมายตามรูปวาด
            local sideVector = -targetCFrame.RightVector -- ฉีกไปทางฝั่งซ้ายของเป้าหมาย
            local p1 = targetCFrame.Position + (sideVector * CURVE_OFFSET)

            -- คำนวณระยะทางรวมตามเส้นโค้งเพื่อหาเวลา (Duration)
            local totalDistance = (p0 - p1).Magnitude + (p1 - p2).Magnitude
            local duration = math.max(totalDistance / SPEED_N, 0.15)

            -- ทำการเคลื่อนที่แบบเส้นโค้ง (Arc) ด้วย RenderStepped
            local startTime = tick()
            local connection

            connection = RunService.RenderStepped:Connect(function()
                local elapsed = tick() - startTime
                local alpha = math.clamp(elapsed / duration, 0, 1)

                -- ใช้ Quad Ease Out ชะลอความเร็วช่วงใกล้ถึงจุดหมาย
                local smoothAlpha = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

                -- คำนวณตำแหน่งพิกัดเส้นโค้ง ณ วินาทีนั้นๆ
                local currentPos = getQuadraticBezierPoint(p0, p1, p2, smoothAlpha)
                
                -- หันหน้าเข้าหาเป้าหมายตลอดเวลาขณะกำลังพุ่งโค้ง
                myRoot.CFrame = CFrame.new(currentPos, predictedPos)

                if alpha >= 1 then
                    connection:Disconnect()
                    
                    -- จบการพุ่ง: หันหน้าเข้าหาด้านหลังเป้าหมายเต็มตัว
                    myRoot.CFrame = CFrame.new(p2, predictedPos)

                    if activeTrack then
                        activeTrack:Stop()
                    end
                    isDashing = false
                end
            end)
        else
            print("[Select Dash] Out of Distance! Current: " .. math.floor(currentDist) .. " Studs (Max: " .. DISTANCE .. ")")
        end
    else
        print("[Select Dash] No target selected! Double tap a player/NPC first.")
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

print("[Select Target Mode] Exact Arc Curve Dash (Bezier Path) Loaded!")
