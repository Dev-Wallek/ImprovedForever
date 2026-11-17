# Taint

Read this before setting anything on a game frame, calling the game's window, frame manager or SmartNavigation code, or debugging `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN`. The rules themselves are in `CLAUDE.md` ("Window focus").

## Debugging a taint error

For `ADDON_ACTION_FORBIDDEN` / blocked (e.g. `SetPreferredGamepadInteractTarget()` when a gamepad-focused window closes):

- Note the addon the error names each time: several modules can taint the same game state, and the name changes as one is fixed.
- Repeat each test 3+ times: the error can be intermittent.
- Taint log: `/console taintLog 1`, reproduce, `/console taintLog 0`, then `/reload`, and read `_forever_/Logs/taint.log` in the game's folder. It restarts on every `/reload` while on. Don't use level 2: it can flood and freeze the game.
- Blocked actions without the taint log: the core logs every `ADDON_ACTION_BLOCKED` / forbidden, with the addon, the function and where (instance, zone, combat), to `ImprovedForeverDB.taintLog` in the saved variables (`ImprovedForever/Diag.lua`; `/if report` shows it, `/if clearreport` empties it). It names what was blocked, not where the taint came from.
- Taint sources found so far:
  - our code filling the game's shared caches first (`QuestCache:Get`, `QuestUtil.CanCreateQuestGroup`) or adding to its shared async listeners (`QuestEventListener:AddCallback`): keep our own copies
  - the game's `EventRegistry` frame events (`EventUtil.ContinueAfterAllEvents`, `RegisterFrameEventAndCallback`): their counts live in attributes of one shared frame, ours writes them tainted, and the game's own waiter (the objective tracker's `Init`) then runs tainted, in sessions where ours ran first. Wait on our own frame
  - setting properties of the game's frames: use `IF.Focus.Fade`
  - `AddManagedFrame` into the game's columns
  - taking, passing on or binding the game's pad buttons while its window has focus
  - calling the game's window code that drives SmartNavigation

## Exceptions

The rules in `CLAUDE.md` (no property of the game's frames set, no call into the frame manager or the game's window code) stay broad on purpose. A case may break one only once it is on the list below, and it gets there only after all of these:

- The game's source shows why it can't taint: the path is one Blizzard opens to addons (`SecureHelper:SetSecureValue` / `SecureHelper:WrapFunction`, an event the game handles in its own handler), or no game code runs with our taint. Forever's source: `github.com/Ketho/wow-ui-source-forever`.
- Why it closes a gamepad-focused window cleanly: closing runs the frame manager's `FrameHidden`, the binding stack, then the protected `SetPreferredGamepadInteractTarget` (`Blizzard_GamepadActionBars/MainActionBarFrame.lua`); any of it run or reading a value tainted by us gets that blocked.
- The taint log, 3+ times: open the case, close a gamepad-focused window (game's and ours), then a fight; no `ADDON_ACTION_BLOCKED` / forbidden.
- In combat too, or guarded: what Blizzard opens to addons only out of combat (`SecureHelper`'s default check) is called only out of combat.
- Its entry here (what, where it may be used, the evidence), and a comment at each use naming this list.

The list:

- `SmartNavigation_MarkFrameIgnored` / `SmartNavigation_ClearIgnoreStatus`, out of combat only: they set the mark through `SecureHelper`, which the game's source says "may be set without causing taint (only while out of combat)" (`Blizzard_GamepadSmartNavigation/Utility.lua`). Taint log: open.
- `C_SettingsUtil.OpenSettingsPanel(categoryID)`: it fires `SETTINGS_PANEL_OPEN`, and the settings panel opens itself in its own event handler (`Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua`), the path of every addon's `Settings.OpenToCategory`. Taint log: open.
- `hooksecurefunc` on the frame manager's functions (`FrameShown`...): a post-hook that only reads; the game's function runs untouched before it. Taint log: open.
- `Hide()` on the game's bag frames (`ContainerFrame_GenerateFrame`'s) while Baganator keeps them under its hidden parent: Baganator, an addon, already reparented them, and the game never shows them. Escape and a fight after it unblocked (measured). Taint log: open.

Not on the list, though Blizzard opens them to addons out of combat (`SecureHelper:WrapFunction`): the frame manager's `FrameShown` / `FrameHidden` and SmartNavigation's `SetTargetButtonForFrame`, `SetScrollFrameForFrame`, `SelectFirstButton`. In combat they're refused ("Interface action blocked"). Calling the manager tainted window closing once, without a record of whether in combat: check them as above, out of combat, before using one. The manager's `Focus*` and `ShowUIPanel` aren't opened to addons.
