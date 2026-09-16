# 🛠️ Design Document: Agentic Document Synchronization Engine (ADSE)

**Framework:** Guardian-Driven Development (GDD)

**Status:** Draft / Implementation Spec

**Data Class:** Private / Internal Engineering

---

## 1. Executive Summary & Objective

The **Agentic Document Synchronization Engine (ADSE)** is a decentralized, local-first documentation pipeline. It bridges a local plain-text Markdown environment (the single source of truth) with disparate enterprise collaboration platforms (Google Docs, Atlassian Confluence, Jira Project Discovery) and open-source infrastructure (Forgejo, Git).

Instead of relying on fragile, real-time, multi-cursor synchronization engines that face corporate firewall restrictions and mangle formatting, ADSE utilizes **Asynchronous Phase-Based Synchronization**. The system leverages read-only Model Context Protocol (MCP) servers for data extraction and structured outbound REST APIs or orchestration platforms (e.g., n8n) for document publishing.

### Key Goals:

* **Single Source of Truth:** All content originates as standard Markdown inside a local repository.
* **Zero Inbound Firewall Requirements:** All operations run via outbound HTTPS API requests or read-only MCP queries.
* **Compliance Friendly:** Documents are fully rendered natively inside corporate tools, ensuring indexing by enterprise search tools (e.g., Glean).
* **Dual Architecture:** Seamless fallback between restricted corporate mode (Macro API Writes) and open-source/hobby mode (Git hooks / local tunnels).

---

## 2. System Architecture & Context

The architecture decouples the storage layer, the execution layer (AI Agent), and the remote viewports.

```
       ┌────────────────────────────────────────────────────────┐
       │                   LOCAL WORKSPACE (GDD)                │
       │                                                        │
       │   ┌──────────────────┐        ┌──────────────────┐     │
       │   │  Local Markdown  │───────►│   Agent Skills   │     │
       │   │   Vault Files    │◄───────│  (Python / Node) │     │
       │   └────────┬─────────┘        └────────┬─────────┘     │
       └────────────┼───────────────────────────┼───────────────┘
                    │                           │
                    │ (n8n Webhook / API Put)   │ (Read-only MCP)
                    ▼                           ▼
       ┌────────────────────────────────────────────────────────┐
       │                 REMOTE VIEWPORTS (HUB)                 │
       │                                                        │
       │  ┌──────────────────┐          ┌──────────────────┐    │
       │  │   Google Docs    │          │    Confluence    │    │
       │  └──────────────────┘          └──────────────────┘    │
       └────────────────────────────────────────────────────────┘

```

---

## 3. Metadata & Configuration Schema

To allow the agent to understand *where* and *how* to publish documents dynamically, the engine utilizes two specific configuration file structures: **Realm Configuration Files** and **Component Metadata Frontmatter**.

### 3.1 Realm Configuration (`.gdd/realm.json`)

The Realm file defines the environmental profiles (e.g., `corporate`, `oss`, `homelab`). It informs the agent which infrastructure endpoints, credentials, and writing strategies are currently active.

```json
{
  "active_realm": "corporate",
  "realms": {
    "corporate": {
      "write_strategy": "macro_overwrite",
      "mcp_profile": "read_only_secure",
      "endpoints": {
        "gdoc_provider": "n8n_webhook",
        "gdoc_trigger_url": "https://n8n.internal.corp/webhook/v1/gdoc-sync",
        "confluence_api": "https://wiki.internal.corp/rest/api/v2"
      }
    },
    "oss": {
      "write_strategy": "git_native",
      "mcp_profile": "none",
      "endpoints": {
        "git_remote": "https://forgejo.open-source.org/workspace/docs.git"
      }
    }
  }
}

```

### 3.2 Component Metadata (Obsidian Frontmatter)

Every documentation asset includes YAML frontmatter detailing its unique execution hooks, compiling sequence order, and target platform identifiers.

```yaml
---
gdd_type: "architecture_spec"
component_id: "core-auth-pipeline"
publish_targets:
  corporate:
    gdoc_id: "1A2B3C4D5E6F7G8H9I0J"
    gdoc_stitch_order: 1
    confluence_page_id: "87654321"
    confluence_space: "ARCH"
  oss:
    path: "docs/architecture/01-auth.md"
tags: [security, architecture, core]
---

```

---

## 4. Execution Pipelines & Workflow Phases

### Phase 1: Macro-Publishing (Push)

When a document section reaches a review gate, the user or agent activates the compilation pass.

1. The Agent parses the target Markdown file and scans the YAML frontmatter.
2. It resolves the current execution realm via `.gdd/realm.json`.
3. **For Google Docs (Corporate):** The agent packages the raw markdown string and the `gdoc_id` into a JSON payload and hits the local wrapper script for n8n. n8n clears the target Google Doc and overwrites it with cleanly parsed typography.
4. **For Confluence (Corporate):** The agent executes a script translating Markdown to XHTML storage markup and updates the page via a targeted `PUT` block request.

### Phase 2: Peer Review & Feedback (Remote)

Corporate users edit, write comments, inline fix, or review content inside the Google Doc or Confluence space. This content is natively exposed to corporate indexers (Glean).

### Phase 3: Extraction & Semantic True-Up (Pull)

When the review phase is complete, the local workspace pulls down changes.

1. The Agent calls the read-only MCP server:
* `google_docs.read_document({"fileId": "1A2B3C4D..."})`
* `confluence.get_page_content({"pageId": "87654321"})`


2. The MCP server returns the data formatted or plain.
3. The Agent performs a **Semantic Diff Pass**: Rather than line-by-line file overwriting, the LLM parses human textual adjustments, strips out editor engine structural metadata, and precisely updates sentences, tables, or lists in the local workspace file without disrupting local frontmatter properties.

---

## 5. Core Operational Scripts & Agent Skills

Below are the base integration engines to be dropped into the workspace directory.

### 5.1 GDoc Macro-Writer Wrapper (`bin/push_gdoc.sh`)

This lightweight runner routes around local proxy constraints by tossing the payload to an internal webhook orchestrator (n8n).

```bash
#!/usr/bin/env bash
# Usage: ./push_gdoc.sh <file_path>

set -euo pipefail

FILE_PATH=$1

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ Error: File $FILE_PATH not found."
    exit 1
fi

# Extract Metadata and Content
GDOC_ID=$(sed -n 's/^  gdoc_id: "\(.*\)"/\1/p' "$FILE_PATH" | tr -d '\r ')
WEBHOOK_URL=$(jq -r '.realms[.active_realm].endpoints.gdoc_trigger_url' .gdd/realm.json)

if [ -z "$GDOC_ID" ] || [ -z "$WEBHOOK_URL" ]; then
    echo "❌ Error: Missing gdoc_id or webhook URL profile endpoint target."
    exit 1
fi

echo "📤 Preparing payload for GDoc ID: $GDOC_ID..."

# Extract the body text excluding frontmatter boundaries
MARKDOWN_BODY=$(sed '1,/^---$/d' "$FILE_PATH")

# Deliver to Outbound Proxy / Orchestration Layer
curl -s -X POST "$WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d jq --null-input \
           --arg id "$GDOC_ID" \
           --arg body "$MARKDOWN_BODY" \
           '{"gdoc_id": $id, "content": $body}' \
     > /dev/null

echo "✅ Document safely exported to compilation pipeline endpoint."

```

### 5.2 Python Agent Skill Component (`skills/sync_engine.py`)

This script forms the execution module that an LLM agent uses when parsing read-only MCP data back into structural local files.

```python
#!/usr/bin/env python3
import json
import yaml
import sys
import os

def load_realm_config():
    with open(".gdd/realm.json", "r") as f:
        return json.load(f)

def parse_local_frontmatter(file_path):
    with open(file_path, "r") as f:
        content = f.read()
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            metadata = yaml.safe_load(parts[1])
            return metadata, parts[2].strip()
    return {}, content.strip()

def true_up_local_file(file_path, semantic_merged_content):
    metadata, _ = parse_local_frontmatter(file_path)
    
    # Reconstruct pristine Markdown file with structural frontmatter intact
    with open(file_path, "w") as f:
        f.write("---\n")
        yaml.safe_dump(metadata, f, default_flow_style=False)
        f.write("---\n\n")
        f.write(semantic_merged_content.strip())
        f.write("\n")
    print(f"✅ Cleanly reconciled source-of-truth file at: {file_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: sync_engine.py <target_file_path> <incoming_mcp_dump.txt>")
        sys.exit(1)
        
    target_file = sys.argv[1]
    mcp_dump = sys.argv[2]
    
    # Agent will invoke this script after executing its LLM contextual diff loop
    with open(mcp_dump, "r") as f:
        merged_text = f.read()
        
    true_up_local_file(target_file, merged_text)

```

---

## 6. Security & Guardrails

* **Credential Decoupling:** Authentication details (API Tokens, Mutual TLS client passphrases, OAuth Secrets) are strictly forbidden from appearing inside `.gdd/realm.json` or frontmatter files. They must be injected at runtime via short-lived local environmental variables or dynamic SSO tokens pulled from local vault utilities.
* **Data Integrity Check:** When pulling structural edits back from a remote session, the agent must treat headers (`#`, `##`) as structural invariant blocks. The agent skill is prohibited from modifying structural document hierarchy without an explicit confirmation override flag.
* **Explicit Disclaimers:** Every out-of-band write operation must prefix or suffix the target viewport file with automated metadata tracing the path back to the parent component repository.