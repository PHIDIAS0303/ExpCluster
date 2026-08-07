---@meta

--- The api documents MapPosition and BoundingBox as a union of the named form
--- and a positional array, because both are accepted as input. Everything read
--- back from the game uses the named form, and we always write it that way too,
--- so the positional variant is removed here.
---@alias MapPosition MapPosition.struct
---@alias BoundingBox BoundingBox.struct
