# Project license

Copyright (C) 2026 Duan

SPDX-License-Identifier: GPL-2.0-or-later

MIDI Clock Controller is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full terms.

Third-party components retain their original copyright notices and licenses: Ableton Link (GPL-2.0-or-later), Asio (Boost Software License 1.0), DSEG7 Classic (SIL Open Font License 1.1), and Sparkle 2.10.1 (MIT and bundled third-party notices). Their notices are kept with the corresponding sources and in the app's ThirdPartyLicenses directory.

Each release includes a corresponding source archive containing the project sources, pinned Link and Asio headers, resources, and build scripts. On macOS with Xcode and Swift 5.9+ / C++17 support, extract the source archive and run `zsh scripts/build-app.sh`, then `zsh scripts/build-dmg.sh`. See README.md and CONTRIBUTING.md for requirements and test commands. The pinned Link and Asio sources are included. Swift Package Manager downloads the pinned Sparkle package and verifies its binary artifact checksum during the first build.
