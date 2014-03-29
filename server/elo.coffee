# (c) 2014 Stephan Hillebrand
#
# This file contains the math for calculating ELO ratings.

# Rating Expectation
exp = (own, opponent) ->
  1 / (1+Math.pow(10, (opponent - own) / 400))

# New Rating
exports.newr = (own, opponent, won) ->
  Math.floor own + kFactor(own)*(won - exp(own, opponent)), 100
  # no rating lower than 100 should be possible
  
kFactor = (rating) ->
  32 # TODO: Choose more accurate model