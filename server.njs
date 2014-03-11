var express = require("express");
var app = express();
var flashify = require("flashify");

app.configure(function() {
  app.use(express.cookieParser());
  app.use(express.bodyParser());
  app.use(express.session({ secret: 'keyboard cat' }));
  app.use(passport.initialize());
  app.use(passport.session());
  app.use(app.router);
});



app.get('/', index);
app.get('/index', index);
app.get("/me", renderProfile);

app.listen(80);

function index(req, res){
  res.render('index.jade', viewData(req,res));
}

function renderProfile(req,res){
  if(req.isAuthenticated){
    res.render("me.jade");
  } else
    res.redirect("/");
}
