# (c) 2014 Stephan Hillebrand
#
# This file handles low-level IMAP stuff, so email.coffee remains clutter-free.

imap = require "imap"
MailParser = require("mailparser").MailParser

config = require "./config"
email = require "./email"


mailparser = new MailParser

mailparser.on "end", (mail) ->
  console.log "Starting to parse a mail"
  gameId = mail.to.split("@")[0].split("+")[1]
  return console.log "Malformed incoming mail" unless gameId
  
  message = mail.text # TODO remove quotes / sigs / html
  
  return console.log "Malformed incoming mail - no attachment" unless attachments?.length
  
  email.handleAttachment gameId, attachment, message


