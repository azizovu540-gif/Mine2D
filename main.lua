-- Управление:
-- F5 — Сохранить мир
-- F9 — Загрузить мир
-- Esc — Пауза | A, D — Бег | Пробел — Прыжок
-- ЛКМ — Сломать блок | ПКМ — Поставить блок

local world = {}
local WORLD_WIDTH = 70
local WORLD_HEIGHT = 40
local TILE_SIZE = 32

local gameState = "menu"

local BLOCKS = {
    [1] = { name = "Трава", color = { 0.2, 0.7, 0.2 } },
    [2] = { name = "Земля", color = { 0.5, 0.3, 0.1 } },
    [3] = { name = "Камень", color = { 0.5, 0.5, 0.5 } },
    [4] = { name = "Древесина", color = { 0.6, 0.4, 0.2 } },
    [5] = { name = "Листва", color = { 0.1, 0.5, 0.1 } }
}

local selectedBlock = 1
local camX, camY = 0, 0
local menuTimer = 0

-- Для уведомлений о сохранении/загрузке
local saveNotificationText = ""
local saveNotificationTimer = 0

local tilesetImage = nil
local tilesetQuads = {}
local bgMusic = nil

local player = {
    x = 0, y = 0, width = 20, height = 54,
    vx = 0, vy = 0, speed = 180, gravity = 950, jumpForce = -390,
    grounded = false, animTimer = 0, direction = 1
}

local buttons = {
    menu = {
        play = { x = 300, y = 260, w = 200, h = 45, text = "Играть", hovered = false },
        exit = { x = 300, y = 325, w = 200, h = 45, text = "Выход", hovered = false }
    },
    paused = {
        resume = { x = 300, y = 240, w = 200, h = 45, text = "Продолжить", hovered = false },
        toMenu = { x = 300, y = 305, w = 200, h = 45, text = "В главное меню", hovered = false }
    }
}

-- Функция генерации звука
local function playDigSound()
    local samplingRate = 44100
    local duration = 0.08
    local numSamples = math.floor(samplingRate * duration)
    local soundData = love.sound.newSoundData(numSamples, samplingRate, 16, 1)
    for i = 0, numSamples - 1 do
        local t = i / samplingRate
        local frequency = 800 + (1 - (t / duration)) * 400
        local sample = math.sin(t * frequency * math.pi * 2) * (1 - (t / duration))
        soundData:setSample(i, sample)
    end
    local audioSource = love.audio.newSource(soundData)
    audioSource:setVolume(0.4)
    audioSource:play()
end

-- =========================================================
-- СИСТЕМА СОХРАНЕНИЯ И ЗАГРУЗКИ
-- =========================================================
local function saveWorld()
    local data = ""
    -- Записываем размеры мира
    data = data .. WORLD_WIDTH .. "," .. WORLD_HEIGHT .. "\n"
    -- Записываем координаты игрока
    data = data .. player.x .. "," .. player.y .. "\n"
    
    -- Записываем ID всех блоков через запятую
    for x = 1, WORLD_WIDTH do
        local columnData = {}
        for y = 1, WORLD_HEIGHT do
            table.insert(columnData, world[x][y])
        end
        data = data .. table.concat(columnData, ",") .. "\n"
    end
    
    -- Сохраняем в системную папку проекта
    love.filesystem.write("world.dat", data)
    
    saveNotificationText = "Мир успешно сохранен! (F5)"
    saveNotificationTimer = 2.5 -- Показывать 2.5 секунды
end

local function loadWorld()
    -- Проверяем, существует ли файл сохранения
    if not love.filesystem.getInfo("world.dat") then
        saveNotificationText = "Файл сохранения не найден!"
        saveNotificationTimer = 2.5
        return
    end
    
    local lineNum = 1
    local currentX = 1
    
    -- Читаем файл построчно
    for line in love.filesystem.lines("world.dat") do
        if lineNum == 1 then
            -- Первая строчка — (не используется, берем базовые настройки)
        elseif lineNum == 2 then
            -- Вторая строчка — координаты игрока
            local px, py = line:match("([^,]+),([^,]+)")
            if px and py then
                player.x = tonumber(px)
                player.y = tonumber(py)
                player.vx = 0
                player.vy = 0
            end
        else
            -- Последующие строки — колонки блоков
            world[currentX] = {}
            local currentY = 1
            for value in line:gmatch("([^,]+)") do
                world[currentX][currentY] = tonumber(value)
                currentY = currentY + 1
            end
            currentX = currentX + 1
        end
        lineNum = lineNum + 1
    end
    
    saveNotificationText = "Мир успешно загружен! (F9)"
    saveNotificationTimer = 2.5
end
-- =========================================================

local function checkCollision(x, y, w, h, bx, by, bw, bh)
    return x < bx + bw and x + w > bx and y < by + bh and y + h > by
end

local function isSolid(gx, gy)
    if gx < 1 or gx > WORLD_WIDTH or gy < 1 or gy > WORLD_HEIGHT then return true end
    return world[gx][gy] and world[gx][gy] > 0
end

local function checkMouseOverButton(bx, by, bw, bh)
    local mx, my = love.mouse.getPosition()
    return mx > bx and mx < bx + bw and my > by and my < by + bh
end

function love.load()
    love.window.setTitle("LÖVE 2D MineClone с сохранениями")
    love.window.setMode(800, 600)
    
    local fontFile = "arial.ttf"
    if not love.filesystem.getInfo(fontFile) then fontFile = "Arial.ttf" end
    if love.filesystem.getInfo(fontFile) then
        love.graphics.setFont(love.graphics.newFont(fontFile, 16))
    end
    
    if love.filesystem.getInfo("tileset.png") then
        tilesetImage = love.graphics.newImage("tileset.png")
        tilesetImage:setFilter("nearest", "nearest")
        for i = 1, 5 do
            tilesetQuads[i] = love.graphics.newQuad((i - 1) * 16, 0, 16, 16, tilesetImage:getDimensions())
        end
    end

    if love.filesystem.getInfo("music.mp3") then
        bgMusic = love.audio.newSource("music.mp3", "stream")
        bgMusic:setLooping(true)
        bgMusic:setVolume(0.5)
        bgMusic:play()
    end
    
    math.randomseed(os.time())
    
    -- Генерация ландшафта (по умолчанию)
    for x = 1, WORLD_WIDTH do
        world[x] = {}
        local surfaceHeight = 20 + math.floor(math.sin(x * 0.15) * 4)
        for y = 1, WORLD_HEIGHT do
            if y > surfaceHeight then
                if y == surfaceHeight + 1 then world[x][y] = 1
                elseif y <= surfaceHeight + 5 then world[x][y] = 2
                else world[x][y] = 3 end
            else
                world[x][y] = 0
            end
        end
    end
    
    -- Деревья
    for x = 5, WORLD_WIDTH - 5 do
        local surfaceY = 0
        for y = 1, WORLD_HEIGHT do if world[x][y] == 1 then surfaceY = y break end end
        if surfaceY > 5 and math.random(1, 8) == 1 and world[x-1][surfaceY] == 1 and world[x+1][surfaceY] == 1 then
            local trunkHeight = math.random(3, 5)
            for t = 1, trunkHeight do world[x][surfaceY - t] = 4 end
            local leavesY = surfaceY - trunkHeight
            for lx = x - 2, x + 2 do
                for ly = leavesY - 2, leavesY do
                    if world[lx] and world[lx][ly] == 0 then world[lx][ly] = 5 end
                end
            end
        end
    end
    
    player.x = (WORLD_WIDTH / 2) * TILE_SIZE
    player.y = 5 * TILE_SIZE
end

function love.update(dt)
    -- Работа таймера уведомлений
    if saveNotificationTimer > 0 then
        saveNotificationTimer = saveNotificationTimer - dt
    end

    if gameState == "menu" then
        menuTimer = menuTimer + dt * 3
        for _, btn in pairs(buttons.menu) do btn.hovered = checkMouseOverButton(btn.x, btn.y, btn.w, btn.h) end
        if bgMusic then bgMusic:setVolume(0.5) end
        return
    elseif gameState == "paused" then
        for _, btn in pairs(buttons.paused) do btn.hovered = checkMouseOverButton(btn.x, btn.y, btn.w, btn.h) end
        if bgMusic then bgMusic:setVolume(0.2) end
        return
    end

    if bgMusic then bgMusic:setVolume(0.5) end

    if love.keyboard.isDown("1") then selectedBlock = 1 end
    if love.keyboard.isDown("2") then selectedBlock = 2 end
    if love.keyboard.isDown("3") then selectedBlock = 3 end
    if love.keyboard.isDown("4") then selectedBlock = 4 end
    if love.keyboard.isDown("5") then selectedBlock = 5 end

    player.vx = 0
    local isMoving = false
    if love.keyboard.isDown("a") then 
        player.vx = -player.speed 
        player.direction = -1
        isMoving = true
    end
    if love.keyboard.isDown("d") then 
        player.vx = player.speed 
        player.direction = 1
        isMoving = true
    end
    
    if isMoving and player.grounded then
        player.animTimer = player.animTimer + dt * 12
    else
        player.animTimer = player.animTimer + (0 - player.animTimer) * 10 * dt
    end

    player.vy = player.vy + player.gravity * dt

    if love.keyboard.isDown("space") and player.grounded then
        player.vy = player.jumpForce
        player.grounded = false
    end

    -- Физика
    player.x = player.x + player.vx * dt
    local startX = math.max(1, math.floor(player.x / TILE_SIZE))
    local endX = math.min(WORLD_WIDTH, math.floor((player.x + player.width) / TILE_SIZE) + 1)
    local startY = math.max(1, math.floor(player.y / TILE_SIZE))
    local endY = math.min(WORLD_HEIGHT, math.floor((player.y + player.height) / TILE_SIZE) + 1)

    for x = startX, endX do
        for y = startY, endY do
            if isSolid(x, y) then
                if checkCollision(player.x, player.y, player.width, player.height, (x-1)*TILE_SIZE, (y-1)*TILE_SIZE, TILE_SIZE, TILE_SIZE) then
                    if player.vx > 0 then player.x = (x - 1) * TILE_SIZE - player.width
                    elseif player.vx < 0 then player.x = x * TILE_SIZE end
                end
            end
        end
    end

    player.y = player.y + player.vy * dt
    startX = math.max(1, math.floor(player.x / TILE_SIZE))
    endX = math.min(WORLD_WIDTH, math.floor((player.x + player.width) / TILE_SIZE) + 1)
    startY = math.max(1, math.floor(player.y / TILE_SIZE))
    endY = math.min(WORLD_HEIGHT, math.floor((player.y + player.height) / TILE_SIZE) + 1)

    player.grounded = false
    for x = startX, endX do
        for y = startY, endY do
            if isSolid(x, y) then
if checkCollision(player.x, player.y, player.width, player.height, (x-1)*TILE_SIZE, (y-1)*TILE_SIZE, TILE_SIZE, TILE_SIZE) then
if player.vy > 0 then
player.y = (y - 1) * TILE_SIZE - player.height
player.vy = 0
player.grounded = true
elseif player.vy < 0 then
player.y = y * TILE_SIZE
player.vy = 0
end
end
end
end
end
camX = player.x - 400 + player.width / 2
camY = player.y - 300 + player.height / 2
end
-- Отслеживание нажатий для меню и кнопок F5 / F9
function love.keypressed(key)
if key == "escape" then
if gameState == "playing" then gameState = "paused"
elseif gameState == "paused" then gameState = "playing" end
end
-- Вызов сохранения / загрузки только во время игры или паузы
if gameState == "playing" or gameState == "paused" then
if key == "f5" then
saveWorld()
elseif key == "f9" then
loadWorld()
end
end
end
local function drawButton(btn)
if btn.hovered then love.graphics.setColor(0.4, 0.4, 0.4, 0.9)
else love.graphics.setColor(0.3, 0.3, 0.3, 0.8) end
love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 4, 4)
love.graphics.setColor(1, 1, 1)
local textWidth = love.graphics.getFont():getWidth(btn.text)
love.graphics.print(btn.text, btn.x + (btn.w - textWidth) / 2, btn.y + 12)
end
function love.draw()
love.graphics.clear(0.5, 0.8, 1)
love.graphics.push()
love.graphics.translate(-math.floor(camX), -math.floor(camY))
for x = 1, WORLD_WIDTH do
for y = 1, WORLD_HEIGHT do
local blockId = world[x][y]
if blockId and blockId > 0 then
local bx, by = (x - 1) * TILE_SIZE, (y - 1) * TILE_SIZE
if tilesetImage and tilesetQuads[blockId] then
love.graphics.setColor(1, 1, 1)
love.graphics.draw(tilesetImage, tilesetQuads[blockId], bx, by, 0, TILE_SIZE / 16, TILE_SIZE / 16)
else
love.graphics.setColor(BLOCKS[blockId].color)
love.graphics.rectangle("fill", bx, by, TILE_SIZE, TILE_SIZE)
end
end
end
end
-- Стив
love.graphics.push()
love.graphics.translate(player.x + player.width / 2, player.y)
local swing = math.cos(player.animTimer) * 12
local colSkin, colHair, colShirt, colPants, colShoes = {0.87, 0.67, 0.53}, {0.45, 0.24, 0.14}, {0.0, 0.64, 0.67}, {0.24, 0.27, 0.68}, {0.3, 0.3, 0.3}
love.graphics.setColor(colShirt)
love.graphics.rectangle("fill", -5 - (swing * 0.3 * player.direction), 14 + (swing * 0.1), 10, 10)
love.graphics.setColor(colSkin)
love.graphics.rectangle("fill", -5 - (swing * 0.5 * player.direction), 24 + (swing * 0.2), 10, 8)
love.graphics.setColor(colPants)
love.graphics.rectangle("fill", -9 + (swing * 0.4), 34, 9, 14)
love.graphics.setColor(colShoes)
love.graphics.rectangle("fill", -9 + (swing * 0.4) + (player.direction * 1), 48, 9, 6)
love.graphics.setColor(colPants)
love.graphics.rectangle("fill", 0 - (swing * 0.4), 34, 9, 14)
love.graphics.setColor(colShoes)
love.graphics.rectangle("fill", 0 - (swing * 0.4) + (player.direction * 1), 48, 9, 6)
love.graphics.setColor(colShirt)
love.graphics.rectangle("fill", -10, 14, 20, 20)
love.graphics.setColor(colSkin)
love.graphics.rectangle("fill", -8, -2, 16, 16)
love.graphics.setColor(colHair)
love.graphics.rectangle("fill", -8, -2, 16, 5)
local faceOffset = 3 * player.direction
love.graphics.setColor(0.2, 0.4, 0.8)
love.graphics.rectangle("fill", faceOffset + (player.direction > 0 and 1 or -5), 3, 4, 3)
love.graphics.setColor(colHair)
love.graphics.rectangle("fill", faceOffset - 2, 7, 4, 3)
love.graphics.setColor(colShirt)
love.graphics.rectangle("fill", -5 + (swing * 0.3 * player.direction), 14 - (swing * 0.1), 10, 10)
love.graphics.setColor(colSkin)
love.graphics.rectangle("fill", -5 + (swing * 0.5 * player.direction), 24 - (swing * 0.2), 10, 8)
love.graphics.pop()
love.graphics.pop()
-- Интерфейсы
if gameState == "menu" then
love.graphics.setColor(0, 0, 0, 0.5)
love.graphics.rectangle("fill", 0, 0, 800, 600)
love.graphics.push()
love.graphics.translate(400, 120 + math.sin(menuTimer) * 8)
love.graphics.scale(2.5, 2.5)
love.graphics.setColor(0, 0, 0, 0.6)
love.graphics.printf("MINECRAFT 2D", -150 + 2, 2, 300, "center")
love.graphics.setColor(0.3, 0.7, 0.3)
love.graphics.printf("MINECRAFT 2D", -150, 0, 300, "center")
love.graphics.pop()
drawButton(buttons.menu.play)
drawButton(buttons.menu.exit)
elseif gameState == "paused" then
love.graphics.setColor(0, 0, 0, 0.6)
love.graphics.rectangle("fill", 0, 0, 800, 600)
love.graphics.setColor(1, 1, 1)
love.graphics.printf("ИГРА НА ПАУЗЕ", 0, 150, 800, "center")
drawButton(buttons.paused.resume)
drawButton(buttons.paused.toMenu)
elseif gameState == "playing" then
local screenWidth, screenHeight = love.graphics.getWidth(), love.graphics.getHeight()
local hbWidth, hbHeight = 300, 50
local hbX, hbY = (screenWidth - hbWidth) / 2, screenHeight - hbHeight - 15
love.graphics.setColor(0, 0, 0, 0.6)
love.graphics.rectangle("fill", hbX, hbY, hbWidth, hbHeight, 8, 8)
for i = 1, 5 do
local slotX = hbX + 15 + (i - 1) * 55
local slotY = hbY + 9
if i == selectedBlock then
love.graphics.setColor(1, 1, 1, 0.4)
love.graphics.rectangle("fill", slotX - 4, slotY - 4, 40, 40, 4, 4)
end
if tilesetImage and tilesetQuads[i] then
love.graphics.setColor(1, 1, 1)
love.graphics.draw(tilesetImage, tilesetQuads[i], slotX, slotY, 0, 2, 2)
else
love.graphics.setColor(BLOCKS[i].color)
love.graphics.rectangle("fill", slotX, slotY, 32, 32)
end
love.graphics.setColor(1, 1, 1, 0.6)
love.graphics.print(tostring(i), slotX + 12, slotY + 10)
end
love.graphics.setColor(0, 0, 0, 0.5)
love.graphics.rectangle("fill", 10, 10, 540, 45, 6, 6)
love.graphics.setColor(1, 1, 1)
love.graphics.print("A / D — Бег | Пробел — Прыжок | Esc — Пауза", 20, 14)
love.graphics.print("ЛКМ — Ломать | ПКМ — Строить | F5 — Сохранить | F9 — Загрузить", 20, 32)
end
-- Отрисовка всплывающего уведомления
if saveNotificationTimer > 0 then
love.graphics.setColor(0, 0, 0, 0.7)
love.graphics.rectangle("fill", 250, 8, 300, 35, 6, 6)
love.graphics.setColor(1, 0.9, 0.3) -- Золотистый текст
love.graphics.printf(saveNotificationText, 250, 16, 300, "center")
end
end
function love.mousepressed(mx, my, button)
if gameState == "menu" then
if button == 1 then
if buttons.menu.play.hovered then gameState = "playing"
elseif buttons.menu.exit.hovered then love.event.quit() end
end
elseif gameState == "paused" then
if button == 1 then
if buttons.paused.resume.hovered then gameState = "playing"
elseif buttons.paused.toMenu.hovered then gameState = "menu" end
end
elseif gameState == "playing" then
local gridX = math.floor((mx + camX) / TILE_SIZE) + 1
local gridY = math.floor((my + camY) / TILE_SIZE) + 1
if gridX >= 1 and gridX <= WORLD_WIDTH and gridY >= 1 and gridY <= WORLD_HEIGHT then
if button == 1 then
if world[gridX][gridY] > 0 then
world[gridX][gridY] = 0
playDigSound()
end
elseif button == 2 then
if world[gridX][gridY] == 0 then
local bx, by = (gridX - 1) * TILE_SIZE, (gridY - 1) * TILE_SIZE
if not checkCollision(player.x, player.y, player.width, player.height, bx, by, TILE_SIZE, TILE_SIZE) then
world[gridX][gridY] = selectedBlock
end
end
end
end
end
end