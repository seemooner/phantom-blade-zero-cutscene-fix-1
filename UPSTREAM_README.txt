Cutscene Fix for Phantom Blade Zero  (version 1.4.2)  by Zypre
==============================================================

Fixes pre-rendered cutscenes that stay black while their audio plays.

All 66 of the game's story cutscenes (the 2D animated ones, the 3D CGs, the shadow-play chapter films and the
rendered sequences) are 4K60 H.264 at level 5.2, above the level 5.1 that the Windows
H.264 decoder officially supports, so on some PCs running above 1080p they show nothing. The game
already ships a 1080p copy of every cutscene (Content\MoviesHalfRes, which it uses at 1080p or below).
This mod knows those 66 videos by name and switches each to its 1080p copy as soon as it starts, kept in
sync with the voices, the same as lowering the game to 1080p does but without lowering the game itself. It
does not wait for the decoder to report anything, so it also works where the decoder refuses the video
outright or (Linux / Steam Deck, Proton) does not report a level. Every other video plays as before.

In case a game update adds videos, any other H.264 video above level 5.1 is switched too, and remembered
(known_bad.txt in the mod folder) so it is switched at once next time. It does nothing until a video opens.


REQUIREMENTS
  UE4SS for Phantom Blade Zero (Phantom Blade Zero Nexus Mods, mod 5).
  Optional: Mods Menu (mod 149) with its PBZModsMenuBridge UE4SS mod, to change the settings in game.


INSTALL
  Copy the platform folder from this zip into the game folder (steamapps\common\PBZ), merging
  folders, so the mod ends up in platform\steam\ue4ss\Mods\CutsceneFix\ . Its enabled.txt switches it
  on; nothing needs adding to mods.txt.

UNINSTALL
  Delete platform\steam\ue4ss\Mods\CutsceneFix\ .


SETTINGS
  In the Mods Menu (Settings > Mods Menu), or in CutsceneFix.config.json in the mod's folder
  (created on first start):
    Enabled       On. Off: every video plays as the game picks it.
    Resync        On. Moves the 1080p copy to where the original would be, so the picture matches the
                  voices. Turn off if the picture jumps at the start of a cutscene.
    DetailedLog   Off. On: write every video checked to the UE4SS log, not just switched ones.
  The Mods Menu also has "Forget remembered videos", which empties known_bad.txt.


STILL BLACK?
  Send the UE4SS log (platform\steam\ue4ss\UE4SS.log): the mod writes one line for each cutscene it sees
  (its name, and why it switched it).

CHANGES
  1.4.2  Stability: the mod no longer keeps any of the game's video players between frames, and its hooks touch no
         game object. 1.3.0 and 1.4.1 kept every player they had seen and checked them again later; a player the
         game had destroyed in the meantime could crash the game (seen at the Loong Pillar). Only the game's
         "media opened" event is hooked now (1.4.1 also hooked "tracks changed", dozens of times per cutscene).
  1.4.1  The game's 66 story cutscenes (all level 5.2, read from its Movie paks) switch as soon as the mod sees
         them, without waiting for the decoder to report a level: on PCs whose decoder refuses them, or (Proton)
         reports no level, the check never fired. A cutscene that fails to open is switched from the failed
         address. The log names each cutscene. The MaxLevel setting and the test build's Mode and Watchdog
         settings are gone: with every cutscene known, they had nothing left to do.
  1.3.0  Mods Menu support; settings in CutsceneFix.config.json.
  1.0.0 to 1.2.0  First versions.


CREDITS
  - UE4SS (the RE-UE4SS project) and UE4SS for Phantom Blade Zero (mod 5), which this mod runs on.
  - Mods Menu (mod 149), whose settings interface this mod registers with.
  - Phantom Blade Zero and its cutscenes are the property of S-GAME. The mod ships no game files.
    Unofficial fan-made mod, not affiliated with S-GAME.
