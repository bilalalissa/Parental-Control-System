# Icon design brief

Stage 00 defines direction only; it does not generate platform icon catalogs.

## Shared concept

Use an original, simple **open shelter** shape surrounding a small four-point compass/star. The open side communicates visibility rather than confinement; the compass communicates guidance rather than surveillance. Use geometry that remains recognizable at 16 px, with no text, eyes, cameras, locks copied from another product, platform logos, or trademarked artwork.

## Product differentiation

- **Parent Controller:** deep indigo shelter with a warm amber compass.
- **Desktop Child Agent:** teal shelter with a pale-blue compass and a clearly related silhouette.
- **iPad child app:** blue-green shelter with a rounded lavender compass, following current Apple icon construction guidance at implementation time.
- **Browser extension:** one-color shelter/compass mark optimized for small toolbar rendering.

## Source and generation rules

Keep one editable vector source plus a small manifest of product color tokens when the first icon catalog is implemented. Use one deterministic generation script. Commit only the vector source and platform-required catalog/package assets; generate intermediate PNGs in project-owned temporary output and remove them after verification. Check light/dark backgrounds, grayscale, high contrast, and 16/32 px legibility. Record authorship and any font or asset licenses; text should not appear in the icon itself.
