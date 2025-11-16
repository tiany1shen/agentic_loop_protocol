from __future__ import annotations
from typing import Protocol, List, Dict, Any, Optional
from abc import abstractmethod
from .messages import BaseMessage, Message


class BaseLLMClient(Protocol):
    """
    Minimal LLM client contract used by Agent / Environment layers.
    Implementations should be async.
    """

    @abstractmethod
    async def chat(
        self,
        messages: List[BaseMessage],
        *,
        model: Optional[str] = None,
        **kwargs: Any,
    ) -> Message:
        """
        Generic multimodal chat. Returns an assistant Message.
        """

    @abstractmethod
    async def chat_json(
        self,
        messages: List[BaseMessage],
        *,
        model: Optional[str] = None,
        schema: Optional[Dict[str, Any]] = None,
        **kwargs: Any,
    ) -> Dict[str, Any]:
        """
        Force JSON-structured output. Returns parsed dict.
        """
