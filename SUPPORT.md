<!-- DRAFT for review: not yet approved for publication. -->

# Tiles Support

Tiles is free and open source, a SOULSPCE Collective product. Support happens in the open, on GitHub.

- **Ask a question or report a bug:** <https://github.com/vannaenae/tiles/issues>
- **Report a security problem privately:** <https://github.com/vannaenae/tiles/security/advisories/new> (see the [security policy](https://github.com/vannaenae/tiles/blob/main/SECURITY.md))
- **Something you can't post in public:** [contact email]

Before you open an issue, search the existing ones. Someone may have already found the answer.

## Install Tiles

Tiles needs macOS 13 Ventura or later. It runs on Apple silicon and Intel Macs.

**Terminal (easiest).** Paste this into Terminal. It downloads the latest Tiles, puts it in Applications and opens it.

```bash
curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash
```

**Homebrew.**

```bash
brew tap vannaenae/tiles https://github.com/vannaenae/tiles
brew install --cask vannaenae/tiles/tiles
```

**Download.** Get the zip from [Releases](https://github.com/vannaenae/tiles/releases), unzip it and drag `Tiles.app` to Applications. The first time, right-click `Tiles.app`, choose **Open**, then **Open** again. If macOS still refuses, run:

```bash
xattr -dr com.apple.quarantine /Applications/Tiles.app
```

## Allow Accessibility access

Tiles needs the macOS Accessibility permission to read where your windows are and to move them. On first launch, Tiles asks you to switch it on in **System Settings → Privacy & Security → Accessibility**. Once you do, Tiles starts on its own.

Tiles doesn't need screen recording. Launch at Login is optional.

## First steps

- New windows tile the moment they open. Tiles lives in the menu bar, the Dock or both.
- Press **⌃⌥Space** (Control + Option + Space) to try the next layout.
- Press **⌃⌥** + arrow keys to move focus between windows, and **⌃⌥⇧** + arrows to swap them.
- Press **⌃⌥F** to float or tile the focused window.
- Open **Open Tiles…** (⌘, from the menu) for the dashboard and settings. Turn on **Launch at login** in **General**.
- Every setting is also in `~/.config/tiles/config.json`. Choose **Edit Config File…** in the menu to open it.

## Common fixes

### Accessibility is switched on, but nothing moves

macOS sometimes keeps an old permission entry that no longer matches the app.

1. Click **Reset** on the Tiles dashboard, or choose **Already Allowed? Reset Permission…** from the Tiles menu.
2. Switch Tiles on again in **System Settings → Privacy & Security → Accessibility**.
3. Still stuck? Remove Tiles from that list with **−**, add it again with **+** (from your Applications folder), then choose **Restart Tiles** from the Tiles menu.

This often happens after you build Tiles from source or switch between install methods.

### Some windows don't tile

- Windows in native full screen are left alone.
- Tiles tiles the current Space only.
- Stage Manager should be off.
- Check whether the window is floating: press **⌃⌥F**, or look at your app rules in **Settings → App Rules**.
- Check that tiling is on: press **⌃⌥T**, or see **Tiling On** in the menu.
- Press **⌃⌥R** to retile everything.

### Windows disappeared

They are probably on another workspace. Press **⌃⌘1** to go back to workspace 1. The menu bar and dashboard show which workspaces hold windows. Turning tiling off or quitting Tiles always brings every window back.

### The menu bar says "Config error"

Your config file has a mistake in it, often a missing comma or quote.

1. Open the Tiles menu. The ⚠︎ line shows what went wrong.
2. Choose **Edit Config File…**, fix that line and save. Tiles reloads the file as soon as you save.
3. To start over, use **Settings → General → Restore All Defaults…**.

### A shortcut doesn't work

If another app already uses a shortcut, the Tiles menu shows a line such as **⚠︎ ⌃⌥X is taken by another app**.

- Change the Tiles shortcut in **Settings → Shortcuts**, or in the `hotkeys` section of the config file.
- Or change or quit the other app.
- Shortcuts use key positions on a US keyboard layout.

### Updates

- Tiles checks GitHub once a day and shows **Update to Tiles x.y.z…** in the menu when there's a new version.
- To check now, go to **Settings → General → Updates** and click **Check Now**, then **Install**.
- Tiles only installs updates signed by the Tiles developer. If a download isn't, Tiles won't install it.
- You can also update by running the Terminal install line again, or with `brew upgrade --cask --greedy tiles`.
- To turn off automatic checks, switch off **Check for updates automatically** in the same place.

If Tiles stops moving windows after an update, follow the Accessibility steps above.

## Is Tiles working?

The `tiles` command shows what Tiles is doing, as JSON. The install script and Homebrew add it for you.

```bash
tiles status
```

It shows the version, whether Tiles has permission, whether tiling is on, each display's layout, workspace and window count, and a plain-language `problem` if something is wrong. Check it before deciding Tiles is broken.

## Report a bug

Open an issue at <https://github.com/vannaenae/tiles/issues> and include:

- **Tiles version** (in **Settings → About**, or in `tiles status`);
- **macOS version** (Apple menu → **About This Mac**);
- **the output of `tiles status`**;
- your displays, for example "MacBook Air plus a 34-inch ultrawide";
- what you did, what you expected, and what happened instead;
- the relevant part of `~/.config/tiles/config.json`, if you changed it.

Issues are public. `tiles status` includes your displays' names but no window titles. Read anything before you paste it and remove what you'd rather keep private.

## Uninstall Tiles

First, turn off **Launch at login** in **Settings → General** if you turned it on.

**If you installed with Terminal:**

```bash
curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash -s uninstall
```

This quits Tiles and removes the app and the `tiles` command. Your settings stay, so delete them too if you want:

```bash
rm -rf ~/.config/tiles "$HOME/Library/Application Support/Tiles"
```

**If you installed with Homebrew:**

```bash
brew uninstall --zap --cask tiles
```

`--zap` also removes your settings folders.

**If you installed by hand:** quit Tiles, drag `Tiles.app` from Applications to the Trash (Bin), then delete `~/.config/tiles` and `~/Library/Application Support/Tiles`.

Finally, you can remove Tiles from **System Settings → Privacy & Security → Accessibility**.

## More

- [Privacy Policy](https://vannaenae.github.io/tiles/privacy.html)
- [Terms of Use](https://vannaenae.github.io/tiles/terms.html)
- [Source code and documentation](https://github.com/vannaenae/tiles)
