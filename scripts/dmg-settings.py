"""Headless dmgbuild settings for the Display Save drag-to-install image."""

import os
from pathlib import Path
import subprocess

app = Path(os.environ["DISPLAY_SAVE_DMG_APP"])
resources = Path(os.environ["DISPLAY_SAVE_DMG_ROOT"]) / "Resources"

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
background = str(resources / "DMGBackground.png")
icon = str(resources / "AppIcon.icns")

# Copy with checked subprocesses in create_hook, not dmgbuild's unchecked ditto.
# Reserve the same 128 MiB overhead as dmgbuild's normal automatic sizing.
allocated_bytes = 128 * 1024 * 1024
for directory, _, names in os.walk(app):
    for name in names:
        length = os.lstat(os.path.join(directory, name)).st_size
        allocated_bytes += ((length + 4095) // 4096) * 4096
size = str((allocated_bytes + 1023) // 1024) + "k"
files = []
symlinks = {"Applications": "/Applications"}

window_rect = ((160, 160), (640, 420))
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0
show_icon_preview = False
show_item_info = False
arrange_by = None
grid_spacing = 80
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 104
icon_locations = {
    "Display Save.app": (170, 210),
    "Applications": (470, 210),
}


def create_hook(mount_point, options):
    """Fail packaging if copying or applying required Finder flags fails."""
    subprocess.run(
        ["/usr/bin/ditto", str(app), str(Path(mount_point) / "Display Save.app")],
        check=True,
    )
    # dmgbuild copies the custom volume icon before this hook; explicitly check
    # its Finder flag rather than relying on the library's unchecked SetFile.
    subprocess.run(["/usr/bin/SetFile", "-a", "C", mount_point], check=True)
    subprocess.run(
        [
            "/usr/bin/SetFile", "-a", "V",
            str(Path(mount_point) / ".VolumeIcon.icns"),
        ],
        check=True,
    )
