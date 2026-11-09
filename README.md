# Hand of Freedom

Trackpad camera control for World of Warcraft on macOS. No more click-and-drag:

- **Two fingers** turn your character (a right-button drag).
- **Three fingers** orbit the camera (a left-button drag).
- **Pinch** zooms.
- Over a chat window, a quest log or the minimap, a two-finger swipe can **scroll** it instead.

Taps stay taps, a resting palm or thumb is ignored, and the tool only acts while the game is in front.

## Requirements

- macOS 26 on a Mac with a built-in trackpad. An external Magic Trackpad is untested.
- World of Warcraft: Forever.
- Xcode 26 (Swift 6.2) to build it.

## Install

```sh
git clone https://github.com/nchie/hand-of-freedom.git
cd hand-of-freedom
make install
```

This builds `Hand of Freedom.app`, copies it to `~/Applications` and starts it. It lives in the menu bar
as a hand icon. There are no prebuilt downloads yet.

## First run

The welcome window asks for **Accessibility**, the one permission the tool needs: it lets it send mouse
input to the game and hold back the trackpad's own scrolling while it does.

**Scrolling game windows automatically** (Settings › Gestures › Scrolling) is optional and needs two more
things, both set up from that screen:

- **The Hand of Freedom addon.** It shows what is under the mouse by drawing a few pixels at the top
  centre of the game, hidden behind the notch on a MacBook. It reads only the mouse focus and changes
  nothing in the game.
- **Screen Recording.** The app captures only a small strip at the top of the game's window to read
  those pixels, never the rest of the screen, and only while the game is in front.

Without them you can still scroll by holding a key of your choice as your fingers land (Hold to scroll).

## Settings

Sensitivity, vertical inversion, which button each finger count holds, pinch zoom, scrolling, and launch
at login. Settings are saved in `~/Library/Application Support/Hand of Freedom/settings.json`.

## Troubleshooting

- **No menu bar icon:** it may be hidden under the notch. Open Hand of Freedom again from
  `~/Applications` or Spotlight to get to its settings.
- **Nothing happens after a rebuild:** macOS ties permissions to the exact build. Reset them and grant
  Accessibility again:
  ```sh
  tccutil reset All se.nchie.handoffreedom
  ```
  A self-signed code-signing certificate named "Hand of Freedom Dev" (Keychain Access › Certificate
  Assistant › Create a Certificate, type Code Signing) avoids this: build with
  `HOF_IDENTITY="Hand of Freedom Dev" make install`.
- **Three fingers drag windows:** turn off three-finger drag in System Settings › Accessibility › Pointer
  Control › Trackpad Options. The welcome window points this out.

## Bug reports

Turn on Settings › Diagnostics › "Record trackpad data for bug reports". When a gesture feels wrong in
the game, press ⌃⌥⌘S: the app saves the last 30 seconds of trackpad data as a clip in
`~/Library/Application Support/Hand of Freedom/Clips`. Attach it to an issue with a few words on what
you expected. Recording is off by default and nothing is written until you save.

## Development

```sh
swift build
swift test
```

`hof` is the developer tool (`swift run hof help`): `log` prints live trackpad frames and what the engine
would do, `record` and `replay` capture and re-run traces, and `live` drives the game from the terminal.
`HOF_UI_PREVIEW=settings` or `=welcome` opens the app's windows without tracking or posting anything.

[docs/how-it-works.md](docs/how-it-works.md) describes the pipeline, the gesture engine and the reasons
behind the less obvious choices.

## Disclaimer

Hand of Freedom is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a
trademark of Blizzard Entertainment.

The tool automates nothing: it turns your own finger movement into the same mouse input a mouse would
send, and the addon only reads what is under the mouse. It uses Apple's private MultitouchSupport
framework, which a macOS update could break. Use it at your own risk and within the game's terms of use.

## License

MIT. See [LICENSE](LICENSE).
