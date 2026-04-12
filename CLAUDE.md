# Windows Terminal Fork — Custom Commands

Fork of Microsoft Windows Terminal with custom CLI commands for agent session management.

## Custom Commands

### `wtd send-input --text "..."` ✅ Working
Sends text to the active pane. Supports C-style escapes (`\r`, `\n`, `\t`, `\x1b`).

### `wtd export-buffer --path <file>` ✅ Working (plain text only)
Exports active pane's scrollback buffer to a file. Currently plain text only.

## Required Changes: ANSI Export + Stdout + Tab Targeting

### Why

The iOS app `ClaudePushNotify` renders Claude Code terminal sessions on phones and external displays. It needs the exact terminal output with ANSI color codes — the same colors the user sees in the terminal. The Unix version uses `tmux capture-pane -p -e` which outputs to stdout with ANSI. Windows needs the same.

### What to change in `export-buffer`

Currently in `src/cascadia/TerminalApp/TabManagement.cpp` line ~365:
```cpp
const auto buffer = control.ReadEntireBuffer();  // plain text only
til::io::write_utf8_string_to_file_atomic(..., til::u16u8(buffer));
```

And `ReadEntireBuffer` in `src/cascadia/TerminalControl/ControlCore.cpp` line ~2348:
```cpp
hstring ControlCore::ReadEntireBuffer() const
{
    const auto lock = _terminal->LockForWriting();
    const auto& textBuffer = _terminal->GetTextBuffer();
    std::wstring str;
    const auto lastRow = textBuffer.GetLastNonSpaceCharacter().y;
    for (auto rowIndex = 0; rowIndex <= lastRow; rowIndex++)
    {
        const auto& row = textBuffer.GetRowByOffset(rowIndex);
        const auto rowText = row.GetText();
        // ... appends plain text only
    }
    return hstring{ str };
}
```

### New method: `ReadBufferWithAnsi`

Add a new method alongside `ReadEntireBuffer` that emits ANSI SGR codes:

```cpp
hstring ControlCore::ReadBufferWithAnsi(int32_t lastNLines) const
{
    const auto lock = _terminal->LockForWriting();
    const auto& textBuffer = _terminal->GetTextBuffer();

    std::wstring str;
    const auto lastRow = textBuffer.GetLastNonSpaceCharacter().y;
    const auto startRow = (lastNLines > 0) ? std::max(0, lastRow - lastNLines + 1) : 0;

    TextAttribute prevAttr{};  // track previous attribute to avoid redundant SGR
    bool firstAttr = true;

    for (auto rowIndex = startRow; rowIndex <= lastRow; rowIndex++)
    {
        const auto& row = textBuffer.GetRowByOffset(rowIndex);
        const auto cols = row.MeasureRight();

        for (til::CoordType col = 0; col < cols; col++)
        {
            const auto attr = row.GetAttrByColumn(col);

            // Emit SGR only when attributes change
            if (firstAttr || attr != prevAttr)
            {
                str.append(attrToAnsi(attr));
                prevAttr = attr;
                firstAttr = false;
            }

            // Emit the character
            const auto [ch, chWidth] = row.GlyphAt(col);
            str.append(ch);
            if (chWidth > 1) col++;  // skip trailing half of wide char
        }

        // Reset at end of line, emit newline
        str.append(L"\x1b[0m");
        if (!row.WasWrapForced())
        {
            str.append(L"\r\n");
        }
    }

    return hstring{ str };
}
```

### Helper: `attrToAnsi`

Convert a `TextAttribute` to ANSI SGR escape sequence:

```cpp
std::wstring attrToAnsi(const TextAttribute& attr)
{
    std::wstring sgr;

    // Foreground RGB
    const auto fg = attr.GetForeground();
    if (fg.IsRgb())
    {
        const auto color = fg.GetRGB();
        sgr.append(fmt::format(L"\x1b[38;2;{};{};{}m",
            GetRValue(color), GetGValue(color), GetBValue(color)));
    }
    else if (fg.IsDefault())
    {
        sgr.append(L"\x1b[39m");
    }

    // Background RGB
    const auto bg = attr.GetBackground();
    if (bg.IsRgb())
    {
        const auto color = bg.GetRGB();
        sgr.append(fmt::format(L"\x1b[48;2;{};{};{}m",
            GetRValue(color), GetGValue(color), GetBValue(color)));
    }
    else if (bg.IsDefault())
    {
        sgr.append(L"\x1b[49m");
    }

    // Bold / Dim
    if (attr.IsIntense()) sgr.append(L"\x1b[1m");
    if (attr.IsFaint()) sgr.append(L"\x1b[2m");

    return sgr;
}
```

Key source files for `TextAttribute` API:
- `src/buffer/out/TextAttribute.hpp` — `GetForeground()`, `GetBackground()`, `IsIntense()`, `IsFaint()`
- `src/buffer/out/TextColor.h` — `IsRgb()`, `GetRGB()`, `IsDefault()`
- `src/buffer/out/Row.hpp` — `GetAttrByColumn()`, `GlyphAt()`, `MeasureRight()`

### Update CLI: new options for `export-buffer`

In `src/cascadia/TerminalApp/AppCommandlineArgs.cpp`, update `_buildExportBufferParser`:

```cpp
void AppCommandlineArgs::_buildExportBufferParser()
{
    _exportBufferCommand = _app.add_subcommand("export-buffer",
        "Export pane buffer (default: stdout with ANSI)");

    auto setupSubcommand = [this](auto* subcommand) {
        // --path is now optional (default: stdout)
        subcommand->add_option("--path,-p", _exportBufferPath,
            "File path (omit for stdout)");
        subcommand->add_option("--tab,-t", _exportBufferTab,
            "Target tab by title");
        subcommand->add_option("--lines,-n", _exportBufferLines,
            "Last N lines (default: all)");
        subcommand->add_flag("--ansi,-a", _exportBufferAnsi,
            "Include ANSI color codes");
        subcommand->add_flag("--json,-j", _exportBufferJson,
            "Output as JSON with dimensions");

        subcommand->callback([&, this]() {
            ActionAndArgs exportAction{};
            exportAction.Action(ShortcutAction::ExportBuffer);
            ExportBufferArgs args{};
            args.Path(winrt::to_hstring(_exportBufferPath));
            args.Tab(winrt::to_hstring(_exportBufferTab));
            args.Lines(_exportBufferLines);
            args.Ansi(_exportBufferAnsi);
            args.Json(_exportBufferJson);
            exportAction.Args(args);
            _startupActions.push_back(exportAction);
        });
    };

    setupSubcommand(_exportBufferCommand);
}
```

### Update handler: stdout support

In `src/cascadia/TerminalApp/TabManagement.cpp`, update `_ExportTab`:

```cpp
safe_void_coroutine TerminalPage::_ExportTab(const Tab& tab, const ExportBufferArgs& args)
{
    try
    {
        // If --tab specified, find that tab instead of active
        TermControl control{ nullptr };
        if (!args.Tab().empty())
        {
            // Find tab by title
            for (const auto& t : _tabs)
            {
                if (t.Title() == args.Tab())
                {
                    control = t.GetActiveTerminalControl();
                    break;
                }
            }
        }
        else
        {
            control = tab.GetActiveTerminalControl();
        }

        if (!control) co_return;

        hstring buffer;
        if (args.Ansi())
            buffer = control.ReadBufferWithAnsi(args.Lines());
        else
            buffer = control.ReadEntireBuffer();

        if (args.Path().empty())
        {
            // Write to stdout
            const auto utf8 = til::u16u8(buffer);
            WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),
                      utf8.data(), (DWORD)utf8.size(), nullptr, nullptr);
        }
        else
        {
            til::io::write_utf8_string_to_file_atomic(
                std::filesystem::path{ std::wstring_view{ args.Path() } },
                til::u16u8(buffer));
        }
    }
    CATCH_LOG();
}
```

### Update `ExportBufferArgs` IDL

In `src/cascadia/TerminalSettingsModel/ActionArgs.idl`, update `ExportBufferArgs`:

```idl
runtimeclass ExportBufferArgs : IActionArgs, IActionArgsDescriptorAccess
{
    ExportBufferArgs();
    String Path;
    String Tab;
    Int32 Lines;
    Boolean Ansi;
    Boolean Json;
}
```

### Expected usage after changes

```bash
# Capture active tab with ANSI → stdout
wtd export-buffer --ansi

# Capture specific tab, last 50 lines, with ANSI → stdout
wtd export-buffer --tab "my-session" --ansi --lines 50

# JSON with dimensions → stdout
wtd export-buffer --tab "my-session" --ansi --json --lines 50
# Output: {"title":"my-session","width":120,"height":40,"output":"\x1b[38;2;78;186;101m⏺..."}

# Plain text to file (backwards compatible)
wtd export-buffer --path C:\output.txt

# Send input to specific tab
wtd send-input --tab "my-session" --text "hello\r"
```

### Testing

```bash
# Should show ANSI escape codes
wtd export-buffer --ansi | findstr /R "\[38"

# Compare with Unix equivalent (should look identical):
# Unix:  tmux capture-pane -t "session" -p -e -S -50
# Win:   wtd export-buffer --tab "session" --ansi --lines 50
```

## Building

```powershell
.\build.ps1 -Configuration Release -Platform x64
# Output: src\cascadia\WindowsTerminal\bin\x64\Release\WindowsTerminal.exe
```

## Architecture Notes

- CLI parsing: `src/cascadia/TerminalApp/AppCommandlineArgs.cpp`
- Action handling: `src/cascadia/TerminalApp/AppActionHandlers.cpp`
- Tab/buffer management: `src/cascadia/TerminalApp/TabManagement.cpp`
- Buffer reading: `src/cascadia/TerminalControl/ControlCore.cpp`
- Text attributes: `src/buffer/out/TextAttribute.hpp`, `TextColor.h`
- Row data: `src/buffer/out/Row.hpp`
