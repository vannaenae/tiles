<!-- DRAFT for legal review: not yet approved for publication. -->

# Security Policy

Tiles is a SOULSPCE Collective product. Thank you for helping keep Tiles and the people who use it safe.

## Report a vulnerability privately

Please **don't** report security problems in a public issue.

Use GitHub's private vulnerability reporting instead:

**<https://github.com/vannaenae/tiles/security/advisories/new>**

Only the maintainers can see your report there. If you can't use GitHub, email <info@soulspcecollective.com>.

Please include:

- what the problem is and what an attacker could do with it;
- the steps to reproduce it, or a proof of concept;
- the Tiles version (`tiles status` shows it) and your macOS version;
- any idea you have for a fix.

## Supported versions

We fix security problems in the **latest release** only. Please update before you report, and check the problem still happens.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Anything older | No |

## What's in scope

- **The Tiles app**, including the `tiles` command and `tiles://` links.
- **The updater:** the update check, the download, and the code-signature check that makes sure an update is signed by the Tiles developer (team ID GQ638955FB) before it's installed.
- **The install script** (`install.sh`), including its own signature check and its uninstall option.
- **The Homebrew cask** in this repository.
- **The website** at <https://i-tilesapp.vercel.app/>.

## What's out of scope

- Problems in macOS, GitHub, Vercel or Homebrew themselves. Please report those to Apple, GitHub, Vercel or Homebrew.
- Attacks that need someone to already control your Mac or your admin account.
- Social engineering, phishing or physical attacks.
- Denial-of-service attacks against GitHub or the website.

## What to expect

Tiles is a small open-source project, so we can't promise fixed response times. Here's what we aim to do:

- acknowledge your report within a week;
- tell you whether we can reproduce it, and keep you updated while we work on it;
- release a fix as soon as we reasonably can, and publish a security advisory on GitHub;
- credit you in the advisory and release notes, if you'd like.

Please give us a reasonable chance to release a fix before you share details publicly. We'll agree a disclosure date with you.

## Good-faith research

If you research security in good faith and follow this policy, we won't complain about it or take action against you. Good faith means you:

- only test against your own Mac and your own copy of Tiles;
- don't access, change or delete other people's data;
- don't disrupt the website or GitHub for others;
- report what you find to us privately and give us time to fix it.

## Checking your copy of Tiles

Official builds are signed by the Tiles developer. To check your copy, run:

```bash
codesign -dv /Applications/Tiles.app 2>&1 | grep TeamIdentifier
```

It should print `TeamIdentifier=GQ638955FB`. If it prints anything else, don't run that copy; download Tiles again from <https://github.com/vannaenae/tiles/releases>.
