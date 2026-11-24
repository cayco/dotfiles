---
name: checkmk-sre
description: Handle Checkmk AGY SRE incident handoffs from @cayco_cmk_bot / CT 107 (cmk-sre-bot), inspect saved forensic Incident Bundles (~/.gemini/antigravity/checkmk-incidents/), verify infrastructure health, and propose human-approved remediations without auto-executing destructive changes.
---

# Checkmk AGY SRE — Desktop Remediation Workflow

Use this skill whenever an incident is handed off from **Checkmk AGY SRE Bot** (`CT 107 loxone-llm`, `:8098`, `https://sre.int.cayco.pl`, `@cayco_cmk_bot`) or when investigating Checkmk alerts in Rybałtów.

## 1. Safety Contract (Mandatory Human-in-the-Loop)

1. **Zero Automatic Remediation**: Never execute service restarts, container recreations, Proxmox guest actions, or file modifications automatically upon opening a handed-off incident.
2. **Verify First (Read-Only)**:
   - Inspect the forensic bundle saved at the exact timestamp of the outage in `~/.gemini/antigravity/checkmk-incidents/<INC-ID>/`:
     - `alert.json`: Original Checkmk alert payload(s).
     - `tool_trace.jsonl`: Exact read-only commands/queries executed by `cmk-sre-bot` and their scrubbed output.
     - `diagnosis.md` & `model_meta.json`: Root-cause hypothesis and model metadata.
   - Cross-check current live status (read-only) and relevant runbooks in `/Users/krzysztofkajkowski/Downloads/Obsidian`.
3. **Present & Wait for Approval**: Present a concise root-cause verification and the exact command(s) or configuration diff to apply, then **wait for explicit user confirmation in chat**.

## 2. Post-Fix Verification & Knowledge Loop

Once the user approves and the fix is executed:
1. Trigger an immediate Checkmk re-check and confirm the service returns to `OK` (`0` regressions).
2. Respect the **Upgrade-Safe Rule** (never patch upstream `custom_components/<vendor>/` or `/usr/bin/check_mk_agent` directly).
3. If any host script, HA package, or runbook changed, automatically update `/Users/krzysztofkajkowski/Downloads/Obsidian` and sync/push `cayco/home-network-automation` (so `cmk-sre-bot`'s knowledge base on `CT 107` learns from the incident).
