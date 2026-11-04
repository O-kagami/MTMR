# CPU and memory graph experiment

This helper stores only local CPU and memory samples in its support directory. Compile `graph.swift` for the host architecture and place the resulting `graph` executable, these scripts, `cpu.png` and `memory.png` in `~/Library/Application Support/MTMR/CPU-Memory/`. The `sample` command creates the graph PNGs; `toggle` switches mode and signals the app to refresh the two indicators. Preset entries need to refer to the files in that directory and use the `cpu` and `memory` alternative image keys. Do not commit locally generated history or personal presets.

The Touch Bar transition and immediate refresh need the corresponding app changes. Mode transition timing and appearance require physical-device validation.
