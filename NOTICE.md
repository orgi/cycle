# Licence notice

Cycle, a bike computer app for Android and iOS.
Copyright (C) 2026 orgi (https://github.com/orgi)

This program is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this
program (see [LICENSE](LICENSE)). If not, see <https://www.gnu.org/licenses/>.

## Additional permissions under GNU GPL version 3 section 7

These permissions apply to the code whose copyright is held by the copyright holder named
above. You may remove them from your copies of the program; you may not add further
restrictions.

1. **Linking with flutter_blue_plus.** If you modify this program, or any covered work, by
   linking or combining it with the flutter_blue_plus Bluetooth library and its federated
   packages (or modified versions of them), containing parts covered by the terms of the
   FlutterBluePlus License, the licensors of this program grant you additional permission
   to convey the resulting work. Corresponding Source for a non-source form of such a
   combination shall include the source code for the parts of flutter_blue_plus used as
   well as that of the covered work. This permission does not change the terms of the
   FlutterBluePlus License itself, which you must still meet for that library (it is free
   for personal and non-profit use; commercial use requires a licence from its author).

2. **App store distribution.** You may convey the program in object code form through an
   app distribution service (for example Apple's App Store or Google Play) even though that
   service's terms of use place restrictions on recipients that this License would
   otherwise not allow, provided that you also make the Corresponding Source of that exact
   version available under this License in the manner described in section 6 (a public
   source repository is sufficient). This permission covers only restrictions that come
   from the distribution service's terms; you may not impose any of your own.

## Third-party components

The app includes or links against third-party code and data under their own licences. Each
package's full licence text ships with its source (see `pubspec.lock` for the exact versions).

| Component | Licence | Notes |
| --- | --- | --- |
| mapsforge_flutter and its packages | LGPL-3.0 | A patched copy lives in [`third_party/mapsforge_flutter`](third_party/mapsforge_flutter) ([what was changed](third_party/mapsforge_flutter/PATCH.md)). |
| Detailed map styles (`assets/render_themes/detailed*.xml`) and their symbols | LGPL-3.0 | Unmodified from mapsforge_flutter; see each file's header. |
| flutter_blue_plus | FlutterBluePlus License 1.5 | Not an open-source licence; see permission 1 above. |
| Other Dart/Flutter packages | MIT, BSD-2/3-Clause, Apache-2.0 | |
| OpenStreetMap map data (bundled Monaco demo map, downloaded maps) | ODbL 1.0 | © OpenStreetMap contributors. |
