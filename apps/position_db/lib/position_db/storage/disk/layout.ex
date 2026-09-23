defmodule PositionDB.Storage.Disk.Layout do
  @moduledoc """
  Maps position IDs to physical segment locations.
  """

  @type segment :: non_neg_integer()
  @type offset :: non_neg_integer()

  @spec location(
          pos_integer(),
          pos_integer(),
          pos_integer()
        ) :: {segment(), offset()}
  def location(
        position_id,
        record_size,
        records_per_segment
      )
      when position_id > 0 and
             record_size > 0 and
             records_per_segment > 0 do
    record_index = position_id - 1

    segment =
      div(
        record_index,
        records_per_segment
      )

    slot =
      rem(
        record_index,
        records_per_segment
      )

    {
      segment,
      slot * record_size
    }
  end
end
