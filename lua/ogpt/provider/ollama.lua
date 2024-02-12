local ProviderBase = require("ogpt.provider.base")

-- ollama is first class citizen on OGPT
local Ollama = ProviderBase:extend("Ollama")

return Ollama
