#!/usr/bin/env python3
"""
Add visual diagrams to a Google Slides presentation.

Usage:
    add_diagrams.py --presentation-id <id> [--targets <slide-title>=<diagram-type> ...]

Diagram types: layer, table, two-column, three-box

Notes:
  - createShape ignores elementProperties.size; size is set via
    updatePageElementTransform (applyMode=ABSOLUTE) immediately after creation
  - Tables use updateTableColumnProperties + updateTableRowProperties for sizing
  - Slide canvas is assumed to be standard widescreen (13.33" x 7.5"); not auto-detected
"""

import argparse
import json
import subprocess
import sys

SLIDE_W = 13.330
SLIDE_H = 7.500
EMU = 914400
DEFAULT_SHAPE_EMU = 3000000  # createShape default size (~3.281")

RH_RED   = {"red": 0.933, "green": 0.000, "blue": 0.000}
RH_LTRED = {"red": 0.860, "green": 0.100, "blue": 0.100}
RH_MDRED = {"red": 0.750, "green": 0.040, "blue": 0.040}
RH_DKRED = {"red": 0.600, "green": 0.030, "blue": 0.030}
RH_DARK  = {"red": 0.082, "green": 0.082, "blue": 0.082}
RH_GRAY  = {"red": 0.400, "green": 0.400, "blue": 0.400}
RH_LGRAY = {"red": 0.930, "green": 0.930, "blue": 0.930}
WHITE    = {"red": 1.000, "green": 1.000, "blue": 1.000}
BLUE_DK  = {"red": 0.063, "green": 0.212, "blue": 0.373}

DIAGRAM_PREFIXES = ("lyr_", "cmp_", "tco_", "rel_", "test_")


def run_gws(args, body=None, params=None):
    cmd = ["gws"] + args
    if params:
        cmd.extend(["--params", json.dumps(params)])
    if body:
        cmd.extend(["--json", json.dumps(body)])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: gws failed\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def e(inches):
    return int(inches * EMU)


def transform_req(oid, x, y, w, h):
    """Set correct size+position via ABSOLUTE transform (works around createShape size bug)."""
    return {
        "updatePageElementTransform": {
            "objectId": oid,
            "applyMode": "ABSOLUTE",
            "transform": {
                "scaleX": (w * EMU) / DEFAULT_SHAPE_EMU,
                "scaleY": (h * EMU) / DEFAULT_SHAPE_EMU,
                "translateX": e(x),
                "translateY": e(y),
                "unit": "EMU",
            },
        }
    }


def create_shape(oid, page_id, x, y, w, h, fill,
                 text=None, text_color=None, font_size=14,
                 bold=False, align="CENTER", italic=False):
    tc = text_color or WHITE
    reqs = [
        {
            "createShape": {
                "objectId": oid,
                "shapeType": "RECTANGLE",
                "elementProperties": {
                    "pageObjectId": page_id,
                    "size": {
                        "width":  {"magnitude": DEFAULT_SHAPE_EMU, "unit": "EMU"},
                        "height": {"magnitude": DEFAULT_SHAPE_EMU, "unit": "EMU"},
                    },
                    "transform": {
                        "scaleX": 1, "scaleY": 1,
                        "translateX": e(x), "translateY": e(y),
                        "unit": "EMU",
                    },
                },
            }
        },
        transform_req(oid, x, y, w, h),
        {
            "updateShapeProperties": {
                "objectId": oid,
                "fields": "shapeBackgroundFill,outline",
                "shapeProperties": {
                    "shapeBackgroundFill": {
                        "solidFill": {"color": {"rgbColor": fill}}
                    },
                    "outline": {"propertyState": "NOT_RENDERED"},
                },
            }
        },
    ]
    if text:
        reqs += [
            {"insertText": {"objectId": oid, "text": text}},
            {
                "updateTextStyle": {
                    "objectId": oid,
                    "style": {
                        "foregroundColor": {"opaqueColor": {"rgbColor": tc}},
                        "fontSize": {"magnitude": font_size, "unit": "PT"},
                        "bold": bold,
                        "italic": italic,
                        "fontFamily": "Arial",
                    },
                    "fields": "foregroundColor,fontSize,bold,italic,fontFamily",
                }
            },
            {
                "updateParagraphStyle": {
                    "objectId": oid,
                    "style": {
                        "alignment": align,
                        "spaceAbove": {"magnitude": 0, "unit": "PT"},
                        "spacingMode": "NEVER_COLLAPSE",
                    },
                    "fields": "alignment,spaceAbove,spacingMode",
                }
            },
        ]
    return reqs


def create_table(oid, page_id, x, y, w, h, rows, cols):
    """Create table at (x,y) with total size (w x h).
    Tables ignore elementProperties.size; size is controlled via
    updateTableColumnProperties + updateTableRowProperties instead.
    Position (translateX/Y) IS respected by createTable.
    """
    col_w_emu = e(w / cols)
    row_h_emu = e(h / rows)
    return [
        {
            "createTable": {
                "objectId": oid,
                "elementProperties": {
                    "pageObjectId": page_id,
                    "size": {
                        "width":  {"magnitude": DEFAULT_SHAPE_EMU, "unit": "EMU"},
                        "height": {"magnitude": DEFAULT_SHAPE_EMU, "unit": "EMU"},
                    },
                    "transform": {
                        "scaleX": 1, "scaleY": 1,
                        "translateX": e(x), "translateY": e(y),
                        "unit": "EMU",
                    },
                },
                "rows": rows,
                "columns": cols,
            }
        },
        # Set column widths (tables cannot use updatePageElementTransform)
        {
            "updateTableColumnProperties": {
                "objectId": oid,
                "tableColumnProperties": {
                    "columnWidth": {"magnitude": col_w_emu, "unit": "EMU"}
                },
                "fields": "columnWidth",
            }
        },
        # Set row heights
        {
            "updateTableRowProperties": {
                "objectId": oid,
                "tableRowProperties": {
                    "minRowHeight": {"magnitude": row_h_emu, "unit": "EMU"}
                },
                "fields": "minRowHeight",
            }
        },
    ]


def restyle_range(oid, start, end, font_size, bold=False, tc=None):
    style = {"fontSize": {"magnitude": font_size, "unit": "PT"}, "bold": bold}
    fields = "fontSize,bold"
    if tc:
        style["foregroundColor"] = {"opaqueColor": {"rgbColor": tc}}
        fields += ",foregroundColor"
    return {
        "updateTextStyle": {
            "objectId": oid,
            "textRange": {"type": "FIXED_RANGE", "startIndex": start, "endIndex": end},
            "style": style,
            "fields": fields,
        }
    }


def cx(w):
    """Left x to center element of width w on the slide."""
    return (SLIDE_W - w) / 2


# ── Diagram 1: 4-Layer Architecture Stack ────────────────────────────────────

def layer_diagram(slide_id, body_id, prefix):
    reqs = []
    if body_id:
        reqs.append({"deleteText": {"objectId": body_id, "textRange": {"type": "ALL"}}})

    layers = [
        ("Inference Layer",      RH_RED,   "Model serving  |  API endpoints  |  Token streaming"),
        ("MLOps Layer",          RH_LTRED, "Pipelines  |  Experiment tracking  |  Model registry"),
        ("Platform Layer",       RH_DKRED, "OpenShift AI  |  Notebooks  |  Distributed training"),
        ("Infrastructure Layer", RH_DARK,  "GPU scheduling  |  Storage  |  Kubernetes / OpenShift"),
    ]

    box_w = 11.5
    box_h = 0.98
    gap   = 0.14
    x0    = cx(box_w)
    y0    = 1.95

    for i, (label, color, sub) in enumerate(layers):
        y   = y0 + i * (box_h + gap)
        oid = f"{prefix}_layer_{i}"
        full = f"{label}\n{sub}"
        reqs += create_shape(oid, slide_id, x0, y, box_w, box_h,
                             color, text=full, font_size=18, bold=True)
        reqs.append(restyle_range(oid, len(label) + 1, len(full), 12, bold=False))

    total_h = 4 * box_h + 3 * gap
    reqs += create_shape(f"{prefix}_label", slide_id,
                         x0 - 0.7, y0, 0.6, total_h,
                         RH_LGRAY, text="Stack\n(bottom to top)\n\n↑",
                         text_color=RH_DARK, font_size=10, bold=True)
    return reqs


# ── Diagram 2: Product Comparison Table ──────────────────────────────────────

def comparison_table(slide_id, body_id, prefix):
    reqs = []
    if body_id:
        reqs.append({"deleteText": {"objectId": body_id, "textRange": {"type": "ALL"}}})

    tbl_w, tbl_h = 12.0, 4.4
    x0, y0 = cx(tbl_w), 1.90

    tbl_oid = f"{prefix}_table"
    reqs += create_table(tbl_oid, slide_id, x0, y0, tbl_w, tbl_h, 4, 3)

    rows_data = [
        ["Product",       "Best For",                           "Scale"],
        ["OpenShift AI",  "Team-based AI/ML platform",          "Medium to Massive"],
        ["RHEL AI",       "Single node  /  edge  /  developer", "Small to Medium"],
        ["RHAIIS",        "High-performance model serving",      "Medium to Massive"],
    ]
    for r, row in enumerate(rows_data):
        is_hdr = r == 0
        bg = RH_RED if is_hdr else (RH_LGRAY if r % 2 == 1 else WHITE)
        tc = WHITE if is_hdr else RH_DARK
        for c, txt in enumerate(row):
            reqs += [
                {
                    "insertText": {
                        "objectId": tbl_oid,
                        "cellLocation": {"rowIndex": r, "columnIndex": c},
                        "text": txt,
                    }
                },
                {
                    "updateTableCellProperties": {
                        "objectId": tbl_oid,
                        "tableRange": {
                            "location": {"rowIndex": r, "columnIndex": c},
                            "rowSpan": 1, "columnSpan": 1,
                        },
                        "tableCellProperties": {
                            "tableCellBackgroundFill": {
                                "solidFill": {"color": {"rgbColor": bg}}
                            },
                            "contentAlignment": "MIDDLE",
                        },
                        "fields": "tableCellBackgroundFill,contentAlignment",
                    }
                },
                {
                    "updateTextStyle": {
                        "objectId": tbl_oid,
                        "cellLocation": {"rowIndex": r, "columnIndex": c},
                        "style": {
                            "foregroundColor": {"opaqueColor": {"rgbColor": tc}},
                            "bold": is_hdr,
                            "fontSize": {"magnitude": 19 if is_hdr else 18, "unit": "PT"},
                            "fontFamily": "Arial",
                        },
                        "fields": "foregroundColor,bold,fontSize,fontFamily",
                    }
                },
                {
                    "updateParagraphStyle": {
                        "objectId": tbl_oid,
                        "cellLocation": {"rowIndex": r, "columnIndex": c},
                        "style": {"alignment": "CENTER"},
                        "fields": "alignment",
                    }
                },
            ]

    note_oid = f"{prefix}_note"
    reqs += create_shape(note_oid, slide_id, x0, y0 + tbl_h + 0.2, tbl_w, 0.4,
                         WHITE,
                         text="Complementary products — enterprises typically adopt all three.",
                         text_color=RH_GRAY, font_size=14, align="CENTER")
    return reqs


# ── Diagram 3: RHEL AI vs OpenShift AI ───────────────────────────────────────

def two_column_compare(slide_id, body_id, prefix):
    reqs = []
    if body_id:
        reqs.append({"deleteText": {"objectId": body_id, "textRange": {"type": "ALL"}}})

    col_w = 5.7
    gap   = 0.75
    total = col_w * 2 + gap
    x0    = cx(total)
    y0    = 1.95
    hdr_h = 0.75
    bdy_h = 4.2

    cols = [
        {
            "header": "RHEL AI",
            "color": BLUE_DK,
            "items": [
                "Single node / workstation",
                "Edge & disconnected environments",
                "Developer-first, fast start",
                "Air-gapped deployments",
                "ilab CLI tooling",
                "Small to medium scale",
            ],
        },
        {
            "header": "OpenShift AI",
            "color": RH_RED,
            "items": [
                "Multi-user team platform",
                "Hybrid cloud & on-prem fleet",
                "Operator-managed lifecycle",
                "Pipelines & model registry",
                "GPU cluster orchestration",
                "Medium to massive scale",
            ],
        },
    ]

    for ci, col in enumerate(cols):
        xi = x0 + ci * (col_w + gap)
        reqs += create_shape(f"{prefix}_hdr_{ci}", slide_id,
                             xi, y0, col_w, hdr_h,
                             col["color"], text=col["header"],
                             font_size=23, bold=True)
        body_text = "\n".join(f"  * {item}" for item in col["items"])
        reqs += create_shape(f"{prefix}_bdy_{ci}", slide_id,
                             xi, y0 + hdr_h + 0.06, col_w, bdy_h,
                             RH_LGRAY, text=body_text,
                             text_color=RH_DARK, font_size=15, align="START")

    vs_x = x0 + col_w + (gap - 0.45) / 2
    vs_y = y0 + hdr_h + bdy_h / 2 - 0.22
    reqs += create_shape(f"{prefix}_vs", slide_id, vs_x, vs_y, 0.45, 0.45,
                         WHITE, text="vs", text_color=RH_GRAY,
                         font_size=20, bold=True)

    bar_y = y0 + hdr_h + bdy_h + 0.18
    reqs += create_shape(f"{prefix}_bar", slide_id, x0, bar_y, total, 0.42,
                         RH_DARK,
                         text="Shared foundation: Red Hat support  |  RHEL security  |  CVE lifecycle coverage",
                         font_size=13, bold=False)
    return reqs


# ── Diagram 4: 3-Product Relationship ────────────────────────────────────────

def product_relationship(slide_id, body_id, prefix):
    reqs = []
    if body_id:
        reqs.append({"deleteText": {"objectId": body_id, "textRange": {"type": "ALL"}}})

    box_w = 3.5
    gap   = 0.52
    total = box_w * 3 + gap * 2
    x0    = cx(total)
    y0    = 1.95
    hdr_h = 0.75
    tag_h = 0.46
    bdy_h = 3.7

    products = [
        {
            "name": "OpenShift AI",
            "color": RH_RED,
            "role": "Build  *  Train  *  Experiment",
            "body": "Multi-user ML platform\nJupyter workbenches\nPipelines & model registry\nGPU orchestration\nHybrid cloud scale",
        },
        {
            "name": "RHAIIS",
            "color": RH_DARK,
            "role": "Serve  *  Scale  *  Optimize",
            "body": "Production LLM serving\nvLLM optimized runtime\nToken streaming\nOpenAI-compatible API\nAutoscaling support",
        },
        {
            "name": "RHEL AI",
            "color": BLUE_DK,
            "role": "Deploy  *  Edge  *  Simplify",
            "body": "Single-node inference\nilab CLI tooling\nEdge & air-gapped\nDeveloper workstation\nFast onboarding",
        },
    ]

    for i, prod in enumerate(products):
        xi = x0 + i * (box_w + gap)

        reqs += create_shape(f"{prefix}_hdr_{i}", slide_id,
                             xi, y0, box_w, hdr_h,
                             prod["color"], text=prod["name"],
                             font_size=20, bold=True)

        reqs += create_shape(f"{prefix}_tag_{i}", slide_id,
                             xi, y0 + hdr_h + 0.04, box_w, tag_h,
                             RH_LGRAY, text=prod["role"],
                             text_color=prod["color"], font_size=12, bold=True)

        reqs += create_shape(f"{prefix}_bdy_{i}", slide_id,
                             xi, y0 + hdr_h + tag_h + 0.08, box_w, bdy_h,
                             WHITE, text=prod["body"],
                             text_color=RH_DARK, font_size=14, align="CENTER")

    for i in range(2):
        arr_x = x0 + (i + 1) * box_w + i * gap + (gap - 0.38) / 2
        arr_y = y0 + hdr_h / 2 - 0.22
        reqs += create_shape(f"{prefix}_arr_{i}", slide_id,
                             arr_x, arr_y, 0.38, 0.44,
                             WHITE, text=">", text_color=RH_GRAY,
                             font_size=26, bold=True)

    return reqs


# ── Main ─────────────────────────────────────────────────────────────────────

def get_slide_info(pres):
    result = {}
    for slide in pres.get("slides", []):
        sid        = slide["objectId"]
        title_text = None
        body_pid   = None
        for elem in slide.get("pageElements", []):
            shape   = elem.get("shape", {})
            ph      = shape.get("placeholder", {})
            ph_type = ph.get("type", "")
            raw = "".join(
                t.get("textRun", {}).get("content", "")
                for t in shape.get("text", {}).get("textElements", [])
                if t.get("textRun")
            ).strip()
            if ph_type in ("TITLE", "CENTERED_TITLE"):
                title_text = raw
            elif ph_type in ("BODY", "SUBTITLE") and raw:
                body_pid = elem["objectId"]
        if title_text:
            result[title_text] = {"slide_id": sid, "body_id": body_pid}
    return result


def find_existing_diagram_ids(pres):
    ids = []
    for slide in pres.get("slides", []):
        for elem in slide.get("pageElements", []):
            oid = elem.get("objectId", "")
            if any(oid.startswith(p) for p in DIAGRAM_PREFIXES):
                ids.append(oid)
    return ids


DIAGRAM_FNS = {
    "layer":      (layer_diagram,        "lyr"),
    "table":      (comparison_table,     "cmp"),
    "two-column": (two_column_compare,   "tco"),
    "three-box":  (product_relationship, "rel"),
}


def main():
    parser = argparse.ArgumentParser(description="Add diagrams to a Google Slides presentation")
    parser.add_argument("--presentation-id", required=True,
                        help="Presentation ID from the Google Slides URL")
    parser.add_argument("--target", action="append", metavar="TITLE=TYPE",
                        help=(
                            "Slide title and diagram type, e.g. "
                            "'Product Comparison=table'. "
                            f"Types: {', '.join(DIAGRAM_FNS)}. "
                            "Repeat for multiple slides."
                        ))
    args = parser.parse_args()

    pres_id = args.presentation_id

    if not args.target:
        parser.error("Provide at least one --target TITLE=TYPE")

    targets = {}
    for t in args.target:
        if "=" not in t:
            parser.error(f"--target must be TITLE=TYPE, got: {t!r}")
        title, dtype = t.split("=", 1)
        if dtype not in DIAGRAM_FNS:
            parser.error(f"Unknown diagram type {dtype!r}. Choose from: {', '.join(DIAGRAM_FNS)}")
        targets[title.strip()] = DIAGRAM_FNS[dtype]

    print("Fetching presentation...", file=sys.stderr)
    pres = run_gws(["slides", "presentations", "get"],
                   params={"presentationId": pres_id})

    slides  = get_slide_info(pres)
    old_ids = find_existing_diagram_ids(pres)
    print(f"Found {len(slides)} slides, {len(old_ids)} old diagram shapes to remove",
          file=sys.stderr)

    if old_ids:
        print("Removing old shapes...", file=sys.stderr)
        run_gws(
            ["slides", "presentations", "batchUpdate"],
            params={"presentationId": pres_id},
            body={"requests": [{"deleteObject": {"objectId": oid}} for oid in old_ids]}
        )
        pres   = run_gws(["slides", "presentations", "get"],
                         params={"presentationId": pres_id})
        slides = get_slide_info(pres)

    all_reqs = []
    for title, (fn, prefix) in targets.items():
        if title in slides:
            info = slides[title]
            unique_prefix = f"{prefix}_{info['slide_id'][:8]}"
            all_reqs += fn(info["slide_id"], info.get("body_id"), unique_prefix)
            print(f"  + {title}", file=sys.stderr)
        else:
            print(f"  - NOT FOUND: {title}", file=sys.stderr)

    if not all_reqs:
        print("Nothing to apply.", file=sys.stderr)
        return

    print(f"\nApplying {len(all_reqs)} operations...", file=sys.stderr)
    run_gws(
        ["slides", "presentations", "batchUpdate"],
        params={"presentationId": pres_id},
        body={"requests": all_reqs}
    )
    print("Done!", file=sys.stderr)


if __name__ == "__main__":
    main()
