"""
Seed AI Search index with demo documents and per-group ACLs.

Creates an index with permissionFilterOption=ENABLED and pushes documents
with Entra group-based access control. Uses the preview API (2025-11-01-preview).

Usage:
    python scripts/seed_search_index.py

Requires:
    AZURE_SEARCH_ENDPOINT=https://<search-service>.search.windows.net
    AZURE_SEARCH_INDEX=secure-docs  (optional, defaults to 'secure-docs')
    CONTOSO_GROUP_RESTRICTED_DOCS_ID=<Entra group object ID for restricted docs>
"""

import os
import sys

from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    PermissionFilter,
    SearchField,
    SearchIndex,
    SearchIndexPermissionFilterOption,
)
from dotenv import load_dotenv

load_dotenv()

ENDPOINT = os.environ["AZURE_SEARCH_ENDPOINT"]
INDEX_NAME = os.getenv("AZURE_SEARCH_INDEX", "secure-docs")
CREDENTIAL = DefaultAzureCredential()

# Entra group ID (not individual user OID — best practice)
RESTRICTED_DOCS_GROUP_ID = os.environ.get("CONTOSO_GROUP_RESTRICTED_DOCS_ID", "")

if not RESTRICTED_DOCS_GROUP_ID:
    print("Set CONTOSO_GROUP_RESTRICTED_DOCS_ID environment variable.")
    print("Create one Entra security group, add the test users, and use its Object ID.")
    sys.exit(1)

DOCUMENTS = [
    # ── Restricted documents (all tagged to the Contoso-RestrictedDocs Entra group in this simplified POC) ──
    {
        "id": "pm-budget-q3",
        "group_ids": [RESTRICTED_DOCS_GROUP_ID],
        "title": "Q3 2026 Event Budget Tracker",
        "content": (
            "Project Alpha — Annual Sales Kickoff (Paris, Sept 15-17)\n"
            "Venue: Marriott Champs-Élysées — €45,000\n"
            "Catering (150 pax, premium + wine): €22,500\n"
            "AV & stage setup: €18,000\n"
            "Speaker fees: €12,000\n"
            "Travel & accommodation (exec team): €35,000\n"
            "Contingency (10%): €13,250\n"
            "Total approved budget: €145,750\n"
            "Status: 68% committed, 32% remaining."
        ),
    },
    {
        "id": "pm-vendor-contracts",
        "group_ids": [RESTRICTED_DOCS_GROUP_ID],
        "title": "Vendor Contracts & SLAs — Active",
        "content": (
            "1. Marriott Champs-Élysées — Contract signed 2026-03-01, cancellation penalty 50% if <30 days.\n"
            "2. Traiteur Lenôtre — Catering SLA: 48h menu confirmation, allergies managed, €150/head premium tier.\n"
            "3. Europalco AV — Equipment rental + 2 technicians on-site, SLA: 4h replacement guarantee.\n"
            "4. SecuriEvent — 4 security agents, badge scanning, emergency protocol included.\n"
            "All contracts expire 2026-12-31. Renewal negotiation starts November."
        ),
    },
    {
        "id": "pm-risk-register",
        "group_ids": [RESTRICTED_DOCS_GROUP_ID],
        "title": "Risk Register — Project Alpha",
        "content": (
            "R1 — Venue unavailability (Impact: High, Likelihood: Low): Backup venue identified at Pullman Tour Eiffel.\n"
            "R2 — Speaker cancellation (Impact: Medium, Likelihood: Medium): 2 backup speakers on standby.\n"
            "R3 — Budget overrun >15% (Impact: High, Likelihood: Medium): Contingency fund at 10%, escalation to CFO if exceeded.\n"
            "R4 — Catering allergy incident (Impact: Critical, Likelihood: Low): Lenôtre allergy protocol validated, medical team on-site.\n"
            "Last reviewed: 2026-03-28. Next review: 2026-04-15."
        ),
    },
    {
        "id": "mktg-campaign-plan",
        "group_ids": [RESTRICTED_DOCS_GROUP_ID],
        "title": "Marketing Campaign Plan — Sales Kickoff 2026",
        "content": (
            "Objective: Generate internal buzz + 3 external press mentions.\n"
            "Timeline: Tease phase (Aug 15-31), Launch phase (Sept 1-14), Event phase (Sept 15-17), Post-event (Sept 18-30).\n"
            "Channels: LinkedIn (company page + exec profiles), internal Viva Engage, press release via PR agency.\n"
            "Content: 4 LinkedIn posts, 1 video teaser (30s), 1 blog article, 1 press release.\n"
            "KPIs: 50k LinkedIn impressions, 500 internal engagements, 3 press pickups.\n"
            "Budget: €8,500 (content creation €3,000 + LinkedIn ads €4,000 + PR agency €1,500)."
        ),
    },
    {
        "id": "mktg-brand-guidelines",
        "group_ids": [RESTRICTED_DOCS_GROUP_ID],
        "title": "Brand Guidelines — Event Communications",
        "content": (
            "Logo: Use Contoso primary logo (blue) on white backgrounds. Minimum size: 24px height.\n"
            "Colors: Primary #0078D4, Secondary #50E6FF, Accent #FFB900. No gradients on print.\n"
            "Typography: Segoe UI for digital, Segoe UI Semibold for headlines. Minimum body size: 14px.\n"
            "Photography: Use authentic employee photos, no stock images. Diverse representation required.\n"
            "Tone of voice: Professional but approachable. Active voice. Short sentences.\n"
            "Approval process: All external communications must be reviewed by Brand team (48h SLA)."
        ),
    },
    {
        "id": "mktg-social-content",
        "group_ids": [RESTRICTED_DOCS_GROUP_ID],
        "title": "Social Media Content Calendar — September 2026",
        "content": (
            "Sept 1 — LinkedIn: 'Save the date' post with event visual. Target: 10k impressions.\n"
            "Sept 5 — LinkedIn: Speaker spotlight (Dr. Sarah Chen interview clip). Target: 15k impressions.\n"
            "Sept 10 — Viva Engage: Internal countdown + registration reminder.\n"
            "Sept 15 — LinkedIn: Live event coverage thread (3-4 posts during the day).\n"
            "Sept 16 — LinkedIn: Day 2 highlights + attendee testimonials.\n"
            "Sept 17 — LinkedIn: Closing keynote recap + thank you post.\n"
            "Sept 22 — Blog: Full event recap with photos and key takeaways.\n"
            "Sept 25 — LinkedIn: Post-event metrics infographic."
        ),
    },
    {
        "id": "shared-event-brief",
        "group_ids": ["all"],
        "title": "Event Brief — Annual Sales Kickoff 2026",
        "content": (
            "Event: Annual Sales Kickoff 2026\n"
            "Date: September 15-17, 2026\n"
            "Location: Paris, France\n"
            "Attendees: 150 (sales team + executives)\n"
            "Objective: Align on H2 targets, celebrate H1 wins, team building.\n"
            "Format: Day 1 — Keynotes + strategy sessions. Day 2 — Workshops + partner demos. Day 3 — Team building + gala dinner.\n"
            "Key stakeholders: VP Sales (sponsor), PM (Adele Vance), Marketing (Alex Wilber), Finance (CFO approval)."
        ),
    },

    {
        "id": "shared-catering-policy",
        "group_ids": ["all"],
        "title": "Corporate Catering Policy 2026",
        "content": (
            "All corporate events must use approved vendors from the Contoso preferred vendor list.\n"
            "Dietary requirements: Vegetarian, vegan, halal, and gluten-free options mandatory for events >50 people.\n"
            "Budget caps: Standard events €50/person, executive events €80/person, gala dinners €120/person.\n"
            "Alcohol policy: Wine and beer only at daytime events. Spirits allowed at evening galas with prior approval.\n"
            "Sustainability: Single-use plastics prohibited. Local sourcing preferred. Food waste must be <15%."
        ),
    },
]


def create_index():
    index_client = SearchIndexClient(endpoint=ENDPOINT, credential=CREDENTIAL)

    index = SearchIndex(
        name=INDEX_NAME,
        fields=[
            SearchField(name="id", type="Edm.String", key=True,
                        filterable=True, sortable=True),
            SearchField(
                name="group_ids",
                type="Collection(Edm.String)",
                filterable=True,
                permission_filter=PermissionFilter.GROUP_IDS,
            ),
            SearchField(name="title", type="Edm.String", searchable=True),
            SearchField(name="content", type="Edm.String", searchable=True),
        ],
        permission_filter_option=SearchIndexPermissionFilterOption.ENABLED,
    )

    index_client.create_or_update_index(index)
    print(
        f"✅ Index '{INDEX_NAME}' created with permissionFilterOption=ENABLED")


def upload_documents():
    search_client = SearchClient(
        endpoint=ENDPOINT, index_name=INDEX_NAME, credential=CREDENTIAL)
    result = search_client.upload_documents(documents=DOCUMENTS)
    succeeded = sum(1 for r in result if r.succeeded)
    print(f"✅ Uploaded {succeeded}/{len(DOCUMENTS)} documents")

    print("\nDocument ACLs:")
    for doc in DOCUMENTS:
        group_display = doc["group_ids"][0] if len(
            doc["group_ids"]) == 1 else str(doc["group_ids"])
        if group_display == RESTRICTED_DOCS_GROUP_ID:
            group_display = f"Restricted Docs Group ({RESTRICTED_DOCS_GROUP_ID})"
        print(f"  {doc['title']} -> {group_display}")


if __name__ == "__main__":
    print(f"🔧 Seeding AI Search index '{INDEX_NAME}' at {ENDPOINT}\n")
    try:
        create_index()
        upload_documents()
        print("\n🎉 Done! Test with different user tokens to see per-user results.")
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)
