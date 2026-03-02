from pydantic import BaseModel, Field


class CateringResponse(BaseModel):
    """
    Structured response from the catering agent.
    """

    status: str | None = Field(..., description="Status indicating missing information or ok")
    question_to_human: str = Field(..., description="Question to ask the human for more information")
    menu: list[dict[str, str | list[str] | float]] = Field(
        ..., 
        description="List of menu items with name, diet_tags, course, and estimated_unit_cost"
    )
    quantities: list[dict[str, str | int]] = Field(
        ..., 
        description="List of quantities for each menu item"
    )
    costs: float = Field(..., description="Total cost for the catering")
    assumptions: list[str] = Field(
        default_factory=list, 
        description="List of assumptions made"
    )
    sources: list[dict[str, str]] = Field(
        default_factory=list, 
        description="List of sources with url and timestamp"
    )