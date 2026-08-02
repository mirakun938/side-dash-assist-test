-- [[ CONFIGURATION ]] --
local DISTANCE = 30           -- ระยะทางสูงสุดที่ต้องเข้าใกล้เป้าหมายก่อนถึงจะใช้ Side Dash ได้ (30 Studs)
local RANGE = 4               -- ระยะห่างที่จะไปหยุดอยู่ด้านหลังเป้าหมาย (4 Studs)
local SPEED_N = 95            -- ความเร็วตั้งต้นในการพุ่ง (95 Studs per second)
local PREDICTION = 0.1        -- การคาดการณ์การเคลื่อนที่ล่วงหน้า

-- 🎬 ช่องใส่ ID Animation (ใส่ตัวเลข ID ได้เลยครับ)
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

-- [[ 2. PERFORM DASH WITH DUAL ANIMATION & DECELERATION ]] --
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

            -- ตรวจสอบว่าเป้าหมายอยู่ฝั่งซ้ายหรือขวาของหน้าจอ (Screen Position)
            local screenPos, onScreen = camera:WorldToViewportPoint(selectedTargetRoot.Position)
            local screenWidth = camera.ViewportSize.X
            local side = (screenPos.X < screenWidth / 2) and "Left" or "Right"

            -- เล่น Animation ตามฝั่งหน้าจอที่เป้าหมายอยู่
            local activeTrack = playSideAnimation(humanoid, side)

            -- คำนวณพิกัดเป้าหมายด้านหลัง (RANGE = 4)
            local targetVelocity = selectedTargetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            local predictedPos = selectedTargetRoot.Position + (targetVelocity * PREDICTION)
            local targetLookVector = selectedTargetRoot.CFrame.LookVector
            local behindPos = predictedPos - (targetLookVector * RANGE)
            behindPos = Vector3.new(behindPos.X, selectedTargetRoot.Position.Y, behindPos.Z)

            -- คำนวณระยะทางและเวลา
            local dashDistance = (myRoot.Position - behindPos).Magnitude
            local baseDuration = math.max(dashDistance / SPEED_N, 0.05)

            -- ปรับใช้ Quad + Out เพื่อให้พุ่งเร็วช่วงแรก และค่อยๆ ชะลอความเร็วลงเมื่อใกล้ถึงเป้าหมาย
            local tweenInfo = TweenInfo.new(
                baseDuration * 1.25,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            )

            local tween = TweenService:Create(myRoot, tweenInfo, {
                CFrame = CFrame.new(behindPos, predictedPos)
            })
            
            tween:Play()
            tween.Completed:Wait()

            -- หยุด Animation เมื่อแดชเสร็จสิ้น
            if activeTrack then
                activeTrack:Stop()
            end
            
            isDashing = false
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

print("[Select Target Mode] Dual Screen-Based Animation System Loaded!")
