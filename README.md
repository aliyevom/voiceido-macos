# TextSnipper

A menu-bar app for Mac. Select text on the screen and copy it, or save screenshots of a selected area.

This project is not affiliated with the commercial TextSniper app.

## Download

The latest universal disk image, for Apple silicon and Intel, is on the [releases](https://github.com/aliyevom/voiceido-macos/releases) page. It runs on macOS 27 and later.

Open the disk image and drag TextSnipper to Applications. The first time, right-click TextSnipper and choose Open, then Open. Allow Screen Recording when macOS asks.

## Install from source

You need a Mac on macOS 27 or newer, plus the Xcode Command Line Tools.

```bash
xcode-select --install
cd textsniper
chmod +x build.sh
./build.sh
```

`./build.sh` compiles the app, installs it to `~/Applications/TextSnipper.app`, and opens it. A text-viewfinder icon appears in the menu bar.

## Use

- **⌘⇧2** — drag around text. It is copied to the clipboard.
- **⌘⇧1** — drag around an area. Each shot is added to the screenshot pool.
- **⌘V** — pastes the copied text, or every saved screenshot in capture order.
- **⌘⇧0** — deletes the screenshot pool.
- **Esc** — cancels the selection. A click that is too small to be a selection also cancels.

The first capture asks for Screen Recording permission. Allow **TextSnipper**, then press the shortcut again.

From the menu-bar icon:

- **Keep Line Breaks** — on copies the original lines; off joins them into one paragraph
- **Code Capture** — keeps code, symbols, and indentation as read
- **Auto-heal** — sends the capture to a vision model when a repair key is available
- **Change Shortcut…** — pick another global shortcut for text capture (it must include ⌘, ⌥, or ⌃)
- **Quit TextSnipper**

The menu shows how many screenshots are saved. To have the app ready after a restart, add `~/Applications/TextSnipper.app` in System Settings → General → Login Items.

## Rebuild

From this folder:

```bash
./build.sh
```

## License

[MIT](LICENSE)
