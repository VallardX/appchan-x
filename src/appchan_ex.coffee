$.extend Style.color, {
  toHex: (color) ->
    if color.substr(0, 1) is '#'
      return color.slice 1, color.length

    if digits = color.match /(.*?)rgba?\((\d+), ?(\d+), ?(\d+)(.*?)\)/
      # [R, G, B] to 0xRRGGBB
      hex = (
        (parseInt(digits[2], 10) << 16) |
        (parseInt(digits[3], 10) << 8)  |
        (parseInt(digits[4], 10))
      ).toString 16

      while hex.length < 6
        hex = "0#{hex}"
    else
      hex = "000000"
    hex

  calc_rgb: (hex) ->
    hex = parseInt hex, 16

    # 0xRRGGBB to [R, G, B]
    [
      (hex >> 16) & 0xFF
      (hex >> 8) & 0xFF
      hex & 0xFF
    ]

  isLight: ->
    rgb = @private_rgb
    return (rgb[0] + rgb[1] + rgb[2]) >= 400

  shiftRGB: (shift, smart) ->
    minmax = (base) ->
      Math.min Math.max(base, 0), 255
    rgb = @private_rgb.slice 0
    shift = if smart
      (
        if @isLight rgb
          -1
        else
          1
      ) * Math.abs shift
    else
      shift

    return [ 
      minmax rgb[0] + shift
      minmax rgb[1] + shift
      minmax rgb[2] + shift
    ].join ","

}