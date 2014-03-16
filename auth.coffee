common = require "./common"
email = require "./email"

exports.passport = require "passport"
passport = exports.passport
LocalStrategy = require("passport-local").Strategy;

database = common.database
User = database.User


# Set up Passport strategies
passport.use new LocalStrategy (username, password, done) ->
  User.findOne {name: username}, (err, user) ->
    return done err if err
    if not user?
      return done null, false, "Invalid credentials!"
    user.comparePassword password, (err, valid) ->
      if err
        return done err, false, err.message
      if valid
        if user.banned
          return done null, false, "You are banned!"
        if not user.activated
          return done null, false, "Please follow the instructions you
          received by e-mail before logging in for the first time. We need to make sure the e-mail address you are using actually belongs to you."
        return done null, user
      else
        return done null, false, "Invalid credentials!"

exports.setupRoutes = (app) ->       
  app.post "/do/login", passport.authenticate("local", {successRedirect: "/games", failureRedirect: "/login", failureFlash: true})
  app.get "/do/logout", (req,res) -> 
    req.logout()
    res.redirect("/")
  app.get "/validate/:userid/:token", (req,res) ->
    database.User.findOne
      _id: req.params.userid
      validationToken: req.params.token
    , (err, user) ->
      return res.send err if err
      return res.send "Invalid user or token" if not user
      user.activated = true
      user.save (err) ->
        return res.send err if err
        return res.redirect "/login"
        # TODO Make error handling more fancy!
 
  app.post "/do/signup", (req,res) -> 
    failed = no
    # validate data
    flashes = []
    if not req.body.username?
      flashes.push "A username is required."
      failed = yes
    if not req.body.password1?
      flashes.push "A password is required."
      failed = yes
    if req.body.password1 isnt req.body.password2
      flashes.push "Passwords don't match."
      failed = yes
    if not req.body.email?
      flashes.push "An E-Mail address is required."
      failed = yes
      
    # should do for now
    # TODO add e-mail and password validation
    
    if failed
      console.log "failed signup attempt"
      for flash in flashes
        req.flash "warning", flash
      res.redirect "/signup"
      
    else
      # write the user into the database
      # which I don't have as of now
      # which kind of sucks
      console.log "successful signup attempt"
      user = new User {
        name: req.body.username,
        password: req.body.password1,
        email: req.body.email
      }
      
      user.save (err, user) ->
        if err
          req.flash "error", err.message
          res.redirect "/error"
        else
          res.redirect "/"
        # send confirmation mail
      email.sendConfirmationMail user, (err, res) ->
        console.log err if err
        console.log "Validation mail sent: ", res if res
      
          
passport.serializeUser (user,done) -> 
  done null, user.name
  
exports.getActiveUser = (done) ->
  passport.deserializeUser req.user?.username, (err, user) ->
    done err, user
  
passport.deserializeUser (user, done) ->
  User.findOne {name: user}, (err, user) ->
    done err, user