"""Shared code for dbxWearables cloud-API connector providers.

This package exposes the provider-agnostic pieces every connector depends on:

- ``silver.health_event.HealthEvent`` — the canonical silver-layer event
  schema, used by every provider's ``silver/normalizer.py``.
- ``connector_protocol.ConnectorProtocol`` — the Python mirror of the
  AppKit ``WearableConnector`` interface, used by the Lakeflow fanout
  notebook to dispatch ``pull_batch`` across providers.
- ``credential_store.CredentialStore`` — an abstract interface plus a
  ``LakebaseCredentialStore`` default that reads encrypted OAuth tokens
  from the ``wearable_credentials`` table managed by the AppKit
  ``wearable-core`` plugin.
"""
