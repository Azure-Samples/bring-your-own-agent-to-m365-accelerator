from typing import Annotated

from pydantic import Field


class ComputePricingTools():
    def addition(self, a: Annotated[int, Field(description="The first number to add")], b: Annotated[int, Field(description="The second number to add")]) -> int:
        """Add two numbers together."""
        return a + b

    def multiplication(self, a: Annotated[int, Field(description="The first number to multiply")], b: Annotated[int, Field(description="The second number to multiply")]) -> int:
        """Multiply two numbers together."""
        return a * b

    def pricing_with_tax(self, base_price: Annotated[float, Field(description="The base price of the item")]) -> float:
        """Calculate the final price including tax."""
        return base_price * (1.25)  # Assuming a tax rate of 25%
