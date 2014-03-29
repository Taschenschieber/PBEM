# contains all e-mail related functions - setup, sending and later receiving mail

nodemailer = require "nodemailer"

# Please note: "config.coffee" is not included in the public github because
# it contains credentials for e-mail transport. 
config = require "./config"
database = require "./database"
emailimap = require "./email-imap"

# set up mail transport
transport = nodemailer.createTransport "SMTP", config.email

# Create a tagged mail address for log files sent to the server
generateReplyMail = (mail, id) ->
  split = mail.split "@"
  if split.length != 2
    console.log "Malformed e-mail encountered, return mail failed."
    return mail
  return "#{split[0]}+#{id}@#{split[1]}"


# notify a user about a new log file
exports.sendLogMail = (game, callback) ->
  console.log "sendLogMail called"
  if not game?.logs?.length
    return callback new Error("Faulty game data.")
  
  recipient = ""
  if game.logs[game.logs.length-1].sentBy == game.playerA
    recipientName = game.playerB
    opponent = game.playerA
  else
    recipientName = game.playerA
    opponent = game.playerB
    
  # retrieve e-mail and notification settings for recipient from DB
  database.User.findOne
    name: recipientName
  .select "email notifications name"
  .exec (err, user) ->
    if err
      console.log "sendLogMail aborting due to error"
      return callback err
    unless user
      console.log "sendLogMail aborting due to missing user data"
      return callback new Error "No such user"
    
    unless user.notifications?.onNewLog
      console.log "Skipping mail for #{user.name}, not requested"
      return callback null, null
    
    text = "
      <h1>Hello, #{recipientName}!</h1>
      
      <p>A new log file was just uploaded in your match against #{opponent}.</p>
      

      <ul>
      <li><a href='http://#{config.server.url}/logfiles/#{game._id}/#{game.logs[game.logs.length-1]._id}.vlog'>
          Download the log file</a></li>
      <li><a href='http://#{config.server.url}/game/#{game._id}'>Open game in browser</a></li>
      </ul>
    "
    
    attachments = []
    if user.notifications?.onNewLogWithLog
      text += "<p>Additionally, the new log file is also attached to this e-mail.</p>"
      attachments.push
        fileName: "latest.vlog"
        filePath: "./pub/logfiles/#{game._id}/#{game.logs[game.logs.length-1]._id}.vlog"
      
      
    text += "<p>You can either upload your log file on the web site linked 
      above, or you can simply reply to this e-mail with the log file attached.
      Make sure to use the 'Reply' button in your mail client. You can also add
      a message for your opponent in the mail.</p>
      
      <p>You can change your notification settings at any time in 
      <a href='http://#{config.server.url}/account'>your account settings</a>.</p>
      
      <p>Roll low and COWTRA!</p>
      "
      
    console.log "Sending log notification to ", user.email  
    
    transport.sendMail
      from: config.mailSender
      replyTo: generateReplyMail config.mailSender, game.id
      to: user.email
      subject: "It's your turn in #{game.scenario.title || 'one of your VASL games'}!"
      generateTextFromHTML: on
      html: text
      attachments: attachments
    , (err, res) ->
      callback err, res

exports.handleAttachment = (gameId, attachment, message) ->
  console.log gameId
  console.log attachment?
  console.log message

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