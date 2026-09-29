# Jason.Encoder impl for `Chess.Position`.
#
# Lives here (rather than in `apps/chess`) for the same reason
# `Chess.Move`'s encoder does: the JSON wire format is defined by
# the SPA's analysis API surface, which is owned by `apps/analysis`.
# `apps/chess` is intentionally dep-free; the only place Jason is
# needed is wherever the encoder is consulted, and Jason is already
# a dep of `apps/analysis`.
#
# The output is exactly `Chess.Position.to_wire/1`. Don't call
# `Jason.Encode.map/2` inside another `defimpl Jason.Encoder` and
# store the iodata result — the outer pass re-interprets iodata as
# a list. Use plain Elixir maps all the way down and call
# `Jason.Encode.map/2` only at the top of an encode function.

defimpl Jason.Encoder, for: Chess.Position do
  def encode(%Chess.Position{} = position, opts) do
    Jason.Encode.map(Chess.Position.to_wire(position), opts)
  end
end
