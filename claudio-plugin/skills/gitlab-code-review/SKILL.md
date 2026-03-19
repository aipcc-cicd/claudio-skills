---
name: gitlab-code-review
description: Code review a GitLab merge request using multiple specialized agents with confidence-based scoring to filter false positives. Use when the user asks to review an MR, do a code review, or check changes in a merge request.
allowed-tools: Bash(glab mr view:*),Bash(glab mr diff:*),Bash(glab mr note:*),Bash(glab mr list:*),Bash(glab api:*),Bash(git remote:*),Bash(git branch:*),Bash(git log:*),Bash(git blame:*),Bash(git diff:*),Bash(git rev-parse:*)
---

# GitLab Code Review

Automated code review for GitLab merge requests using multiple specialized agents with confidence-based scoring to filter false positives.

**Agent assumptions (applies to all agents and subagents):**
- All tools are functional and will work without error. Do not test tools or make exploratory calls. Make sure this is clear to every subagent that is launched.
- All agents must be given the allowed-tools listed at the top.

To do this, follow these steps precisely:

1. Verify auth. Do NOT use a subagent — run this directly yourself:
   - Run `glab auth status`. If it fails, tell the user to authenticate (`glab auth login`) and stop.

2. Launch a fast, lightweight subagent to check if any of the following are true:
   - The merge request is closed or merged
   - The merge request is a draft
   - The merge request does not need code review (e.g. automated MR, trivial change that is obviously correct)
   - Claude has already commented on this MR (check `glab mr view <MR_IID> -R <owner/repo> --comments` for comments left by claude)

   If any condition is true, stop and do not proceed.

Note: Still review Claude-generated MRs.

3. Launch a fast, lightweight subagent to return a list of file paths (not their contents) for all relevant CLAUDE.md files including:
   - The root CLAUDE.md file, if it exists
   - Any CLAUDE.md files in directories containing files modified by the merge request

4. Launch a subagent to view the merge request and return a summary of the changes. Use:
   - `glab mr view <MR_IID> -R <owner/repo> -F json` for metadata
   - `glab mr diff <MR_IID> -R <owner/repo> --color=never --raw` for the diff

5. Launch 4 agents in parallel to independently review the changes. Each agent should return the list of issues, where each issue includes a description and the reason it was flagged (e.g. "CLAUDE.md adherence", "bug"). The agents should do the following:

   Agents 1 + 2: CLAUDE.md compliance agents
   Audit changes for CLAUDE.md compliance in parallel. Note: When evaluating CLAUDE.md compliance for a file, you should only consider CLAUDE.md files that share a file path with the file or parents.

   Agent 3: Bug detection agent
   Scan for obvious bugs in the changed code. Focus exclusively on changes (not pre-existing issues). Look for:
   - Null pointer dereferences or unchecked returns
   - Off-by-one errors
   - Race conditions or concurrency issues
   - Resource leaks
   - Security vulnerabilities (injection, XSS, hardcoded secrets)
   - Incorrect error handling
   - API misuse or wrong return types
   - Performance issues (N+1 queries, unnecessary allocations, missing indexes)

   Agent 4: Historical context agent
   Analyze git blame and history for context-based issues. Check:
   - Whether changes break patterns established in the codebase
   - Whether removed code was intentionally placed
   - Whether changes conflict with recent modifications

   Important guidance for ALL review agents:
   - Only flag issues in changed code, not pre-existing issues
   - For each issue assign a confidence score from 0-100
   - Be specific: cite file paths and line numbers
   - Consider the author's intent from the MR title and description
   - If you are not certain an issue is real, do not flag it. False positives erode trust and waste reviewer time.

   In addition to the above, each subagent should be told the MR title and description. This will help provide context regarding the author's intent.

6. For each issue found in the previous step by agents 3 and 4, launch parallel subagents to validate the issue. These subagents should get the MR title and description along with a description of the issue. The agent's job is to review the issue to validate that the stated issue is truly an issue with high confidence. For example, if an issue such as "variable is not defined" was flagged, the subagent's job would be to validate that is actually true in the code. Another example would be CLAUDE.md issues. The agent should validate that the CLAUDE.md rule that was violated is scoped for this file and is actually violated.

7. Filter out any issues that were not validated in step 6. Filter out any issues with a score less than 80. This step will give us our list of high signal issues for our review.

8. Output a summary of the review findings to the terminal:
   - If issues were found, list each issue with a brief description.
   - If no issues were found, state: "No issues found. Checked for bugs and CLAUDE.md compliance."

   If `--comment` argument was NOT provided, stop here. Do not post any comments.

   If `--comment` argument IS provided and NO issues were found, post a summary comment using `glab mr note <MR_IID> -R <owner/repo> -m "<body>"` and stop.

   If `--comment` argument IS provided and issues were found, continue to step 9.

9. Create a list of all comments that you plan on leaving. This is only for you to make sure you are comfortable with the comments. Do not post this list anywhere.

10. Post inline comments for each issue. For each comment:
    - Provide a brief description of the issue
    - For small, self-contained fixes, include a committable suggestion block
    - For larger fixes (6+ lines, structural changes, or changes spanning multiple locations), describe the issue and suggested fix without a suggestion block
    - Never post a committable suggestion UNLESS committing the suggestion fixes the issue entirely. If follow up steps are required, do not leave a committable suggestion.

    **How to post inline comments:**

    First fetch the MR diff refs:
    ```bash
    glab api projects/<url-encoded-fullpath>/merge_requests/<MR_IID> | jq '{base_sha: .diff_refs.base_sha, start_sha: .diff_refs.start_sha, head_sha: .diff_refs.head_sha}'
    ```

    Then post each inline comment:
    ```bash
    glab api projects/<url-encoded-fullpath>/merge_requests/<MR_IID>/discussions -X POST \
      -f body="<comment>" \
      -f "position[position_type]=text" \
      -f "position[base_sha]=<base_sha>" \
      -f "position[start_sha]=<start_sha>" \
      -f "position[head_sha]=<head_sha>" \
      -f "position[new_path]=<file_path>" \
      -f "position[new_line]=<line_number>"
    ```

    **IMPORTANT: Only post ONE comment per unique issue. Do not post duplicate comments.**

Use this list when evaluating issues in Steps 5 and 6 (these are false positives, do NOT flag):

- Pre-existing issues
- Something that appears to be a bug but is actually correct
- Purely cosmetic or style issues (formatting, naming preferences)
- Missing documentation unless it's a public API change
- Suggestions that are merely alternative approaches, not improvements
- Issues that are clearly intentional design decisions

Notes:

- Use `glab` CLI to interact with GitLab. Do not use web fetch.
- Create a todo list before starting.
- You must cite and link each issue in inline comments (e.g., if referring to a CLAUDE.md, include a link to it).
- If no issues are found and `--comment` argument is provided, post a comment with the following format:

```
## Code Review

No issues found. Checked for bugs and CLAUDE.md compliance.
```

---

- When linking to code in inline comments, use the GitLab link format precisely, otherwise the Markdown preview won't render correctly.
  Example: `https://gitlab.com/owner/repo/-/blob/c21d3c10bc8e898b7ac1a2d745bdc9bc4e423afe/path/file.ext#L10-15`
  - Requires full git sha (not abbreviated)
  - You must provide the full sha. Commands like `$(git rev-parse HEAD)` will not work, since your comment will be directly rendered in Markdown.
  - Use `/-/blob/` in the path
  - Line range format is `L<start>-<end>` (no second `L`)
  - Provide at least 1 line of context before and after, centered on the line you are commenting about (eg. if you are commenting about lines 5-6, you should link to `L4-7`)
- Determine the GitLab host from `git remote get-url origin`. Parse the host from the URL (HTTPS: `https://host/owner/repo.git`, SSH: `git@host:owner/repo.git`). Use this host for all links.
