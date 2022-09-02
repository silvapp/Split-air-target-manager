function widget:GetInfo()
    return {
        name = "Split air target manager",
        desc = "To enable select AA and press Alt+Space, to disable deselect any unit and press Alt+Space two times",
        author = "[MOL]Silver",
        version = "1.3",
        date = "25.08.2022",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true
    }
end

local maxTargetsPerEnemy = 1
local minPower = 60 -- skip t1 air scouts
local rangeMultiplier = 1.4
local CMD_UNIT_SET_TARGET = 34923
local CMD_UNIT_CANCEL_TARGET = 34924
local ENEMY_UNITS = Spring.ENEMY_UNITS
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitsInSphere = Spring.GetUnitsInSphere
local GetUnitViewPosition = Spring.GetUnitViewPosition
local GiveOrderToUnit = Spring.GiveOrderToUnit
local glColor = gl.Color
local glDrawGroundCircle = gl.DrawGroundCircle
local glLineStipple = gl.LineStipple
local glVertex = gl.Vertex
local glLineWidth = gl.LineWidth
local glBeginEnd = gl.BeginEnd
local GL_LINE_STRIP = GL.LINE_STRIP
local GetKeyCode = Spring.GetKeyCode
local targetPerEnemy = {}
local targetData = {}
local UnitDefsCachedAA = {}
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitWeaponTestTarget = Spring.GetUnitWeaponTestTarget
local GetSelectedUnits = Spring.GetSelectedUnits
local ghostedEnemyData = {}
local n = 0



local AllowedWeapons = {}
for index, udefs in pairs(UnitDefs) do
    if udefs.weapons[1] and udefs.weapontype ~= "Shield" then
        local isShield
        for wdefName, value in udefs.wDefs[1]:pairs() do
            if wdefName == "isShield" then
                isShield = value
            end
        end
        local wNumber = udefs.primaryWeapon
        if udefs.weapons[wNumber].onlyTargets.vtol == true and not isShield and not udefs.isMobileBuilder then
            AllowedWeapons[udefs.id] = {
                name = udefs.name,
                maxWeaponRange = udefs.maxWeaponRange
            }
        end
    end
end

local UnitDefsCached = {}
for name, udefs in pairs(UnitDefs) do
    if udefs.canFly then
        local power = udefs.metalCost
        power = math.pow(power / minPower, 5)
        UnitDefsCached[udefs.id] = {
            power = power
        }
    end
end

local function compare(a, b)
    return a[1] > b[1]
end

function widget:KeyPress(key, modifier, isRepeat)
    if not modifier["alt"] and not isRepeat then
        n = 0
    end
    if key == GetKeyCode("space") and modifier["alt"] and not modifier["shift"] and not modifier["ctrl"] and not isRepeat then
        local SelectedUnits = GetSelectedUnits()
        if #SelectedUnits == 0 then
            n = n + 1
            if n > 1 then
                UnitDefsCachedAA = {}
                n = 0
            end
        end
        for _, unitID in pairs(SelectedUnits) do
            local udefid =  GetUnitDefID(unitID)
            if not UnitDefsCachedAA[unitID] and AllowedWeapons[udefid] then
                local udefs = UnitDefs[Spring.GetUnitDefID(unitID)]
                UnitDefsCachedAA[unitID] = {
                    maxWeaponRange = udefs.maxWeaponRange
                }
            end
        end
    end
end

function widget:GameFrame(f)
    if f % 15 == 0 then
        targetPerEnemy = {}
        targetData = {}
        checkTargets()
    end
end

function checkTargets()
    for unitID, def in pairs(UnitDefsCachedAA) do
        GiveOrderToUnit(unitID, CMD_UNIT_CANCEL_TARGET, {}, {})
        local range = def.maxWeaponRange * rangeMultiplier
        local x, y, z = GetUnitPosition(unitID, true, false)
        local enemyData = {}
        local j = 0
        local k = 0
        if x and y and z then
            local EnemyUnitsInRange = GetUnitsInSphere(x, y, z, range, ENEMY_UNITS)
            for i = 1, #EnemyUnitsInRange do
                local EnemyUnitID = EnemyUnitsInRange[i]
                if targetData[unitID] ~= EnemyUnitID then
                    k = k + 1
                end
                local uidid = GetUnitDefID(EnemyUnitID)
                local udefs = UnitDefsCached[uidid]
                if udefs then
                    local power = udefs.power
                    if minPower < power then
                        j = j + 1
                        local separation = GetUnitSeparation(unitID, EnemyUnitID, true)
                        local priority = power / separation
                        enemyData[j] = {priority, EnemyUnitID, unitID}
                        ghostedEnemyData[EnemyUnitID] = {
                            power = power,
                        }
                    end
                else
                    if ghostedEnemyData[EnemyUnitID] then
                        j = j + 1
                        local power = ghostedEnemyData[EnemyUnitID].power
                        local separation = GetUnitSeparation(unitID, EnemyUnitID, true)
                        local priority = power / separation
                        enemyData[j] = {priority, EnemyUnitID, unitID}
                    else
                        local TestTarget = GetUnitWeaponTestTarget(unitID, 1, EnemyUnitID)
                        if TestTarget == true then
                            j = j + 1
                            local separation = GetUnitSeparation(unitID, EnemyUnitID, true)
                            local power = minPower
                            local priority = power / separation
                            enemyData[j] = {priority, EnemyUnitID, unitID}
                        end
                    end
                end
            end
        end
        if j == k then
            targetData[unitID] = nil
        end
        if #enemyData > 0 then
            Spring.Echo(#enemyData)
            table.sort(enemyData, compare)
            for i, v in pairs(enemyData) do
                if not targetPerEnemy[v[2]] then
                    targetPerEnemy[v[2]] = 1
                    if v[3] then
                        targetData[v[3]] = v[2]
                    end
                    break
                end
            end
            -- for i, v in pairs(enemyData) do
            --     if targetPerEnemy[v[2]] and targetPerEnemy[v[2]] <= maxTargetsPerEnemy then
            --         targetPerEnemy[v[2]] = targetPerEnemy[v[2]] + 1
            --         lastUnitID = v[3]
            --         if targetData[v[3]] then
            --             targetData[v[3]] = v[2]
            --         end
            --         break
            --     end
            -- end
            if tonumber(targetData[unitID]) ~= nil then
                GiveOrderToUnit(unitID, CMD_UNIT_SET_TARGET, {targetData[unitID]}, {})
            end
        end
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if UnitDefsCachedAA[unitID] then
        UnitDefsCachedAA[unitID] = nil
        targetData[unitID] = nil
    end
    if ghostedEnemyData[unitID] then
        ghostedEnemyData[unitID] = nil
    end
end

function widget:UnitCreated(unitID, allyTeam)
    if ghostedEnemyData[unitID] then
        ghostedEnemyData[unitID] = nil
    end
end

local function Line(a, b)
    glVertex(a[1], a[2], a[3])
    glVertex(b[1], b[2], b[3])
end

local function DrawLine(a, b)
    glLineStipple(false)
    glBeginEnd(GL_LINE_STRIP, Line, a, b)
end

function widget:DrawWorld()
    for unitID in pairs(UnitDefsCachedAA) do
        if unitID then
            local ux, uy, uz = GetUnitViewPosition(unitID)
            if ux and uy and uz then
                glLineWidth(2)
                glColor(1.0, 0.2, 0.0, 0.5)
                glDrawGroundCircle(ux, uy, uz, 40, 3)
                if targetData[unitID] then
                    local ex, ey, ez = GetUnitViewPosition(targetData[unitID])
                    if ex and ey and ez then
                        glLineWidth(3)
                        glColor(1.0, 0.2, 0.0, 0.5)
                        DrawLine({ux, uy, uz}, {ex, ey, ez})
                    end
                end
            end
        end
    end
    glLineWidth(1)
    glColor(1, 1, 1, 1)
end
