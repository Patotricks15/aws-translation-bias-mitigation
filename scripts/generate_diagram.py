"""Generates docs/architecture.drawio for the Bias Mitigation in Translation project using drawpyo.

Run with: python3 scripts/generate_diagram.py
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_group(page, name, x, y, width, height):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF2CC;strokeColor=#D6B656;"
        "fontSize=10;fontColor=#7F6000;align=center;verticalAlign=top;"
    )
    return group


def add_edge(page, source, target, label=None, bidirectional=False):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "block" if bidirectional else "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Bias Mitigation in Translation"

    # ── Live translation service path ────────────────────────────────────
    user = add_node(page, "Users", 20, 220, "client", "#232F3E")
    cdn = add_node(page, "CDN for\nweb app", 180, 220, "cloudfront", "#8C4FFF")
    static_site = add_node(page, "Static\nwebsite", 180, 360, "bucket", "#7AA116")
    translation_service = add_node(page, "Translation\nservice", 340, 220, "client", "#232F3E")
    rest_api = add_node(page, "REST API", 500, 220, "api_gateway", "#E7157B")
    update_endpoint = add_node(page, "Update\nendpoint", 660, 220, "lambda_function", "#ED7100")
    model_endpoint = add_node(
        page, "Fine-tuned model\nendpoint (unbiased)", 820, 220, "machine_learning", "#01A88D"
    )

    add_edge(page, user, cdn, "Access web app")
    add_edge(page, cdn, static_site, "Serves")
    add_edge(page, user, translation_service, "Translation request", bidirectional=True)
    add_edge(page, translation_service, rest_api, "Translation request / Response", bidirectional=True)
    add_edge(page, rest_api, update_endpoint, "Invoke", bidirectional=True)
    add_edge(page, update_endpoint, model_endpoint, "Invoke endpoint / Translation", bidirectional=True)

    # ── Bias-mitigation training workflow ───────────────────────────────
    training_group = add_group(page, "Bias-mitigation training workflow", 340, 420, 580, 240)
    notebook = add_node(page, "Jupyter notebook\nTranslation\n(gender bias)", 380, 480, "machine_learning", "#01A88D")
    model_artifacts = add_node(page, "Model\nartifacts", 580, 480, "bucket", "#7AA116")

    add_edge(page, notebook, model_artifacts, "Train / upload artifacts")
    add_edge(page, model_artifacts, model_endpoint, "Deploy fine-tuned,\nunbiased model")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
