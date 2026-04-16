from __future__ import annotations

import logging
from datetime import date

from garminconnect import Garmin, GarminConnectAuthenticationError

from garmin.pull.config import get_settings

logger = logging.getLogger(__name__)


def get_client() -> Garmin:
    """Authenticate to Garmin Connect using saved OAuth tokens.

    On first run, email/password obtain DI OAuth tokens saved to the
    tokenstore directory. Subsequent runs restore from saved tokens --
    the refresh token auto-renews without credentials.
    """
    settings = get_settings()
    tokenstore = str(settings.garmin_tokenstore)

    try:
        client = Garmin()
        client.login(tokenstore)
        logger.info("Garmin: logged in using saved tokens from %s", tokenstore)
        return client
    except (GarminConnectAuthenticationError, FileNotFoundError):
        logger.info("Garmin: no valid saved tokens, logging in with credentials")

    if not settings.garmin_configured:
        raise RuntimeError(
            "No saved Garmin tokens and no credentials configured. "
            "Run `make garmin-login` first or set GARMIN_EMAIL and GARMIN_PASSWORD."
        )

    client = Garmin(
        email=settings.garmin_email,
        password=settings.garmin_password,
        is_cn=False,
    )
    client.login(tokenstore)
    logger.info("Garmin: fresh login, tokens saved to %s", tokenstore)
    return client


def extract_daily(target_date: date) -> dict:
    """Pull comprehensive health data from Garmin Connect for a single date.

    Returns a dict keyed by data category, each containing the raw API response.
    """
    client = get_client()
    ds = target_date.isoformat()
    logger.info("Garmin: extracting data for %s", ds)

    data: dict = {"date": ds}

    extractors: list[tuple[str, str]] = [
        ("stats", "get_stats"),
        ("heart_rates", "get_heart_rates"),
        ("sleep", "get_sleep_data"),
        ("stress", "get_stress_data"),
        ("hrv", "get_hrv_data"),
        ("spo2", "get_spo2_data"),
        ("body_battery", "get_body_battery"),
        ("steps", "get_steps_data"),
        ("respiration", "get_respiration_data"),
    ]

    for key, method_name in extractors:
        try:
            method = getattr(client, method_name)
            data[key] = method(ds)
        except Exception:
            logger.warning("Garmin: failed to extract %s for %s", key, ds, exc_info=True)
            data[key] = None

    try:
        data["activities"] = client.get_activities_fordate(ds)
    except Exception:
        logger.warning("Garmin: failed to extract activities for %s", ds, exc_info=True)
        data["activities"] = None

    category_counts = {k: "ok" if v is not None else "missing" for k, v in data.items() if k != "date"}
    logger.info("Garmin: extraction summary for %s: %s", ds, category_counts)

    return data
