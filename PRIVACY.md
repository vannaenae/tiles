<!-- DRAFT for legal review: not yet approved for publication. -->

# Tiles Privacy Policy

**Effective 9 November 2026**

Tiles is a free, open-source window manager for Mac. It is a SOULSPCE Collective product. This policy covers the Tiles app and the Tiles website at <https://vannaenae.github.io/tiles/>. In this policy, "we" and "us" means SOULSPCE Collective.

## The short version

**Tiles collects nothing.**

- There is no account and no sign-in.
- There are no ads and no in-app purchases.
- There is no analytics, no telemetry and no crash reporting.
- Your settings stay on your Mac.
- The only network traffic is the update check with GitHub, and you can turn it off.
- We never collect, sell or share your personal data.

The rest of this page gives the details.

## What stays on your Mac

Tiles saves a few files on your Mac so it can remember your setup. They never leave your Mac unless you copy or share them yourself.

| File | What's in it |
|---|---|
| `~/.config/tiles/config.json` | Your settings, app rules and keyboard shortcuts. |
| `~/.config/tiles/profiles/` | Settings snapshots that you choose to save as profiles. |
| `~/Library/Application Support/Tiles/scenes.json` | Your layouts for each set of displays: display IDs and names, layout, split ratio, and app bundle identifiers such as `com.apple.Safari`. Never window titles. |
| `~/Library/Application Support/Tiles/status.json` | What Tiles is doing right now: its current phase, your displays' names, their layouts and window counts. Tiles writes it while running and deletes it when it quits. |

If you export your settings, the file goes wherever you choose to save it.

We can't see any of these files. You can open, edit or delete them at any time.

## Permissions and why Tiles needs them

**Accessibility.** Tiles uses the macOS Accessibility permission to read each window's position, size, app and title, and to move and resize windows. Tiles can't tile without it. You can turn it off at any time in **System Settings → Privacy & Security → Accessibility**.

**Window titles.** Tiles reads window titles in memory only, to check app rules that use `titleContains` (for example, "float Finder windows whose title contains Copy") and to list windows when you search with the window finder. Titles are never stored and never sent anywhere.

**Keyboard shortcuts.** Tiles registers global keyboard shortcuts so its commands work in any app. Tiles is told only when you press one of its own shortcuts. It does not record what you type.

**Mouse and trackpad.** Some features react to the pointer as you use it, such as focus follows mouse and scrolling with ⌃⌥ held in the Scrolling layout. Tiles handles these events as they happen and does not store or send them.

**Launch at Login (optional).** If you turn on Launch at Login, Tiles registers itself with macOS to open when you log in. You can turn it off in Tiles' settings or in **System Settings → General → Login Items**.

## Network: update checks

The only network traffic Tiles makes is for updates.

If **Check for updates automatically** is on, Tiles asks GitHub for the latest release once when it launches and then once a day. It contacts this address:

`https://api.github.com/repos/vannaenae/tiles/releases/latest`

When you click **Install**, Tiles downloads the new version from:

`https://github.com/vannaenae/tiles/releases/download/v<version>/Tiles.zip`

Before installing, Tiles checks that the download is signed by the Tiles developer (team ID GQ638955FB). If it isn't, Tiles doesn't install it.

These requests go to GitHub, Inc. Like any website, GitHub receives your IP address and standard request headers, and handles them under the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). Tiles sends no identifiers, no settings and nothing about your windows.

**Turn it off:** in Tiles, go to **Settings → General → Updates** and switch off **Check for updates automatically**. Or set `"checkForUpdates": false` in `~/.config/tiles/config.json`. Update checks are on by default.

**Installing Tiles.** The install script and the Homebrew cask download Tiles from GitHub too, so GitHub handles those requests in the same way. Homebrew is a separate project with its own privacy policy.

**Mac App Store.** If you get Tiles from the Mac App Store, Apple handles the download under Apple's own privacy policy. Apple may give developers aggregated download figures that don't identify you.

## The website

The Tiles website is hosted on GitHub Pages. GitHub may log visits, including your IP address, under the GitHub Privacy Statement. The site itself sets no cookies, has no analytics and loads nothing from other websites.

## Contacting us

If you open an issue or start a discussion on GitHub, it is public and handled under GitHub's terms. Please don't post anything private. Check `tiles status` output and config files before you paste them.

If you email us at [contact email], we receive your email address and whatever you write. We use it only to reply to you.

## Children

Tiles is not directed at children. It collects no data from anyone, including children.

## Your rights and choices

We hold no personal data about you, so there is nothing for us to access, correct, export or delete. Everything Tiles saves is on your Mac and under your control.

- **Turn off update checks:** Settings → General → Updates, or `"checkForUpdates": false` in the config file.
- **Remove Accessibility access:** System Settings → Privacy & Security → Accessibility.
- **Delete your data:** delete `~/.config/tiles` and `~/Library/Application Support/Tiles`, and any settings files you exported.
- **Remove Tiles completely:** see the uninstall steps on the [Support page](https://vannaenae.github.io/tiles/support.html#uninstall-tiles). If you used the install script, run `curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash -s uninstall`, then delete the two folders above.

Depending on where you live, you may have legal rights over your personal data, such as the right to complain to your local data protection authority. Those rights still apply.

## Changes to this policy

If Tiles changes how it handles data, we will update this policy first. We will change the effective date at the top and publish the new version on the website and in the [Tiles repository](https://github.com/vannaenae/tiles). The repository history shows every past version.

## Contact

- Publisher: SOULSPCE Collective, [legal entity name and address]
- Email: [contact email]
- Questions and issues: <https://github.com/vannaenae/tiles/issues>
- Security reports: <https://github.com/vannaenae/tiles/security/advisories/new>

## Appendix: App Store privacy answers

For the Mac App Store listing ("App Privacy" in App Store Connect):

| Question | Answer |
|---|---|
| Data collection | **Data Not Collected.** Tiles does not collect any data from this app. |
| Tracking | **No.** Tiles does not track you across apps or websites owned by other companies. |
| Third-party SDKs | None. |
| Privacy Policy URL | <https://vannaenae.github.io/tiles/privacy.html> |
| Support URL | <https://vannaenae.github.io/tiles/support.html> |

Notes for whoever fills in the form:

- Everything Tiles saves stays on the Mac. Apple counts data handled only on the device as not collected.
- The update check sends no identifiers and stores nothing about the user. If the App Store build leaves out the built-in updater, because the App Store delivers updates, then the App Store copy makes no network requests at all.
