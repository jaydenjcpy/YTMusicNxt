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


Return-YouTube-Music-Dislikes
---------------------------
  Upstream:   https://github.com/PoomSmart/Return-YouTube-Music-Dislikes
  Also:       https://github.com/PoomSmart/Return-YouTube-Dislikes
  Author:     PoomSmart
  Licence:    GPL-3.0
  Files:      Source/ReturnDislikes/, Source/Headers/ASDisplayNode.h,
              Source/Headers/YTILikeButtonRenderer.h
  Changes:    YouTube Music hides dislike counts but still builds the
              like/dislike row, so the counts are fetched from the Return
              YouTube Dislike database and written over the "Dislike" label.
              The upstream Settings.x is dropped: it builds its UI from
              YTMSettingsSectionItem's itemWithTitle:... and
              switchItemWithTitle:... factories, which 9.39 no longer has. The
              four switches live in YTMusicUltimate > Player options instead and
              all default to off, so nothing is sent to the RYD database until
              the user asks for it. Only the YTLikeServiceImpl vote hook is
              installed, because YTLikeService no longer exists. Upstream's ICU
              compact number formatting is replaced by the K/M/B suffixes it
              uses on iOS 12, since theos' iPhoneOS SDK ships no ICU headers.


YTMABConfig
-----------
  Upstream:   https://github.com/PoomSmart/YTMABConfig
  Author:     PoomSmart
  Licence:    GPL-3.0
  Files:      Source/ABFlags/, Source/Prefs/ABFlagsSettingsController.m,
              Source/Headers/YTMAppDelegate.h
  Changes:    The hook is kept: it walks
              YTMAppDelegate -> _MDXServices -> _MDXConfig -> the three config
              objects and hooks every BOOL getter on them, which is how you turn
              an experiment on before YouTube serves it to your account. All
              three links and all three config classes still exist in 9.39.
              Two things changed. The chain is walked defensively, because
              upstream raises an exception when an instance is nil and that
              takes the app down if YouTube renames an ivar. And an
              un-overridden flag now calls the original implementation instead
              of a value cached at hook time, so a flag YouTube reloads later is
              not frozen at its launch value.
              Upstream's Settings.x is dropped for the same reason as the
              dislikes port: YTMSettingsSectionItem's itemWithTitle:... and
              switchItemWithTitle:... factories are gone in 9.39. The replacement
              browser sorts flags by class and selector, adds a search field,
              tints overridden flags orange, and can reset them all. Category
              grouping, import/export, copy and "view modified settings" are not
              carried over.


YouMusicPiP
-----------
  Upstream:   https://github.com/PoomSmart/YouMusicPiP
  Based on:   https://github.com/PoomSmart/YouPiP
  Author:     PoomSmart
  Licence:    MIT, Copyright (c) 2021 - 2024 PoomSmart
  Files:      Source/MusicPiP/YouMusicPiP.x, Source/Headers/MusicPiP.h
  Changes:    This is the one port that had to be rebuilt rather than moved.
              Upstream hooks four things that no longer exist in 9.39:
              MLPIPController (now MLPIPControllerImpl),
              YTBackgroundabilityPolicy and its Impl (deleted),
              YTPlayerViewController's -appWillResignActive: (the callback moved
              to YTPlayerPIPController as -appWillResignActive, with no
              argument), and YTIPlayabilityStatus's -hasPictureInPicture. Three
              of MLDefaultPlayerViewFactory's ...ForVideo: methods are gone too.
              Its server-side assignment had to be rewritten rather than
              dropped: YTIIosMediaHotConfig no longer has an
              enablePictureInPicture property, but it does have
              enablePipForNonPremiumUsers and
              enablePipForNonBackgroundableContent, which are what gate
              picture in picture in a music app. Those are set from
              MLDefaultPlayerViewFactory, where upstream sets the old one, and
              this is the part that actually turns the feature on.
              The client-side gates are forced as well: YTPlayerPIPController's
              isPictureInPictureAllowed, isEligibleForPictureInPicture and
              canEnablePictureInPicture, MLPIPControllerImpl's
              pictureInPictureSupported, AVPictureInPictureController's
              supported check, and YTIPlayabilityStatus's two playability
              flags. Leaving the app is caught on YTPlayerPIPController
              -appWillResignActive, which then activates the MediaHub PiP
              controller and starts the AVPlayer one.
              Forcing the AVPlayer render view (renderViewType 6) is kept, since
              hamplayer views cannot be handed to AVPlayerViewController.
              Defaults off, because it changes how video renders even when PiP
              is never used.


Before vendoring another tweak into this project
------------------------------------------------
  1. Add an entry to +[YTMUVendoredCredit allCredits] in Source/VendoredCredits.m.
     That is what makes the credit show up in the app.
  2. Put a header comment at the top of every ported file naming the upstream
     project, its author, its licence and what you changed.
  3. Add a section to this file and to the Credits section of README.md.
  4. Ship the upstream licence text alongside the ported files if it is not
     already in this repository.