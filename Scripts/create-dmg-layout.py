#!/usr/bin/env python3
"""Regenerate the static Finder layout. Optional tooling: pip install ds-store.

Normal packaging copies the generated resource and needs no Python dependencies.
The layout contains only fixed display settings and item names, no machine paths.
"""
from pathlib import Path
from ds_store import DSStore

output = Path(__file__).resolve().parent.parent / 'Resources' / 'DMGLayout.store'
with DSStore.open(str(output), 'w+') as store:
    store['.']['vstl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        'ShowToolbar': False, 'ShowSidebar': False, 'ShowStatusBar': False,
        'ShowPathbar': False, 'ShowTabView': False,
        'WindowBounds': '{{200, 200}, {600, 330}}',
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 1,
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0,
        'backgroundColorBlue': 1.0, 'iconSize': 104.0, 'textSize': 14.0,
        'gridSpacing': 100.0, 'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
        'arrangeBy': 'none', 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': True,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['NetMon.app']['Iloc'] = (150, 145)
    store['Applications']['Iloc'] = (450, 145)
print('Created Resources/DMGLayout.store')
