window.deleteNotifications = () ->

  $("#notifications-menu").html("<li class='dropdown-header'>No new notifications!</li>")
  $("#notifications-toggle").html("Notifications")
  
  $.ajax({
    url: "/notifications/delete"
  })
  return

  
### 
  # handlers for events on challenge form
###
window.dyo = () ->
  if $("#dyo").is(":checked")
    $("#scenario").attr("disabled", "disabled")
  else
    $("#scenario").removeAttr("disabled")
  return
  
# autocomplete scenarios
window.scenario = () ->
  text = $("#scenario").val()
  if text
    $.ajax "/ajax/scenario/"+encodeURI(text)
      .done (result, status) ->
        console.log result # TODO reasonable handling here
        alert result

  