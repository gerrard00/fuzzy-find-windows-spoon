# FuzzyFindWindows Spoon

A Hammerspoon spoon that allows you to search for windows by title across all spaces and screens using fuzzy matching.

## Features

- **Fuzzy Search**: Search for windows by title with fuzzy matching
- **Cross-Space**: Finds windows across all spaces and screens
- **Chooser Interface**: Uses Hammerspoon's chooser for a clean, searchable interface
- **Quick Focus**: Instantly focus any window by selecting it from the list

## Installation

1. Copy the `FuzzyFindWindows.spoon` directory to your Hammerspoon Spoons directory:
   ```bash
   cp -r FuzzyFindWindows.spoon ~/.hammerspoon/Spoons/
   ```

2. Load the spoon in your `~/.hammerspoon/init.lua`:
   ```lua
   hs.loadSpoon("FuzzyFindWindows")
   ```

## Usage

### Basic Setup

```lua
hs.loadSpoon("FuzzyFindWindows")
spoon.FuzzyFindWindows:bindHotkeys({
    search = { {"cmd", "alt"}, "F" }
})
```

This will bind the search function to `Command + Option + F`.

### Manual Trigger

You can also trigger the search programmatically:

```lua
spoon.FuzzyFindWindows:showChooser()
```

## How It Works

1. When triggered, the spoon collects all windows across all spaces and screens
2. It builds a list of choices with window titles and application names
3. The chooser displays these choices with built-in fuzzy matching
4. You can type to filter the list (searches both window title and app name)
5. Selecting a window focuses it and brings it to the front

## Configuration

### Custom Hotkeys

You can customize the hotkey binding:

```lua
spoon.FuzzyFindWindows:bindHotkeys({
    search = { {"cmd", "shift"}, "W" }  -- Command + Shift + W
})
```

## Requirements

- Hammerspoon (latest version recommended)
- macOS

## License

MIT

