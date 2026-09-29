# Jason.Encoder impl for `Chess.Move`.
#
# Lives here (rather than in `apps/chess`) because the JSON wire
# format is defined by the SPA's analysis API surface, which is owned
# by `apps/analysis`. This also keeps `apps/chess` dep-free; the only
# place Jason is needed is wherever the encoder is consulted, and
# Jason is already a dep of `apps/analysis`.
#
# The promotion atom becomes a lowercase string so the wire format is
# the same shape the SPA sends to
# `/api/rooms/:code/analyses/:id/move`; a
# non-promotion move is `null`. The full output shape is therefore:
#
#     {"from": 12, "to": 28, "promotion": null}
#     {"from": 52, "to": 60, "promotion": "queen"}
defimpl Jason.Encoder, for: Chess.Move do
  def encode(%Chess.Move{from: from, to: to, promotion: promotion}, opts) do
    Jason.Encode.map(
      %{from: from, to: to, promotion: encode_promotion(promotion)},
      opts
    )
  end

  defp encode_promotion(nil), do: nil
  defp encode_promotion(promotion) when is_atom(promotion), do: Atom.to_string(promotion)
end
