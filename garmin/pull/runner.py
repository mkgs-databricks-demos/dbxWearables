"""CLI runner for Garmin health data ingestion.

Usage:
    python -m garmin.pull.runner --date 2026-04-15
    python -m garmin.pull.runner  # defaults to yesterday
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from datetime import date, timedelta

from garmin.pull.config import get_settings
from garmin.pull.extractor import extract_daily
from garmin.pull.normalizer import normalize, to_bronze_rows

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s  %(message)s",
)
logger = logging.getLogger(__name__)


def run(target_date: date, *, dry_run: bool = False, output_file: str | None = None) -> int:
    """Extract, normalize, and push Garmin data for a single date.

    Returns the number of records pushed (or that would be pushed in dry-run mode).
    """
    settings = get_settings()

    if not settings.garmin_tokens_exist and not settings.garmin_configured:
        logger.error(
            "Garmin not configured. Run `make garmin-login` to authenticate, "
            "or set GARMIN_EMAIL and GARMIN_PASSWORD."
        )
        return 0

    raw = extract_daily(target_date)

    if output_file:
        events = normalize(raw)
        event_dicts = [e.to_dict() for e in events]
        with open(output_file, "w") as f:
            json.dump(event_dicts, f, indent=2, default=str)
        logger.info("Wrote %d silver-layer events to %s", len(events), output_file)
        return len(events)

    bronze_rows = to_bronze_rows(raw)
    logger.info("Built %d bronze rows for %s", len(bronze_rows), target_date)

    if not bronze_rows:
        logger.warning("No data to push for %s", target_date)
        return 0

    if dry_run:
        for row in bronze_rows:
            logger.info("  [DRY RUN] record_type=%s  record_id=%s", row["record_type"], row["record_id"][:8])
        return len(bronze_rows)

    if not settings.zerobus_configured:
        logger.error(
            "ZeroBus not configured. Set ZEROBUS_SERVER_ENDPOINT, "
            "DATABRICKS_WORKSPACE_URL, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET. "
            "Use --dry-run or --output to test without ZeroBus."
        )
        return 0

    try:
        from zerobus.sdk.shared import RecordType, StreamConfigurationOptions, TableProperties
        from zerobus.sdk.sync import ZerobusSdk
    except ImportError:
        logger.error("databricks-zerobus-ingest-sdk not installed. Run: pip install databricks-zerobus-ingest-sdk")
        return 0

    sdk = ZerobusSdk(
        settings.zerobus_server_endpoint,
        settings.databricks_workspace_url,
    )
    table_props = TableProperties(settings.bronze_table_fqn)
    options = StreamConfigurationOptions(
        record_type=RecordType.JSON,
        max_inflight_requests=50,
    )
    stream = sdk.create_stream(
        settings.databricks_client_id,
        settings.databricks_client_secret,
        table_props,
        options,
    )

    try:
        offsets = []
        for row in bronze_rows:
            offset = stream.ingest_record_offset(row)
            offsets.append(offset)
        if offsets:
            stream.wait_for_offset(offsets[-1])
        logger.info("Pushed %d rows to ZeroBus -> %s", len(offsets), settings.bronze_table_fqn)
        return len(offsets)
    finally:
        stream.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest Garmin health data into Databricks")
    parser.add_argument(
        "--date",
        default=str(date.today() - timedelta(days=1)),
        help="Date to extract (YYYY-MM-DD, default: yesterday)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Extract and build bronze rows but don't push to ZeroBus",
    )
    parser.add_argument(
        "--output", "-o",
        help="Write silver-layer normalized events to a JSON file (for inspection)",
    )
    args = parser.parse_args()

    count = run(date.fromisoformat(args.date), dry_run=args.dry_run, output_file=args.output)
    if count == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
