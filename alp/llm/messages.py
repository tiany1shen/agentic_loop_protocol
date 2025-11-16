from __future__ import annotations
from typing import Any, Optional, Protocol, Type, Union, Literal
from pydantic import BaseModel, Field, ValidationError

from langchain_core.messages import (
    BaseMessage as LCBaseMessage,
    HumanMessage as LCHumanMessage,
    AIMessage as LCAIMessage,
    SystemMessage as LCSystemMessage,
    ChatMessage as LCChatMessage,
)


# ============================================================
# 1) Protocol (interface)
# ============================================================
class MessageProtocol(Protocol):
    """
    Provider-agnostic message protocol. Implementations must provide:
    - role: str
    - content: Union[str, list[MessageBlock]]
    - metadata: dict
    - helpers: is_multimodal(), to_dict(), to_langchain(), from_langchain()
    """
    role: str
    content: Union[str, list["MessageBlock"]]
    metadata: dict[str, Any]

    def is_multimodal(self) -> bool: ...
    def to_dict(self) -> dict[str, Any]: ...
    def to_langchain(self) -> "LCBaseMessage": ...
    @classmethod
    def from_langchain(cls: Type["MessageProtocol"], msg: "LCBaseMessage") -> "MessageProtocol": ...


# ============================================================
# 2) MessageBlock 抽象与实现（严格的 block 类型）
# ============================================================
class MessageBlock(BaseModel):
    """Base class for message blocks. Concrete blocks must set `type`."""
    type: str = Field(...)

    def to_dict(self) -> dict[str, Any]:
        return self.model_dump()

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "MessageBlock":
        # Basic factory: pick subclass by "type"
        if (t := data.get("type")) is None:
            raise ValueError("Block dict missing 'type' field")
        mapping = {
            "text": TextBlock,
            "image": ImageBlock,
            "audio": AudioBlock,
            "tool_call": ToolCallBlock,
            "tool_result": ToolResultBlock,
        }
        sub = mapping.get(t)
        if not sub:
            raise ValueError(f"Unknown block type: {t}")
        return sub.model_validate(data)  # pydantic v2


class TextBlock(MessageBlock):
    type: Literal["text"] = "text"
    text: str = Field(...)


class ImageBlock(MessageBlock):
    type: Literal["image"] = "image"
    # Use either url or binary data. Prefer storing url or reference; binary allowed for in-process.
    url: Optional[str] = None
    data: Optional[bytes] = None
    mime_type: Optional[str] = "image/png"

    def model_post_init(self, __context: Any) -> None:  # ensure at least one of url/data
        if not (self.url or self.data):
            raise ValueError("ImageBlock requires either 'url' or 'data'.")


class AudioBlock(MessageBlock):
    type: Literal["audio"] = "audio"
    url: Optional[str] = None
    data: Optional[bytes] = None
    mime_type: Optional[str] = "audio/wav"


class ToolCallBlock(MessageBlock):
    type: Literal["tool_call"] = "tool_call"
    name: str = Field(...)
    arguments: dict[str, Any] = Field(default_factory=dict)


class ToolResultBlock(MessageBlock):
    type: Literal["tool_result"] = "tool_result"
    name: str = Field(...)
    result: Any = Field(...)


# ============================================================
# 3) Message (Pydantic 实现) — content 更窄：str | list[MessageBlock]
# ============================================================
class Message(BaseModel):
    """
    Strict Message model:
      - role: one of user/assistant/system/tool (can be extended)
      - content: either plain text (str) or a list of MessageBlock
      - metadata: arbitrary dict for trace/tool/source/etc.
    """
    role: str = Field(...)
    content: Union[str, list[MessageBlock]] = Field(...)
    metadata: dict[str, Any] = Field(default_factory=dict)

    # -------------------------
    # helpers / factories
    # -------------------------
    def is_multimodal(self) -> bool:
        return isinstance(self.content, list)

    def to_dict(self) -> dict[str, Any]:
        """
        Export to plain dict suitable for HTTP/SDK usage.
        Blocks are converted to dicts.
        """
        base = {"role": self.role, "metadata": self.metadata.copy()}
        if isinstance(self.content, str):
            base["content"] = self.content
        else:
            base["content"] = [b.to_dict() for b in self.content]
        return base

    @staticmethod
    def text(role: str, text: str, metadata: Optional[dict[str, Any]] = None) -> "Message":
        return Message(role=role, content=text, metadata=metadata or {})

    @staticmethod
    def blocks(role: str, blocks: list[MessageBlock], metadata: Optional[dict[str, Any]] = None) -> "Message":
        # validate blocks are of correct types
        validated: list[MessageBlock] = []
        for b in blocks:
            if isinstance(b, MessageBlock):
                # pydantic model, but ensure it's concrete subclass
                if isinstance(b, (TextBlock, ImageBlock, AudioBlock, ToolCallBlock, ToolResultBlock)):
                    validated.append(b)  # type: ignore[arg-type]
                else:
                    raise TypeError("Unsupported MessageBlock subclass")
            elif isinstance(b, dict):
                # allow dicts (will validate)
                validated.append(MessageBlock.from_dict(b))  # type: ignore[call-arg]
            else:
                raise TypeError("blocks must be MessageBlock instances or dicts")
        return Message(role=role, content=validated, metadata=metadata or {})

    # -------------------------
    # LangChain conversion
    # -------------------------
    def to_langchain(self) -> "LCBaseMessage":
        """
        Convert to LangChain BaseMessage.
        - If content is str -> use Human/AI/System by role
        - If content is blocks -> convert to list-of-dicts and pass as content
        """
        content_payload: Any
        if isinstance(self.content, str):
            content_payload = self.content
        else:
            content_payload = [b.to_dict() for b in self.content]

        rl = self.role.lower()
        if rl in ("user", "human"):
            return LCHumanMessage(content=content_payload, additional_kwargs=self.metadata)
        if rl in ("assistant", "ai"):
            return LCAIMessage(content=content_payload, additional_kwargs=self.metadata)
        if rl == "system":
            return LCSystemMessage(content=content_payload, additional_kwargs=self.metadata)
        # fallback generic
        return LCChatMessage(role=self.role, content=content_payload, additional_kwargs=self.metadata)

    @classmethod
    def from_langchain(cls, msg: "LCBaseMessage") -> "Message":
        """
        Build Message from LangChain message. We try to infer role and convert content:
          - if content is str -> content as text
          - if content is list/dict -> try to convert each block via MessageBlock.from_dict when possible
        """
        # determine role
        role = getattr(msg, "role", None)
        if role is None:
            name = msg.__class__.__name__.lower()
            if "human" in name:
                role = "user"
            elif "ai" in name or "assistant" in name:
                role = "assistant"
            elif "system" in name:
                role = "system"
            else:
                role = "user"

        # get content and metadata
        content_raw = getattr(msg, "content", None)
        metadata = getattr(msg, "additional_kwargs", {}) or {}

        # convert content
        if isinstance(content_raw, str) or content_raw is None:
            return cls(role=role, content=content_raw or "", metadata=metadata)
        # if it's a single dict representing structured content, or list of parts
        try:
            if isinstance(content_raw, dict):
                # try to interpret as one block
                blk = MessageBlock.from_dict(content_raw)
                return cls(role=role, content=[blk], metadata=metadata)
            elif isinstance(content_raw, list):
                blocks: list[MessageBlock] = []
                for item in content_raw:
                    if isinstance(item, dict):
                        blocks.append(MessageBlock.from_dict(item))
                    else:
                        # if it's simple text part (e.g. "hello"), wrap as TextBlock
                        if isinstance(item, str):
                            blocks.append(TextBlock(text=item))
                        else:
                            # unknown structure -> keep as generic text block with repr
                            blocks.append(TextBlock(text=str(item)))
                return cls(role=role, content=blocks, metadata=metadata)
        except (ValidationError, ValueError):
            # fallback: stringify content
            return cls(role=role, content=str(content_raw), metadata=metadata)

        # ultimate fallback
        return cls(role=role, content=str(content_raw), metadata=metadata)


# runtime registration so isinstance checks against Protocol may pass (optional)
try:
    MessageProtocol.register(Message)  # type: ignore[arg-type]
except Exception:
    pass


# ============================================================
# 4) Aliases
# ============================================================
Messagelist = list[Message]
MessageBlockType = ConcreteBlock


# ============================================================
# 5) Small examples (docstring style; not executed)
# ============================================================
"""
Usage examples:

# text message
m1 = Message.text("user", "Hello")

# image message (by url)
img = ImageBlock(url="https://example.com/img.png")
m2 = Message.blocks("user", [TextBlock(text="Describe this image"), img])

# tool call
tcall = ToolCallBlock(name="lookup", arguments={"q":"pineapple"})
m3 = Message.blocks("assistant", [tcall])

# convert to langchain
lc_msg = m2.to_langchain()

# parse from langchain
m_parsed = Message.from_langchain(lc_msg)
"""
