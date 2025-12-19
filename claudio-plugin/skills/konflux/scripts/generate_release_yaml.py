#!/usr/bin/env python3
"""
Generate Konflux Production Release YAML

Generic script that takes all parameters and a release notes template to generate
production release YAML. No product-specific logic hardcoded.

Usage:
    generate_release_yaml.py --component cuda-ubi9 \\
                             --version 3.2.5 \\
                             --snapshot my-app-78c7f \\
                             --release-plan my-product-ubi9-prod \\
                             --release-name my-product-cuda-ubi9-3-2-5-prod-4 \\
                             --accelerator CUDA \\
                             --namespace my-namespace \\
                             --release-notes-template /tmp/ga-rhea.yaml \\
                             --release-type RHSA \\
                             --cves-file cves \\
                             --output out/my-product-cuda-ubi9-3.2.5-prod.yaml

Arguments:
    --component NAME              Component name (required)
    --version VERSION             Semantic version (e.g., 3.2.5) (required)
    --snapshot NAME               Snapshot name (required)
    --release-plan NAME           Release plan name (required)
    --release-name NAME           Production release name (required)
    --accelerator TYPE            Accelerator/variant name for substitution (required)
    --namespace NAME              Kubernetes namespace (default: my-namespace)
    --release-notes-template FILE Path to release notes YAML template (required)
    --release-type TYPE           Release type: RHEA or RHSA (default: RHEA)
    --cves-file PATH              Path to CVE list file (optional, for RHSA)
    --grace-period DAYS           Grace period in days (default: 365)
    --output FILE                 Output file (default: stdout)
"""

import argparse
import sys
import yaml


def load_cves_from_file(cve_file_path):
    """
    Load CVE list from file.

    File format:
    - One CVE per line
    - Format: CVE-YYYY-NNNNN
    - Whitespace trimmed
    - Empty lines ignored
    - Lines starting with # ignored (comments)

    Args:
        cve_file_path: Path to CVE file

    Returns:
        List of CVE IDs
    """
    cves = []
    try:
        with open(cve_file_path, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                cves.append(line)
    except FileNotFoundError:
        print(f"Error: CVE file not found: {cve_file_path}", file=sys.stderr)
        sys.exit(1)

    return cves


def load_release_notes_template(template_path):
    """
    Load release notes template from YAML file.

    Args:
        template_path: Path to template file

    Returns:
        dict: Template dictionary

    Exits on file not found or YAML parsing errors.
    """
    try:
        with open(template_path) as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: Release notes template not found: {template_path}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML in template: {e}", file=sys.stderr)
        sys.exit(1)


def apply_template_substitutions(template, version, accelerator):
    """
    Apply version and accelerator substitutions to template.

    Replaces {version} and {accelerator} placeholders in all string values.

    Args:
        template: Dict/list/str with template placeholders
        version: Version string to substitute
        accelerator: Accelerator/variant string to substitute

    Returns:
        Template with substitutions applied
    """
    def substitute(value):
        if isinstance(value, str):
            return value.format(version=version, accelerator=accelerator)
        elif isinstance(value, list):
            return [substitute(item) for item in value]
        elif isinstance(value, dict):
            return {k: substitute(v) for k, v in value.items()}
        return value

    return substitute(template)


def generate_prod_release_yaml(component_name, version, snapshot, release_plan,
                               release_name, accelerator, namespace, release_notes_template,
                               release_type, cves_file, grace_period):
    """
    Generate production release YAML.

    Args:
        component_name: Component name
        version: Version string (e.g., "3.2.5")
        snapshot: Snapshot name
        release_plan: Release plan name
        release_name: Production release name
        accelerator: Accelerator/variant type string
        namespace: Kubernetes namespace
        release_notes_template: Release notes template dict
        release_type: "RHEA" or "RHSA"
        cves_file: Path to CVE file (optional)
        grace_period: Grace period in days

    Returns:
        dict: Production release YAML structure
    """
    # Apply template substitutions
    release_notes = apply_template_substitutions(
        release_notes_template,
        version,
        accelerator
    )

    # Set the type field
    release_notes['type'] = release_type

    # Add CVEs for RHSA if file provided
    if release_type == 'RHSA' and cves_file:
        cve_ids = load_cves_from_file(cves_file)
        # Build CVE list with component name
        release_notes['cves'] = [{'key': cve_id, 'component': component_name} for cve_id in cve_ids]

    # Build production release YAML
    prod_release = {
        'apiVersion': 'appstudio.redhat.com/v1alpha1',
        'kind': 'Release',
        'metadata': {
            'name': release_name,
            'namespace': namespace
        },
        'spec': {
            'gracePeriodDays': grace_period,
            'releasePlan': release_plan,
            'snapshot': snapshot,
            'data': {
                'releaseNotes': release_notes
            }
        }
    }

    return prod_release


def main():
    parser = argparse.ArgumentParser(
        description='Generate Konflux Production Release YAML',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument('--component', type=str, required=True,
                       help='Component name')
    parser.add_argument('--version', type=str, required=True,
                       help='Semantic version (e.g., 3.2.5)')
    parser.add_argument('--snapshot', type=str, required=True,
                       help='Snapshot name')
    parser.add_argument('--release-plan', type=str, required=True,
                       help='Release plan name')
    parser.add_argument('--release-name', type=str, required=True,
                       help='Production release name')
    parser.add_argument('--accelerator', type=str, required=True,
                       help='Accelerator/variant type for template substitution')
    parser.add_argument('--namespace', type=str, default='my-namespace',
                       help='Kubernetes namespace (default: my-namespace)')
    parser.add_argument('--release-notes-template', type=str, required=True,
                       help='Path to release notes YAML template (required)')
    parser.add_argument('--release-type', type=str, default='RHEA',
                       choices=['RHEA', 'RHSA'],
                       help='Release type (default: RHEA)')
    parser.add_argument('--cves-file', type=str,
                       help='Path to CVE list file (optional, for RHSA)')
    parser.add_argument('--grace-period', type=int, default=365,
                       help='Grace period in days (default: 365)')
    parser.add_argument('--output', type=str,
                       help='Output file (default: stdout)')

    args = parser.parse_args()

    # Load release notes template
    release_notes_template = load_release_notes_template(args.release_notes_template)

    # Generate production release YAML
    prod_release = generate_prod_release_yaml(
        args.component,
        args.version,
        args.snapshot,
        args.release_plan,
        args.release_name,
        args.accelerator,
        args.namespace,
        release_notes_template,
        args.release_type,
        args.cves_file,
        args.grace_period
    )

    # Convert to YAML string
    yaml_str = yaml.dump(prod_release, default_flow_style=False, sort_keys=False)

    # Output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(yaml_str)
        print(f"Generated: {args.output}", file=sys.stderr)
        print(f"  Release: {prod_release['metadata']['name']}", file=sys.stderr)
        print(f"  Release Plan: {prod_release['spec']['releasePlan']}", file=sys.stderr)
        print(f"  Snapshot: {prod_release['spec']['snapshot']}", file=sys.stderr)
    else:
        print(yaml_str)


if __name__ == '__main__':
    main()
