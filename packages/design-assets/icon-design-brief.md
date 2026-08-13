# Icon design brief

Stage 00 defines direction only; it does not generate platform icon catalogs.

The canonical Parent Controller vector source lives at [`controller-icon.svg`](controller-icon.svg). Platform-ready raster/icon output is generated from that one file in project-owned temporary build output.

## Shared concept

Use an original **connected family constellation**: three warm, human-centered nodes joined by an open forward orbit. The different node sizes suggest an adult guiding children, while the open orbit communicates family connection and communication without implying surveillance or confinement. Use geometry that remains recognizable at 16 px, with no text, eyes, cameras, locks copied from another product, platform logos, or trademarked artwork.

## Product differentiation

- **Parent Controller:** teal-to-navy field, pale open orbit, and warm family nodes.
- **Desktop Child Agent:** one family node with a short orbit segment and a clearly related silhouette.
- **iPad child app:** rounded aqua family node and orbit treatment following current Apple icon construction guidance at implementation time.
- **Browser extension:** one-color node/orbit mark optimized for small toolbar rendering.

## Source and generation rules

Keep one editable vector source plus a small manifest of product color tokens when the first icon catalog is implemented. Use one deterministic generation script. Commit only the vector source and platform-required catalog/package assets; generate intermediate PNGs in project-owned temporary output and remove them after verification. Check light/dark backgrounds, grayscale, high contrast, and 16/32 px legibility. Record authorship and any font or asset licenses; text should not appear in the icon itself.
