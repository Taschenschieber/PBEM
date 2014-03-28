# (c) 2014 Stephan Hillebrand
#
# This file handles low-level IMAP stuff, so email.coffee remains clutter-free.

inbox = require "inbox"
MailParser = require("mailparser").MailParser

config = require "./config"
email = require "./email"

parseMailHighLevel = (mail) ->
  console.log "Parsing mail "+mail.messageId
  gameId = getId mail.to[0].address
  return console.log "Malformed incoming mail" unless gameId
  
  message = mail.text # TODO remove quotes / sigs / html
  
  return console.log "Malformed incoming mail - no attachment" unless mail.attachments?.length
    
  #email.handleAttachment gameId, attachment, message

  
getId = (addr) ->
  start = addr.indexOf("+")+1
  unless start >= 0
    return false
  end = addr.indexOf("@")
  unless end > 0
    return false
  if end <= start
    return false
    
  return addr.substring start, end

parseMailLowLevel = (mail, done) ->

  mailparser = new MailParser
  mailparser.on "end", parseMailHighLevel
  
  console.log "Streaming mail ##{mail.UID}"
  stream = imap.createMessageStream mail.UID
  return done new Error "No stream" unless stream
  
  stream.pipe mailparser, {end: true}
  stream.on "end", () ->
    imap.deleteMessage mail.UID, (err) ->
      done err

syncMailbox = () ->
  imap.openMailbox "INBOX", {readOnly: false}, (err, info) ->
    if err
      console.log err
    console.log "#{info.count} new messages in inbox"
    imap.listMessages 0-info.count, (err, messages) ->
      if err
        console.log err
      console.log "Retrieved #{messages.length} messages"
      for message in messages
        parseMailLowLevel message, (err2) ->
          console.log err2 if err2      
  
imap = inbox.createConnection no, "imap.gmail.com", 
  secureConnection: true
  auth: config.email.auth 
  
imap.on "connect", () ->
  console.log "Connected to IMAP server"
  syncMailbox()
          
imap.on "new", () ->
  console.log "Received new e-mail"
  syncMailbox()
    
console.log "Establishing IMAP connection..."
imap.connect()