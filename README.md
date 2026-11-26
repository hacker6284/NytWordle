# NytWordle

Playdate port of [Crordle](https://github.com/mpbarlow/crordle) that loads today's official New York Times Wordle over HTTPS and scores guesses on device.

## How it works

1. On the first `playdate.update`, the game opens `playdate.network.http` to `www.nytimes.com:443` with SSL.
2. It GETs `/svc/wordle/v2/YYYY-MM-DD.json` for the America/New_York calendar day.
3. The JSON `solution` becomes the puzzle word. Existing Crordle UI and `checkEntry` score guesses locally, matching the official web client.

## Build

```sh
export PLAYDATE_SDK_PATH=/Users/zachmills/Developer/PlaydateSDK
"$PLAYDATE_SDK_PATH/bin/pdc" source NytWordle.pdx
open -a "$PLAYDATE_SDK_PATH/bin/Playdate Simulator.app" NytWordle.pdx
```

Allow network access when the simulator asks. Device builds use the same `.pdx` for Lua games.

## Verify Wordle day math

```sh
python3 scripts/verify_nyt_date.py
```

## Controls

Same as Crordle. Crank or Up/Down to pick letters. A/Right advances. B/Left goes back. Submit on the button after the fifth letter.

## License

Crordle was released by Matt Barlow for others to reuse. NYT Wordle content remains New York Times property. This project is an unofficial client.
