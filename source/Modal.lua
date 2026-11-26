-- Modal.lua
-- This class handles the rendering of full-screen messages to the player.

import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/object"
import "support"

local gfx <const> = playdate.graphics
local bounds <const> = playdate.geometry.rect.new(35, 70, 330, 100)

-- These constants are used to lay out the modal contents.
local smallFontHeight <const> = fonts.small:getHeight()
local regularFontHeight <const> = fonts.regular:getHeight()
local buttonIconWidth <const> = fonts.small:getTextWidth("Ⓐ")
local buttonMargin <const> = {x = 8, y = 5, inner = 3}

class("Modal").extends()

function Modal:init()
    Modal.super.init(self)

    local sprite <const> = gfx.sprite.new()

    -- Message to display in the modal. If this is nil, the modal does not draw.
    local message = nil

    -- The number lines of text in message
    local lines = 1

    -- The text to render in the prompt to dismiss the modal
    local buttonText = nil

    local showButton = true

    local function show(self, newMessage, newButtonText, withButton)
        message = newMessage
        showButton = withButton
        buttonText = newButtonText
        lines = 1

        for _ in message:gmatch("\n") do
            lines += 1
        end

        sprite:markDirty()
    end

    local function displayMessage(self, newMessage, newButtonText)
        show(self, newMessage, newButtonText, true)
    end

    local function displayLoading(self, newMessage)
        show(self, newMessage, nil, false)
    end

    local function dismiss(self)
        message = nil
        sprite:markDirty()
    end

    -- Configure the modal sprite
    function sprite:draw(x, y, width, height)
        -- Don't draw anything if we have no modal to show
        if message == nil then
            return
        end

        doInGraphicsContext(function ()
            -- 3D/shadow effect
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(0, 2, self.width, self.height - 2, 10)

            -- Background
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRoundRect(0, 0, self.width, self.height - 2, 10)

            -- Border
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRoundRect(0, 0, self.width, self.height - 2, 10)

            -- Draw the message in the center of the roundrect.
            gfx.setFont(fonts.regular)
            gfx.drawTextAligned(
                message,
                self.width / 2,
                (self.height / 2) - ((regularFontHeight * lines) / 2),
                kTextAlignment.center
            )

            if showButton then
                gfx.setFont(fonts.small)

                local buttonText <const> = buttonText or "OK"
                local buttonTextWidth <const> = fonts.small:getTextWidth(buttonText)

                gfx.drawText(
                    "Ⓐ",
                    self.width - buttonTextWidth - buttonIconWidth - buttonMargin.x - buttonMargin.inner,
                    self.height - smallFontHeight - buttonMargin.y
                )

                gfx.drawText(
                    buttonText,
                    self.width - buttonTextWidth - buttonMargin.x,
                    self.height - smallFontHeight - buttonMargin.y
                )
            end
        end)
    end

    sprite:setBounds(bounds)

    -- Ensure the modal renders above everything else
    sprite:setZIndex(10)
    sprite:add()

    self.displayMessage = displayMessage
    self.displayLoading = displayLoading
    self.dismiss = dismiss
end
