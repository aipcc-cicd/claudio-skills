#!/usr/bin/env python3
"""
Create or overwrite a Google Slides presentation from a JSON content file.

Usage:
    create_presentation.py --title "Title" --content /path/to/content.json [--human]
    create_presentation.py --presentation-id <id> --content /path/to/content.json [--human]

When --presentation-id is given, all existing slides are replaced (overwrite mode).
When only --title is given, a new blank presentation is created.

Content JSON format:
{
  "slides": [
    {"layout": "TITLE", "title": "...", "subtitle": "..."},
    {"layout": "SECTION_HEADER", "title": "...", "subtitle": "..."},
    {"layout": "TITLE_AND_BODY", "title": "...", "body": ["bullet 1", "bullet 2"]},
    {"layout": "TITLE_ONLY", "title": "..."}
  ]
}

Supported predefined layouts: TITLE, SECTION_HEADER, TITLE_AND_BODY, TITLE_ONLY, BLANK
"""

import argparse
import json
import subprocess
import sys
import uuid


def run_gws(args, body=None, params=None):
    cmd = ["gws"] + args
    if params:
        cmd.extend(["--params", json.dumps(params)])
    if body:
        cmd.extend(["--json", json.dumps(body)])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: gws command failed: {' '.join(cmd)}", file=sys.stderr)
        print(f"stderr: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    if not result.stdout.strip():
        return {}
    return json.loads(result.stdout)


def build_slide_requests(slides_content, existing_slide_ids=None):
    requests = []

    # Add new slides first (so the deck is never empty during the operation)
    for i, slide in enumerate(slides_content):
        # layoutId takes precedence — used for custom/branded masters
        if "layoutId" in slide:
            layout_ref = {"layoutId": slide["layoutId"]}
        else:
            layout_ref = {"predefinedLayout": slide.get("layout", "TITLE_AND_BODY")}

        requests.append({
            "createSlide": {
                "objectId": f"slide_{i}_{uuid.uuid4().hex[:8]}",
                "insertionIndex": i,
                "slideLayoutReference": layout_ref
            }
        })

    # Delete all pre-existing slides after the new ones are in place
    for slide_id in (existing_slide_ids or []):
        requests.append({"deleteObject": {"objectId": slide_id}})

    return requests


def build_text_requests(slides_content, presentation_data):
    requests = []
    slides_data = presentation_data.get("slides", [])

    if len(slides_content) != len(slides_data):
        raise ValueError(
            f"Slide count mismatch: content has {len(slides_content)} slides "
            f"but presentation returned {len(slides_data)}"
        )

    for i, (slide_content, slide_data) in enumerate(zip(slides_content, slides_data)):
        page_elements = slide_data.get("pageElements", [])

        for elem in page_elements:
            if "shape" not in elem:
                continue
            shape = elem["shape"]
            if "placeholder" not in shape:
                continue

            ph_type = shape["placeholder"]["type"]
            elem_id = elem["objectId"]

            if ph_type in ("TITLE", "CENTERED_TITLE") and "title" in slide_content:
                requests.append({
                    "insertText": {
                        "objectId": elem_id,
                        "text": slide_content["title"]
                    }
                })

            elif ph_type == "SUBTITLE" and "subtitle" in slide_content:
                requests.append({
                    "insertText": {
                        "objectId": elem_id,
                        "text": slide_content["subtitle"]
                    }
                })

            elif ph_type == "BODY":
                if "body" in slide_content:
                    body = slide_content["body"]
                    body_text = "\n".join(str(b) for b in body) if isinstance(body, list) else str(body)
                    requests.append({
                        "insertText": {
                            "objectId": elem_id,
                            "text": body_text
                        }
                    })
                elif "subtitle" in slide_content and "title" in slide_content:
                    # SECTION_HEADER uses BODY for its second placeholder
                    requests.append({
                        "insertText": {
                            "objectId": elem_id,
                            "text": slide_content["subtitle"]
                        }
                    })

    return requests


def main():
    parser = argparse.ArgumentParser(description="Create or overwrite a Google Slides presentation")
    parser.add_argument("--title", help="Presentation title (required when creating new)")
    parser.add_argument("--presentation-id", help="Existing presentation ID to overwrite")
    parser.add_argument("--content", required=True, help="Path to content JSON file")
    parser.add_argument("--human", action="store_true", help="Human-readable output")
    args = parser.parse_args()

    if not args.title and not args.presentation_id:
        print("ERROR: --title or --presentation-id is required", file=sys.stderr)
        sys.exit(1)

    with open(args.content) as f:
        content = json.load(f)

    slides_content = content.get("slides", [])
    if not slides_content:
        print("ERROR: No slides found in content file", file=sys.stderr)
        sys.exit(1)

    if args.presentation_id:
        # Overwrite mode — use existing presentation
        pres_id = args.presentation_id
        print(f"Overwriting existing presentation: {pres_id}", file=sys.stderr)
        existing = run_gws(
            ["slides", "presentations", "get"],
            params={"presentationId": pres_id}
        )
        existing_slide_ids = [s["objectId"] for s in existing.get("slides", [])]
        title = args.title or existing.get("title", "Presentation")
        print(f"Found {len(existing_slide_ids)} existing slides to replace", file=sys.stderr)
    else:
        # Create mode — new blank presentation
        title = args.title
        print(f"Creating new presentation: {title}", file=sys.stderr)
        create_result = run_gws(
            ["slides", "presentations", "create"],
            body={"title": title}
        )
        pres_id = create_result["presentationId"]
        existing_slide_ids = [create_result["slides"][0]["objectId"]]
        print(f"Presentation ID: {pres_id}", file=sys.stderr)

    print(f"Adding {len(slides_content)} slides...", file=sys.stderr)
    batch1 = build_slide_requests(slides_content, existing_slide_ids)
    run_gws(
        ["slides", "presentations", "batchUpdate"],
        params={"presentationId": pres_id},
        body={"requests": batch1}
    )

    print("Fetching slide structure for text insertion...", file=sys.stderr)
    pres_data = run_gws(
        ["slides", "presentations", "get"],
        params={"presentationId": pres_id}
    )

    batch2 = build_text_requests(slides_content, pres_data)
    if batch2:
        print(f"Inserting text ({len(batch2)} operations)...", file=sys.stderr)
        run_gws(
            ["slides", "presentations", "batchUpdate"],
            params={"presentationId": pres_id},
            body={"requests": batch2}
        )

    pres_url = f"https://docs.google.com/presentation/d/{pres_id}/edit"

    if args.human:
        print(f"\nDone!")
        print(f"Title:  {title}")
        print(f"Slides: {len(slides_content)}")
        print(f"ID:     {pres_id}")
        print(f"URL:    {pres_url}")
    else:
        print(json.dumps({
            "presentationId": pres_id,
            "title": title,
            "slideCount": len(slides_content),
            "url": pres_url
        }))


if __name__ == "__main__":
    main()
