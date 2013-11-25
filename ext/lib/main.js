var pageMod = require("sdk/page-mod");
var ccc = require("./ccc");
var data = require("sdk/self").data;

exports.main = function() {

	var popup = require("sdk/panel").Panel({
      width: 120,
      height: 230,
      contentURL: data.url("popup.html"),
      contentScriptFile: data.url("popup.js"),
	  contentScriptWhen: "end"
    });
     
    // Create a widget, and attach the panel to it, so the panel is
    // shown when the user clicks the widget.
    require("sdk/widget").Widget({
      label: "Popup",
      id: "popup",
      contentURL: data.url("icon/icon.png"),
      panel: popup
    });
     
    // When the panel is displayed it generated an event called
    // "show": we will listen for that event and when it happens,
    // send our own "show" event to the panel's script, so the
    // script can prepare the panel for display.
    popup.port.on("panelActions", function(w) {
		switch(w.action)
		{
			case "navAndRecord":
				ccc.navAndRecord(w.site);
				break;
			case "refreshAndRecord":
				ccc.refreshAndRecord();
				break;
			default:
				break;
		}
		popup.hide();
    });
}