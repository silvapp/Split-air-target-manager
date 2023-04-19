function widget:GetInfo()
    return {
        name = "Split air target manager",
        desc = "To enable select AA and press Alt+Space, to disable deselect any unit and press Alt+Space two times",
        author = "[MOL]Silver",
        version = "1.61",
        date = "12.04.2023",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true
    }
end

local maxTargetsPerEnemy = 2 -- if "weak" AA
local minPower = 0.040 -- skip T1 scouts 
local rangeMultiplier = 1.25
local CMD_UNIT_SET_TARGET = 34923
local CMD_UNIT_CANCEL_TARGET = 34924
local ENEMY_UNITS = Spring.ENEMY_UNITS
local GetKeyCode = Spring.GetKeyCode
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitIsDead = Spring.GetUnitIsDead
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitsInSphere = Spring.GetUnitsInSphere
local GetUnitViewPosition = Spring.GetUnitViewPosition
local GetUnitWeaponState = Spring.GetUnitWeaponState
local GetUnitWeaponHaveFreeLineOfFire = Spring.GetUnitWeaponHaveFreeLineOfFire
local GiveOrderToUnit = Spring.GiveOrderToUnit
local GL_LINE_STRIP = GL.LINE_STRIP
local glBeginEnd = gl.BeginEnd
local glColor = gl.Color
local glDrawGroundCircle = gl.DrawGroundCircle
local glLineStipple = gl.LineStipple
local glLineWidth = gl.LineWidth
local glVertex = gl.Vertex
local allowedWeapons = {}
local ghostedEnemyData = {}
local targetData = {}
local targetPerEnemy = {}
local unitDefsCached = {}
local myDefenders = {}
local PriorityTargets = {}

-- local ArmorDefs = VFS.Include("gamedata/armordefs.lua")
-- if ArmorDefs.priority_air then
--     PriorityTargets = ArmorDefs.priority_air
-- else
--     if ArmorDefs.bombers then
--         PriorityTargets = ArmorDefs.bombers
--     end
-- end

-- for unitID, def in pairs(myDefenders) do repeat
-- if not isLoaded then do break end end
--      
--  --end
-- until true

PriorityTargets = { -- "Bombers"
                   "armcybr", "armlance", "armpnix", "armthund", "armcyclone", "armgripn", "corhurc", "corshad", "cortitan", "tllabomber",
                   "tllbomber", "tlltorpp", "coreclipse", "corseap", "armseap", "corsbomb", "armorion", "tllanhur", "tllaether", "talon_shade",
                   "talon_eclipse", "talon_handgod", "gok_dirgesinger", "gok_hookah", "gok_nurgle",
                    -- "Transporters"
                    "armatlas", "armdfly", "corseahook", "corvalk", "tllrobber", "tlltplane", "armmuat", "tllbtrans", "cormuat", "talon_wyvern",
                    "talon_rukh", "talon_tau", "talon_plutor", "talon_spirit", "corlift", "armlift", "gok_chariot", "gok_wordbearer", "gok_benne",}

function widget:Initialize()
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
                local isWeak = false
                if udefs.metalCost < 400 then
                    isWeak = true
                end
                allowedWeapons[udefs.id] = {
                    maxWeaponRange = udefs.maxWeaponRange,
                    weakWeapon = isWeak,
                    name = udefs.name
                }
            end
        end
    end

    for id, udefs in pairs(UnitDefs) do
        if udefs.canFly then
            local cost = udefs.metalCost
            local power = cost / 1000
            local unitName
            for i, name in pairs(PriorityTargets) do
                if name == udefs.name then
                    power = math.pow(cost / 10, 5)
                    unitName = name
                end
            end
            unitDefsCached[udefs.id] = {
                power = power,
                name = unitName,
            }
        end
    end
end

local function compare(a, b)
    return a[1] > b[1]
end

local n = 0
function widget:KeyPress(key, modifier, isRepeat)
    if not modifier["alt"] and not isRepeat then
        n = 0
    end
    if key == GetKeyCode("space") and modifier["alt"] and not modifier["shift"] and not modifier["ctrl"] and not isRepeat then
        local SelectedUnits = GetSelectedUnits()
        if #SelectedUnits == 0 then
            n = n + 1
            if n > 1 then
                myDefenders = {}
                n = 0
            end
        end
        for _, unitID in pairs(SelectedUnits) do
            local unitDefID = GetUnitDefID(unitID)
            if not myDefenders[unitID] and allowedWeapons[unitDefID] then
                myDefenders[unitID] = allowedWeapons[unitDefID]
            end
        end
    end
end

function widget:GameFrame(f)
    if f % 10 == 0 then
        targetPerEnemy = {}
        targetData = {}
        checkTargets()
    end
end

function widget:Update()
    for enemyID in pairs(ghostedEnemyData) do
        local isDead = GetUnitIsDead(enemyID)
        if isDead then
            ghostedEnemyData[enemyID] = nil
        end
    end
end

function checkTargets()
    for unitID, def in pairs(myDefenders) do
        local _, isLoaded = GetUnitWeaponState(unitID, 1)
        if isLoaded then
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
                    local unitDefID = GetUnitDefID(EnemyUnitID)
                    local udefs = unitDefsCached[unitDefID]

                    if udefs then
                        -- Spring.Echo("unitDef: is known")
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
                            --Spring.Echo("ghostedEnemy: yes")
                            j = j + 1
                            local power = ghostedEnemyData[EnemyUnitID].power
                            local separation = GetUnitSeparation(unitID, EnemyUnitID, true)
                            local priority = power / separation
                            enemyData[j] = {priority, EnemyUnitID, unitID}
                        else
                            -- -- uncomment if want split/sort unknown radar dots 
                            -- Spring.Echo("unknown dot: yes")
                            -- j = j + 1
                            -- local separation = GetUnitSeparation(unitID, EnemyUnitID, true)
                            -- local power = minPower
                            -- local priority = power / separation
                            -- enemyData[j] = {priority, EnemyUnitID, unitID}
                        end

                    end
                end
            end

            if j == k then
                targetData[unitID] = nil
            end

            if #enemyData > 0 then
                table.sort(enemyData, compare)

                if def.weakWeapon == false then
                    for i, v in pairs(enemyData) do
                        -- v[1] priority value
                        -- v[2] enemyID
                        -- v[3] your unitID (weapon)
                        if not targetPerEnemy[v[2]] or targetPerEnemy[v[2]][1] == false then
                            local testTarget = GetUnitWeaponHaveFreeLineOfFire(v[3], 1, v[2])
                            if testTarget == true then
                                targetPerEnemy[v[2]] = {true, 1}
                                --if v[3] then
                                    targetData[v[3]] = v[2]
                                --end
                                break
                            end
                        end
                    end
                end

                if def.weakWeapon == true then
                    for i, v in pairs(enemyData) do
                        if targetPerEnemy[v[2]] == nil then
                            targetPerEnemy[v[2]] = {false, 1}
                        end
                        if targetPerEnemy[v[2]][2] <= maxTargetsPerEnemy then
                            targetPerEnemy[v[2]][2] = targetPerEnemy[v[2]][2] + 1
                            targetData[v[3]] = v[2]
                            break
                        end
                    end
                end

                if tonumber(targetData[unitID]) ~= nil then
                    GiveOrderToUnit(unitID, CMD_UNIT_SET_TARGET, {targetData[unitID]}, {})
                end
            end
        end
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if myDefenders[unitID] then
        myDefenders[unitID] = nil
        targetData[unitID] = nil
    end
end

function widget:UnitCreated(unitID, allyTeam)
    --kill the dot info if this unitID gets reused on own team
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
    for unitID in pairs(myDefenders) do
        if unitID then
            local ux, uy, uz = GetUnitViewPosition(unitID)
            if ux and uy and uz then
                glLineWidth(2)
                glColor(1.0, 0.2, 0.0, 0.5)
                glDrawGroundCircle(ux, uy, uz, 50, 3)
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