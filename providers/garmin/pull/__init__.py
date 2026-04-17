"""Garmin Python pull connector.

Importing this module side-effects a registration into
``providers.common.connector_protocol`` so the Lakeflow fanout notebook
can discover and dispatch to it without a hardcoded map.

When this connector gets a full ConnectorProtocol implementation wired
to the Lakebase-backed CredentialStore, uncomment the registration at
the bottom. For now the module is lazy — importing does not fail, but
no connector is registered yet (the fanout notebook falls back to the
legacy single-user path in ``runner.py``).
"""
from __future__ import annotations

# TODO: wire a GarminPullConnector class that satisfies
# providers.common.connector_protocol.ConnectorProtocol and reads tokens
# from providers.common.credential_store.LakebaseCredentialStore instead
# of the single-user ~/.garminconnect tokenstore. Then:
#
#     from providers.common.connector_protocol import register_connector
#     from providers.garmin.pull.connector import GarminPullConnector
#     register_connector(GarminPullConnector())
