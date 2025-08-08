local CODE_TOOLTIPS = 105

local tooltipWindow = nil
local itemSprite = nil
local itemWeightLabel = nil
local labels = nil
local hoveredItem = nil
local player = nil
local protocolGame = nil
local showingVirtual = nil
local hoveredLinked = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local cachedItems = {}

local Colors = {
  Default = "#ffffff",
  ItemLevel = "#abface",
  Description = "#8080ff",
  Implicit = "#ffbb22",
  Attribute = "#2266ff",
  Mirrored = "#22ffbb"
}

local rarityColor = {
  {name = "", color = "#ffffff"},
  {name = "Common", color = "#7b7b7b"},
  --{name = "Rare", color = "#1258a2"},
  {name = "Rare", color = "#25fc19"},
  {name = "Epic", color = "#bd3ffa"},
  {name = "Legendary", color = "#ff7605"},
  {name = "Mythic", color = "#FF0000"}
}

local implicits = {
  ["ca"] = "Critical Damage",
  ["cc"] = "Critical Chance",
  ["la"] = "Life Leech",
  ["lc"] = "Life Leech Chance",
  ["ma"] = "Mana Leech",
  ["mc"] = "Mana Leech Chance",
  ["speed"] = "Movement Speed",
  ["fist"] = "Fist Fighting",
  ["sword"] = "Sword Fighting",
  ["club"] = "Club Fighting",
  ["axe"] = "Axe Fighting",
  ["dist"] = "Distance Fighting",
  ["shield"] = "Shielding",
  ["fish"] = "Fishing",
  ["mag"] = "Magic Level",
  ["a_phys"] = "Physical Protection",
  ["a_ene"] = "Energy Protection",
  ["a_earth"] = "Earth Protection",
  ["a_fire"] = "Fire Protection",
  ["a_ldrain"] = "Lifedrain Protection",
  ["a_mdrain"] = "Manadrain Protection",
  ["a_heal"] = "Healing Protection",
  ["a_drown"] = "Drown Protection",
  ["a_ice"] = "Ice Protection",
  ["a_holy"] = "Holy Protection",
  ["a_death"] = "Death Protection",
  ["a_all"] = "Protection All"
}

local impPercent = {
  ["ca"] = true,
  ["cc"] = true,
  ["la"] = true,
  ["lc"] = true,
  ["ma"] = true,
  ["mc"] = true,
  ["a_phys"] = true,
  ["a_ene"] = true,
  ["a_earth"] = true,
  ["a_fire"] = true,
  ["a_ldrain"] = true,
  ["a_mdrain"] = true,
  ["a_heal"] = true,
  ["a_drown"] = true,
  ["a_ice"] = true,
  ["a_holy"] = true,
  ["a_death"] = true,
  ["a_all"] = true
}

function init()
  connect(UIItem, {onHoverChange = onHoverChange})
  connect(g_game, {onGameEnd = resetData})

  ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  tooltipWindow = g_ui.displayUI("item_tooltip")
  tooltipWindow:hide()

  labels = tooltipWindow:getChildById("labels")
  itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
  itemSprite = tooltipWindow:getChildById("itemSprite")
end

function terminate()
  disconnect(UIItem, {onHoverChange = onHoverChange})
  disconnect(g_game, {onGameEnd = resetData})

  ProtocolGame.unregisterExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  if tooltipWindow then
    cachedItems = {}
    hoveredItem = nil
    player = nil
    protocolGame = nil
    showingVirtual = nil
    hoveredLinked = nil

    itemWeightLabel = nil
    itemSprite = nil
    labels = nil

    tooltipWindow:destroy()
    tooltipWindow = nil
  end
end

function onExtendedOpcode(protocol, code, buffer)
  local json_status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not json_status then
    g_logger.error("Tooltips JSON error: " .. json_data)
    return
  end

  local action = json_data.action
  local data = json_data.data
  if not action or not data then
    return
  end
  if action == "new" then
    newTooltip(data)
  end
end

function newTooltip(data)
  local _itemUId = data.uid or 0
  local _itemName = data.itemName or data.name or "Unknown"
  local _itemDesc = data.desc or data.description or ""
  local _itemId = data.clientId or data.id or 0
  local _itemLevel = data.itemLevel or data.iLvl or 0
  local _imp = data.imp
  local _unidentified = data.unidentified or false
  local _mirrored = data.mirrored or false
  local _upgradeLevel = data.uLevel or data.upgradeLevel or 0
  local _uniqueName = data.uniqueName
  local _itemRarity = data.rarityId or data.rarity or 0
  local _itemMaxAttributes = data.maxAttr or data.maxAttributes or 0
  local _itemAttributes = data.attr or data.attributes or {}
  local _requiredLevel = data.reqLvl or data.requiredLevel or 0

  if _itemRarity ~= 0 and _itemAttributes and _itemMaxAttributes > 0 then
    for i = _itemMaxAttributes, 1, -1 do
      if _itemAttributes[i] then
        _itemAttributes[i] = _itemAttributes[i]:gsub("%%%%", "%%")
      end
    end
  end
  local _isStackable = data.stackable or false
  local _itemType = data.itemType or data.type or "Common"
  
  -- Processar stats de combate baseado no tipo de item
  local _firstStat = 0
  local _secondStat = 0
  local _thirdStat = 0
  
  if data.armor and data.armor > 0 then
    _firstStat = data.armor
  elseif data.attack and data.attack > 0 then
    _firstStat = data.attack
    _secondStat = data.defense or 0
    _thirdStat = data.extraDefense or 0
  elseif data.defense and data.defense > 0 then
    _firstStat = data.defense
    _thirdStat = data.extraDefense or 0
  end
  
  -- Para armas de distância
  if data.hitChance and data.hitChance > 0 then
    _secondStat = data.hitChance
  end
  
  if data.shootRange and data.shootRange > 0 then
    _thirdStat = data.shootRange
  end
  
  local _weight = data.weight or 0
  local _count = data.count or 1
  
  -- Generate a UID if not provided (for simple tooltips)
  if _itemUId == 0 and hoveredItem then
    _itemUId = hoveredItem:getId() * 1000 + _count
  end
  
  cachedItems[_itemUId] = {
    last = os.time(),
    name = _itemName,
    desc = _itemDesc,
    iLvl = _itemLevel,
    imp = _imp,
    unidentified = _unidentified,
    mirrored = _mirrored,
    uLvl = _upgradeLevel,
    uniqueName = _uniqueName,
    rarity = _itemRarity,
    maxAttributes = _itemMaxAttributes,
    attributes = _itemAttributes,
    stackable = _isStackable,
    type = _itemType,
    first = _firstStat,
    second = _secondStat,
    third = _thirdStat,
    weight = _weight,
    reqLvl = _requiredLevel,
    itemId = _itemId,
    -- Novos campos específicos
    armor = data.armor,
    attack = data.attack,
    defense = data.defense,
    extraDefense = data.extraDefense,
    hitChance = data.hitChance,
    shootRange = data.shootRange
  }
  
  if hoveredLinked and _itemUId == hoveredLinked.uid then
    hoveredLinked.cached = true
    for key, value in pairs(cachedItems[_itemUId]) do
      hoveredLinked[key] = value
    end
    buildItemTooltip(hoveredLinked:getLinkedTooltip())
    return
  end

  if hoveredItem and (_itemId == hoveredItem:getId() or _itemId == 0) then
    hoveredItem.uid = _itemUId
    hoveredItem.name = _itemName .. (_upgradeLevel > 0 and " +" .. _upgradeLevel or "")
    hoveredItem.rarity = _itemRarity
    showTooltip(_itemUId)
  end
end

function resetData()
  cachedItems = {}
  hoveredItem = nil
  player = nil
  protocolGame = nil
  showingVirtual = nil
  hoveredLinked = nil
  tooltipWindow:hide()
end

function onHoverChange(widget, hovered)
  if not protocolGame then
    protocolGame = g_game.getProtocolGame()
  end
  
  if widget.getLinkedTooltip then
    hoveredLinked = widget
    if not widget.cached then
      if protocolGame then
        protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({widget.uid}))
      end
    else
      if hovered then
        showingVirtual = widget:getLinkedTooltip()
        buildItemTooltip(widget:getLinkedTooltip())
      else
        tooltipWindow:hide()
        showingVirtual = nil
      end
    end
    return
  end
  
  local item = widget:getItem()
  if item and widget.getItemTooltip then
    if hovered then
      buildItemTooltip(widget:getItemTooltip())
    else
      tooltipWindow:hide()
    end
    return
  end
  if not item or widget:getId() == "containerItemWidget" or widget:isVirtual() then
    return
  end

  if player == nil then
    player = g_game.getLocalPlayer()
  end

  if hovered then
    hoveredItem = item
    if protocolGame then
      local pos = item:getPosition()
      protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({pos.x, pos.y, pos.z, item:getStackPos()}))
    end
  else
    hoveredItem = nil
    tooltipWindow:hide()
  end
end

function showTooltip(uid)
  local cachedItem = cachedItems[uid]

  cachedItem.id = hoveredItem:getId()
  cachedItem.count = hoveredItem:getCount()

  buildItemTooltip(cachedItem)
end

function buildItemTooltip(item)
  if not item then
    return
  end
  
  tooltipWidth = 0
  longestString = 0
  tooltipWidthBase = BASE_WIDTH
  tooltipHeight = BASE_HEIGHT
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  labels:destroyChildren()

  local id = item.id or item.itemId or 0
  local name = item.name or "Unknown"
  local desc = item.desc or ""
  local iLvl = item.iLvl or 0
  local reqLvl = item.reqLvl or 0
  local unidentified = item.unidentified or false
  local mirrored = item.mirrored or false
  local rarity = (item.rarity or 0) + 1
  local maxAttributes = item.maxAttributes or 0
  local attributes = item.attributes or {}
  local count = item.count or 1
  local type = item.type or "Common"
  local first = item.first or 0
  local second = item.second or 0
  local third = item.third or 0
  local weight = item.weight or 0

  itemWeightLabel:setText(formatWeight(weight))

  itemSprite:setItemId(id)
  itemSprite:setItemCount(count)

  local itemNameColor
  if unidentified then
    itemNameColor = (rarityColor[2] and rarityColor[2].color) or "#7b7b7b"
  elseif item.uniqueName then
    itemNameColor = "#dca01e"
  elseif rarity > 1 and rarity <= #rarityColor then
    itemNameColor = (rarityColor[rarity] and rarityColor[rarity].color) or "#ffffff"
  else
    itemNameColor = "#ffffff"
  end

  name =
  name:gsub(
  "(%a)(%a+)",
  function(a, b)
    return string.upper(a) .. string.lower(b)
  end
)
  if item.uLvl > 0 then
    name = name .. " +" .. item.uLvl
  end

  if unidentified then
    addString("Unidentified" .. " " .. name, (rarityColor[2] and rarityColor[2].color) or "#7b7b7b")
  else
    if item.uniqueName then
      addString(item.uniqueName .. " " .. name, "#dca01e")
    elseif item.rarity ~= 0 and rarity <= #rarityColor and rarityColor[rarity] then
      addString(rarityColor[rarity].name .. " " .. name, rarityColor[rarity].color)
    else
      addString(name, itemNameColor)
    end
  end
  --addString(name, itemNameColor)

  if iLvl > 0 then
    addString("Item Level " .. iLvl, Colors.ItemLevel)
  end

  -- Combat stats - melhorado para mostrar armor, defense e attack corretamente
  local firstText, secondText, thirdText
  
  -- Verificar se temos dados específicos de armor, attack, defense
  if item.armor and item.armor > 0 then
    firstText = "Armor: " .. item.armor
  elseif item.attack and item.attack > 0 then
    firstText = "Attack: " .. item.attack
  elseif item.defense and item.defense > 0 then
    firstText = "Defense: " .. item.defense
  end
  
  if item.extraDefense and item.extraDefense > 0 then
    secondText = "Extra Defense: " .. item.extraDefense
  elseif item.hitChance and item.hitChance > 0 then
    secondText = "Hit Chance: +" .. item.hitChance .. "%"
  end
  
  if item.shootRange and item.shootRange > 0 then
    thirdText = "Shoot Range: " .. item.shootRange
  end
  
  -- Fallback para o sistema antigo (first, second, third) se não temos dados específicos
  if not firstText and not secondText and not thirdText then
    if (type == "Armor" or type == "Helmet" or type == "Legs" or type == "Ring" or type == "Necklace" or type == "Boots") and first ~= 0 then
      firstText = "Armor: " .. first
    elseif
      type == "Two-Handed Sword" or type == "Two-Handed Club" or type == "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or type == "Fist" or
        type == "Distance" or
        type == "Ammunition"
     then
      firstText = "Attack: " .. first
    elseif type == "Shield" then
      firstText = "Defense: " .. second
    end

    if type == "Two-Handed Sword" or type == "Two-Handed Club" or type == "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or type == "Fist" then
      secondText = "Defense: " .. second
    elseif type == "Distance" then
      secondText = "Hit Chance: +" .. second .. "%"
    end

    if type == "Two-Handed Sword" or type == "Two-Handed Club" or type == "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or type == "Fist" then
      thirdText = "Extra-Defense: " .. third
    elseif type == "Distance" then
      thirdText = "Shoot Range: " .. third
    end
  end

  if reqLvl > 0 then
      addString("Required Level " .. reqLvl, Colors.ItemLevel)
  end

  if (firstText and (type == "Shield" or type == "Ring" or type == "Necklace")) or (first ~= 0 and second == 0 and third == 0) then
    addSeparator()
    addEmpty(5)
    addString(firstText, Colors.Default)
  elseif first ~= 0 and second ~= 0 and third == 0 then
    addSeparator()
    addEmpty(5)
    addString(firstText, Colors.Default)
    addString(secondText, Colors.Default)
  elseif first ~= 0 and second ~= 0 and third ~= 0 or type == "Distance" then
    addSeparator()
    addEmpty(5)
    addString(firstText, Colors.Default)
    addString(secondText, Colors.Default)
    addString(thirdText, Colors.Default)
  end

  if item.imp then
    if first ~= 0 or second ~= 0 or third ~= 0 or item.rarity ~= 0 then
      addSeparator()
      addEmpty(5)
    end

    for key, value in pairs(item.imp) do
      local impText
      if not implicits[key] then
        impText = value
      else
        impText = implicits[key] .. " " .. (value > 0 and "+" or "") .. value .. (impPercent[key] and "%" or "")
      end
      addString(impText, Colors.Implicit)
    end
  end

  if item.rarity ~= 0 then
    addSeparator()
    addEmpty(5)
    for i = 1, maxAttributes do
      addString(attributes[i], Colors.Attribute)
    end
  end

  if mirrored then
    addEmpty(5)
    addString("Mirrored", Colors.Mirrored)
  end

  if desc and desc:len() > 0 then
    addEmpty(5)
    addString(desc, Colors.Description, true)
  end

  shrinkSeparators()
  showItemTooltip()
end

function addString(text, color, resize)
  local label = g_ui.createWidget("TooltipLabel", labels)
  label:setColor(color)

  if resize then
    tooltipWindow:setWidth(tooltipWidth)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
    label:setText(text)
    tooltipHeight = tooltipHeight + label:getTextSize().height + 4
  else
    label:setText(text)
    local textSize = label:getTextSize()
    if longestString == 0 then
      longestString = textSize.width + itemWeightLabel:getWidth()
      tooltipWidth = tooltipWidthBase + longestString
      label:addAnchor(AnchorTop, "parent", AnchorTop)
    elseif textSize.width > longestString then
      longestString = textSize.width
      tooltipWidth = tooltipWidthBase + longestString
    end
    tooltipHeight = tooltipHeight + textSize.height
  end
end

function shrinkSeparators()
  local children = labels:getChildren()
  local m = math.max(60, math.floor(tooltipWidth / 4))
  for _, child in ipairs(children) do
    if child:getStyleName() == "TooltipSeparator" then
      child:setMarginLeft(m)
      child:setMarginRight(m)
    end
  end
end

function addSeparator()
  local sep = g_ui.createWidget("TooltipSeparator", labels)
  tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
  local empty = g_ui.createWidget("TooltipEmpty", labels)
  empty:setHeight(height)
  tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
  local mousePos = g_window.getMousePosition()
  tooltipHeight = math.max(tooltipHeight, 40)
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)
  
  local windowSize = g_window.getSize()
  if mousePos.x > windowSize.width / 2 then
    tooltipWindow:move(mousePos.x - (tooltipWidth + 2), math.min(windowSize.height - tooltipHeight, mousePos.y + 5))
  else
    tooltipWindow:move(mousePos.x + 5, mousePos.y + 10)
  end
  tooltipWindow:raise()
  tooltipWindow:show()
  g_effects.fadeIn(tooltipWindow, 100)
end

function formatWeight(weight)
  local ss

  if weight < 10 then
    ss = "0.0" .. weight
  elseif weight < 100 then
    ss = "0." .. weight
  else
    local weightString = tostring(weight)
    local len = weightString:len()
    ss = weightString:sub(1, len - 2) .. "." .. weightString:sub(len - 1, len)
  end

  ss = ss .. " oz."
  return ss
end
