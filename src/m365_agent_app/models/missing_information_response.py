from pydantic import BaseModel, Field


class MissingInformationResponse(BaseModel):
    """
    Structured response indicating missing information.
    """

    status: str | None = Field(default="missing_information", description="Status indicating missing information")
    question_to_human: str = Field(..., description="Question to ask the human for more information")