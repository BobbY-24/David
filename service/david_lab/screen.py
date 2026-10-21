"""Instruction-override screening, ported from lib/src/control/rails.dart.

Evidence pasted by a user is third-party text. A unit that tries to instruct
the model is quarantined when it is written, so it is never sent. The patterns
and the normalization must match the Dart rules; `quarantine_golden` in
cases.json holds rows from the desk that the tests check.
"""

import re

_INVISIBLE = re.compile("[­​-‏⁠﻿]")
_NON_WORD = re.compile(r"[^a-z0-9]+")

INSTRUCTION_OVERRIDES = [
    re.compile(r"\bignore (?:all |any |the |your |of |these |those )*(?:previous|prior|above|earlier|preceding)\b"),
    re.compile(r"\b(?:disregard|forget|override|bypass) (?:all |any |the |your |these |those |previous |prior |above |earlier )*(?:instructions|rules|policy|guardrails|prompt)\b"),
    re.compile(r"\bnew instructions\b"),
    re.compile(r"\byou are now\b"),
    re.compile(r"\bact as (?:an? |the )?(?:admin|administrator|developer|system|root)\b"),
    re.compile(r"\bsystem prompt\b"),
    re.compile(r"\bexfiltrate\b"),
    re.compile(r"\breveal (?:the |your )?(?:api key|secret|password|token)s?\b"),
]


def normalize_for_screen(text: str) -> str:
    visible = _INVISIBLE.sub("", text.lower())
    return " " + _NON_WORD.sub(" ", visible).strip() + " "


def contains_instruction_override(text: str) -> bool:
    normalized = normalize_for_screen(text)
    return any(pattern.search(normalized) for pattern in INSTRUCTION_OVERRIDES)
