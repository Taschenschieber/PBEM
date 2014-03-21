# (c) 2014 Stephan Hillebrand
#
# This file offers nice error handling. So far, it is mostly a stub.

exports.handle = (req, res, error) ->
  console.log error
  res.send error if res