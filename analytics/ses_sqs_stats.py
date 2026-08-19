#!/usr/bin/env python3
"""Scan the SES events SQS queue and print delivery / open / click stats.

Messages are read and then made visible again. They are not deleted unless
you pass --delete.

Example:
    python analytics/ses_sqs_stats.py --subject "Re: Veterans Affairs Enterprise AI RFI"
    python analytics/ses_sqs_stats.py --list-subjects
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict

import boto3


DEFAULT_QUEUE_NAME = "ses-argorand-events-queue"
DEFAULT_REGION = "us-east-1"
MAX_MESSAGES = 10
WAIT_SECONDS = 5
VISIBILITY_TIMEOUT = 600
EMPTY_POLLS_TO_STOP = 2

# SES uses these eventType values with configuration-set event publishing.
TRACKED_EVENTS = ("Delivery", "Open", "Click")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Mini-stats for SES events in SQS, filtered by email Subject."
    )
    parser.add_argument(
        "--subject",
        help="Exact Subject to filter on (case-insensitive). Required unless --list-subjects.",
    )
    parser.add_argument(
        "--list-subjects",
        action="store_true",
        help="Print unique Subject values found in the queue and exit.",
    )
    parser.add_argument(
        "--contains",
        action="store_true",
        help="Match Subject as a case-insensitive substring instead of an exact match.",
    )
    parser.add_argument("--queue-name", default=DEFAULT_QUEUE_NAME)
    parser.add_argument("--queue-url", help="Full SQS queue URL. Overrides --queue-name.")
    parser.add_argument("--region", default=DEFAULT_REGION)
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete messages after reading. Default is to restore visibility so they stay in the queue.",
    )
    return parser.parse_args()


def unwrap_body(raw_body: str) -> dict:
    """Parse an SQS body that may be SES JSON or an SNS envelope around it."""
    payload = json.loads(raw_body)
    if isinstance(payload, dict) and payload.get("Type") == "Notification" and "Message" in payload:
        inner = payload["Message"]
        payload = json.loads(inner) if isinstance(inner, str) else inner
    if not isinstance(payload, dict):
        raise ValueError("Unexpected SQS payload type")
    return payload


def event_type(event: dict) -> str:
    return event.get("eventType") or event.get("notificationType") or "Unknown"


def event_subject(event: dict) -> str:
    mail = event.get("mail") or {}
    common = mail.get("commonHeaders") or {}
    subject = common.get("subject")
    if subject:
        return subject
    for header in mail.get("headers") or []:
        if str(header.get("name", "")).lower() == "subject":
            return header.get("value") or ""
    return ""


def event_message_id(event: dict) -> str:
    mail = event.get("mail") or {}
    return mail.get("messageId") or ""


def event_recipients(event: dict) -> list[str]:
    mail = event.get("mail") or {}
    destination = mail.get("destination") or []
    if destination:
        return destination
    common = mail.get("commonHeaders") or {}
    return common.get("to") or []


def subject_matches(actual: str, wanted: str, contains: bool) -> bool:
    left = actual.casefold()
    right = wanted.casefold()
    return right in left if contains else left == right


def drain_queue(sqs, queue_url: str, delete: bool) -> list[dict]:
    """Receive every currently visible message. Does not delete unless delete=True."""
    seen_ids: set[str] = set()
    receipt_handles: list[str] = []
    events: list[dict] = []
    empty_polls = 0
    parse_errors = 0

    while empty_polls < EMPTY_POLLS_TO_STOP:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=MAX_MESSAGES,
            WaitTimeSeconds=WAIT_SECONDS,
            VisibilityTimeout=VISIBILITY_TIMEOUT,
            MessageAttributeNames=["All"],
            AttributeNames=["All"],
        )
        messages = response.get("Messages") or []
        if not messages:
            empty_polls += 1
            continue
        empty_polls = 0

        for message in messages:
            message_id = message["MessageId"]
            receipt_handles.append(message["ReceiptHandle"])
            if message_id in seen_ids:
                continue
            seen_ids.add(message_id)
            try:
                events.append(unwrap_body(message["Body"]))
            except (json.JSONDecodeError, ValueError, TypeError):
                parse_errors += 1

    if delete:
        for i in range(0, len(receipt_handles), 10):
            sqs.delete_message_batch(
                QueueUrl=queue_url,
                Entries=[
                    {"Id": str(j), "ReceiptHandle": handle}
                    for j, handle in enumerate(receipt_handles[i : i + 10])
                ],
            )
    else:
        for i in range(0, len(receipt_handles), 10):
            sqs.change_message_visibility_batch(
                QueueUrl=queue_url,
                Entries=[
                    {"Id": str(j), "ReceiptHandle": handle, "VisibilityTimeout": 0}
                    for j, handle in enumerate(receipt_handles[i : i + 10])
                ],
            )

    if parse_errors:
        print(f"Skipped {parse_errors} message(s) that were not valid SES JSON.", file=sys.stderr)

    return events


def print_subject_list(events: list[dict]) -> None:
    counts: Counter[str] = Counter()
    for event in events:
        counts[event_subject(event) or "(no subject)"] += 1
    print(f"Scanned {len(events)} event(s). Unique subjects:\n")
    for subject, count in counts.most_common():
        print(f"  {count:5d}  {subject}")


def print_stats(events: list[dict], subject: str, contains: bool) -> None:
    matched = [e for e in events if subject_matches(event_subject(e), subject, contains)]
    type_counts: Counter[str] = Counter(event_type(e) for e in matched)
    unique_messages: dict[str, set[str]] = defaultdict(set)
    unique_recipients: dict[str, set[str]] = defaultdict(set)

    for event in matched:
        kind = event_type(event)
        mid = event_message_id(event)
        if mid:
            unique_messages[kind].add(mid)
        for recipient in event_recipients(event):
            unique_recipients[kind].add(recipient)

    match_label = "containing" if contains else "equal to"
    print(f"Scanned {len(events)} event(s); {len(matched)} matched Subject {match_label} {subject!r}.\n")

    if not matched:
        found = sorted({event_subject(e) for e in events if event_subject(e)})
        if found:
            print("No matches. Subjects present in the queue:")
            for value in found:
                print(f"  - {value}")
        else:
            print("No matches, and no Subject headers were found on scanned events.")
        return

    print(f"{'Event':<16} {'Events':>8} {'Unique emails':>15} {'Unique recipients':>18}")
    print("-" * 59)
    for kind in TRACKED_EVENTS:
        print(
            f"{kind:<16} {type_counts[kind]:8d} "
            f"{len(unique_messages[kind]):15d} {len(unique_recipients[kind]):18d}"
        )

    extras = sorted(k for k in type_counts if k not in TRACKED_EVENTS)
    if extras:
        print("\nOther event types for this Subject:")
        for kind in extras:
            print(f"  {kind}: {type_counts[kind]}")

    delivered = len(unique_messages["Delivery"])
    opened = len(unique_messages["Open"])
    clicked = len(unique_messages["Click"])
    if delivered:
        print("\nRates (unique emails / unique deliveries):")
        print(f"  Open rate:  {opened / delivered:.1%}")
        print(f"  Click rate: {clicked / delivered:.1%}")


def main() -> int:
    args = parse_args()
    if not args.list_subjects and not args.subject:
        print("Pass --subject or --list-subjects.", file=sys.stderr)
        return 2

    sqs = boto3.client("sqs", region_name=args.region)
    queue_url = args.queue_url or sqs.get_queue_url(QueueName=args.queue_name)["QueueUrl"]

    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"],
    )["Attributes"]
    print(
        f"Queue {queue_url}\n"
        f"Approximate visible: {attrs.get('ApproximateNumberOfMessages', '?')}, "
        f"in flight: {attrs.get('ApproximateNumberOfMessagesNotVisible', '?')}\n"
    )

    events = drain_queue(sqs, queue_url, delete=args.delete)
    if args.delete:
        print(f"Deleted {len(events)} unique message(s) from the queue.\n")

    if args.list_subjects:
        print_subject_list(events)
        return 0

    print_stats(events, args.subject, args.contains)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
