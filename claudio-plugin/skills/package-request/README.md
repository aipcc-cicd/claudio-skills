# Package Request Skill

Submit package onboarding requests directly via Jira REST API and GitLab CI. Creates a Jira epic with security level "Red Hat Employee" and triggers the package-onboarding pipeline.

## Quick Start

Tell Claude to request a package:

```text
Request the torch package with cuda extras for AIPCC-12345
```

Or provide everything upfront:

```text
Submit a package request:
- Package: torch[cuda]
- Requester: rkothari@redhat.com
- Jira project: RHAISTRAT
- Team: Accelerator Enablement
- Related ticket: AIPCC-12345
- Justification: Needed for training pipeline support
- Delivery timeline: 2026-08-01
```

Claude will collect any missing fields, confirm the submission, and return the Jira ticket link.

## Fields

### Required

| Field | Description |
|---|---|
| Package name | Python package name (e.g. `torch`, `torch[cuda]`). No version specifiers. |
| Requester | Email, kerberos ID, or display name. Must exist in Jira. |
| Jira project | `RHAISTRAT` or `AIPCC` — determines available teams. |
| Team | Component from the selected Jira project. Claude fetches options from Jira. |
| Related Jira ticket | Format: `PROJECT-NUMBER` (e.g. `AIPCC-12345`). |
| Business justification | Why this package is needed (10-5000 chars). |
| Delivery timeline | Target date in ISO format (YYYY-MM-DD), at least 8 days from today. |

### Optional

| Field | Description |
|---|---|
| Extras | Comma-separated PEP 508 identifiers (e.g. `cuda,tensor`). |
| Package source | `pypi` (default), `git`, or `other`. |
| Source URL | Required when source is `git` or `other`. |
| Version | PEP 440 specifier (e.g. `>=2.0.0`, `~=1.4`). |
| Backport versions | Stable series to backport to (e.g. `3.4,3.5-EA1`). |
| Release targets | Target product versions (e.g. `RHAI 3.6,RHAIIS 3.4`). |
| Release commitment | Free text, max 2000 chars. |
| Hardware requirements | Free text, max 500 chars. |
| Testing requirements | Free text, max 2000 chars. |

## Configuration

| Variable | Required | Description |
|---|---|---|
| `JIRA_SITE` | Yes | Atlassian site hostname (e.g. `redhat.atlassian.net`) |
| `JIRA_TOKEN` | Yes | Atlassian API token |
| `JIRA_EMAIL` | Yes | Atlassian account email |
| `GITLAB_TOKEN` | No | GitLab personal access token with `api` scope (pipeline trigger is skipped without it) |
| `JIRA_PROJECT` | No | Jira project key (default: `AIPCC`) |
| `JIRA_COMPONENT` | No | Component set on created epics (default: `Accelerator Enablement`) |

## What Happens After Submission

1. Creates a Jira epic in the selected project with security level "Red Hat Employee"
2. Best-effort triggers the `package-onboarding` GitLab pipeline via `glab ci run` (skipped if `GITLAB_TOKEN` or `glab` is unavailable; trigger failures are warnings, not errors)
3. If triggered, the pipeline runs security checks, builds, and creates child stories (QE testing, RHAI pipeline onboarding)

## Troubleshooting

- **Missing env vars**: Ensure `JIRA_SITE`, `JIRA_TOKEN`, `JIRA_EMAIL`, and `GITLAB_TOKEN` are set.
- **Pipeline trigger fails**: Verify `GITLAB_TOKEN` has `api` scope (not just `read_api`).
- **TLS errors in claudio container**: Install the Red Hat CA bundle via `tools/redhat-ca/install.sh`.
- **Validation errors**: Check that the requester exists in Jira and the delivery date is at least 8 days out.
