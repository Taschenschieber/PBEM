# (c) 2014 Stephan Hillebrand
#
# This file handles low-level IMAP stuff, so email.coffee remains clutter-free.

fs = require "fs"
inbox = require "inbox"
MailParser = require("mailparser").MailParser
tmp = require "tmp"

config = require "./config"
database = require "./database"
email = require "./email"
gameLogic = require "./games/logic"

parseMailHighLevel = (mail) ->
  console.log "Parsing mail "+mail.messageId
  gameId = getId mail.to[0].address
  from = mail.from[0].address
  return sendLogErrMail from, "Malformed incoming mail" unless gameId
  
  message = mail.text # TODO remove quotes / sigs / html
  
  return sendLogErrMail from, "Malformed incoming mail - no attachment" unless mail.attachments?.length
  
  # find out which user sent the log
  database.User.findOne
    email: from
  .select "name password"
  .exec (err, user) ->
    if err
      console.log err
      return sendLogErrMail from, err.message
    if not user
      return sendLogErrMail from, "Your address is not associated with any account."
    if user.banned
      return
    
    log = new database.Log
      sentBy: user.name
      empty: false 
      message: message
      # TODO find a way to parse first and last phase
      #firstPhase: req.body.firstPhase
      #lastPhase: req.body.lastPhase
  
    database.Game.findOne
      _id: gameId
    .exec (err, game) ->
      if err
        sendLogErrMail from, err.message
        console.log err
      if not game
        sendLogErrMail from, "The game ID is invalid."
  
      # get tmp file name
      tmp.tmpName {template: "./uploads/mail-XXXXXXXX"}, (err, file) ->
        fs.writeFile file, mail.attachments[0].content, (err) ->
          if err 
            console.log err
            return sendLogErrMail from, err.message
  
          gameLogic.addLog log, file, game, user, (err) ->
            if err
              console.log err
              return sendLogErrMail from, err.message
            # in case of success, no confirmation is necessary.
            # all further actions are taken by gameLogic.
        
sendLogErrMail = (a, b)->
  email.sendLogErrMail a, b
 
  
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