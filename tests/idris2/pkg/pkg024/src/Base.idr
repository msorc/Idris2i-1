module Base

public export
data Colour = Red | Green | Blue

public export
next : Colour -> Colour
next Red = Green
next Green = Blue
next Blue = Red
