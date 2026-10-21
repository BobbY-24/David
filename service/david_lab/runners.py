"""Deterministic demo scorer for due-diligence engagements.

This is not a live model and not legal, credit, or investment advice. Each
result carries the scorer id so a caller can tell a demo score from a
provider response.
"""

import json
import re
from pathlib import Path

from sqlalchemy.orm import Session

from . import SCORER_ID
from .errors import PermanentJobError

# Exported from the desk by `dart run tool/export_cases.dart`. The desk
# engagement packs are the only place an engagement is written.
_EXPORT = json.loads((Path(__file__).with_name("cases.json")).read_text())
_CASES = {case["id"]: case for case in _EXPORT["cases"]}

_WORD = re.compile(r"[a-z0-9]+")
_SENTENCE_BREAK = re.compile(r"[.;!?](?=\s|$)|\n")
_NEGATIONS = frozenset({"no", "not", "without", "never", "none"})
# Same list as `indexStopwords` in lib/src/retrieval/text_match.dart.
_STOPWORDS = frozenset(
    {
        "a",
        "an",
        "the",
        "of",
        "and",
        "to",
        "for",
        "in",
        "on",
        "with",
        "from",
        "by",
        "is",
        "are",
        "was",
        "were",
        "this",
        "that",
        "as",
        "at",
        "or",
        "be",
        "it",
        "its",
        "into",
        "over",
        "than",
        "then",
        "during",
        "while",
        "across",
        "under",
        "after",
        "before",
        "between",
    }
)
_NEGATION_WINDOW = int(_EXPORT["negation_window"])
_RESOLVE_MARGIN = 0.45


def phrase_tokens(value: str) -> list[str]:
    return _WORD.findall(value.lower().replace("'", ""))


def _negated_before(tokens: list[str], start: int) -> bool:
    content = 0
    k = start - 1
    while k >= 0 and content < _NEGATION_WINDOW:
        token = tokens[k]
        if token in _NEGATIONS:
            return True
        if token not in _STOPWORDS:
            content += 1
        k -= 1
    return False


def phrase_matches(corpus: str, phrase: str) -> bool:
    """Port of `phraseMatches` in lib/src/retrieval/text_match.dart.

    Sentence-scoped, and a negation reaches three content tokens back.
    `tests/test_jobs.py` checks this against every verdict the desk exported.
    """
    need = phrase_tokens(phrase)
    if not need:
        return False
    for sentence in _SENTENCE_BREAK.split(corpus):
        tokens = phrase_tokens(sentence)
        for i in range(len(tokens) - len(need) + 1):
            if tokens[i : i + len(need)] == need and not _negated_before(tokens, i):
                return True
    return False


def _score_case(case: dict) -> dict:
    usable = [unit["text"] for unit in case["evidence"] if not unit["quarantined"]]

    def fired(signatures: list) -> tuple[float, list[str]]:
        hits = [(phrase, weight) for phrase, weight in signatures if any(phrase_matches(t, phrase) for t in usable)]
        return sum(weight for _, weight in hits), [phrase for phrase, _ in hits]

    scored = []
    for risk in case["risk_questions"]:
        support, support_fired = fired(risk["support"])
        against, against_fired = fired(risk["contradict"])
        scored.append(
            {
                "id": risk["id"],
                "title": risk["title"],
                "net": support - against,
                "fired": support_fired,
                "falsified_by": against_fired,
            }
        )
    scored.sort(key=lambda item: (-item["net"], item["id"]))
    lead = scored[0]
    runner = scored[1] if len(scored) > 1 else None
    margin = lead["net"] - (runner["net"] if runner else 0.0)
    held = lead["net"] <= 0 or margin < _RESOLVE_MARGIN
    return {
        "lead": None if held else lead["id"],
        "title": None if held else lead["title"],
        "margin": margin,
        "fired": [] if held else lead["fired"],
        "held": held,
        "ranked": [{"id": item["id"], "net": round(item["net"], 3)} for item in scored],
    }


def engagement(spec: dict, session: Session) -> dict:
    del session
    case_id = str(spec.get("case_id") or "")
    case = _CASES.get(case_id)
    if case is None:
        raise PermanentJobError(f"Unknown engagement '{case_id}'.")
    scored = _score_case(case)
    if scored["held"]:
        headline = f"{case['title']} stayed held. Margin {scored['margin']:.2f}."
    else:
        headline = f"{scored['title']} leads {case['title']}."
    return {
        "fixture": True,
        "scorer": SCORER_ID,
        "kind": "engagement",
        "case_id": case_id,
        "deal_type": case["deal_type"],
        "loop": case["loop"],
        "lead": scored["lead"],
        "headline": headline,
        "detail": (
            "Service-side demo scorer for throughput. The desk agent remains "
            "the citation path. Fired: " + ", ".join(scored["fired"] or ["none"]) + "."
        ),
        "fired": scored["fired"],
        "approval": "No payment, signature, order, or message is available on this job.",
    }


def probe(spec: dict, session: Session) -> dict:
    del session
    return {
        "fixture": True,
        "scorer": SCORER_ID,
        "kind": "probe",
        "lead": "ok",
        "headline": "Probe completed.",
        "detail": "Load-test probe. Not a model response.",
        "sleep_ms": int(spec.get("sleep_ms") or 0),
    }


_RUNNERS = {
    "engagement": engagement,
    "probe": probe,
}


def run(kind: str, spec: dict, session: Session) -> dict:
    runner = _RUNNERS.get(kind)
    if runner is None:
        raise PermanentJobError(f"Unknown job kind '{kind}'.")
    return runner(spec, session)


def catalog() -> list[dict]:
    return [
        {
            "kind": "engagement",
            "title": case["title"],
            "blurb": f"{case['deal_type'].title()} check on the demo scorer. The desk writes the cited memo.",
            "spec": {"case_id": case["id"]},
        }
        for case in _EXPORT["cases"]
    ]
