#!/usr/bin/env python3
"""Magic Hat — Service Provisioner

Reads /etc/magichat/desired-services.conf and provisions each service
via Familiar's ServiceManager (which handles hardened container specs,
capabilities, volume mounts, health checks, etc.).

Called by:
  - profile-install.sh (after recording desired services)
  - magichat services provision (CLI)
  - First-boot wizard step 3 (job class → services)

Usage:
  provision-services.py                  # Provision all from desired-services.conf
  provision-services.py svc1 svc2 ...    # Provision specific services
  provision-services.py --status         # Show status of all managed services
  provision-services.py --json           # JSON output (for wizard integration)

Copyright (c) 2026 George Scott Foley — MIT License
"""

from __future__ import annotations

import json
import sys

DESIRED_SERVICES_FILE = "/etc/magichat/desired-services.conf"


def _get_service_manager():
    """Import and return Familiar's ServiceManager singleton."""
    try:
        from familiar.services.manager import get_service_manager
        return get_service_manager()
    except ImportError:
        print("ERROR: familiar-agent package not installed", file=sys.stderr)
        sys.exit(1)


def _get_service_specs():
    """Import and return Familiar's SERVICE_SPECS."""
    try:
        from familiar.services.specs import SERVICE_SPECS
        return SERVICE_SPECS
    except ImportError:
        return {}


def read_desired_services() -> list[str]:
    """Read service keys from desired-services.conf."""
    try:
        with open(DESIRED_SERVICES_FILE) as f:
            return [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return []


def _find_stacks(service_keys: list[str], specs: dict) -> tuple[list[list[str]], list[str]]:
    """Split service_keys into compose stacks and standalone services.

    Services with depends_on (or that are depended upon by stack members)
    are grouped together. Returns (stacks, standalone).
    """
    # Build dependency graph
    stack_members: set[str] = set()
    for key in service_keys:
        spec = specs.get(key)
        if spec and getattr(spec, "depends_on", None):
            stack_members.add(key)
            for dep in spec.depends_on:
                if dep in service_keys:
                    stack_members.add(dep)

    # Group stack members that share dependencies into a single stack
    stacks: list[list[str]] = []
    if stack_members:
        # For now, all interconnected services form one stack
        stacks.append(sorted(stack_members))

    standalone = [k for k in service_keys if k not in stack_members]
    return stacks, standalone


def provision_services(service_keys: list[str], json_output: bool = False) -> list[dict]:
    """Provision a list of services via Familiar's ServiceManager.

    Automatically detects compose stacks (services with depends_on)
    and provisions them together via podman-compose for shared networking.

    Returns list of {service, key, status, message} result dicts.
    """
    mgr = _get_service_manager()
    specs = _get_service_specs()
    results = []

    # Separate native, stack, and standalone services
    native_keys = []
    container_keys = []
    for key in service_keys:
        spec = specs.get(key)
        if not spec:
            results.append({
                "service": key, "key": key,
                "status": "skipped", "message": f"Unknown service key: {key}",
            })
            continue
        if spec.service_type.value == "native":
            results.append({
                "service": spec.display_name, "key": key,
                "status": "ok", "message": "Built-in (runs inside Reflection)",
            })
        else:
            container_keys.append(key)

    # Split containers into compose stacks and standalone
    stacks, standalone = _find_stacks(container_keys, specs)

    # Provision compose stacks (Wazuh, etc.)
    for stack_keys in stacks:
        if not json_output:
            names = ", ".join(specs[k].display_name for k in stack_keys if k in specs)
            print(f"  Provisioning stack: {names}...")
        try:
            stack_result = mgr.provision_compose_stack(stack_keys)
            for svc in stack_result.get("services", []):
                key = svc.get("service", "")
                results.append({
                    "service": svc.get("display_name", key), "key": key,
                    "status": "ok" if svc.get("ok") else "error",
                    "message": svc.get("url", svc.get("error", "")),
                })
        except Exception as e:
            for key in stack_keys:
                spec = specs.get(key)
                results.append({
                    "service": spec.display_name if spec else key, "key": key,
                    "status": "error", "message": str(e)[:200],
                })

    # Provision standalone containers individually
    for key in standalone:
        spec = specs[key]
        try:
            status = mgr.get_status(key)
            if status and status.status == "running":
                results.append({
                    "service": spec.display_name, "key": key,
                    "status": "ok", "message": "Already running",
                })
                continue

            if not json_output:
                print(f"  Provisioning {spec.display_name}...")
            mgr.provision(key)
            mgr.start(key)

            status = mgr.get_status(key)
            is_running = status and status.status == "running"

            first_port = next(iter(spec.ports), "?")
            if is_running:
                results.append({
                    "service": spec.display_name, "key": key,
                    "status": "ok", "message": f"Running on port {first_port}",
                })
            else:
                results.append({
                    "service": spec.display_name, "key": key,
                    "status": "error",
                    "message": f"Provisioned but not running (port {first_port})",
                })
        except Exception as e:
            results.append({
                "service": spec.display_name, "key": key,
                "status": "error", "message": str(e)[:200],
            })

    return results


def show_status(json_output: bool = False) -> None:
    """Show status of all managed services."""
    mgr = _get_service_manager()
    statuses = mgr.get_all_statuses()

    if json_output:
        out = []
        for s in statuses:
            out.append({
                "key": s.service_key, "status": s.status,
                "container": s.container_id or "",
            })
        print(json.dumps(out, indent=2))
        return

    if not statuses:
        print("  No managed services.")
        return

    print(f"  {'SERVICE':<20s} {'STATUS':<12s} {'CONTAINER':<16s}")
    print(f"  {'─' * 20} {'─' * 12} {'─' * 16}")
    for s in statuses:
        color = "\033[32m" if s.status == "running" else "\033[31m"
        reset = "\033[0m"
        cid = (s.container_id or "")[:12]
        print(f"  {s.service_key:<20s} {color}{s.status:<12s}{reset} {cid:<16s}")


def main() -> None:
    args = sys.argv[1:]
    json_output = "--json" in args
    args = [a for a in args if a != "--json"]

    if "--status" in args:
        show_status(json_output)
        return

    if "--help" in args or "-h" in args:
        print(__doc__)
        return

    # Determine which services to provision
    if args:
        service_keys = args
    else:
        service_keys = read_desired_services()

    if not service_keys:
        if not json_output:
            print("  No services to provision.")
            print(f"  Add service keys to {DESIRED_SERVICES_FILE} or pass them as arguments.")
        else:
            print("[]")
        return

    if not json_output:
        print(f"  Provisioning {len(service_keys)} service(s): {', '.join(service_keys)}")
        print()

    results = provision_services(service_keys, json_output)

    if json_output:
        print(json.dumps(results, indent=2))
    else:
        print()
        ok = sum(1 for r in results if r["status"] == "ok")
        err = sum(1 for r in results if r["status"] == "error")
        skip = sum(1 for r in results if r["status"] == "skipped")
        for r in results:
            icon = "✓" if r["status"] == "ok" else "✗" if r["status"] == "error" else "–"
            print(f"  {icon} {r['service']}: {r['message']}")
        print()
        print(f"  Done: {ok} ok, {err} errors, {skip} skipped")


if __name__ == "__main__":
    main()
