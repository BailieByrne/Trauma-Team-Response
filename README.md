# Trauma Team Subscriptions

Version 0.1.11 beta: dispatch priority is now AV, then road crew, then a team on foot. The road truck is only requested if the AV has not appeared after a longer wait, and an AV that arrives late stands the truck crew down instead of both attending. The AV medic now waits until they have landed before the return point is recorded and the run to the patient begins (one continuous run, no mid-fall restart), and pickup triggers when the medic finishes within a few metres of the body rather than needing an exact 1.5 m. No fields were added to the saved response class. REDscript was not compiled in this build; the AV scene needs live tests.

Standalone Cyberpunk 2077 mod. Install the archive with Vortex, or extract it into the game directory while preserving its `r6/` and `bin/` paths. Restart the game after installation. Requires REDscript, RED4ext, TweakXL, Codeware, Cyber Engine Tweaks, and Native Settings UI.

Scan skull-marked human elites and mission bosses for a Trauma Team policy in the scanner abilities panel. Lethal player kills trigger a Silver, Gold, or Platinum dispatch. Nonlethal takedowns do not. The mod permits one active recovery and one queued dispatch.

For full policy odds, guaranteed NPCs, limitations, and test instructions, see `Nexus-Description.txt` beside the upload archive on the mod page.

Optional CET command: `Game.AddToInventory("Items.TraumaTeamTestProgram", 1)`.

Uninstall by removing `r6/scripts/TraumaTeamSubscriptions`, `r6/tweaks/traumaTeamSubscriptions.yaml`, and `bin/x64/plugins/cyber_engine_tweaks/mods/Trauma Team Subscriptions`, then restarting the game. Do not keep duplicate loose copies active alongside a Vortex deployment.
