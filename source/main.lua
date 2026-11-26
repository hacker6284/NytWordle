-- main.lua
-- Contains the initialisation code and the core game loop with input handling.

import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/ui"

import "support"
import "Game"
import "Selection"
import "SubmitButton"
import "Modal"
import "checkEntry"
import "nytDate"
import "wordleFetch"

math.randomseed(playdate.getSecondsSinceEpoch())

local gfx <const> = playdate.graphics
local logo <const> = playdate.graphics.image.new("images/Crordle logo")

-- An 8x8 pattern that has a white background with a single block dot (approximately) in the center
local dotPattern <const> = {0xFF, 0xFF, 0xFF, 0xEF, 0xFF, 0xFF, 0xFF, 0xFF}

local wordList <const> = import "words"

-- UI state determines where we direct our inputs, e.g. into the game or into "UI-y" stuff like
-- dismissing a modal.
local uiState = kUIStateLoadingPuzzle

-- Retrieve the stored game stats
local userData = playdate.datastore.read() or {}

-- Set defaults for any new options the player's datastore doesn't currently have.
local defaultUserData <const> = {
    autofill = true,
    startFromA = false,
    gameStats = {played = 0, won = 0, streak = 0}
}

for key, default in pairs(defaultUserData) do
    if userData[key] == nil then
        userData[key] = default
    end
end

-- Add an option to the menu allowing the player to auto-fill correct guesses.
playdate.getSystemMenu():addCheckmarkMenuItem(
    "autofill",
    userData.autofill,
    function (newValue)
        userData.autofill = newValue
        playdate.datastore.write(userData)
    end
)

-- Add an option to the menu allowing the player to have every piece start at "A", rather than the
-- previous letter.
playdate.getSystemMenu():addCheckmarkMenuItem(
    "start on \"a\"",
    userData.startFromA,
    function (newValue)
        userData.startFromA = newValue
        playdate.datastore.write(userData)
    end
)

-- Objects for UI elements in-game:
-- Selection draws a ring around the active piece
local selection <const> = Selection(boardOrigin, pieceSize, pieceMargin)

-- Submit button draws the sprite for submitting a word entry.
local submitButton <const> = SubmitButton()

-- Modal assists with displaying pop-up, focus-stealing messages to the player.
local modal <const> = Modal()

local game

local cachedDate = nil
local cachedWord = nil

local fetchPending = true

-- Draw our static UI elements
gfx.sprite.setBackgroundDrawingCallback(function (x, y, width, height)
    gfx.setClipRect(x, y, width, height)

    doInGraphicsContext(function ()
        -- Background pattern
        gfx.setPattern(dotPattern)
        gfx.fillRect(x, y, width, height)

        -- Logo
        logo:draw(210, 25)

        if cachedDate ~= nil then
            fonts.small:drawTextAligned("NYT " .. cachedDate, 290, 95, kTextAlignment.center)
        end

        -- Controls
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRoundRect(200, 155, 180, 65, 5)

        gfx.setColor(gfx.kColorBlack)
        gfx.drawRoundRect(200, 155, 180, 65, 5)

        fonts.small:drawTextAligned("Crank/Up/Down: Choose", 290, 160, kTextAlignment.center)
        fonts.small:drawTextAligned("Ⓐ/Right: Next", 290, 180, kTextAlignment.center)
        fonts.small:drawTextAligned("Ⓑ/Left: Previous", 290, 200, kTextAlignment.center)
    end)

    gfx.clearClipRect()
end)

-- Update the player's streak stats and write them back to the save file.
local function updateGameStats(gameWon)
    local gameStats <const> = userData.gameStats

    gameStats.played += 1

    if gameWon then
        gameStats.won += 1
        gameStats.streak += 1
    else
        gameStats.streak = 0
    end

    playdate.datastore.write(userData)
end

-- To avoid having to implement a system where we check the game state each update and ensure we
-- only react to each change once, we instead have a nice event system where the game will call
-- our functions in response to various state changes.
local function registerEventHandlers()
    game:registerEventHandler(kEventGameStateDidTransition, function (game, newState)
        -- If we move into submission mode, we want to hide the selection ring and highlight the
        -- submit button.
        if newState == kGameStateSubmittingWord then
            selection:hide()
            submitButton:setHighlighted()

        -- Otherwise we want to do the opposite.
        elseif newState == kGameStateEnteringWord then
            selection:moveTo(game:getCurrentRow(), game:getCurrentPosition())
            submitButton:setHighlighted(false)

        -- If the player has won or lost, we want to update the game stats and display either a
        -- congratulatory or condolence message.
        elseif newState == kGameStateWon then
            updateGameStats(true)

            uiState = kUIStateDisplayingModal
            modal:displayMessage(
                "Splendid!\n" .. getGameStatsDescription(userData.gameStats),
                "New game"
            )

        elseif newState == kGameStateLost then
            updateGameStats(false)

            uiState = kUIStateDisplayingModal
            modal:displayMessage(
                "Bad luck! The word was \""
                    .. game.word
                    .. "\".\n"
                    .. getGameStatsDescription(userData.gameStats),
                "Try again"
            )

        end
    end)

    -- If the word was not in the list, display a modal informing the player.
    game:registerEventHandler(kEventEnteredWordNotInList, function ()
        uiState = kUIStateDisplayingModal
        modal:displayMessage("That's not in the word list!")
    end)
end

local showingCrankAlert = false
local crankAlertTimerExpired = false
local crankAlertUsed = false

local function maybeShowCrankAlert()
    if crankAlertUsed or not playdate.isCrankDocked() then
        return
    end

    crankAlertUsed = true
    playdate.ui.crankIndicator:start()
    showingCrankAlert = true
    crankAlertTimerExpired = false
    playdate.timer.performAfterDelay(2500, function () crankAlertTimerExpired = true end)
end

local function writeVerify(payload)
    if playdate.isSimulator then
        playdate.datastore.write(payload, "nyt-verify")
    end
end

local function beginPlaying(word)
    if game ~= nil then
        game:tearDown()
    end

    game = Game(word, wordList, userData)
    registerEventHandlers()

    selection:moveTo(game:getCurrentRow(), game:getCurrentPosition())
    submitButton:setHighlighted(false)
    modal:dismiss()
    uiState = kUIStatePlayingGame
    maybeShowCrankAlert()

    -- Optional simulator smoke: scripts/sim_smoke.sh drops Data/run-smoke before launch.
    if playdate.isSimulator and playdate.file.exists("run-smoke") then
        playdate.file.delete("run-smoke")

        local probeGuess <const> = "crane"
        local expected <const> = checkEntry(probeGuess, word, wordList)

        playdate.timer.performAfterDelay(200, function ()
            if game == nil or game.state ~= kGameStateEnteringWord then
                return
            end

            game:fillRowForSmoke(probeGuess)
            selection:moveTo(game:getCurrentRow(), game:getCurrentPosition())
            game:transitionTo(kGameStateSubmittingWord)
            game:transitionTo(kGameStateCheckingEntry)

            writeVerify({
                ok = true,
                date = cachedDate,
                word = word,
                probeGuess = probeGuess,
                probeState = expected.state,
                selfCheckState = kWordStateCorrect,
                expectedCorrect = kWordStateCorrect,
                playedGuess = true,
            })
        end)
    elseif playdate.isSimulator then
        writeVerify({
            ok = true,
            date = cachedDate,
            word = word,
            selfCheckState = kWordStateCorrect,
            expectedCorrect = kWordStateCorrect,
            playedGuess = false,
        })
    end
end

local function showPuzzleError(message)
    uiState = kUIStatePuzzleError
    modal:displayMessage("Could not load today's Wordle.\n" .. message, "Retry")
end

local function requestPuzzle()
    if game ~= nil then
        game:tearDown()
        game = nil
    end

    cachedDate = nil
    cachedWord = nil
    uiState = kUIStateLoadingPuzzle
    modal:displayLoading("Fetching the " .. nytWordleDate() .. " Wordle…")
    fetchPending = true
end

local function resetGame()
    local today = nytWordleDate()

    if cachedWord ~= nil and cachedDate == today then
        beginPlaying(cachedWord)
        return
    end

    requestPuzzle()
end

local function startPendingFetch()
    fetchPending = false
    uiState = kUIStateLoadingPuzzle
    modal:displayLoading("Fetching the " .. nytWordleDate() .. " Wordle…")

    fetchNytWordle(
        function (word, date)
            cachedDate = date
            cachedWord = word

            if playdate.isSimulator then
                print(cachedDate .. " " .. cachedWord)
            end

            beginPlaying(word)
        end,
        function (message)
            writeVerify({
                ok = false,
                error = message,
                date = nytWordleDate(),
            })

            showPuzzleError(message)
        end
    )
end

-- Handles all input based on current game and UI state.
local function handleInput()
    if uiState == kUIStateLoadingPuzzle then
        return
    end

    if uiState == kUIStatePuzzleError then
        if
            playdate.buttonJustPressed(playdate.kButtonA)
            or playdate.buttonJustPressed(playdate.kButtonRight)
        then
            requestPuzzle()
        end

        return
    end

    if game == nil then
        return
    end

    -- If we're displaying a modal, direct input into that instead of the game. We can press A or
    -- right to dismiss the modal and move back to the "playing game" state.
    if uiState == kUIStateDisplayingModal then
        if
            playdate.buttonJustPressed(playdate.kButtonA)
            or playdate.buttonJustPressed(playdate.kButtonRight)
        then
            -- If we've won or lost, start a new game
            if game.state == kGameStateWon or game.state == kGameStateLost then
                resetGame()
            else
                modal:dismiss()
                uiState = kUIStatePlayingGame
            end
        end

        return
    end

    if game.state == kGameStateEnteringWord then
        local change, acceleratedChange = playdate.getCrankChange()

        -- Handle changing letters by pressing up or down
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            game:moveLetter(-1)

        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            game:moveLetter(1)

        -- Left/B are used to move back to the previous square.
        elseif
            playdate.buttonJustPressed(playdate.kButtonLeft)
            or playdate.buttonJustPressed(playdate.kButtonB)
        then
            if game:getCurrentPosition() > 1 then
                game:movePosition(-1)
                selection:moveTo(game:getCurrentRow(), game:getCurrentPosition())
            end

        -- Right/A are used to enter a letter and advance to the next square.
        elseif
            playdate.buttonJustPressed(playdate.kButtonRight)
            or playdate.buttonJustPressed(playdate.kButtonA)
        then
            if game:getCurrentPosition() < 5 then
                game:movePosition(1)
                selection:moveTo(game:getCurrentRow(), game:getCurrentPosition())
            else
                -- If we go off the right edge, move into "submit" mode.
                game:transitionTo(kGameStateSubmittingWord)
            end

        -- Handle changing letters by cranking if the player has moved the crank.
        -- We want to check this last as crank acceleration has a slight roll-off that can block
        -- button input, which doesn't feel right.
        elseif acceleratedChange ~= 0 then
            game:handleCranking(acceleratedChange)

        end

        return
    end

    -- In submit mode we are focussed on the submit button. We can only move back out of submit
    -- mode (left/B), or confirm our submission (right/A).
    if game.state == kGameStateSubmittingWord then
        if
            playdate.buttonJustPressed(playdate.kButtonLeft)
            or playdate.buttonJustPressed(playdate.kButtonB)
        then
            game:transitionTo(kGameStateEnteringWord)

        elseif
            playdate.buttonJustPressed(playdate.kButtonRight)
            or playdate.buttonJustPressed(playdate.kButtonA)
        then
            game:transitionTo(kGameStateCheckingEntry)
        end
    end
end

modal:displayLoading("Fetching the " .. nytWordleDate() .. " Wordle…")

function playdate.update()
    if fetchPending then
        startPendingFetch()
    end

    -- Check to see if we're crankin' or pressing any buttons, and handle accordingly.
    handleInput()

    -- Update pieces so any animations etc. continue to run.
    if game ~= nil then
        game:updatePieces()
    end

    gfx.sprite.update()

    if showingCrankAlert and not crankAlertTimerExpired then
        playdate.ui.crankIndicator:update()
    end

    playdate.timer.updateTimers()
end
