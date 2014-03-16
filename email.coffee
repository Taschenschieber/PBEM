# contains all e-mail related functions - setup, sending and later receiving mail


# Please note: "config.coffee" is not included in the public github because
# it contains credentials for e-mail transport. 
config = require "./config"


# set up mail transport
nodemailer = require "nodemailer"
transport = nodemailer.createTransport "SMTP", config.email




# send a newly-registered user an e-mail asking him to confirm his address
# user = the relevant database entry (conforming to UserSchema)
# callback receives an error or null as first argument, no other args
#
# TODO Make the e-mail fancier, probably even including HTML
exports.sendConfirmationMail = (user, callback) ->
  transport.sendMail
    from: config.mailSender
    to: user.email
    generateTextFromHTML: true
    subject: "Account validation"
    html: "<p>Your account needs to be validated. Please click the following link or copy it into your browser, should that not be possible.</p>
    
    <p><a href='http://"+config.server.url+"/validate/"+user._id+"/"+user.validationToken+">http://"+config.server.url+"/validate/"+user._id+"/"+user.validationToken+"</a></p>
    
    <p>You will only be able to log in to your account once you took this measure.</p>
    
    <p>If you did not create an account, please ignore this e-mail. Your
    address will be automatically deleted out of our database soon.</p>"
    
  , (err, res) ->
      callback err, res