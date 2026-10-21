"""Stand-ins for the Anthropic SDK so no test spends tokens or needs a real key."""

import json
from types import SimpleNamespace


class FakeResponse:
    def __init__(self, text: str, stop_reason: str = "end_turn", model: str = "claude-opus-5-5",
                 stop_details=None, input_tokens: int = 1200, output_tokens: int = 600) -> None:
        self.content = [SimpleNamespace(type="text", text=text)]
        self.stop_reason = stop_reason
        self.stop_details = stop_details
        self.model = model
        self.usage = SimpleNamespace(input_tokens=input_tokens, output_tokens=output_tokens)


class _Messages:
    def __init__(self, client: "FakeClient", label: str) -> None:
        self._client = client
        self._label = label

    def create(self, **kwargs):
        self._client.calls.append((self._label, kwargs))
        if self._client.create_error is not None:
            raise self._client.create_error
        return self._client.response


class _Models:
    def __init__(self, client: "FakeClient") -> None:
        self._client = client

    def retrieve(self, model_id: str):
        self._client.calls.append(("models.retrieve", {"model": model_id}))
        if self._client.retrieve_error is not None:
            raise self._client.retrieve_error
        return SimpleNamespace(id=model_id)


class FakeClient:
    def __init__(self, response=None, retrieve_error=None, create_error=None) -> None:
        self.calls: list[tuple[str, dict]] = []
        self.response = response
        self.retrieve_error = retrieve_error
        self.create_error = create_error
        self.messages = _Messages(self, "messages")
        self.beta = SimpleNamespace(messages=_Messages(self, "beta.messages"))
        self.models = _Models(self)


def judgment(risks: list[dict]) -> str:
    return json.dumps({"risks": risks})


def entry(evidence_id: str, weight: float = 1.0, note: str = "note") -> dict:
    return {"evidence_id": evidence_id, "weight": weight, "note": note}


def auth_error():
    import anthropic
    import httpx

    request = httpx.Request("GET", "https://api.anthropic.com/v1/models/x")
    return anthropic.AuthenticationError("invalid x-api-key", response=httpx.Response(401, request=request), body=None)
