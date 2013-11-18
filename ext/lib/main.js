var pageMod = require("sdk/page-mod");
var ccc = require("./ccc");
var data = require("sdk/self").data;

exports.main = function() {
	
    /*pageMod.PageMod({
		include: "*",
		contentScriptFile: [data.url("tabInfo.js")],
		contentScriptWhen: 'start',
		onAttach: function(worker) {
			ccc.initTabInfoWorker(worker);
		},
		attachTo: ["top"]
    });*/
}