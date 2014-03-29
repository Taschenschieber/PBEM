# (c) 2014 Stephan Hillebrand
#
# This file offers nice error handling. So far, it is mostly a stub.

exports.handle = (error, req, res) ->
  console.log error
  res.send error if res