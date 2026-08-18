-- Digital Terrarium ecological rules.
-- This file is intentionally portable: it can run in Lua 5.4, a game engine,
-- or a WASM-hosted Lua VM without access to the cloud stack.

local ecology = {}

local species = {
  ["moon-moss"] = {
    moisture = { min = 0.48, ideal = 0.72, max = 0.96 },
    light = { min = 0.08, ideal = 0.34, max = 0.68 },
    growth = 0.042,
    resilience = 0.91,
    traits = { "nocturnal", "dew-collector", "soft-glow" }
  },
  ["glass-fern"] = {
    moisture = { min = 0.36, ideal = 0.61, max = 0.84 },
    light = { min = 0.28, ideal = 0.58, max = 0.88 },
    growth = 0.037,
    resilience = 0.78,
    traits = { "prismatic", "shade-maker", "rain-listener" }
  },
  ["whisper-caps"] = {
    moisture = { min = 0.62, ideal = 0.82, max = 1.0 },
    light = { min = 0.04, ideal = 0.22, max = 0.52 },
    growth = 0.031,
    resilience = 0.74,
    traits = { "fungal", "networked", "weather-sensitive" }
  },
  ["button-vine"] = {
    moisture = { min = 0.30, ideal = 0.56, max = 0.80 },
    light = { min = 0.35, ideal = 0.66, max = 0.94 },
    growth = 0.048,
    resilience = 0.69,
    traits = { "climbing", "curious", "touch-responsive" }
  },
  ["rain-thread"] = {
    moisture = { min = 0.58, ideal = 0.88, max = 1.0 },
    light = { min = 0.10, ideal = 0.40, max = 0.76 },
    growth = 0.028,
    resilience = 0.85,
    traits = { "filament", "storm-blooming", "conductive" }
  }
}

local interactions = {
  { from = "glass-fern", to = "moon-moss", effect = "shade", strength = 0.012 },
  { from = "moon-moss", to = "whisper-caps", effect = "humidity", strength = 0.016 },
  { from = "whisper-caps", to = "button-vine", effect = "nutrients", strength = 0.009 },
  { from = "button-vine", to = "glass-fern", effect = "support", strength = 0.006 },
  { from = "rain-thread", to = "moon-moss", effect = "dew", strength = 0.014 }
}

local function clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function triangular(value, range)
  if value <= range.min or value >= range.max then return 0 end
  if value == range.ideal then return 1 end
  if value < range.ideal then
    return (value - range.min) / (range.ideal - range.min)
  end
  return (range.max - value) / (range.max - range.ideal)
end

local function deterministic_noise(seed, cycle, channel)
  local hash = seed + cycle * 7919
  for index = 1, #channel do
    hash = (hash * 33 + string.byte(channel, index)) % 2147483647
  end
  return ((hash % 10000) / 5000) - 1
end

local function climate(seed, cycle, previous)
  local rain = deterministic_noise(seed, cycle, "rain")
  local sun = deterministic_noise(seed, cycle, "sun")
  local heat = deterministic_noise(seed, cycle, "heat")

  return {
    moisture = clamp(previous.moisture + rain * 0.075 - sun * 0.028, 0.04, 1),
    light = clamp(previous.light + sun * 0.065, 0.06, 1),
    temperature = clamp(previous.temperature + heat * 1.2 + sun * 0.35, 7, 37),
    weather = rain > 0.45 and "glass rain"
      or sun > 0.52 and "wide sun"
      or heat < -0.55 and "silver chill"
      or "soft static"
  }
end

local function interaction_bonus(name, populations)
  local bonus = 0
  for _, relation in ipairs(interactions) do
    if relation.to == name then
      bonus = bonus + (populations[relation.from] or 0) * relation.strength
    end
  end
  return bonus
end

function ecology.advance(habitat)
  local cycle = (habitat.cycle or 0) + 1
  local conditions = climate(habitat.seed or 1, cycle, habitat)
  local old_populations = habitat.plants or {}
  local next_populations = {}

  for name, profile in pairs(species) do
    local current = old_populations[name] or 0
    local moisture_fit = triangular(conditions.moisture, profile.moisture)
    local light_fit = triangular(conditions.light, profile.light)
    local stress = math.abs(conditions.temperature - 21) / 30
    local fitness = moisture_fit * 0.55 + light_fit * 0.35 + profile.resilience * 0.10
    local growth = profile.growth * (fitness - 0.46) - stress * 0.012
    local community = interaction_bonus(name, old_populations)

    next_populations[name] = clamp(current + growth + community, 0, 1)
  end

  local total = 0
  local active = 0
  for _, population in pairs(next_populations) do
    total = total + population
    if population > 0.08 then active = active + 1 end
  end

  habitat.cycle = cycle
  habitat.moisture = conditions.moisture
  habitat.light = conditions.light
  habitat.temperature = conditions.temperature
  habitat.weather = conditions.weather
  habitat.plants = next_populations
  habitat.biomass = total
  habitat.biodiversity = clamp(active / 5 * 0.7 + total / 5 * 0.3, 0, 1)
  return habitat
end

function ecology.describe(habitat)
  local thriving = {}
  for name, population in pairs(habitat.plants or {}) do
    if population > 0.62 then
      table.insert(thriving, name)
    end
  end
  table.sort(thriving)

  if #thriving == 0 then
    return "The terrarium is listening. Nothing has decided to thrive yet."
  end

  return "Thriving now: " .. table.concat(thriving, ", ") .. "."
end

ecology.species = species
ecology.interactions = interactions

return ecology
