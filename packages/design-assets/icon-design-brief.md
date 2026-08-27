# Icon design brief

Stage 00 defines direction only; it does not generate platform icon catalogs.

The canonical Parent Controller vector source lives at [`controller-icon.svg`](controller-icon.svg). Platform-ready raster/icon output is generated from that one file in project-owned temporary build output.

## Shared interface language

All visible product surfaces use one adapted dark editorial language. Native macOS controls and accessibility behavior remain intact; the visual system never hides the app or makes monitoring look covert.

- Canvas: near-black navy (`#06080C`) with slightly raised navy surfaces.
- Primary accent: warm coral (`#FF5843`); softer coral is reserved for emphasis and warnings.
- Text: warm off-white with cool gray secondary copy and clearly visible focus/selection states.
- Typography: monospaced display headings and small uppercase eyebrow labels, paired with the platform system font for long text and controls.
- Shape: restrained 8–12 px radii, thin low-contrast borders, short coral rules, and sparse ornament.
- Motion: brief and functional only; respect Reduce Motion.
- Accessibility: preserve native keyboard navigation, VoiceOver labels, system notification preferences, and sufficient text/control contrast.

The native macOS apps import the single `DesignSystem` Swift target. The Chromium popup mirrors the same semantic values in its self-contained CSS. Future Windows and iPad implementations should map these semantics to native platform tokens instead of copying view code. The system macOS Installer remains platform-owned and is not custom-skinned.

## Shared concept

Use an original **connected family constellation**: three warm, human-centered nodes joined by an open forward orbit. The different node sizes suggest an adult guiding children, while the open orbit communicates family connection and communication without implying surveillance or confinement. Use geometry that remains recognizable at 16 px, with no text, eyes, cameras, locks copied from another product, platform logos, or trademarked artwork.

## Product differentiation

- **Parent Controller:** teal-to-navy field, pale open orbit, and warm family nodes.
- **Desktop Child Agent:** one family node with a short orbit segment and a clearly related silhouette.
- **iPad child app:** rounded aqua family node and orbit treatment following current Apple icon construction guidance at implementation time.
- **Browser extension:** one-color node/orbit mark optimized for small toolbar rendering.

## Source and generation rules

Keep one editable vector source plus a small manifest of product color tokens when the first icon catalog is implemented. Use one deterministic generation script. Commit only the vector source and platform-required catalog/package assets; generate intermediate PNGs in project-owned temporary output and remove them after verification. Check light/dark backgrounds, grayscale, high contrast, and 16/32 px legibility. Record authorship and any font or asset licenses; text should not appear in the icon itself.
