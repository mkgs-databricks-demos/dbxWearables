.PHONY: setup garmin-login ingest ingest-dry-run setup-secrets backfill lint

setup:
	pip install -e ".[dev]"

garmin-login:
	@echo "Authenticating to Garmin Connect (one-time, saves tokens locally)..."
	@python -c "\
	from garminconnect import Garmin; \
	import os; \
	g = Garmin( \
	    os.environ.get('GARMIN_EMAIL', ''), \
	    os.environ.get('GARMIN_PASSWORD', ''), \
	    prompt_mfa=lambda: input('MFA code: ') \
	); \
	g.login(os.path.expanduser('~/.garminconnect')); \
	print('Tokens saved to ~/.garminconnect/garmin_tokens.json')"

ingest:
	python -m garmin.pull.runner --date $$(date -v-1d +%Y-%m-%d)

ingest-dry-run:
	python -m garmin.pull.runner --date $$(date -v-1d +%Y-%m-%d) --dry-run

ingest-to-file:
	python -m garmin.pull.runner --date $$(date -v-1d +%Y-%m-%d) --output garmin_events.json

setup-secrets:
	@echo "Pushing Garmin tokens to shared secret scope..."
	@PROFILE=$${DATABRICKS_PROFILE:-DEFAULT} && \
	SCOPE=$${SECRET_SCOPE:-dbxw_zerobus_credentials} && \
	databricks secrets put-secret $$SCOPE garmin_oauth_tokens \
	  --string-value "$$(cat ~/.garminconnect/garmin_tokens.json)" --profile=$$PROFILE && \
	echo "Garmin tokens pushed to scope '$$SCOPE' key 'garmin_oauth_tokens' via profile '$$PROFILE'"

backfill:
	@echo "Backfilling from $(START_DATE) to $(END_DATE)..."
	@START=$${START_DATE:?Set START_DATE=YYYY-MM-DD}; \
	END=$${END_DATE:?Set END_DATE=YYYY-MM-DD}; \
	CURRENT=$$START; \
	while [ "$$CURRENT" != "$$END" ]; do \
	  echo "Ingesting $$CURRENT..."; \
	  python -m garmin.pull.runner --date $$CURRENT || true; \
	  CURRENT=$$(date -j -v+1d -f "%Y-%m-%d" $$CURRENT +%Y-%m-%d); \
	done

lint:
	ruff check garmin/pull/
	ruff format --check garmin/pull/
