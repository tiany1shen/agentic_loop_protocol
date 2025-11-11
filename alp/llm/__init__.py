from pydantic import BaseModel, Field
from langchain_openai import ChatOpenAI

from alp.utils import MultiModalMessage


# OpenAI LLM 接口规范 
class LLMRequest(BaseModel):
    model: str
    messages: list[MultiModalMessage]


class LLMResponse(BaseModel):
    id: str
    created: int
    choices: list
    usage: dict
    model: str


class LLMChatClient(ChatOpenAI):
    pass