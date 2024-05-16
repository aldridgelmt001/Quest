-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = "-vsAs0-3xQw6QUAYbUuonTbXAnFNJtzqhriKKOymQ9w" --Bikini Botom
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Function to decide the next action for the player
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local closestTarget, minDistance = findClosestTarget(player)

  if player.energy > 5 and closestTarget and minDistance <= 1 then
    -- Attack the closest target if within range and energy is sufficient
    print("Player in range. Attacking " .. closestTarget .. ".")
    ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(player.energy), Target = closestTarget})
  else
    -- Move towards the closest target or strategically reposition if no target is in range
    local nextMove = determineNextMove(player, closestTarget, minDistance)
    print("Moving " .. nextMove .. ".")
    ao.send({Target = Game, Action = "PlayerMove", Direction = nextMove})
  end
  InAction = false
end

-- Helper function to find the closest target
function findClosestTarget(player)
  local minDistance = math.huge
  local closestTarget = nil
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id then
      local distance = calculateDistance(player.x, player.y, state.x, state.y)
      if distance < minDistance then
        minDistance = distance
        closestTarget = target
      end
    end
  end
  return closestTarget, minDistance
end

-- Helper function to calculate distance between two points
function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Helper function to determine the next move based on strategic positioning
function determineNextMove(player, closestTarget, minDistance)
  if closestTarget and minDistance <= 3 then
    -- If there's a closest target within a safe distance, move towards it
    return moveToTarget(player, closestTarget)
  else
    -- If no closest target or it's not within a safe distance, avoid crowded areas
    return avoidCrowdedAreas(player, LatestGameState.Players)
  end
end

-- Function to move towards the target
function moveToTarget(player, target)
  local directionX = target.x - player.x
  local directionY = target.y - player.y
  local moveX = (directionX > 0 and "Right") or (directionX < 0 and "Left") or ""
  local moveY = (directionY > 0 and "Down") or (directionY < 0 and "Up") or ""
  return moveX .. moveY -- Concatenates the X and Y direction
end

-- Function to avoid crowded areas
function avoidCrowdedAreas(player, players)
  local grid = {}
  local gridSize = 40 -- Assuming a 40x40 grid
  local leastCrowdedDirection = "Up"
  local minPlayersInDirection = math.huge

  -- Initialize grid with player counts
  for x = 1, gridSize do
    grid[x] = {}
    for y = 1, gridSize do
      grid[x][y] = 0
    end
  end

  -- Count players in each grid cell
  for _, otherPlayer in pairs(players) do
    if otherPlayer.id ~= player.id then
      grid[otherPlayer.x][otherPlayer.y] = grid[otherPlayer.x][otherPlayer.y] + 1
    end
  end

  -- Check adjacent cells to find the direction with the least players
  local directions = {
    Up = {x = 0, y = -1},
    Down = {x = 0, y = 1},
    Left = {x = -1, y = 0},
    Right = {x = 1, y = 0},
    UpRight = {x = 1, y = -1},
    UpLeft = {x = -1, y = -1},
    DownRight = {x = 1, y = 1},
    DownLeft = {x = -1, y = 1}
  }

  for dir, offset in pairs(directions) do
    local newX = (player.x + offset.x - 1) % gridSize + 1
    local newY = (player.y + offset.y - 1) % gridSize + 1
    local playersInDirection = grid[newX][newY]

    if playersInDirection < minPlayersInDirection then
      minPlayersInDirection = playersInDirection
      leastCrowdedDirection = dir
    end
  end

  return leastCrowdedDirection
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction and LatestGameState.GameMode == "Playing" then
      InAction = true
      local player = LatestGameState.Players[ao.id]
      local playerEnergy = player.energy

      if playerEnergy == nil then
        print("Unable to read energy.")
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print("Player has insufficient energy.")
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        -- Determine the best move: attack if there's energy and a target is in range, otherwise move strategically
        local closestTarget, minDistance = findClosestTarget(player)
        if closestTarget and minDistance <= 1 then
          print("Returning attack on " .. closestTarget .. ".")
          ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(playerEnergy), Target = closestTarget})
        else
          local nextMove = determineNextMove(player, closestTarget, minDistance)
          print("Moving to a better position: " .. nextMove .. ".")
          ao.send({Target = Game, Action = "PlayerMove", Direction = nextMove})
        end
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)


