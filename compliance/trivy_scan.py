#!/usr/bin/env python3
"""
Scan latest images in all ECR repositories with Trivy and generate an HTML report
containing ONLY HIGH and CRITICAL vulnerabilities.

Requirements:
  - trivy installed locally and in PATH
  - AWS credentials available for boto3
  - Docker available (Trivy usually pulls via Docker)
  - Access to the ECR registry

Usage:
  export AWS_PROFILE=<profile_name>
  python ecr_trivy_report.py --ecr-registry 123456789000.dkr.ecr.us-east-1.amazonaws.com \
    --region us-east-1 \
    --out report.html

Notes:
  - "latest image" is interpreted as the most recently pushed image in each repo.
  - The report explicitly lists the image reference that was scanned.
"""

import argparse
import base64
import datetime as dt
import html
import json
import os
import subprocess
import sys
from collections import defaultdict
from typing import Any, Dict, List, Optional, Tuple

import boto3


SEVERITIES = {"HIGH", "CRITICAL"}


def run(cmd: List[str], check: bool = True, capture: bool = True, text: bool = True, env: Optional[dict] = None):
    """Run a subprocess command."""
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=text,
        env=env,
    )


def ecr_docker_login(ecr_client, registry: str) -> None:
    """
    Perform `docker login` to ECR using GetAuthorizationToken.
    This helps Trivy pull images (if your Docker isn't already logged in).
    """
    auth = ecr_client.get_authorization_token()
    if not auth.get("authorizationData"):
        raise RuntimeError("ECR authorization token response missing authorizationData")

    # Pick the auth data that matches our registry, otherwise just use first.
    auth_data = None
    for item in auth["authorizationData"]:
        proxy = item.get("proxyEndpoint", "").replace("https://", "").replace("http://", "")
        if proxy == registry:
            auth_data = item
            break
    if auth_data is None:
        auth_data = auth["authorizationData"][0]

    token = auth_data["authorizationToken"]
    decoded = base64.b64decode(token).decode("utf-8")
    username, password = decoded.split(":", 1)

    # docker login <registry> -u AWS --password-stdin
    p = subprocess.Popen(
        ["docker", "login", registry, "-u", username, "--password-stdin"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    out, err = p.communicate(password + "\n")
    if p.returncode != 0:
        raise RuntimeError(f"docker login failed for {registry}: {err.strip() or out.strip()}")


def list_all_repositories(ecr_client) -> List[Dict[str, Any]]:
    repos: List[Dict[str, Any]] = []
    paginator = ecr_client.get_paginator("describe_repositories")
    for page in paginator.paginate():
        repos.extend(page.get("repositories", []))
    return repos


def get_latest_image(ecr_client, repository_name: str) -> Optional[Dict[str, Any]]:
    """
    Return the most recently pushed image (describe_images sorted by imagePushedAt desc).
    """
    paginator = ecr_client.get_paginator("describe_images")
    newest: Optional[Dict[str, Any]] = None

    for page in paginator.paginate(repositoryName=repository_name, filter={"tagStatus": "ANY"}):
        for d in page.get("imageDetails", []):
            pushed = d.get("imagePushedAt")
            if pushed is None:
                continue
            if newest is None or pushed > newest.get("imagePushedAt", pushed):
                newest = d

    return newest


def build_image_ref(repository_uri: str, image_details: Dict[str, Any]) -> str:
    """
    Prefer tag ref if available (repoUri:tag). Otherwise use digest ref (repoUri@sha256:...).
    """
    tags = image_details.get("imageTags") or []
    digest = image_details.get("imageDigest")

    if tags:
        # If multiple tags exist, pick one deterministically (prefer "latest" if present).
        if "latest" in tags:
            tag = "latest"
        else:
            tag = sorted(tags)[0]
        return f"{repository_uri}:{tag}"

    if digest:
        return f"{repository_uri}@{digest}"

    raise RuntimeError(f"Cannot build image reference for {repository_uri}: missing tags and digest")


def trivy_scan_image(image_ref: str, trivy_timeout_seconds: int = 0) -> Dict[str, Any]:
    """
    Run Trivy and return JSON output.
    We ask Trivy to consider only HIGH/CRITICAL severities; we still filter in code too.
    """
    cmd = [
        "trivy",
        "image",
        "--format",
        "json",
        "--severity",
        "HIGH,CRITICAL",
        image_ref,
    ]
    # Optional: timeout via subprocess if requested
    if trivy_timeout_seconds and trivy_timeout_seconds > 0:
        completed = run(cmd, check=False)
        # If you want a strict timeout, you'd need subprocess.run(..., timeout=...)
        # Keeping it simple; most people rely on Trivy's own behavior.
    else:
        completed = run(cmd, check=False)

    if completed.returncode != 0:
        # Trivy sometimes returns non-zero for operational errors; include stderr for report.
        raise RuntimeError(f"Trivy failed for {image_ref}: {completed.stderr.strip() or completed.stdout.strip()}")

    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse Trivy JSON for {image_ref}: {e}")


def extract_findings(trivy_json: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Extract vulnerabilities (HIGH/CRITICAL only) from Trivy JSON.
    Returns flat list of findings with useful fields.
    """
    findings: List[Dict[str, Any]] = []

    results = trivy_json.get("Results") or []
    for r in results:
        target = r.get("Target") or ""
        rtype = r.get("Type") or ""
        vulns = r.get("Vulnerabilities") or []
        for v in vulns:
            sev = (v.get("Severity") or "").upper()
            if sev not in SEVERITIES:
                continue
            findings.append(
                {
                    "Target": target,
                    "Type": rtype,
                    "VulnerabilityID": v.get("VulnerabilityID") or "",
                    "PkgName": v.get("PkgName") or "",
                    "InstalledVersion": v.get("InstalledVersion") or "",
                    "FixedVersion": v.get("FixedVersion") or "",
                    "Severity": sev,
                    "Title": v.get("Title") or "",
                    "Description": v.get("Description") or "",
                    "PrimaryURL": v.get("PrimaryURL") or "",
                }
            )
    return findings


def html_escape(s: str) -> str:
    return html.escape(s or "", quote=True)


def render_html_report(
    scanned: List[Dict[str, Any]],
    generated_at: dt.datetime,
    registry: str,
) -> str:
    """
    scanned: list of dicts like
      {
        "repository": "...",
        "image_ref": "...",
        "pushed_at": datetime,
        "findings": [ ... ],
        "error": "..." (optional)
      }
    """
    # Summary counts
    total_images = len(scanned)
    images_with_findings = sum(1 for x in scanned if x.get("findings"))
    total_findings = sum(len(x.get("findings", [])) for x in scanned)

    # Per-image severity counts
    for x in scanned:
        counts = {"CRITICAL": 0, "HIGH": 0}
        for f in x.get("findings", []):
            counts[f["Severity"]] += 1
        x["sev_counts"] = counts

    # Sort by: errors first, then critical count desc, then high count desc, then repo name
    def sort_key(x):
        err = 1 if x.get("error") else 0
        c = x.get("sev_counts", {}).get("CRITICAL", 0)
        h = x.get("sev_counts", {}).get("HIGH", 0)
        return (-err, -c, -h, x.get("repository", ""))

    scanned_sorted = sorted(scanned, key=sort_key)

    css = """
    body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 24px; }
    h1 { margin: 0 0 8px 0; }
    .meta { color: #444; margin-bottom: 18px; }
    .summary { display: flex; gap: 12px; margin: 16px 0 22px 0; flex-wrap: wrap; }
    .pill { border: 1px solid #ddd; border-radius: 999px; padding: 8px 12px; }
    table { border-collapse: collapse; width: 100%; margin: 10px 0 26px 0; }
    th, td { border: 1px solid #ddd; padding: 8px; vertical-align: top; }
    th { background: #f6f6f6; text-align: left; }
    .repo-card { border: 1px solid #e5e5e5; border-radius: 10px; padding: 14px; margin-bottom: 14px; }
    .repo-title { display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
    .counts { display: flex; gap: 8px; align-items: center; }
    .badge { border-radius: 8px; padding: 4px 8px; border: 1px solid #ddd; font-weight: 600; }
    .crit { }
    .high { }
    .error { color: #b00020; font-weight: 600; }
    .muted { color: #555; }
    .small { font-size: 12px; }
    .nowrap { white-space: nowrap; }
    details { margin-top: 10px; }
    summary { cursor: pointer; font-weight: 600; }
    """

    rows = []
    for item in scanned_sorted:
        repo = item.get("repository", "")
        image_ref = item.get("image_ref", "")
        pushed_at = item.get("pushed_at")
        pushed_str = pushed_at.isoformat() if pushed_at else "unknown"
        counts = item.get("sev_counts", {"CRITICAL": 0, "HIGH": 0})
        err = item.get("error")

        header = f"""
        <div class="repo-card">
          <div class="repo-title">
            <div>
              <div><strong>{html_escape(repo)}</strong></div>
              <div class="muted small">Scanned image: <span class="nowrap">{html_escape(image_ref)}</span></div>
              <div class="muted small">Pushed at: {html_escape(pushed_str)}</div>
            </div>
            <div class="counts">
              <span class="badge crit">CRITICAL: {counts.get("CRITICAL", 0)}</span>
              <span class="badge high">HIGH: {counts.get("HIGH", 0)}</span>
            </div>
          </div>
        """

        if err:
            body = f"""
              <div class="error" style="margin-top:10px;">Scan error: {html_escape(err)}</div>
            </div>
            """
            rows.append(header + body)
            continue

        findings = item.get("findings", [])
        if not findings:
            body = """
              <div class="muted" style="margin-top:10px;">No HIGH/CRITICAL vulnerabilities found.</div>
            </div>
            """
            rows.append(header + body)
            continue

        # Group findings by severity then package
        grouped: Dict[Tuple[str, str], List[Dict[str, Any]]] = defaultdict(list)
        for f in findings:
            grouped[(f["Severity"], f["PkgName"])].append(f)

        # Render table of findings
        table_rows = []
        for (sev, pkg), items in sorted(grouped.items(), key=lambda x: (x[0][0] != "CRITICAL", x[0][1])):
            for f in sorted(items, key=lambda x: x["VulnerabilityID"]):
                url = f.get("PrimaryURL") or ""
                vid = html_escape(f["VulnerabilityID"])
                vid_cell = vid
                if url:
                    vid_cell = f'<a href="{html_escape(url)}" target="_blank" rel="noopener noreferrer">{vid}</a>'

                table_rows.append(
                    f"""
                    <tr>
                      <td class="nowrap">{html_escape(sev)}</td>
                      <td>{vid_cell}</td>
                      <td>{html_escape(pkg)}</td>
                      <td class="nowrap">{html_escape(f.get("InstalledVersion",""))}</td>
                      <td class="nowrap">{html_escape(f.get("FixedVersion",""))}</td>
                      <td>{html_escape(f.get("Target",""))}</td>
                      <td>{html_escape(f.get("Type",""))}</td>
                    </tr>
                    """
                )

        table_html = f"""
          <details open>
            <summary>Vulnerabilities: {len(findings)}</summary>
            <table>
              <thead>
                <tr>
                  <th>Severity</th>
                  <th>Vuln ID</th>
                  <th>Package</th>
                  <th>Installed</th>
                  <th>Fixed</th>
                  <th>Target</th>
                  <th>Type</th>
                </tr>
              </thead>
              <tbody>
                {''.join(table_rows)}
              </tbody>
            </table>
          </details>
        </div>
        """
        rows.append(header + table_html)

    html_doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ECR Trivy Vulnerabilities Report</title>
  <style>{css}</style>
</head>
<body>
  <h1>ECR Trivy Vulnerability Report</h1>
  <div class="meta">
    Registry: <strong>{html_escape(registry)}</strong><br/>
    Generated at: <strong>{html_escape(generated_at.isoformat())}</strong><br/>
  </div>

  <div class="summary">
    <div class="pill">Repositories scanned: <strong>{total_images}</strong></div>
    <div class="pill">Images with vulnerabilities: <strong>{images_with_findings}</strong></div>
    <div class="pill">Total findings: <strong>{total_findings}</strong></div>
  </div>

  {''.join(rows)}
</body>
</html>
"""
    return html_doc


def parse_registry(registry: str) -> Tuple[str, str]:
    """
    From 123456789000.dkr.ecr.us-east-1.amazonaws.com extract:
      account_id, region
    """
    # Expected: <acct>.dkr.ecr.<region>.amazonaws.com
    parts = registry.split(".")
    if len(parts) < 6:
        raise ValueError(f"Unexpected ECR registry format: {registry}")
    account_id = parts[0]
    # parts: [acct, dkr, ecr, us-east-1, amazonaws, com]
    region = parts[3]
    return account_id, region


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ecr-registry", required=True, help="ECR registry URL like 123456789000.dkr.ecr.us-east-1.amazonaws.com")
    ap.add_argument("--region", default=None, help="AWS region (defaults to region parsed from the registry)")
    ap.add_argument("--profile", default=None, help="AWS profile name (optional)")
    ap.add_argument("--out", default="trivy_ecr_report.html", help="Output HTML path")
    ap.add_argument("--no-docker-login", action="store_true", help="Skip docker login step")
    args = ap.parse_args()

    registry = args.ecr_registry.strip()
    _, parsed_region = parse_registry(registry)
    region = args.region or parsed_region

    # boto3 session
    session_kwargs = {"region_name": region}
    if args.profile:
        session_kwargs["profile_name"] = args.profile
    session = boto3.Session(**session_kwargs)
    ecr = session.client("ecr")

    # Optional docker login (recommended)
    if not args.no_docker_login:
        try:
            ecr_docker_login(ecr, registry)
        except Exception as e:
            print(f"[WARN] Docker login failed; continuing anyway. Error: {e}", file=sys.stderr)

    repos = list_all_repositories(ecr)
    if not repos:
        print("No repositories found.", file=sys.stderr)
        sys.exit(1)

    scanned_results: List[Dict[str, Any]] = []
    for repo in sorted(repos, key=lambda r: r.get("repositoryName", "")):
        repo_name = repo["repositoryName"]
        repo_uri = repo.get("repositoryUri") or f"{registry}/{repo_name}"

        latest = None
        try:
            latest = get_latest_image(ecr, repo_name)
            if not latest:
                scanned_results.append(
                    {
                        "repository": repo_name,
                        "image_ref": f"{repo_uri}:<none>",
                        "pushed_at": None,
                        "findings": [],
                        "error": "No images found in repository",
                    }
                )
                continue

            image_ref = build_image_ref(repo_uri, latest)
            pushed_at = latest.get("imagePushedAt")

            print(f"[INFO] Scanning {repo_name} -> {image_ref}", file=sys.stderr)
            trivy_json = trivy_scan_image(image_ref)
            findings = extract_findings(trivy_json)

            scanned_results.append(
                {
                    "repository": repo_name,
                    "image_ref": image_ref,
                    "pushed_at": pushed_at,
                    "findings": findings,
                }
            )

        except Exception as e:
            # Still show which image we attempted (best effort)
            image_ref = ""
            pushed_at = None
            try:
                if latest:
                    image_ref = build_image_ref(repo_uri, latest)
                    pushed_at = latest.get("imagePushedAt")
                else:
                    image_ref = f"{repo_uri}:<unknown>"
            except Exception:
                image_ref = f"{repo_uri}:<unknown>"

            scanned_results.append(
                {
                    "repository": repo_name,
                    "image_ref": image_ref,
                    "pushed_at": pushed_at,
                    "findings": [],
                    "error": str(e),
                }
            )
            print(f"[ERROR] {repo_name} scan failed: {e}", file=sys.stderr)

    generated_at = dt.datetime.now(dt.timezone.utc)
    report_html = render_html_report(scanned_results, generated_at=generated_at, registry=registry)

    out_path = os.path.abspath(args.out)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(report_html)

    print(out_path)


if __name__ == "__main__":
    main()

