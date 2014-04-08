# Use this file as a template for server/config.coffee.
exports.email =
  # so far, only gmail is supported!
  service: "Gmail",
  auth:
    user: ""
    pass: ""
    
# what is reported as the "From:" header in sent e-mails.
# Preferrably, this should be in the form "Name <address@domain.tld>".
exports.mailSender = ""

# The server's basic URL, in the form of "http://domain.tld", used to generate
# links to JS / CSS / etc files on the client side.
exports.server =  
  url: ""
  
# The secret for encrypting sessions. Should never be empty in production.  
exports.session = 
  secret: ""

# Set this to "no" for production.  
exports.debug = yes