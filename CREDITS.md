YTMusicNxt (fork of YTMusicUltimate) -- third-party credits
==========================================================

YTMusicUltimate itself is GPL-3.0, Copyright (c) Ginsu and Dayanch96,
https://github.com/dayanch96/YTMusicUltimate. The fork keeps that licence.

Ported code from other projects keeps its original licence and copyright.
Every ported tweak is listed below and credited in the app itself, under
YTMusicUltimate > Links.


VolumeBoostYT
-------------
  Upstream:   https://github.com/irum0320/VolumeBoostYT
  Author:     vasirakcalgux
  Licence:    MIT, Copyright (c) 2024 vasirakcalgux
  Files:      Source/VolumeBoost.x, Source/VolumeBoostHUD.h, Source/VolumeBoostHUD.m
  Changes:    The AVFoundation volume hooks, the edge-swipe gesture and the HUD
              were reused as-is. The upstream tweak's settings injection
              (YTSettingsGroupData / YTAppSettingsPresentationData /
              YTSettingsSectionItemManager) was dropped because those are
              YouTube-only classes with no YouTube Music equivalent, which is
              why its settings section never showed up in this app. It is driven
              by the "Volume boost" switch in YTMusicUltimate > Player options
              instead, and defaults to off.


Before vendoring another tweak into this project
------------------------------------------------
  1. Add an entry to +[YTMUVendoredCredit allCredits] in Source/VendoredCredits.m.
     That is what makes the credit show up in the app.
  2. Put a header comment at the top of every ported file naming the upstream
     project, its author, its licence and what you changed.
  3. Add a section to this file and to the Credits section of README.md.
  4. Ship the upstream licence text alongside the ported files if it is not
     already in this repository.