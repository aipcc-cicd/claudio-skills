"""Slack Utilities Scripts

Generic Slack utilities for fetching messages, thread replies, posting messages,
and timestamp conversion. These scripts are product-agnostic and can be used
by any Slack-based workflow.

Exit Code Conventions:
    0: Success
    1: Invalid parameters
    2: API error
    3: Parsing error
    4: Authentication error
"""

__version__ = "1.0.0"
