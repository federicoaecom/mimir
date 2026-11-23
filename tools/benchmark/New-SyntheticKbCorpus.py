#!/usr/bin/env python3
"""Generate a synthetic GeneXus KB XML corpus for benchmarking the KB Intelligence build.

Contributor tool. The corpus is made from parameters and a fixed synthetic vocabulary only; it
never reads or copies real KB content. The XML shapes follow tests/fixtures/sample-kb/ and what
skills/mimir-lite/scripts/Build-KbIntelligenceIndex.py reads:

- Procedure: a Procedure Source Part and a Rules Part, with calls (Name.Call(...) and Name(...)),
  Data Provider calls, explicit "for each <Table>" blocks and attribute reads and writes.
- WebPanel: an Events Part and a Rules Part, with Procedure calls, WebPanel .Link() calls,
  for each blocks and attribute reads.
- DataProvider: a DataProvider Source Part with attribute reads and Procedure calls.
- Transaction: one Level whose Type names its Table, its own attributes (the first is the key)
  and the key of a parent Transaction (a tree, three children per parent) as a foreign key; a
  Rules Part reading its attributes.
- Table: Key Item and a duplicate Index on the foreign key.
- Attribute: root <Attribute>; about half are based on a Domain through idBasedOn.
- Domain: Properties only.

The output is deterministic for a given set of parameters and --seed. The tool writes only to
--output-dir (default: a new folder under the system temp folder), refuses a non-empty folder and
any folder inside this repository, and prints a JSON summary on stdout. The corpus is marked as
completely synchronized (.mimir-sync-state.json, state complete, a generation derived from --seed),
so the index builder accepts it.

Exit codes: 0 success, 2 invalid parameters or refused output folder.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import tempfile
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

TYPE_GUIDS = {
    "Procedure": "84a12160-f59b-4ad7-a683-ea4481ac23e9",
    "WebPanel": "c9584656-94b6-4ccd-890f-332d11fc2c25",
    "DataProvider": "2a9e9aba-d2de-4801-ae7f-5e3819222daf",
    "Transaction": "1db606f2-af09-4cf9-a3b5-b481519d28f6",
    "Table": "857ca50e-7905-0000-0007-c5d9ff2975ec",
    "Domain": "00972a17-9975-449e-aab1-d26165d51393",
}
PROCEDURE_SOURCE_PART_GUID = "528d1c06-a9c2-420d-bd35-21dca83f12ff"
RULES_PART_GUID = "9b0a32a3-de6d-4be1-a4dd-1b85d3741534"
EVENTS_PART_GUID = "c44bd5ff-f918-415b-98e6-aca44fed84fa"
DATA_PROVIDER_SOURCE_PART_GUID = "1d8aeb5a-6e98-45a7-92d2-d8de7384e432"
ZERO_GUID = "00000000-0000-0000-0000-000000000000"
TIMESTAMP = "2026-01-01T00:00:00"

# Relation kinds the generated corpus is meant to produce (checked by the self-test).
RELATION_FAMILIES = (
    "calls_procedure",
    "calls_dataprovider",
    "calls_webpanel",
    "navigates_explicit_table",
    "code_references_attribute",
    "has_level_attribute",
    "has_level_table",
    "has_key_attribute",
    "has_index_member_attribute",
    "based_on_domain",
)

VERBS = (
    "Get", "Set", "Calc", "Load", "Save", "Validate", "Check", "Update", "Delete", "Process",
    "Build", "Send", "Print", "Export", "Import", "Sync", "Compute", "Find", "List", "Close",
    "Open", "Post", "Apply", "Generate", "Notify", "Approve", "Cancel", "Merge", "Split", "Audit",
)
NOUNS = (
    "Customer", "Invoice", "Product", "Order", "Account", "Payment", "Stock", "Supplier",
    "Employee", "Contract", "Shipment", "Warehouse", "Ledger", "Budget", "Branch", "Vehicle",
    "Policy", "Claim", "Ticket", "Project", "Task", "Asset", "Receipt", "Quote", "Tariff",
    "Region", "Country", "Currency", "Bank", "Card", "Loan", "Deposit", "Batch", "Route",
    "Station", "Device", "Sensor", "Meter", "Reading", "Session",
)
QUALIFIERS = (
    "Total", "Status", "Date", "Balance", "Line", "Detail", "Header", "Summary", "Rate",
    "Limit", "Report", "Queue", "Cache", "History", "Snapshot", "Delta", "Index", "Group",
    "Rule", "Event",
)
SCREENS = ("View", "List", "Edit", "Prompt", "Dashboard", "Search", "Detail", "Selection", "Wizard", "Panel")
FIELDS = (
    "Id", "Name", "Date", "Amount", "Status", "Code", "Description", "Quantity", "Price", "Type",
    "Note", "Email", "Phone", "Address", "Rate", "Discount", "Weight", "Category", "Level", "Flag",
)
DOMAIN_KINDS = ("Id", "Name", "Amount", "Date", "Code", "Text", "Flag", "Percent", "Quantity", "Email")


class Refused(Exception):
    """An invalid parameter or a refused output folder (exit code 2)."""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a synthetic GeneXus KB XML corpus (no real KB content).")
    parser.add_argument("--output-dir", type=Path, help="New or empty folder outside this repository (default: a new temp folder).")
    parser.add_argument("--objects", type=int, default=2000, help="Total object count (default 2000).")
    parser.add_argument("--procedure-share", type=float, default=0.5, help="Share of Procedure objects, 0 to 0.9 (default 0.5).")
    parser.add_argument("--lines-per-source", type=int, default=120, help="Code lines per Procedure Source; WebPanels get half (default 120).")
    parser.add_argument("--call-density", type=float, default=0.05, help="Probability that a code line is a call (default 0.05).")
    parser.add_argument("--for-each-density", type=float, default=0.02, help="Probability that a code line opens a for each block (default 0.02).")
    parser.add_argument("--attribute-density", type=float, default=0.15, help="Probability that a code line reads or writes an attribute (default 0.15).")
    parser.add_argument("--seed", type=int, default=1, help="Random seed (default 1).")
    return parser.parse_args(argv)


def validate(args: argparse.Namespace) -> None:
    if args.objects < 30:
        raise Refused("--objects must be at least 30.")
    if not 0.0 <= args.procedure_share <= 0.9:
        raise Refused("--procedure-share must be between 0 and 0.9.")
    if args.lines_per_source < 10:
        raise Refused("--lines-per-source must be at least 10.")
    for name in ("call_density", "for_each_density", "attribute_density"):
        if not 0.0 <= getattr(args, name) <= 1.0:
            raise Refused("--{} must be between 0 and 1.".format(name.replace("_", "-")))
    if args.call_density + args.for_each_density + args.attribute_density > 1.0:
        raise Refused("the three densities must add up to 1 or less.")


def resolve_output_dir(requested: Path | None) -> Path:
    if requested is None:
        return Path(tempfile.mkdtemp(prefix="mimir-synthetic-kb-"))
    output = requested.resolve()
    try:
        output.relative_to(REPO_ROOT)
        inside_repo = True
    except ValueError:
        inside_repo = False
    if inside_repo:
        raise Refused("refused output folder inside the repository: {}".format(output))
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise Refused("refused output folder that is not empty: {}".format(output))
    output.mkdir(parents=True, exist_ok=True)
    return output


def plan_counts(total: int, procedure_share: float) -> dict[str, int]:
    procedures = round(total * procedure_share)
    rest = total - procedures
    transactions = max(1, round(rest * 0.06))
    domains = max(1, round(rest * 0.04))
    webpanels = max(1, round(rest * 0.25))
    data_providers = max(1, round(rest * 0.10))
    attributes = rest - 2 * transactions - domains - webpanels - data_providers
    if attributes < 2 * transactions:
        raise Refused("too few objects for the requested Procedure share; raise --objects or lower --procedure-share.")
    return {
        "Procedure": procedures,
        "WebPanel": webpanels,
        "DataProvider": data_providers,
        "Transaction": transactions,
        "Table": transactions,
        "Attribute": attributes,
        "Domain": domains,
    }


class NamePool:
    """Unique names (case-insensitive across every type) built from the synthetic vocabulary."""

    def __init__(self) -> None:
        self.used: set[str] = set()

    def take(self, candidates: list[str], count: int) -> list[str]:
        names: list[str] = []
        suffix = 1
        while len(names) < count:
            for base in candidates:
                name = base if suffix == 1 else "{}{}".format(base, suffix)
                if name.lower() in self.used:
                    continue
                self.used.add(name.lower())
                names.append(name)
                if len(names) == count:
                    break
            suffix += 1
        return names


def shuffled(rng: random.Random, items: list[str]) -> list[str]:
    copy = list(items)
    rng.shuffle(copy)
    return copy


def new_guid(rng: random.Random) -> str:
    return str(uuid.UUID(int=rng.getrandbits(128), version=4))


def skewed_pick(rng: random.Random, items: list[str]) -> str:
    """A few items are called much more often than the rest, as in a real KB."""
    return items[int(len(items) * (rng.random() ** 2.5))]


def object_xml(rng: random.Random, object_type: str, name: str, description: str, body: str) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<Object parentGuid="{zero}" user="SyntheticKbUser" versionDate="{ts}" lastUpdate="{ts}" checksum="0" '
        'fullyQualifiedName="{name}" moduleGuid="{zero}" guid="{guid}" name="{name}" type="{type_guid}" '
        'description="{description}" parent="{zero}" parentType="Module">\n'
        "  <Properties>\n"
        "    <Property><Name>Name</Name><Value>{name}</Value></Property>\n"
        "    <Property><Name>Description</Name><Value>{description}</Value></Property>\n"
        "    <Property><Name>ObjectVisibility</Name><Value>Public</Value></Property>\n"
        "  </Properties>\n"
        "{body}"
        "</Object>\n"
    ).format(
        zero=ZERO_GUID,
        ts=TIMESTAMP,
        name=name,
        guid=new_guid(rng),
        type_guid=TYPE_GUIDS[object_type],
        description=description,
        body=body,
    )


def code_part(part_guid: str, lines: list[str]) -> str:
    return '  <Part type="{}">\n    <Source><![CDATA[\n{}\n]]></Source>\n  </Part>\n'.format(part_guid, "\n".join(lines))


class CodeWriter:
    """Code lines for one object, drawn from the densities."""

    def __init__(self, rng: random.Random, args: argparse.Namespace, model: dict[str, object]) -> None:
        self.rng = rng
        self.args = args
        self.model = model

    def call_line(self, allow_webpanel: bool) -> str:
        rng = self.rng
        roll = rng.random()
        procedures: list[str] = self.model["procedures"]  # type: ignore[assignment]
        data_providers: list[str] = self.model["data_providers"]  # type: ignore[assignment]
        webpanels: list[str] = self.model["webpanels"]  # type: ignore[assignment]
        if allow_webpanel and webpanels and roll < 0.15:
            return "{}.Link(&Id)".format(skewed_pick(rng, webpanels))
        if data_providers and roll < 0.30:
            return "&Collection = {}(&Id)".format(skewed_pick(rng, data_providers))
        if procedures and roll < 0.65:
            return "{}.Call(&Id, &Result)".format(skewed_pick(rng, procedures))
        if procedures:
            return "&Result = {}(&Id)".format(skewed_pick(rng, procedures))
        return "&Result = &Id"

    def attribute_line(self) -> str:
        attributes: list[str] = self.model["attributes"]  # type: ignore[assignment]
        attribute = self.rng.choice(attributes)
        if self.rng.random() < 0.7:
            return "&Value = {} + &Value".format(attribute)
        return "{} = &Value".format(attribute)

    def for_each_lines(self) -> list[str]:
        tables: list[str] = self.model["tables"]  # type: ignore[assignment]
        table_attributes: dict[str, list[str]] = self.model["table_attributes"]  # type: ignore[assignment]
        table = self.rng.choice(tables)
        own = table_attributes[table]
        lines = ["for each {}".format(table), "    where {} = &Id".format(own[0])]
        for _ in range(self.rng.randint(1, 3)):
            lines.append("    &Value = {}".format(self.rng.choice(own)))
        lines.append("endfor")
        return lines

    def filler_lines(self) -> list[str]:
        roll = self.rng.random()
        if roll < 0.30:
            return ["&Counter = &Counter + 1"]
        if roll < 0.50:
            return ["// Synthetic step {}".format(self.rng.randint(1, 999))]
        if roll < 0.70:
            return ["if &Counter > {}".format(self.rng.randint(1, 50)), "    &Text = 'synthetic text ' + &Text", "endif"]
        if roll < 0.85:
            return ["&Text = &Text.Trim()"]
        return ["&Date = &Date.AddDays({})".format(self.rng.randint(1, 30))]

    def lines(self, count: int, allow_webpanel: bool) -> list[str]:
        args = self.args
        result: list[str] = []
        while len(result) < count:
            roll = self.rng.random()
            if roll < args.call_density:
                result.append(self.call_line(allow_webpanel))
            elif roll < args.call_density + args.for_each_density:
                result.extend(self.for_each_lines())
            elif roll < args.call_density + args.for_each_density + args.attribute_density:
                result.append(self.attribute_line())
            else:
                result.extend(self.filler_lines())
        return result


def build_model(rng: random.Random, counts: dict[str, int]) -> dict[str, object]:
    pool = NamePool()
    transactions = pool.take(shuffled(rng, list(NOUNS)), counts["Transaction"])
    procedures = pool.take(
        shuffled(rng, [v + n + q for v in VERBS for n in NOUNS for q in QUALIFIERS]), counts["Procedure"]
    )
    webpanels = pool.take(shuffled(rng, ["Wp" + n + s for n in NOUNS for s in SCREENS]), counts["WebPanel"])
    data_providers = pool.take(shuffled(rng, ["Dp" + n + q for n in NOUNS for q in QUALIFIERS]), counts["DataProvider"])
    domains = pool.take(["Dom" + kind for kind in DOMAIN_KINDS], counts["Domain"])

    # Attributes go round-robin to the Transactions; the first of each is its key.
    per_transaction: dict[str, list[str]] = {name: [] for name in transactions}
    field_cursor: dict[str, int] = {name: 0 for name in transactions}
    attributes: list[str] = []
    for index in range(counts["Attribute"]):
        transaction = transactions[index % len(transactions)]
        cursor = field_cursor[transaction]
        field_cursor[transaction] = cursor + 1
        field = FIELDS[cursor % len(FIELDS)] + ("" if cursor < len(FIELDS) else str(cursor // len(FIELDS) + 1))
        name = pool.take([transaction + field], 1)[0]
        per_transaction[transaction].append(name)
        attributes.append(name)
    return {
        "transactions": transactions,
        "tables": list(transactions),
        "table_attributes": per_transaction,
        "procedures": procedures,
        "webpanels": webpanels,
        "data_providers": data_providers,
        "domains": domains,
        "attributes": attributes,
    }


def write_file(path: Path, text: str) -> int:
    data = text.encode("utf-8")
    with open(str(path), "wb") as handle:
        handle.write(data)
    return len(data)


def write_complete_sync_state(output: Path, seed: int) -> None:
    """Write the state file the XPZ sync publishes after a verified run, in its shape."""
    state = {
        "schemaVersion": 1,
        "state": "complete",
        "generation": "{:032x}".format(random.Random(seed).getrandbits(128)),
        "updatedAt": TIMESTAMP + ".000Z",
        "packageSha256": "0" * 64,
        "recoveryPackageSha256": None,
    }
    (output / ".mimir-sync-state.json").write_bytes((json.dumps(state, indent=2) + "\n").encode("utf-8"))


def generate(args: argparse.Namespace, output: Path) -> dict[str, object]:
    rng = random.Random(args.seed)
    counts = plan_counts(args.objects, args.procedure_share)
    model = build_model(rng, counts)
    writer = CodeWriter(rng, args, model)
    total_bytes = 0
    for folder in counts:
        (output / folder).mkdir()

    domains: list[str] = model["domains"]  # type: ignore[assignment]
    for name in domains:
        body = (
            "  <Properties>\n"
            "    <Property><Name>DataType</Name><Value>Numeric</Value></Property>\n"
            "    <Property><Name>Length</Name><Value>9</Value></Property>\n"
            "  </Properties>\n"
        )
        total_bytes += write_file(output / "Domain" / (name + ".xml"), object_xml(rng, "Domain", name, "Synthetic domain", body))

    attributes: list[str] = model["attributes"]  # type: ignore[assignment]
    for index, name in enumerate(attributes):
        based_on = ""
        if index % 2 == 0:
            based_on = "    <Property><Name>idBasedOn</Name><Value>Domain:{}</Value></Property>\n".format(domains[index % len(domains)])
        text = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<Attribute name="{name}" guid="{guid}" lastUpdate="{ts}" description="Synthetic attribute">\n'
            "  <Properties>\n"
            "    <Property><Name>Name</Name><Value>{name}</Value></Property>\n"
            "{based_on}"
            "  </Properties>\n"
            "</Attribute>\n"
        ).format(name=name, guid=new_guid(rng), ts=TIMESTAMP, based_on=based_on)
        total_bytes += write_file(output / "Attribute" / (name + ".xml"), text)

    transactions: list[str] = model["transactions"]  # type: ignore[assignment]
    table_attributes: dict[str, list[str]] = model["table_attributes"]  # type: ignore[assignment]
    for index, name in enumerate(transactions):
        own = table_attributes[name]
        # Foreign keys form a tree (each Transaction references one with a lower index, three
        # children per parent), so the reference depth grows like log3 of the count, as in a real KB.
        foreign_key = table_attributes[transactions[(index - 1) // 3]][0] if index > 0 else None
        level = ['  <Level name="{0}" Type="{0}">'.format(name)]
        level.append('    <Attribute key="True">{}</Attribute>'.format(own[0]))
        for attribute in own[1:]:
            level.append('    <Attribute key="False">{}</Attribute>'.format(attribute))
        if foreign_key:
            level.append('    <Attribute key="False">{}</Attribute>'.format(foreign_key))
        level.append("  </Level>")
        rules = ["default({}, &Today);".format(rng.choice(own)), "error('Synthetic rule') if {}.IsEmpty();".format(own[0])]
        body = "\n".join(level) + "\n" + code_part(RULES_PART_GUID, rules)
        total_bytes += write_file(
            output / "Transaction" / (name + ".xml"), object_xml(rng, "Transaction", name, "Synthetic transaction", body)
        )
        table_body = "  <Key>\n    <Item>{}</Item>\n  </Key>\n".format(own[0])
        if foreign_key:
            table_body += '  <Index Type="Duplicate" name="IDX_{0}_{1}">\n    <Member>{1}</Member>\n  </Index>\n'.format(name, foreign_key)
        total_bytes += write_file(output / "Table" / (name + ".xml"), object_xml(rng, "Table", name, "Synthetic table", table_body))

    procedures: list[str] = model["procedures"]  # type: ignore[assignment]
    for name in procedures:
        body = code_part(PROCEDURE_SOURCE_PART_GUID, writer.lines(args.lines_per_source, allow_webpanel=False))
        body += code_part(RULES_PART_GUID, ["parm(in:&Id, out:&Result);"])
        total_bytes += write_file(output / "Procedure" / (name + ".xml"), object_xml(rng, "Procedure", name, "Synthetic procedure", body))

    webpanels: list[str] = model["webpanels"]  # type: ignore[assignment]
    for name in webpanels:
        events = ["Event Start", "    &Counter = 0", "EndEvent", "Event 'Load'"]
        events.extend("    " + line for line in writer.lines(max(5, args.lines_per_source // 2), allow_webpanel=True))
        events.append("EndEvent")
        body = code_part(EVENTS_PART_GUID, events) + code_part(RULES_PART_GUID, ["parm(in:&Id);"])
        total_bytes += write_file(output / "WebPanel" / (name + ".xml"), object_xml(rng, "WebPanel", name, "Synthetic web panel", body))

    data_providers: list[str] = model["data_providers"]  # type: ignore[assignment]
    for name in data_providers:
        source = ["SyntheticItems", "{"]
        for _ in range(rng.randint(3, 8)):
            source.append("    Item = {}".format(rng.choice(attributes)))
        if procedures:
            source.append("    Total = {}(&Id)".format(skewed_pick(rng, procedures)))
        source.append("}")
        body = code_part(DATA_PROVIDER_SOURCE_PART_GUID, source) + code_part(RULES_PART_GUID, ["parm(in:&Id);"])
        total_bytes += write_file(
            output / "DataProvider" / (name + ".xml"), object_xml(rng, "DataProvider", name, "Synthetic data provider", body)
        )

    write_complete_sync_state(output, args.seed)
    return {
        "output_dir": str(output),
        "objects": sum(counts.values()),
        "objects_by_type": counts,
        "size_bytes": total_bytes,
        "parameters": {
            "objects": args.objects,
            "procedure_share": args.procedure_share,
            "lines_per_source": args.lines_per_source,
            "call_density": args.call_density,
            "for_each_density": args.for_each_density,
            "attribute_density": args.attribute_density,
            "seed": args.seed,
        },
        "relation_families": list(RELATION_FAMILIES),
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        validate(args)
        plan_counts(args.objects, args.procedure_share)
        output = resolve_output_dir(args.output_dir)
    except Refused as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 2
    summary = generate(args, output)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
