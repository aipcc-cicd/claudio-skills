#!/usr/bin/env python3
"""
Generate Konflux Production Release YAML from Stage Release

Takes a successful stage release and generates production release YAML with
release notes. Extracts all necessary information from the stage release
object and applies release notes template with version/variant substitution.

Usage:
    generate_release_yaml.py --stage-release base-images-4gd9f-25f6273-946fr \\
                             --version 3.2.0 \\
                             --namespace ai-tenant \\
                             --release-notes-template .konflux/release_notes.yaml \\
                             --output release.yaml

Arguments:
    --stage-release NAME            Stage release name (required)
    --version VERSION               Semantic version (e.g., 3.2.0) (required)
    --namespace NAME                Kubernetes namespace (required)
    --release-notes-template FILE   Path to release notes YAML template (default: .konflux/release_notes.yaml)
    --grace-period DAYS             Grace period in days (default: 365 for prod)
    --output FILE                   Output file (default: stdout)
"""

import argparse
import json
import subprocess
import sys
import yaml
from pathlib import Path


def run_kubectl(args_list):
    """Run kubectl command and return output."""
    try:
        result = subprocess.run(
            ['kubectl'] + args_list,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error running kubectl: {e.stderr}", file=sys.stderr)
        sys.exit(1)


def get_stage_release(release_name, namespace=None):
    """
    Fetch stage release object from Kubernetes.

    Args:
        release_name: Name of the stage release
        namespace: Namespace (optional, will search if not provided)

    Returns:
        dict: Release object
    """
    cmd = ['get', 'release', release_name, '-o', 'json']
    if namespace:
        cmd.extend(['-n', namespace])

    output = run_kubectl(cmd)
    return json.loads(output)


def derive_variant_from_component(component_name):
    """
    Derive variant from component name.

    Examples:
        base-image-rocm-7-0 → ROCm
        base-image-cuda-12-9 → CUDA
        base-image-cpu → CPU
        base-image-gaudi → Gaudi
        base-image-tpu → TPU
        base-image-spyre → Spyre

    Args:
        component_name: Component name

    Returns:
        Variant string or "Unknown"
    """
    component_lower = component_name.lower()

    # Map of patterns to variants
    variant_map = {
        'rocm': 'ROCm',
        'cuda': 'CUDA',
        'cpu': 'CPU',
        'gaudi': 'Gaudi',
        'tpu': 'TPU',
        'spyre': 'Spyre',
    }

    for pattern, variant in variant_map.items():
        if pattern in component_lower:
            return variant

    return "Unknown"


def derive_prod_release_plan(stage_plan):
    """
    Derive production release plan from stage release plan.

    Examples:
        base-images-stage → base-images-prod
        base-images-stage-3-0 → base-images-prod-3-0

    Args:
        stage_plan: Stage release plan name

    Returns:
        Production release plan name
    """
    return stage_plan.replace('-stage', '-prod')


def load_release_notes_template(template_path):
    """
    Load release notes template from YAML file.

    Returns None if template file doesn't exist (optional template).
    Exits on YAML parsing errors.
    """
    try:
        with open(template_path) as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        # Template is optional - return None
        return None
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML in template: {e}", file=sys.stderr)
        sys.exit(1)


def apply_template_substitutions(template, version, variant):
    """
    Apply version and variant substitutions to template.

    Replaces {version} and {variant} placeholders in all string values.

    Args:
        template: Dict/list/str with template placeholders
        version: Version string to substitute
        variant: Variant string to substitute

    Returns:
        Template with substitutions applied
    """
    def substitute(value):
        if isinstance(value, str):
            return value.format(version=version, variant=variant)
        elif isinstance(value, list):
            return [substitute(item) for item in value]
        elif isinstance(value, dict):
            return {k: substitute(v) for k, v in value.items()}
        return value

    return substitute(template)


def generate_release_name(component, version):
    """
    Generate production release name.

    Pattern: <component>-<version-dashes>-prod-1

    Args:
        component: Component name
        version: Version string (e.g., "3.2.0")

    Returns:
        Release name
    """
    version_dashes = version.replace('.', '-')
    return f"{component}-{version_dashes}-prod-1"


def generate_prod_release_yaml(stage_release, version, release_notes_template, grace_period):
    """
    Generate production release YAML from stage release.

    Args:
        stage_release: Stage release object dict
        version: Semantic version string
        release_notes_template: Release notes template dict (or None if no template)
        grace_period: Grace period in days

    Returns:
        dict: Production release YAML
    """
    # Extract from stage release
    metadata = stage_release['metadata']
    spec = stage_release['spec']
    labels = metadata.get('labels', {})

    component = labels.get('appstudio.openshift.io/component')
    if not component:
        print("Error: Component label not found in stage release", file=sys.stderr)
        sys.exit(1)

    snapshot = spec.get('snapshot')
    if not snapshot:
        print("Error: Snapshot not found in stage release spec", file=sys.stderr)
        sys.exit(1)

    namespace = metadata.get('namespace')
    stage_plan = spec.get('releasePlan')

    # Derive values
    variant = derive_variant_from_component(component)
    prod_plan = derive_prod_release_plan(stage_plan)
    release_name = generate_release_name(component, version)

    # Build production release YAML
    prod_release = {
        'apiVersion': 'appstudio.redhat.com/v1alpha1',
        'kind': 'Release',
        'metadata': {
            'namespace': namespace,
            'name': release_name
        },
        'spec': {
            'snapshot': snapshot,
            'releasePlan': prod_plan,
            'gracePeriodDays': grace_period
        }
    }

    # Add release notes if template provided
    if release_notes_template:
        release_notes = apply_template_substitutions(
            release_notes_template,
            version,
            variant
        )
        prod_release['spec']['data'] = {
            'releaseNotes': release_notes
        }

    return prod_release


def main():
    parser = argparse.ArgumentParser(
        description='Generate Konflux Production Release YAML from Stage Release',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument('--stage-release', type=str, required=True,
                       help='Stage release name')
    parser.add_argument('--version', type=str, required=True,
                       help='Semantic version (e.g., 3.2.0)')
    parser.add_argument('--namespace', type=str, required=True,
                       help='Kubernetes namespace')
    parser.add_argument('--release-notes-template', type=str,
                       default='.konflux/release_notes.yaml',
                       help='Path to release notes YAML template (default: .konflux/release_notes.yaml)')
    parser.add_argument('--grace-period', type=int, default=365,
                       help='Grace period in days (default: 365)')
    parser.add_argument('--output', type=str,
                       help='Output file (default: stdout)')

    args = parser.parse_args()

    # Fetch stage release
    stage_release = get_stage_release(args.stage_release, args.namespace)

    # Load release notes template (optional)
    release_notes_template = load_release_notes_template(args.release_notes_template)
    if release_notes_template is None:
        print(f"Warning: Release notes template not found at {args.release_notes_template}", file=sys.stderr)
        print(f"         Generating release without releaseNotes section", file=sys.stderr)

    # Generate production release YAML
    prod_release = generate_prod_release_yaml(
        stage_release,
        args.version,
        release_notes_template,
        args.grace_period
    )

    # Convert to YAML string
    yaml_str = yaml.dump(prod_release, default_flow_style=False, sort_keys=False)

    # Output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(yaml_str)
        print(f"Generated: {args.output}", file=sys.stderr)
        print(f"  Component: {prod_release['spec']['releasePlan']}", file=sys.stderr)
        print(f"  Snapshot: {prod_release['spec']['snapshot']}", file=sys.stderr)
        print(f"  Release: {prod_release['metadata']['name']}", file=sys.stderr)
    else:
        print(yaml_str)


if __name__ == '__main__':
    main()
