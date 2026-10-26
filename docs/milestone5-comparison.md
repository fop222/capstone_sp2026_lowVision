# Milestone 5: tray-focused inference comparison

Date: 26 October 2026. Decision: **do not enable either evaluated tray-focused prompt**. Neither demonstrated better food recognition on the five Sprint 21 reference images, and the shorter variant introduced unsupported names that passed the confidence filter.

## Method

- Source: images embedded in `Sprint 21 Report - Low Vision Daily Companion - 19 Oct 2026 (1).pdf`.
- Used the original embedded images, not screenshots of complete PDF pages. Test 2 is available only inside an app screenshot: extracted its photo rectangle `(128, 172, 1008, 320)` to exclude the old results. Its pans are partially cut off, limiting conclusions about that case.
- Server health reported Qwen3-VL-2B-Instruct and EasyOCR. The existing server handles resizing and generation.
- Baseline: application prompt and parser at commit `97f6956`, with OCR first, `task=dining`, `max_tokens=1024`, and `requireEvidence: true`.
- Candidate A: append instructions to infer unlabeled dishes only from food inside their serving containers, ignore surrounding objects, and keep visual descriptions out of the output. Preserve readable labels and drink options.
- Candidate B: replace the existing unlabeled-food sentence with shorter tray-focused wording instead of appending instructions.
- Each variant used identical image bytes and identical cached OCR text for each image. Baseline/A order alternated between images. Candidate B ran afterward against the same inputs.
- Comparison criterion: fewer unsupported guesses and fewer missed clearly identifiable items, without sacrificing label or drink recognition. Counts alone are not accuracy scores.
- Evaluated 15 completed full-photo predictions: five images times three prompts. This isolates the prompt change; it does not exercise camera capture, app-side resizing, crop retries, UI, or Flutter tests. It is a small qualitative comparison, not a calibrated accuracy benchmark.

## Results after the app's response parser

| Report image | Baseline | Candidate A | Candidate B | Assessment |
| --- | --- | --- | --- | --- |
| 1: fountain drinks | Water | Water | Water | No additional drink options recovered. |
| 2: four pans | Cilantro Lime; Cilantro Rice; Roasted Broccoli | Same | Same | The single Cilantro Lime Rice label remains split into two items; no improvement. |
| 3: desserts | No accepted items | No accepted items | Krispie Kreme | A invents this name at 0.8, so the filter rejects it; B gives it 0.9 and it reaches the parsed results. The pictured sign does not support that name. |
| 4: labeled hot line | Pasta; Marinara; Steamed Green Beans | Pasta; Marinara; Green Beans | Same names as baseline | A loses readable label specificity. B does not recover more distinct foods and marks the names as visual estimates. |
| 5: wide buffet | Pasta | Pasta | Pasta; Hondoxt | B introduces an unsupported name. Both baseline and A still attach the station heading PASTA to a dish. |

Candidate A also produced a long repetitive explanation on the dessert image despite the JSON-only instruction, taking approximately 48 seconds versus approximately 2 seconds for the baseline. Existing parsing kept that explanation out of the displayed results. Candidate B was shorter, but its unsupported names make it unsuitable for enabling.

The baseline itself still has recognition gaps, including missed drink options, missed desserts, split label text, and misuse of a station heading. These observations do **not** validate milestone 1's end-to-end image recognition. Adding the evaluated tray-only wording did not resolve those gaps.

## Separate parser fix discovered during comparison

The initial run exposed `Unsupported operation: Cannot add to an unmodifiable list` when the VLM omitted dietary/allergen arrays. `_stringList` returned `const []`, while normalization appended sign-derived metadata. Commit `97f6956` makes the empty list mutable. The complete comparison above was rerun with this same fix applied to all variants. The parser fix is not counted as an accuracy benefit of tray-focused inference.

## Reproduction and retained evidence

The manual runner is `scripts/compare_dining_milestone5.dart`. It records prompts, raw server responses, parsed dish names, and elapsed times. It does not invoke Flutter tests. Run against the baseline commit and the original images:

```text
dart scripts/compare_dining_milestone5.dart INPUT_DIR OUTPUT_DIR
dart scripts/compare_dining_milestone5.dart INPUT_DIR OUTPUT_DIR compact
```

Expected input names: `test1-drinks.png`, `test2-four-pans.png`, `test3-desserts.png`, `test4-hot-line.png`, `test5-wide-line.png`.

The completed local evidence is in `%TEMP%\lumio-sprint21\comparison-fixed`; extracted images are in `%TEMP%\lumio-sprint21\originals`. Original images and raw server responses are not included in this commit. Production keeps the baseline prompt. This result applies to the two evaluated prompt variants, not every possible tray-localization approach.
