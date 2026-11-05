# Local level control development

This working tree builds on upstream MTMR commit `94fc98c` with a `localLevel` item that locally switches between brightness and volume sliders. It does not rewrite the preset on each switch. Both modes reserve the same width, so switching does not displace other items. The volume slider uses the same standard round knob as the brightness slider, and the level icons vary by the observed level. Short visual transitions respect macOS Reduce Motion.

The brightness slider reads and writes the built-in display through the private DisplayServices framework. The requested value is validated, and on a write failure the slider is disabled and reset to the measured value. The slider is also disabled when a display or required API is unavailable. This private API can change in future macOS releases. A same-value write and a small physical-device adjustment both succeeded in a local trial.

A local existing preset may use `{"type":"localLevel","align":"right"}` in place of the old level-control region. Do not commit personal presets, API keys or Spotify information. The level control reads brightness and audio capability in-process. Bundled artwork and CPU/memory helpers are provisioned as described in `MANAGED_MEDIA.md`; existing custom presets are not overwritten.

Automatic updates are not configured. The update menu opens this fork’s releases page; a fork-specific signed feed is required for automatic updates. Existing login-at-startup code remains present and has not been tested in this build.

An unsigned arm64 debug build and brightness write-policy and Reduce Motion tests succeeded locally. The user confirmed a small brightness adjustment and matching round volume knob in a physical-device trial. Audio route changes, the full existing widget configuration, layout, permissions, launch-at-login and updater behavior are not yet comprehensively verified. Do not install over an existing app without a backup and explicit real-device validation.

The experimental `flexibleDock` option lets a left-aligned Dock absorb available width without changing the width of the other items. The slider edge observer attempts to reach the minimum and maximum when a single-finger swipe ends at an edge; normal dragging remains active. Both changes have automated tests, but their behavior on a physical Touch Bar is not yet confirmed.
