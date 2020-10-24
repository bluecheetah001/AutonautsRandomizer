-- FEATURE REQUEST: split mods into multiple files
--                  there is going to be a lot of code and data to make this mod work
--                  it would be really nice to not have to mash everything into a single file in some build process
local util

do -- mod.lua
    function SteamDetails()
        ModBase.SetSteamWorkshopDetails("Randomizer Experiments", "Some experiments to figure out what is possible to randomize", {"experiments"})
    end

    local globalSettings = {
        seed = "",
    }

    function Expose()
        -- FEATURE REQUEST: per world exposed variables
        --                  currently the seed (and other configuration) will be ignored when loading a save, since i need to do the randomization from the same starting point each time
        --                  it would be convenient to move such settings to somewhere in the new game menu, which could potentially remove the need to load save data in BeforeLoad
        ModBase.ExposeVariable("Seed (empty is random)", globalSettings.seed, function(value) globalSettings.seed = value end)
    end

    local settings = {}

    function BeforeLoad()
        -- FEATURE REQUEST: need to be able to load save data during BeforeLoad
        --                  otherwise cannot use randomly generated seeds, and have to verify the same seed (and other settings) is still set
        -- IMPROVE DOCS: does LoadValue return "" or nil for something that was never saved (eg starting a new save)?
        --               decompile looks like it will return nil, but docs could explicitly call that out.
        settings.seed = util.parseSeed( --[[ ModSaveData.LoadValue("Seed") or ]] globalSettings.seed)

        -- TODO does setting the random seed (or making random calls) in BeforeLoad change how the world is generated?
        -- TODO does using a fixed world seed cause the same random seed to be chosen by util.parseSeed? (not inherently an issue, but could be fixed by mixing in os.time())
        -- FEATURE REQUEST: instead of managing a seed myself, could a guarantee be made that math.random is in a determined state in BeforeLoad based on the world seed?
        --                  some potential issues: load order of mods that use math.random
        --                                         the fact that the game iself isn't fully determined by the world seed
        --                                         starting a new game vs loading a save
        --                  this is pretty low priority since there are a lot of ways it could go wrong and it only removes a single input box
        math.randomseed(settings.seed - 2147483648) -- seed is unsigned integer, math.randomseed takes a signed integer


        -- some example calls that the randomizer might make that I have noticed that might cause me issues

        -- setting the recipe for a building that normally has stages works but removes the stages
        util.setBuildingRecipe{input = {Stick = 1}, output = "LogCabin"}

        -- BUG: Using a recipe in a Barn that takes less than two animals or doesn't produce an animal (haven't tested using different types) causes an exception to be thrown
        --      in Barn.Update when this.m_StateTime >= this.m_ConversionDelay assume the recipe has at least two input animal and 1 outupt animal (there are probably other assumptions thoughout the class as well)
        -- I can work around this, it just changes what is able to be randomized
        util.setRecipe{converter = "Barn", input = {AnimalCow = 1}, output = "AnimalChicken"}
    end

    -- FEATURE REQUEST: need a callback to know when to save settings
    --                  though I could probably get away with just saving in the first OnUpdate callback
    function AfterSave()
        ModSaveData.SaveValue("Seed", settings.seed)
    end
end

do -- util.lua
    local function parseSeed(seed)
        if seed == "" then
            -- generate a random seed
            -- split into two calls to avoid overflow from signed integer inside math.random
            return math.random(65535) * 65536 + math.random(65535)
        elseif string.match(seed, "^%x%x%x%x%x%x%x%x$") then
            -- use the exact seed specified
            return tonumber(seed, 16)
        else
            -- hash the given seed into a number
            local hash = 7
            for i = 0, #seed do
                hash = bit32.xor(hash * 31, seed:byte(i))
            end
            return hash
        end
    end

    -- recipe: {converter = Object, input = {[Object] = count}, output = Object, count = number | nil, output2 = Object | nil, count2 = number | nil}
    local function removeRecipe(recipe)
        ModVariable.RemoveRecipeFromConverter(recipe.converter, recipe.output)
    end

    -- splits recipe input into 2 lists
    local function splitInput(recipe)
        local input = {}
        for object, _ in pairs(recipe.input) do
            table.insert(input, object)
        end
        table.sort(input) -- sort for determinism, could supply a function to get a more meaningful sort if desired
        local inputCount = {}
        for i, object in ipairs(input) do
            inputCount[i] = recipe.input[object]
        end
        return input, inputCount
    end

    -- recipe: {converter = Object, input = {[Object] = count}, output = Object, count = number | nil, output2 = Object | nil, count2 = number | nil}
    local function setRecipe(recipe)
        local input, inputCount = splitInput(recipe)

        if recipe.output2 then
            -- set the recipe for an object with an extra output
            ModVariable.SetIngredientsForRecipeSpecificDoubleResults(recipe.converter, recipe.output, recipe.output2, input, inputCount, recipe.count or 1, recipe.count2 or 1)
        else
            -- set the recipe for an object
            ModVariable.SetIngredientsForRecipeSpecific(recipe.converter, recipe.output, input, inputCount, recipe.count or 1)
        end
    end

    -- recipe: {input = {[Object] = count}, output = Object}
    local function setBuildingRecipe(recipe)
        local input, inputCount = splitInput(recipe)

        -- FEATURE REQUEST: set ingredients for each stage of a building
        --                  not sure what this would look like, especially for custom buildings or attempting to add a stage to vanilla buildings that dont normally have one
        --                  this is pretty low priority, more just an annoyance that multi stage buildings get replaced with a single stage
        ModVariable.SetIngredientsForRecipe(recipe.output, input, inputCount, 1)
    end

    util = {
        parseSeed = parseSeed,
        removeRecipe = removeRecipe,
        setRecipe = setRecipe,
        setBuildingRecipe = setBuildingRecipe,
    }
end
