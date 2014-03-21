
var server = "192.168.178.23:8080"

var deleteNotifications = function() {
  
  
  $("#notifications-menu").html("<li class='dropdown-header'>No new notifications!</li>");
  $("#notifications-toggle").html("Notifications");
  
  $.ajax({
    url: "/notifications/delete"
  });
};
