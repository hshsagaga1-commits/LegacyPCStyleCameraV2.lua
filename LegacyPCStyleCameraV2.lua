local Players = game:GetService("Players")

local player = Players.LocalPlayer
local env = getgenv and getgenv() or _G

if env.__EvadeLegacyPCStyleCameraV2 then
    local old = env.__EvadeLegacyPCStyleCameraV2

    pcall(function()
        if old.baseCamera
            and old.originalGetSubjectPosition
            and old.baseCamera.GetSubjectPosition == old.wrapper
        then
            old.baseCamera.GetSubjectPosition = old.originalGetSubjectPosition
        end
    end)

    pcall(function()
        if old.gui then
            old.gui:Destroy()
        end
    end)

    old.running = false
end

local state = {
    running = true,
    baseCamera = nil,
    originalGetSubjectPosition = nil,
    wrapper = nil,
    gui = nil,
    controllers = setmetatable({}, {__mode = "k"})
}

env.__EvadeLegacyPCStyleCameraV2 = state

local HORIZONTAL_FOLLOW = 8.5
local VERTICAL_FOLLOW = 15.5
local MAX_HORIZONTAL_LAG = 4.25
local MAX_VERTICAL_LAG = 1.15
local MIN_HORIZONTAL_LAG = 1.15
local MIN_VERTICAL_LAG = 0.35
local HORIZONTAL_DISTANCE_FACTOR = 0.30
local VERTICAL_DISTANCE_FACTOR = 0.08
local RESET_DISTANCE = 30
local RESET_TIME = 0.30
local FIRST_PERSON_DISTANCE = 1.9

local function findLegacyBaseCamera()
    local playerScripts = player:FindFirstChild("PlayerScripts")

    if not playerScripts then
        return nil
    end

    local playerModule = playerScripts:FindFirstChild("PlayerModule")

    if not playerModule then
        return nil
    end

    local cameraModule = playerModule:FindFirstChild("CameraModule")

    if not cameraModule then
        return nil
    end

    if cameraModule:FindFirstChild("CameraInput") then
        return nil
    end

    local baseCamera = cameraModule:FindFirstChild("BaseCamera")

    if baseCamera and baseCamera:IsA("ModuleScript") then
        return baseCamera
    end

    return nil
end

local function createCrosshair()
    local playerGui = player:WaitForChild("PlayerGui")

    local oldGui = playerGui:FindFirstChild("EvadeLegacyPCCrosshair")

    if oldGui then
        oldGui:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "EvadeLegacyPCCrosshair"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local shadow = Instance.new("Frame")
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.Size = UDim2.fromOffset(8, 8)
    shadow.BackgroundColor3 = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency = 0.55
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 1
    shadow.Parent = gui

    local shadowCorner = Instance.new("UICorner")
    shadowCorner.CornerRadius = UDim.new(1, 0)
    shadowCorner.Parent = shadow

    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromScale(0.5, 0.5)
    dot.Size = UDim2.fromOffset(4, 4)
    dot.BackgroundColor3 = Color3.new(1, 1, 1)
    dot.BorderSizePixel = 0
    dot.ZIndex = 2
    dot.Parent = gui

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = dot

    state.gui = gui
end

local function clampHorizontal(vector, maxMagnitude)
    local flat = Vector3.new(vector.X, 0, vector.Z)
    local magnitude = flat.Magnitude

    if magnitude > maxMagnitude and magnitude > 0 then
        flat = flat.Unit * maxMagnitude
    end

    return flat
end

local function getDistance(self)
    local ok, distance = pcall(function()
        return self:GetCameraToSubjectDistance()
    end)

    if ok and type(distance) == "number" then
        return distance
    end

    return nil
end

local function isLocalHumanoidSubject()
    local camera = workspace.CurrentCamera

    if not camera then
        return false
    end

    local subject = camera.CameraSubject
    local character = player.Character

    return subject
        and character
        and subject:IsA("Humanoid")
        and subject.Parent == character
end

local function attach()
    local module = findLegacyBaseCamera()

    if not module then
        return false
    end

    local ok, baseCamera = pcall(require, module)

    if not ok
        or type(baseCamera) ~= "table"
        or type(baseCamera.GetSubjectPosition) ~= "function"
    then
        return false
    end

    if state.baseCamera == baseCamera
        and baseCamera.GetSubjectPosition == state.wrapper
    then
        return true
    end

    if state.baseCamera
        and state.originalGetSubjectPosition
        and state.baseCamera.GetSubjectPosition == state.wrapper
    then
        pcall(function()
            state.baseCamera.GetSubjectPosition = state.originalGetSubjectPosition
        end)
    end

    local original = baseCamera.GetSubjectPosition

    local function wrapper(self, ...)
        local realPosition = original(self, ...)

        if typeof(realPosition) ~= "Vector3" then
            return realPosition
        end

        if not isLocalHumanoidSubject() then
            state.controllers[self] = nil
            return realPosition
        end

        local distance = getDistance(self)

        if distance and distance <= FIRST_PERSON_DISTANCE then
            state.controllers[self] = nil
            return realPosition
        end

        local now = os.clock()
        local data = state.controllers[self]

        if not data then
            data = {
                focus = realPosition,
                lastReal = realPosition,
                time = now
            }

            state.controllers[self] = data
            return realPosition
        end

        local dt = now - data.time
        data.time = now

        local deltaFromLast = realPosition - data.lastReal
        data.lastReal = realPosition

        if dt <= 0
            or dt > RESET_TIME
            or deltaFromLast.Magnitude > RESET_DISTANCE
        then
            data.focus = realPosition
            return realPosition
        end

        dt = math.min(dt, 1 / 20)

        local maxHorizontal = MAX_HORIZONTAL_LAG
        local maxVertical = MAX_VERTICAL_LAG

        if distance then
            maxHorizontal = math.clamp(
                distance * HORIZONTAL_DISTANCE_FACTOR,
                MIN_HORIZONTAL_LAG,
                MAX_HORIZONTAL_LAG
            )

            maxVertical = math.clamp(
                distance * VERTICAL_DISTANCE_FACTOR,
                MIN_VERTICAL_LAG,
                MAX_VERTICAL_LAG
            )
        end

        local current = data.focus
        local horizontalAlpha = 1 - math.exp(-HORIZONTAL_FOLLOW * dt)
        local verticalAlpha = 1 - math.exp(-VERTICAL_FOLLOW * dt)

        local nextHorizontal =
            Vector3.new(current.X, 0, current.Z):Lerp(
                Vector3.new(realPosition.X, 0, realPosition.Z),
                horizontalAlpha
            )

        local nextY =
            current.Y
            + (realPosition.Y - current.Y) * verticalAlpha

        local nextFocus =
            Vector3.new(
                nextHorizontal.X,
                nextY,
                nextHorizontal.Z
            )

        local lag = nextFocus - realPosition

        local horizontalLag =
            clampHorizontal(lag, maxHorizontal)

        local verticalLag =
            math.clamp(
                lag.Y,
                -maxVertical,
                maxVertical
            )

        nextFocus =
            realPosition
            + horizontalLag
            + Vector3.new(0, verticalLag, 0)

        data.focus = nextFocus

        return nextFocus
    end

    state.baseCamera = baseCamera
    state.originalGetSubjectPosition = original
    state.wrapper = wrapper

    baseCamera.GetSubjectPosition = wrapper

    return true
end

pcall(createCrosshair)

player.CharacterAdded:Connect(function()
    state.controllers =
        setmetatable({}, {__mode = "k"})
end)

task.spawn(function()
    while state.running do
        pcall(attach)
        task.wait(0.5)
    end
end)

pcall(attach)