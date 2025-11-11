from pydantic import BaseModel, Field
from datetime import datetime


class Message(BaseModel):
    role: str
    content: str
    timestamp: datetime = Field(default=datetime.now())
    metadata: dict = Field(default={})


class MultiModalMessage(Message):
    content: str | list[dict]


if __name__ == "__main__":
    msg = Message(role="user", content="Hello World")
    
    print(msg.model_dump_json())