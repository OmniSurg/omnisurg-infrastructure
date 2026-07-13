# COMPOSE merges the shared-infra base file with the application-services
# overlay so a single docker compose invocation validates and runs the full
# local stack. See ADR 0003 for the multi-module build strategy.
COMPOSE := docker compose -f compose/docker-compose.local.yml -f compose/docker-compose.services.yml --env-file .env

# INFRA_ONLY is the base file alone: postgres, redis, traefik, mailhog, and the
# three stubs, WITHOUT the 13 application containers. The per-service `compose-up`
# targets (billing, payment, claims, etc.) use `up-infra` so a single service's
# CST brings up only the shared dependencies and runs that one service on the
# host, not all 13 app containers. The full overlay (COMPOSE) is for `up`,
# `bootstrap`, and `e2e`. See docs/adr/0004-full-stack-e2e-and-up-infra.md.
INFRA_ONLY := docker compose -f compose/docker-compose.local.yml --env-file .env

.PHONY: help bootstrap up up-infra down down-infra ps logs psql redis ci e2e seed seed-synthetic seed-demo seed-verify seed-selftest smoke smoke-selftest clean render-env deploy-config-check lint-actions

help:
	@echo "make bootstrap  - one shot: copy .env.example to .env if missing, build stubs, bring up the stack, wait healthy"
	@echo "make up         - bring up the full stack (13 app services plus infra) in the background"
	@echo "make up-infra   - bring up ONLY the shared infra (postgres, redis, traefik, mailhog, stubs) for single-service CSTs"
	@echo "make e2e        - full-stack gate: down -v, bootstrap, seed, verify, cross-service smoke, teardown"
	@echo "make down       - tear the full stack down"
	@echo "make down-infra - tear down ONLY the shared infra (the up-infra counterpart)"
	@echo "make clean      - tear the full stack down AND remove volumes (down -v); next bootstrap re-runs init.sql"
	@echo "make ps         - list services and health"
	@echo "make logs       - follow logs from all services"
	@echo "make psql       - psql into the local postgres as omnisurg superuser"
	@echo "make redis      - redis-cli into the local redis with the local password"
	@echo "make seed       - run each service seed in dependency order then verify (LOCAL ONLY: needs OMNISURG_ENV=local)"
	@echo "make seed-synthetic - load generic synthetic business data (local or staging only; never production)"
	@echo "make seed-demo  - add 15 realistic demo patients with full activity via the live HTTP APIs (idempotent; for staff testing)"
	@echo "make seed-verify- run only the cross-service seed verifier against the running stack"
	@echo "make smoke      - run the cross-service money-loop plus tenant-isolation smoke against the running, seeded stack"
	@echo "make ci         - lint compose plus go vet stubs plus the seed and smoke fail-closed selftests (the local CI gate)"
	@echo "make deploy-config-check - validate the production and staging deploy stacks (config -q, part of ci)"
	@echo "make render-env ENV=production|staging - render per-service secret env files from deploy/<env>/.env (VPS bootstrap)"

bootstrap:
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env from .env.example"; fi
	$(COMPOSE) build
	$(COMPOSE) up -d
	@echo "Waiting for healthchecks (full stack: 13 app services plus infra)..."
	@for i in $$(seq 1 60); do \
		sleep 5; \
		PENDING=$$($(COMPOSE) ps --format '{{.Health}}' | grep -E 'starting|unhealthy' | wc -l | tr -d ' '); \
		if [ "$$PENDING" = "0" ]; then \
			echo "Stack ready (no container is starting or unhealthy)."; \
			$(COMPOSE) ps; \
			exit 0; \
		fi; \
	done; \
	echo "Stack did not become ready in 300 seconds." >&2; \
	$(COMPOSE) ps; \
	exit 1

up:
	$(COMPOSE) up -d

# up-infra brings up ONLY the shared infra (base file). Single-service CSTs call
# this via `make -C ../omnisurg-infrastructure up-infra` so one service's smoke
# does not need all 13 app containers; the service itself runs on the host.
up-infra:
	$(INFRA_ONLY) up -d

down:
	$(COMPOSE) down

# down-infra tears down only the shared infra (the up-infra counterpart). It does
# not touch app containers a full `up` may have started.
down-infra:
	$(INFRA_ONLY) down

# clean tears the full stack down AND removes the postgres/redis volumes. The
# next bootstrap re-runs init.sql on the fresh volume (the documented gotcha:
# init.sql only runs on a fresh volume; editing it requires a clean). The
# deterministic seed also needs a clean before a reseed when seed LOGIC changed,
# because stale volumes hold the old ids.
clean:
	$(COMPOSE) down -v

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

psql:
	$(COMPOSE) exec postgres psql -U $$POSTGRES_USER

redis:
	$(COMPOSE) exec redis redis-cli -a $$REDIS_PASSWORD

ci:
	$(COMPOSE) config -q
	@echo "compose syntax OK"
	@$(MAKE) deploy-config-check
	go vet ./stubs/afrosoft/... ./stubs/paynow/... ./stubs/zimrate/...
	@echo "go vet OK"
	@$(MAKE) seed-selftest
	@echo "seed contract selftest OK"
	@$(MAKE) smoke-selftest
	@echo "smoke contract selftest OK"

# deploy-config-check validates the two isolated deploy stacks (production and
# staging) with `docker compose config -q`. It needs no env file: the only
# interpolation is IMAGE_TAG (which defaults to :prod/:staging), and the
# per-service env_file entries are declared required:false so validation does not
# need the runtime secret files (rendered on the VPS by deploy/render-env.sh).
deploy-config-check:
	docker compose -f deploy/production/docker-compose.yml config -q
	docker compose -f deploy/staging/docker-compose.yml config -q
	@echo "deploy compose syntax OK (production + staging)"

# lint-actions runs actionlint over the reusable GitHub Actions workflows and the
# per-repo caller templates. It is a SEPARATE target (not folded into `make ci`)
# so the stack-free `make ci` gate stays dependency-light: actionlint is a Go
# binary that is not needed on every dev machine. Install once with:
#   go install github.com/rhysd/actionlint/cmd/actionlint@latest
# Run before touching any workflow or template.
lint-actions:
	@command -v actionlint >/dev/null 2>&1 || { echo "actionlint not found. Install: go install github.com/rhysd/actionlint/cmd/actionlint@latest"; exit 1; }
	actionlint .github/workflows/*.yml
	actionlint deploy/ci-templates/*.yml
	@echo "actionlint OK (workflows + caller templates)"

# render-env renders the per-service, least-privilege env files for a deploy
# environment from its deploy/<env>/.env. Run on the VPS at bootstrap.
#   make render-env ENV=production
#   make render-env ENV=staging
render-env:
	@test -n "$(ENV)" || { echo "Usage: make render-env ENV=production|staging"; exit 1; }
	./deploy/render-env.sh $(ENV)

# e2e is the full-stack gate. It folds the whole path together: a clean slate
# (down -v so a reseed is not poisoned by stale-volume ids), a full-stack
# bootstrap (all 20 containers healthy), the deterministic seed plus its
# cross-reference verify, then the cross-service money-loop and tenant-isolation
# smoke, then a clean teardown. It is the capstone that proves every service
# works together with the shared Zimbabwe seed and fails on any broken
# cross-service reference, disagreeing number, violated HOLD, or tenant leak.
# `make ci` (config-q plus stub vet plus the fail-closed selftests) stays the
# stack-free gate; `make e2e` is the stack-up gate.
e2e:
	$(COMPOSE) down -v
	@$(MAKE) bootstrap
	@OMNISURG_ENV=local $(MAKE) seed
	@$(MAKE) smoke
	$(COMPOSE) down -v
	@echo "e2e complete: full stack healthy, seed + verify green, cross-service money loop + isolation green, clean teardown"

# smoke runs the cross-service money-loop plus tenant-isolation runner against
# the running, seeded stack. Run after `make bootstrap && make seed` (or use
# `make e2e` for the whole path). It fails on any broken cross-service reference,
# disagreeing number (incl. the BFF-stitched-vs-payment agreement), violated
# HOLD, or tenant leak.
smoke:
	@if [ -x ./smoke/run.sh ]; then \
		./smoke/run.sh; \
	else \
		echo "skipped: internal live-stack smoke (smoke/run.sh) is not present in this checkout"; \
	fi

# smoke-selftest is the stack-free TDD guard: it proves the smoke runner fails
# closed against an unreachable stack and that its fixed-id contract and
# load-bearing cross-service assertions do not drift. It runs as part of make ci.
smoke-selftest:
	@if [ -x ./smoke/run_selftest.sh ]; then \
		./smoke/run_selftest.sh; \
	else \
		echo "skipped: internal live-stack smoke selftest (smoke/run_selftest.sh) is not present in this checkout"; \
	fi

# seed runs each service seed binary (/app/seed, built into every image) inside
# its container in dependency order: tenant and identity first (tenants and
# users), then currency (FX rates the billing hop reads), then patient (the
# fixed-id demo patients), then billing (the fixed-id invoices), then payment
# (settles the cash invoices, mobile money pending shell), then claims (claims
# the aid invoice), then notification (one message through the stub), then
# scheduling (a day of free consult slots so the day book has free times to book
# against) and audit (the four POTRAZ access events so the activity log has
# practice activity to show). Each seed is idempotent (fixed ids, ON CONFLICT /
# skip-if-exists) so seed is safe to rerun. It fails on the first non-zero seed
# exit, then runs the verifier.
#
# This is the DEMO path: it loads documented test logins and fixed ids, so it is
# LOCAL ONLY. The guard (seed/seed-guard.sh) refuses to run unless
# OMNISURG_ENV=local and exits BEFORE any seed exec, so it can never touch
# staging or production. Run it as: OMNISURG_ENV=local make seed
seed:
	./seed/seed-guard.sh demo
	$(COMPOSE) exec -T tenant-service /app/seed
	$(COMPOSE) exec -T identity-service /app/seed
	$(COMPOSE) exec -T currency-service /app/seed
	$(COMPOSE) exec -T patient-service /app/seed
	$(COMPOSE) exec -T billing-service /app/seed
	$(COMPOSE) exec -T payment-service /app/seed
	$(COMPOSE) exec -T claims-service /app/seed
	$(COMPOSE) exec -T notification-service /app/seed
	$(COMPOSE) exec -T scheduling-service /app/seed
	$(COMPOSE) exec -T audit-service /app/seed
	@echo "seed complete; verifying cross-references"
	@$(MAKE) seed-verify

# seed-synthetic loads GENERIC SYNTHETIC business data (a fictional practice, no
# real customer, no documented password, no fixed secret) from
# seed/synthetic/fixtures.json via the live HTTP APIs. It is guarded to
# OMNISURG_ENV local or staging and refuses production. The admin credentials it
# authenticates with are supplied at run time from the environment, never
# committed. Use it for staging convenience data:
#   OMNISURG_ENV=staging make seed-synthetic
# The runner guards first (seed/seed-guard.sh) so a refusal writes nothing.
seed-synthetic:
	./seed/synthetic/seed-synthetic.sh

# seed-demo adds 15 realistic demo patients to the local DEMO practice, each
# having used MULTIPLE modules (memberships, this-week appointments with exactly
# 5 today, clinical eye visits, invoices + payments, medical aid claims,
# referrals), so staff can test the staff web UI end to end. It talks ONLY to the
# live service HTTP APIs (and the admin-bff for invoices/payments), which handle
# PII encryption, validation, and tenant RLS, so every record is guaranteed
# visible through the admin-bff. It is idempotent (search-then-skip per patient
# and per record), so it is safe to rerun. It is part of the internal DEMO path
# and layers on top of the deterministic `make seed` fixtures. Run after
# `make bootstrap` and `OMNISURG_ENV=local make seed`.
seed-demo:
	node seed/internal/demo/seed-demo.mjs

# seed-verify asserts every fixed-id cross-reference resolves and the
# billing/payment dues agree. It fails on any dangling reference or mismatched
# due. It is the internal DEMO verifier (kept under seed/internal, gitignored).
# Run on the host against the published service ports.
seed-verify:
	./seed/internal/verify.sh

# seed-selftest is the stack-free TDD guard for both seed paths. It proves the
# environment guards refuse correctly, that seed-synthetic --check writes
# nothing, that the committed tree carries no scrubbed strings, and that the
# internal demo fixtures stay untracked. When the internal demo fixtures are
# present it also runs the demo verifier's own fail-closed selftest. It runs as
# part of make ci and needs no running stack.
seed-selftest:
	./seed/seed_selftest.sh
	@if [ -f ./seed/internal/verify_selftest.sh ]; then \
		./seed/internal/verify_selftest.sh; \
	else \
		echo "  (demo verify selftest skipped: seed/internal not present, e.g. a public checkout)"; \
	fi
