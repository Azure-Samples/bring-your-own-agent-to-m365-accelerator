from pydantic import BaseModel, Field


class EventMediaValidatorResponse(BaseModel): 
    """
    Structured response from the event media validator agent.
    """
    approved: bool = Field(..., description="Indicates if the media assets are approved")
    score: int = Field(..., ge=0, le=100, description="Quality score of the media assets (0-100)")
    suggested_edits: list[str] = Field(
        ...,
        description="List of suggested edits to improve the media assets",
        examples=[["Make the event name more engaging.", "Clarify the target audience in the description."]]
    )
    final_name: str = Field(..., description="Final approved event name", examples=["Innovate 2024 Conference"])
    final_description: str = Field(..., description="Final approved event description", examples=["Join us for a day of innovation and networking at Innovate 2024."])    
    final_linkedin_post: str = Field(..., description="Final approved LinkedIn post content", examples=["Excited to announce the Innovate 2024 Conference! Don't miss out on a day full of insights and networking opportunities. #Innovate2024 #TechConference"])
    revised_post: str = Field(..., description="Revised LinkedIn post content after applying suggestions", examples=["Join us at Innovate 2024 for a day of innovation and networking!"])
